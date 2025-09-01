/*
  # Final Fix - UID Shim + Task Posting/Moderation Rebuild

  1. Compatibility
    - Creates `public.uid()` shim function that calls `auth.uid()`
    - Allows legacy functions to continue working without modification

  2. Schema Setup
    - Ensures `task_moderation_status` enum exists
    - Adds all required task columns (title, description, category, etc.)
    - Creates moderation columns (status, reason, timestamps)
    - Sets up `updated_at` trigger

  3. RPC Rebuild
    - Drops all existing `moderate_task_and_save` variants
    - Creates single TEXT-only version with exact 10 parameters
    - Uses only `auth.uid()` throughout
    - No enum casts for category (pure TEXT)

  4. Security
    - Minimal RLS policies using `auth.uid()`
    - Proper moderation visibility rules
    - Execute grants for authenticated users

  5. Verification
    - Targeted checks on our functions only
    - Compatibility shim handles legacy `uid()` usage
    - Clear diagnostics if issues found
*/

-- Phase 0: Compatibility shim (idempotent)
-- Create public.uid() wrapper so legacy code continues working
CREATE OR REPLACE FUNCTION public.uid()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid();
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.uid() TO authenticated;
GRANT EXECUTE ON FUNCTION public.uid() TO service_role;

-- Phase 1: Ensure moderation enum (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_moderation_status') THEN
    CREATE TYPE public.task_moderation_status AS ENUM ('approved', 'needs_review', 'blocked');
  END IF;
END $$;

-- Phase 2: Ensure task columns (add-only, idempotent)
DO $$
BEGIN
  -- Core task columns
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'title') THEN
    ALTER TABLE public.tasks ADD COLUMN title text;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'description') THEN
    ALTER TABLE public.tasks ADD COLUMN description text DEFAULT '';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'category') THEN
    ALTER TABLE public.tasks ADD COLUMN category text DEFAULT 'food';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'urgency') THEN
    ALTER TABLE public.tasks ADD COLUMN urgency text DEFAULT 'medium';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'dropoff_address') THEN
    ALTER TABLE public.tasks ADD COLUMN dropoff_address text DEFAULT '';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'dropoff_instructions') THEN
    ALTER TABLE public.tasks ADD COLUMN dropoff_instructions text DEFAULT '';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'store') THEN
    ALTER TABLE public.tasks ADD COLUMN store text DEFAULT '';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'estimated_minutes') THEN
    ALTER TABLE public.tasks ADD COLUMN estimated_minutes integer DEFAULT 30;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'reward_cents') THEN
    ALTER TABLE public.tasks ADD COLUMN reward_cents integer DEFAULT 0;
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

-- Backfill moderation status
UPDATE public.tasks 
SET moderation_status = 'approved' 
WHERE moderation_status IS NULL;

-- Phase 3: Ensure moderation index (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_tasks_moderation_status') THEN
    CREATE INDEX idx_tasks_moderation_status ON public.tasks (moderation_status);
  END IF;
END $$;

-- Phase 4: Updated-at trigger (idempotent)
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Drop and recreate trigger
DROP TRIGGER IF EXISTS trg_tasks_set_updated_at ON public.tasks;
CREATE TRIGGER trg_tasks_set_updated_at
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- Phase 5: Legacy safety enum (idempotent, not used in RPC)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_category') THEN
    CREATE TYPE public.task_category AS ENUM ('food_delivery', 'food_pickup', 'workout', 'errand', 'other');
  END IF;
END $$;

-- Phase 6: Enable RLS and recreate policies (idempotent)
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS tasks_select_visible ON public.tasks;
DROP POLICY IF EXISTS tasks_update_owner_or_assignee ON public.tasks;
DROP POLICY IF EXISTS tasks_insert_owner ON public.tasks;
DROP POLICY IF EXISTS profiles_select_public ON public.profiles;

-- Recreate policies with auth.uid()
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
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'profiles' 
    AND policyname = 'profiles_select_public'
  ) THEN
    CREATE POLICY profiles_select_public ON public.profiles
      FOR SELECT
      USING (true);
  END IF;
END $$;

-- Phase 7: Drop all existing moderate_task_and_save variants
DO $$
DECLARE
  func_record RECORD;
BEGIN
  FOR func_record IN 
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as identity_args
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' 
    AND p.proname = 'moderate_task_and_save'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS public.moderate_task_and_save(%s)', func_record.identity_args);
    RAISE NOTICE 'Dropped function: moderate_task_and_save(%)', func_record.identity_args;
  END LOOP;
END $$;

