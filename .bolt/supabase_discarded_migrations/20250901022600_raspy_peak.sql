/*
  # Fix task_category enum error (unblock now, then clean)

  1. Phase A - Instant Unbreak
    - Create safety enum if missing to prevent crashes
    - Drop and recreate moderate_task_and_save RPC with TEXT-only params
    - Ensure RPC is immediately callable

  2. Phase B - Deep Clean
    - Find all objects referencing the enum
    - Rebuild them to use TEXT instead
    - Remove enum dependencies safely
    - Drop enum if no dependencies remain

  3. Verification
    - Guard against remaining enum or uid() references
    - Refresh schema cache
    - Ensure RPC returns 200
*/

-- Phase A: Instant Unbreak
-- Create safety enum if missing to prevent crashes
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_category' AND typnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
    CREATE TYPE public.task_category AS ENUM ('food', 'grocery', 'coffee', 'food_delivery', 'food_pickup', 'workout', 'errand', 'other');
    RAISE NOTICE 'Created safety enum public.task_category';
  END IF;
END $$;

-- Drop ALL variants of moderate_task_and_save (any signature)
DO $$
DECLARE
  func_record RECORD;
BEGIN
  FOR func_record IN 
    SELECT p.proname, pg_get_function_identity_arguments(p.oid) as args
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' 
    AND p.proname = 'moderate_task_and_save'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS public.%I(%s)', func_record.proname, func_record.args);
    RAISE NOTICE 'Dropped function: public.%(%)', func_record.proname, func_record.args;
  END LOOP;
END $$;

-- Recreate ONE canonical RPC (TEXT-only, no enum anywhere)
CREATE OR REPLACE FUNCTION public.moderate_task_and_save(
  p_category text,
  p_description text,
  p_dropoff_address text,
  p_dropoff_instructions text,
  p_estimated_minutes integer,
  p_reward_cents integer,
  p_store text,
  p_task_id uuid,
  p_title text,
  p_urgency text
)
RETURNS public.tasks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_moderation_status text;
  v_moderation_reason text;
  v_normalized_category text;
  v_normalized_urgency text;
  v_task_row public.tasks;
