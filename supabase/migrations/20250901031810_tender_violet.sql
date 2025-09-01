/*
  # Rebuild Task Posting + Moderation Migration (Safe Verification)

  1. Schema Setup
    - Create moderation enum and required columns on tasks table
    - Set up updated_at trigger for automatic timestamp updates
    - Create legacy task_category enum for compatibility (not used in RPC)

  2. RPC Recreation
    - Drop all existing moderate_task_and_save function variants
    - Create single TEXT-only version with exact 10 parameters
    - Implement lightweight content moderation
    - Use auth.uid() exclusively, no enum casts

  3. Security
    - Enable RLS on tasks table with moderation-aware policies
    - Grant execute permissions to authenticated users
    - Add tasks to realtime publication

  4. Verification
    - Count-based verification (exactly 1 function with 10 args)
    - Body content scanning for forbidden patterns
    - No brittle signature string/OID matching
*/

-- Phase 1: Ensure moderation schema (idempotent)

-- Create moderation status enum if missing
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_moderation_status') THEN
    CREATE TYPE public.task_moderation_status AS ENUM ('approved', 'needs_review', 'blocked');
  END IF;
END $$;

-- Add required columns to tasks table if missing
DO $$
BEGIN
  -- Core task columns
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'title') THEN
    ALTER TABLE public.tasks ADD COLUMN title text;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'description') THEN
    ALTER TABLE public.tasks ADD COLUMN description text;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'category') THEN
    ALTER TABLE public.tasks ADD COLUMN category text;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'urgency') THEN
    ALTER TABLE public.tasks ADD COLUMN urgency text;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'dropoff_address') THEN
    ALTER TABLE public.tasks ADD COLUMN dropoff_address text;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'dropoff_instructions') THEN
    ALTER TABLE public.tasks ADD COLUMN dropoff_instructions text;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'store') THEN
    ALTER TABLE public.tasks ADD COLUMN store text;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'estimated_minutes') THEN
    ALTER TABLE public.tasks ADD COLUMN estimated_minutes integer;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'reward_cents') THEN
    ALTER TABLE public.tasks ADD COLUMN reward_cents integer;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'created_by') THEN
    ALTER TABLE public.tasks ADD COLUMN created_by uuid;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'assignee_id') THEN
    ALTER TABLE public.tasks ADD COLUMN assignee_id uuid;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'updated_at') THEN
    ALTER TABLE public.tasks ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
  END IF;
  
  -- Moderation columns
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'moderation_status') THEN
    ALTER TABLE public.tasks ADD COLUMN moderation_status public.task_moderation_status NOT NULL DEFAULT 'approved';
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'moderation_reason') THEN
    ALTER TABLE public.tasks ADD COLUMN moderation_reason text;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'moderated_at') THEN
    ALTER TABLE public.tasks ADD COLUMN moderated_at timestamptz;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'moderated_by') THEN
    ALTER TABLE public.tasks ADD COLUMN moderated_by uuid;
  END IF;
END $$;

-- Backfill moderation status for existing rows
UPDATE public.tasks 
SET moderation_status = 'approved' 
WHERE moderation_status IS NULL;

-- Create moderation index if missing
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_tasks_moderation_status') THEN
    CREATE INDEX idx_tasks_moderation_status ON public.tasks (moderation_status);
  END IF;
END $$;

-- Updated-at trigger function
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Drop and recreate updated_at trigger
DROP TRIGGER IF EXISTS trg_tasks_set_updated_at ON public.tasks;
CREATE TRIGGER trg_tasks_set_updated_at
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- Phase 2: Safety enum for legacy compatibility (not used in RPC)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_category') THEN
    CREATE TYPE public.task_category AS ENUM ('food_delivery', 'food_pickup', 'workout', 'errand', 'other');
  END IF;
END $$;

-- Phase 3: Rebuild RPC (drop all variants, create canonical one)

-- Drop all existing moderate_task_and_save functions
DO $$
DECLARE
  func_record RECORD;
BEGIN
  FOR func_record IN 
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'moderate_task_and_save'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS public.moderate_task_and_save(%s)', func_record.args);
  END LOOP;
END $$;

-- Create the canonical moderate_task_and_save function
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
  v_moderation_status public.task_moderation_status;
  v_moderation_reason text;
  v_category_clean text;
  v_result public.tasks;