-- Phase 8: Create canonical RPC (TEXT-only, exact client params)
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

  -- Sanitize category (pure TEXT, no enum casts)
  v_category_clean := COALESCE(TRIM(p_category), 'other');
  IF v_category_clean = '' THEN
    v_category_clean := 'other';
  END IF;

  -- Lightweight synchronous moderation
  v_moderation_status := 'approved';
  v_moderation_reason := NULL;

  -- Check for blocked content (sexual, violence, illegal drugs)
  IF (
    lower(p_title || ' ' || COALESCE(p_description, '')) ~ '\b(sex|sexual|porn|nude|naked|escort|prostitut|hookup|fuck|dick|pussy|cock|tits|ass|bitch|slut|whore)\b'
    OR lower(p_title || ' ' || COALESCE(p_description, '')) ~ '\b(kill|murder|stab|shoot|gun|weapon|knife|bomb|explosive|violence|fight|beat up|assault)\b'
    OR lower(p_title || ' ' || COALESCE(p_description, '')) ~ '\b(drug|cocaine|heroin|meth|weed|marijuana|pills|molly|ecstasy|acid|lsd|shroom|xanax|adderall)\b'
  ) THEN
    v_moderation_status := 'blocked';
    v_moderation_reason := 'Content violates community guidelines';
  
  -- Check for spam/suspicious content
  ELSIF (
    lower(p_title || ' ' || COALESCE(p_description, '')) ~ '\b(make money|get rich|easy cash|free money|click here|visit my|check out my|follow me|subscribe|like and share)\b'
    OR length(p_title) > 200
    OR (p_description IS NOT NULL AND length(p_description) > 1000)
  ) THEN
    v_moderation_status := 'needs_review';
    v_moderation_reason := 'Content flagged for review';
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
      TRIM(p_title),
      TRIM(COALESCE(p_description, '')),
      v_category_clean,
      COALESCE(TRIM(p_urgency), 'medium'),
      TRIM(COALESCE(p_dropoff_address, '')),
      TRIM(COALESCE(p_dropoff_instructions, '')),
      TRIM(COALESCE(p_store, '')),
      COALESCE(p_estimated_minutes, 30),
      COALESCE(p_reward_cents, 0),
      v_user_id,
      v_moderation_status,
      v_moderation_reason,
      CASE WHEN v_moderation_status != 'approved' THEN now() ELSE NULL END,
      CASE WHEN v_moderation_status != 'approved' THEN v_user_id ELSE NULL END
    )
    RETURNING * INTO v_result;

  -- Update existing task
  ELSE
    UPDATE public.tasks SET
      title = TRIM(p_title),
      description = TRIM(COALESCE(p_description, '')),
      category = v_category_clean,
      urgency = COALESCE(TRIM(p_urgency), 'medium'),
      dropoff_address = TRIM(COALESCE(p_dropoff_address, '')),
      dropoff_instructions = TRIM(COALESCE(p_dropoff_instructions, '')),
      store = TRIM(COALESCE(p_store, '')),
      estimated_minutes = COALESCE(p_estimated_minutes, 30),
      reward_cents = COALESCE(p_reward_cents, 0),
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

-- Phase 9: Legacy safety enum (not used in RPC)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_category') THEN
    CREATE TYPE public.task_category AS ENUM ('food_delivery', 'food_pickup', 'workout', 'errand', 'other');
  END IF;
END $$;

-- Phase 10: Ensure realtime publication (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND tablename = 'tasks'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
  END IF;
EXCEPTION
  WHEN undefined_object THEN
    -- Publication doesn't exist, skip
    NULL;
END $$;

-- Phase 11: Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';

-- Phase 12: Targeted verification (our functions only)
DO $$
DECLARE
  func_count integer;
  func_body text;
  legacy_funcs text := '';
  func_record RECORD;
BEGIN
  -- Count our moderate_task_and_save functions
  SELECT COUNT(*) INTO func_count
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' 
  AND p.proname = 'moderate_task_and_save'
  AND p.pronargs = 10;

  IF func_count = 0 THEN
    RAISE EXCEPTION 'No moderate_task_and_save function found with 10 arguments';
  ELSIF func_count > 1 THEN
    RAISE EXCEPTION 'Multiple moderate_task_and_save functions found with 10 arguments: %', func_count;
  END IF;

  -- Get function body for verification
  SELECT pg_get_functiondef(p.oid) INTO func_body
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' 
  AND p.proname = 'moderate_task_and_save'
  AND p.pronargs = 10;

  -- Check for forbidden patterns in our RPC
  IF func_body ~ '\buid\s*\(' THEN
    RAISE EXCEPTION 'moderate_task_and_save contains forbidden uid() - must use auth.uid()';
  END IF;

  IF func_body ~ '::public\.task_category' THEN
    RAISE EXCEPTION 'moderate_task_and_save contains forbidden enum cast ::public.task_category';
  END IF;

  -- Log legacy functions still using uid() (but don't fail)
  FOR func_record IN 
    SELECT p.proname, pg_get_function_identity_arguments(p.oid) as identity_args
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' 
    AND p.proname != 'moderate_task_and_save'
    AND p.proname != 'uid'
    AND lower(pg_get_functiondef(p.oid)) ~ '\buid\s*\('
  LOOP
    legacy_funcs := legacy_funcs || func_record.proname || '(' || func_record.identity_args || '), ';
  END LOOP;

  IF legacy_funcs != '' THEN
    RAISE NOTICE 'Legacy functions still using uid() (now handled by compatibility shim): %', rtrim(legacy_funcs, ', ');
  END IF;

  RAISE NOTICE 'Migration completed successfully. moderate_task_and_save rebuilt with 10 parameters and auth.uid() usage.';
END $$;