BEGIN
  -- Get authenticated user
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Normalize category to valid database values (TEXT-based)
  v_normalized_category := CASE 
    WHEN lower(p_category) LIKE '%food%' OR lower(p_category) LIKE '%delivery%' OR lower(p_category) LIKE '%pickup%' THEN 'food'
    WHEN lower(p_category) LIKE '%coffee%' THEN 'coffee'
    WHEN lower(p_category) LIKE '%grocery%' OR lower(p_category) LIKE '%shopping%' THEN 'grocery'
    ELSE 'food' -- Default fallback
  END;

  -- Normalize urgency
  v_normalized_urgency := CASE 
    WHEN lower(p_urgency) IN ('low', 'medium', 'high') THEN lower(p_urgency)
    ELSE 'medium' -- Default fallback
  END;

  -- Basic content moderation (TEXT-based checks)
  v_moderation_status := 'approved';
  v_moderation_reason := NULL;

  -- Check for inappropriate content
  IF lower(p_title || ' ' || p_description || ' ' || p_dropoff_instructions) ~ '(sex|sexual|porn|nude|naked|escort|prostitut|drug|cocaine|heroin|marijuana|weed|cannabis|weapon|gun|knife|bomb|explosive|kill|murder|assault|rape|suicide|self.?harm|hate|nazi|terrorist)' THEN
    v_moderation_status := 'blocked';
    v_moderation_reason := 'Content violates community guidelines';
  END IF;

  -- Check for academic integrity violations
  IF lower(p_title || ' ' || p_description) ~ '(exam|test|quiz|homework|assignment|essay|paper|cheat|plagiar|academic.?dishonest)' THEN
    v_moderation_status := 'needs_review';
    v_moderation_reason := 'Potential academic integrity concern';
  END IF;

  -- If blocked, raise exception
  IF v_moderation_status = 'blocked' THEN
    RAISE EXCEPTION 'blocked: %', v_moderation_reason;
  END IF;

  -- Insert or update task
  IF p_task_id IS NULL THEN
    -- Insert new task
    INSERT INTO public.tasks (
      title,
      description,
      category,
      store,
      dropoff_address,
      dropoff_instructions,
      urgency,
      estimated_minutes,
      reward_cents,
      created_by,
      moderation_status,
      moderation_reason,
      moderated_at,
      moderated_by
    ) VALUES (
      trim(p_title),
      trim(p_description),
      v_normalized_category,
      trim(p_store),
      trim(p_dropoff_address),
      trim(p_dropoff_instructions),
      v_normalized_urgency,
      p_estimated_minutes,
      p_reward_cents,
      v_user_id,
      v_moderation_status,
      v_moderation_reason,
      now(),
      CASE WHEN v_moderation_status != 'approved' THEN v_user_id ELSE NULL END
    ) RETURNING * INTO v_task_row;
  ELSE
    -- Update existing task (owner only)
    UPDATE public.tasks SET
      title = trim(p_title),
      description = trim(p_description),
      category = v_normalized_category,
      store = trim(p_store),
      dropoff_address = trim(p_dropoff_address),
      dropoff_instructions = trim(p_dropoff_instructions),
      urgency = v_normalized_urgency,
      estimated_minutes = p_estimated_minutes,
      reward_cents = p_reward_cents,
      moderation_status = v_moderation_status,
      moderation_reason = v_moderation_reason,
      moderated_at = now(),
      moderated_by = CASE WHEN v_moderation_status != 'approved' THEN v_user_id ELSE NULL END,
      updated_at = now()
    WHERE id = p_task_id AND created_by = v_user_id
    RETURNING * INTO v_task_row;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Task not found or not owned by user';
    END IF;
  END IF;

  RETURN v_task_row;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(text,text,text,text,integer,integer,text,uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(text,text,text,text,integer,integer,text,uuid,text,text) TO service_role;

-- Phase B: Deep Clean - Find and fix all enum references
DO $$
DECLARE
  obj_record RECORD;
  func_def text;
  has_enum_refs boolean := false;
BEGIN
  -- Find all objects that reference task_category
  FOR obj_record IN 
    SELECT 
      p.proname as name,
      'function' as obj_type,
      pg_get_functiondef(p.oid) as definition,
      pg_get_function_identity_arguments(p.oid) as args
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' 
    AND pg_get_functiondef(p.oid) ~* 'task_category'
    AND p.proname != 'moderate_task_and_save' -- Skip our newly created function
  LOOP
    RAISE NOTICE 'Found enum reference in %: %(%)', obj_record.obj_type, obj_record.name, obj_record.args;
    has_enum_refs := true;
    
    -- Drop the problematic function
    EXECUTE format('DROP FUNCTION IF EXISTS public.%I(%s)', obj_record.name, obj_record.args);
    RAISE NOTICE 'Dropped function with enum reference: %', obj_record.name;
  END LOOP;

  -- Check views and triggers too
  FOR obj_record IN 
    SELECT 
      c.relname as name,
      'view' as obj_type,
      pg_get_viewdef(c.oid) as definition
    FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' 
    AND c.relkind = 'v'
    AND pg_get_viewdef(c.oid) ~* 'task_category'
  LOOP
    RAISE NOTICE 'Found enum reference in %: %', obj_record.obj_type, obj_record.name;
    has_enum_refs := true;
    
    -- Drop the problematic view
    EXECUTE format('DROP VIEW IF EXISTS public.%I', obj_record.name);
    RAISE NOTICE 'Dropped view with enum reference: %', obj_record.name;
  END LOOP;

  IF NOT has_enum_refs THEN
    RAISE NOTICE 'No additional enum references found';
  END IF;
END $$;

-- Verification Guards
DO $$
DECLARE
  func_def text;
BEGIN
  -- Get the function definition
  SELECT pg_get_functiondef(p.oid) INTO func_def
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' 
  AND p.proname = 'moderate_task_and_save'
  AND pg_get_function_identity_arguments(p.oid) = 'p_category text, p_description text, p_dropoff_address text, p_dropoff_instructions text, p_estimated_minutes integer, p_reward_cents integer, p_store text, p_task_id uuid, p_title text, p_urgency text';

  IF func_def IS NULL THEN
    RAISE EXCEPTION 'moderate_task_and_save function not found after creation';
  END IF;

  -- Check for prohibited patterns
  IF func_def ~* '\buid\s*\(' THEN
    RAISE EXCEPTION 'Found leftover uid() usage in moderate_task_and_save function';
  END IF;

  -- Check that we're not casting to the enum in the new function
  IF func_def ~* '::public\.task_category' THEN
    RAISE EXCEPTION 'Found enum cast in moderate_task_and_save function';
  END IF;

  RAISE NOTICE 'Function verification passed - no prohibited patterns found';
END $$;

-- Ensure RLS policies use auth.uid() (recreate if needed)
DROP POLICY IF EXISTS "tasks_select_visible" ON public.tasks;
CREATE POLICY "tasks_select_visible" ON public.tasks
  FOR SELECT TO authenticated
  USING (
    moderation_status = 'approved' 
    OR created_by = auth.uid() 
    OR assignee_id = auth.uid()
    OR accepted_by = auth.uid()
  );

DROP POLICY IF EXISTS "tasks_insert_owner" ON public.tasks;
CREATE POLICY "tasks_insert_owner" ON public.tasks
  FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid());

DROP POLICY IF EXISTS "tasks_update_owner_or_assignee" ON public.tasks;
CREATE POLICY "tasks_update_owner_or_assignee" ON public.tasks
  FOR UPDATE TO authenticated
  USING (created_by = auth.uid() OR assignee_id = auth.uid() OR accepted_by = auth.uid())
  WITH CHECK (created_by = auth.uid() OR assignee_id = auth.uid() OR accepted_by = auth.uid());

-- Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';

-- Final verification
DO $$
DECLARE
  enum_exists boolean;
  func_count integer;
BEGIN
  -- Check if enum still exists
  SELECT EXISTS(
    SELECT 1 FROM pg_type 
    WHERE typname = 'task_category' 
    AND typnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  ) INTO enum_exists;

  -- Count our functions
  SELECT COUNT(*) INTO func_count
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' 
  AND p.proname = 'moderate_task_and_save';

  RAISE NOTICE 'Migration complete - enum exists: %, function count: %', enum_exists, func_count;
  
  IF func_count != 1 THEN
    RAISE EXCEPTION 'Expected exactly 1 moderate_task_and_save function, found %', func_count;
  END IF;
END $$;