BEGIN
  -- Get authenticated user ID
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Normalize category (TEXT only, no enum cast)
  v_category_clean := COALESCE(TRIM(p_category), 'other');
  IF v_category_clean = '' THEN
    v_category_clean := 'other';
  END IF;

  -- Lightweight content moderation
  v_moderation_status := 'approved';
  v_moderation_reason := NULL;

  -- Check for blocked content
  IF (LOWER(p_title) ~ '(sex|sexual|porn|nude|naked|escort|prostitut|drug|cocaine|heroin|meth|weed|marijuana|cannabis|weapon|gun|knife|bomb|explosive|violence|kill|murder|assault)') OR
     (LOWER(COALESCE(p_description, '')) ~ '(sex|sexual|porn|nude|naked|escort|prostitut|drug|cocaine|heroin|meth|weed|marijuana|cannabis|weapon|gun|knife|bomb|explosive|violence|kill|murder|assault)') THEN
    v_moderation_status := 'blocked';
    v_moderation_reason := 'Content violates community guidelines';
  -- Check for spam/review content
  ELSIF (LOWER(p_title) ~ '(free money|get rich|click here|buy now|limited time|act now|guaranteed|miracle|amazing deal)') OR
        (LOWER(COALESCE(p_description, '')) ~ '(free money|get rich|click here|buy now|limited time|act now|guaranteed|miracle|amazing deal)') THEN
    v_moderation_status := 'needs_review';
    v_moderation_reason := 'Potential spam content';
  END IF;

  -- Insert new task
  IF p_task_id IS NULL THEN
    INSERT INTO public.tasks (
      title,
      description,
      category,
      urgency,
      dropoff_address,
      dropoff_instructions,
      store,
      estimated_minutes,
      reward_cents,
      created_by,
      moderation_status,
      moderation_reason,
      moderated_at,
      moderated_by
    ) VALUES (
      p_title,
      p_description,
      v_category_clean,
      COALESCE(p_urgency, 'medium'),
      p_dropoff_address,
      p_dropoff_instructions,
      p_store,
      COALESCE(p_estimated_minutes, 30),
      COALESCE(p_reward_cents, 200),
      v_user_id,
      v_moderation_status,
      v_moderation_reason,
      CASE WHEN v_moderation_status != 'approved' THEN now() ELSE NULL END,
      CASE WHEN v_moderation_status != 'approved' THEN v_user_id ELSE NULL END
    )
    RETURNING * INTO v_result;
  ELSE
    -- Update existing task (only if owned by user)
    UPDATE public.tasks SET
      title = p_title,
      description = p_description,
      category = v_category_clean,
      urgency = COALESCE(p_urgency, 'medium'),
      dropoff_address = p_dropoff_address,
      dropoff_instructions = p_dropoff_instructions,
      store = p_store,
      estimated_minutes = COALESCE(p_estimated_minutes, 30),
      reward_cents = COALESCE(p_reward_cents, 200),
      moderation_status = v_moderation_status,
      moderation_reason = v_moderation_reason,
      moderated_at = CASE WHEN v_moderation_status != 'approved' THEN now() ELSE NULL END,
      moderated_by = CASE WHEN v_moderation_status != 'approved' THEN v_user_id ELSE NULL END,
      updated_at = now()
    WHERE id = p_task_id AND created_by = v_user_id
    RETURNING * INTO v_result;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'not_authorized';
    END IF;
  END IF;

  RETURN v_result;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save TO authenticated;
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save TO service_role;

-- Phase 4: Minimal RLS (auth.uid everywhere)

-- Enable RLS on tasks
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS tasks_select_visible ON public.tasks;
DROP POLICY IF EXISTS tasks_update_owner_or_assignee ON public.tasks;
DROP POLICY IF EXISTS tasks_insert_owner ON public.tasks;
DROP POLICY IF EXISTS profiles_select_public ON public.profiles;

-- Recreate policies
CREATE POLICY tasks_select_visible ON public.tasks
  FOR SELECT
  USING (moderation_status = 'approved' OR auth.uid() = created_by OR auth.uid() = assignee_id);

CREATE POLICY tasks_update_owner_or_assignee ON public.tasks
  FOR UPDATE
  USING (auth.uid() = created_by OR auth.uid() = assignee_id)
  WITH CHECK (auth.uid() = created_by OR auth.uid() = assignee_id);

CREATE POLICY tasks_insert_owner ON public.tasks
  FOR INSERT
  WITH CHECK (created_by = auth.uid());

-- Ensure profiles can be read for task embeds
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'profiles_select_public') THEN
    CREATE POLICY profiles_select_public ON public.profiles
      FOR SELECT
      USING (true);
  END IF;
END $$;

-- Phase 5: Realtime & schema cache

-- Add tasks to realtime publication (safe if already exists)
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
  EXCEPTION WHEN duplicate_object THEN
    -- Table already in publication, ignore
  END;
END $$;

-- Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';

-- Phase 6: Safe verification (count-based, no brittle signatures)

DO $$
DECLARE
  v_function_count integer;
  v_function_body text;
  v_all_signatures text;
BEGIN
  -- Count functions named moderate_task_and_save with exactly 10 arguments
  SELECT COUNT(*)
  INTO v_function_count
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' 
    AND p.proname = 'moderate_task_and_save'
    AND p.pronargs = 10;

  -- If no function found, list what we do have
  IF v_function_count = 0 THEN
    SELECT string_agg(
      format('moderate_task_and_save(%s)', pg_get_function_identity_arguments(p.oid)), 
      E'\n'
    )
    INTO v_all_signatures
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'moderate_task_and_save';
    
    RAISE EXCEPTION 'No moderate_task_and_save function found with 10 arguments. Found signatures: %', 
      COALESCE(v_all_signatures, 'none');
  END IF;

  -- If multiple functions found, list them
  IF v_function_count > 1 THEN
    SELECT string_agg(
      format('moderate_task_and_save(%s)', pg_get_function_identity_arguments(p.oid)), 
      E'\n'
    )
    INTO v_all_signatures
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' 
      AND p.proname = 'moderate_task_and_save'
      AND p.pronargs = 10;
    
    RAISE EXCEPTION 'Multiple moderate_task_and_save functions found with 10 arguments: %', v_all_signatures;
  END IF;

  -- Get the function body for content verification
  SELECT pg_get_functiondef(p.oid)
  INTO v_function_body
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' 
    AND p.proname = 'moderate_task_and_save'
    AND p.pronargs = 10
  LIMIT 1;

  -- Check for forbidden patterns in function body
  IF v_function_body ~ '\muid\(' THEN
    RAISE EXCEPTION 'Function body contains forbidden uid() - must use auth.uid() only';
  END IF;

  IF v_function_body ~ '::public\.task_category' THEN
    RAISE EXCEPTION 'Function body contains forbidden enum cast ::public.task_category - must treat category as TEXT only';
  END IF;

  -- Success
  RAISE NOTICE 'Migration completed successfully. Function moderate_task_and_save verified with 10 arguments and clean body.';
END $$;