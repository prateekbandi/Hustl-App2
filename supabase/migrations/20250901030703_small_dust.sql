/*
  # Rebuild Task Posting + Moderation (Robust, OID-based Verification)

  1. Schema Setup
    - Creates moderation enum and all required task columns
    - Sets up updated_at trigger
    - Creates legacy enum for compatibility (not used in RPC)

  2. RPC Recreation
    - Drops all existing moderate_task_and_save variants
    - Creates single TEXT-only version with exact 10 parameters
    - Uses only auth.uid() throughout
    - No enum casts anywhere

  3. Security & Access
    - Proper RLS policies with moderation awareness
    - Execute grants for authenticated users
    - Realtime publication setup

  4. OID-based Verification
    - Verifies function signature using type OIDs
    - Guards against uid() and enum cast regressions
    - Provides diagnostic output if verification fails
*/

--------------------------------------------
-- Step 1: Ensure schema for posting & moderation
--------------------------------------------
DO $$
BEGIN
  -- Create moderation enum if missing
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_moderation_status' AND typnamespace = 'public'::regnamespace) THEN
    CREATE TYPE public.task_moderation_status AS ENUM ('approved', 'needs_review', 'blocked');
  END IF;

  -- Add required columns to tasks (add-only, never drop)
  ALTER TABLE public.tasks
    ADD COLUMN IF NOT EXISTS title                   text,
    ADD COLUMN IF NOT EXISTS description             text,
    ADD COLUMN IF NOT EXISTS category                text,
    ADD COLUMN IF NOT EXISTS urgency                 text,
    ADD COLUMN IF NOT EXISTS dropoff_address         text,
    ADD COLUMN IF NOT EXISTS dropoff_instructions    text,
    ADD COLUMN IF NOT EXISTS store                   text,
    ADD COLUMN IF NOT EXISTS estimated_minutes       integer,
    ADD COLUMN IF NOT EXISTS reward_cents            integer,
    ADD COLUMN IF NOT EXISTS created_by              uuid,
    ADD COLUMN IF NOT EXISTS assignee_id             uuid,
    ADD COLUMN IF NOT EXISTS updated_at              timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS moderation_status       public.task_moderation_status NOT NULL DEFAULT 'approved',
    ADD COLUMN IF NOT EXISTS moderation_reason       text,
    ADD COLUMN IF NOT EXISTS moderated_at            timestamptz,
    ADD COLUMN IF NOT EXISTS moderated_by            uuid;

  -- Backfill moderation_status where null
  UPDATE public.tasks 
  SET moderation_status = 'approved'::public.task_moderation_status
  WHERE moderation_status IS NULL;

  -- Create index if missing
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'tasks' AND indexname = 'idx_tasks_moderation_status') THEN
    CREATE INDEX idx_tasks_moderation_status ON public.tasks (moderation_status);
  END IF;
END $$;

--------------------------------------------
-- Step 2: Updated-at trigger
--------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  -- Drop existing trigger if exists
  IF EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_tasks_set_updated_at'
      AND tgrelid = 'public.tasks'::regclass
  ) THEN
    DROP TRIGGER trg_tasks_set_updated_at ON public.tasks;
  END IF;

  -- Create trigger
  CREATE TRIGGER trg_tasks_set_updated_at
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
END $$;

--------------------------------------------
-- Step 3: Safety only (legacy enum)
--------------------------------------------
DO $$
BEGIN
  -- Create legacy enum for compatibility (not used in RPC)
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_category' AND typnamespace = 'public'::regnamespace) THEN
    CREATE TYPE public.task_category AS ENUM ('food_delivery', 'food_pickup', 'workout', 'errand', 'other');
  END IF;
END $$;

--------------------------------------------
-- Step 4: RPC rebuild (TEXT-only; exact client params)
--------------------------------------------
DO $$
DECLARE
  r RECORD;
BEGIN
  -- Drop all existing moderate_task_and_save variants by signature
  FOR r IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'moderate_task_and_save'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS public.%I(%s);', r.proname, r.args);
  END LOOP;
END $$;

-- Create canonical RPC with exact 10 parameters
CREATE OR REPLACE FUNCTION public.moderate_task_and_save(
  p_category             text,
  p_description          text,
  p_dropoff_address      text,
  p_dropoff_instructions text,
  p_estimated_minutes    integer,
  p_reward_cents         integer,
  p_store                text,
  p_task_id              uuid,
  p_title                text,
  p_urgency              text
)
RETURNS public.tasks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_status  public.task_moderation_status := 'approved';
  v_reason  text := NULL;
  v_row     public.tasks;
BEGIN
  -- Get authenticated user ID
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Lightweight synchronous moderation
  IF (coalesce(p_title, '') ~* '(sexual|escort|nude|porn|hookup|sex)'
     OR coalesce(p_description, '') ~* '(sexual|escort|nude|porn|hookup|sex)') THEN
    v_status := 'blocked';
    v_reason := 'Sexual content not allowed';
  ELSIF (coalesce(p_title, '') ~* '(kill|assault|beat up|weapon|gun|knife|violence)'
     OR coalesce(p_description, '') ~* '(kill|assault|beat up|weapon|gun|knife|violence)') THEN
    v_status := 'blocked';
    v_reason := 'Violence/weapon content not allowed';
  ELSIF (coalesce(p_title, '') ~* '(drugs|cocaine|heroin|fentanyl|marijuana|weed)'
     OR coalesce(p_description, '') ~* '(drugs|cocaine|heroin|fentanyl|marijuana|weed)') THEN
    v_status := 'blocked';
    v_reason := 'Illegal drug content not allowed';
  ELSIF (coalesce(p_title, '') ~* '(spam|fake|scam|fraud)'
     OR coalesce(p_description, '') ~* '(spam|fake|scam|fraud)') THEN
    v_status := 'needs_review';
    v_reason := 'Possible spam or fraudulent content';
  END IF;

  -- Normalize category as TEXT (no enum casts)
  p_category := coalesce(nullif(trim(p_category), ''), 'other');

  IF p_task_id IS NULL THEN
    -- INSERT path
    INSERT INTO public.tasks(
      title, description, dropoff_instructions, store,
      dropoff_address, category, urgency, estimated_minutes, reward_cents,
      created_by, moderation_status, moderation_reason, moderated_at, moderated_by
    )
    VALUES(
      p_title, p_description, p_dropoff_instructions, p_store,
      p_dropoff_address, p_category, p_urgency, p_estimated_minutes, p_reward_cents,
      v_user_id, v_status, v_reason,
      CASE WHEN v_status <> 'approved' THEN now() ELSE NULL END,
      CASE WHEN v_status <> 'approved' THEN v_user_id ELSE NULL END
    )
    RETURNING * INTO v_row;
  ELSE
    -- UPDATE path (owner only)
    UPDATE public.tasks
       SET title                 = p_title,
           description           = p_description,
           dropoff_instructions  = p_dropoff_instructions,
           store                 = p_store,
           dropoff_address       = p_dropoff_address,
           category              = p_category,
           urgency               = p_urgency,
           estimated_minutes     = p_estimated_minutes,
           reward_cents          = p_reward_cents,
           moderation_status     = v_status,
           moderation_reason     = v_reason,
           moderated_at          = CASE WHEN v_status <> 'approved' THEN now() ELSE moderated_at END,
           moderated_by          = CASE WHEN v_status <> 'approved' THEN v_user_id ELSE moderated_by END
     WHERE id = p_task_id
       AND created_by = v_user_id
    RETURNING * INTO v_row;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Task not found or not authorized to update';
    END IF;
  END IF;

  RETURN v_row;
END
$$;

--------------------------------------------
-- Step 5: Grants
--------------------------------------------
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(
  text, text, text, text, integer, integer, text, uuid, text, text
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(
  text, text, text, text, integer, integer, text, uuid, text, text
) TO service_role;

--------------------------------------------
-- Step 6: Minimal RLS (auth.uid)
--------------------------------------------
DO $$
BEGIN
  ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
END $$;

-- Drop and recreate policies
DROP POLICY IF EXISTS tasks_select_visible ON public.tasks;
CREATE POLICY tasks_select_visible ON public.tasks
FOR SELECT
USING (
  moderation_status = 'approved'
  OR auth.uid() = created_by
  OR auth.uid() = assignee_id
);

DROP POLICY IF EXISTS tasks_update_owner_or_assignee ON public.tasks;
CREATE POLICY tasks_update_owner_or_assignee ON public.tasks
FOR UPDATE
USING (auth.uid() = created_by OR auth.uid() = assignee_id)
WITH CHECK (auth.uid() = created_by OR auth.uid() = assignee_id);

DROP POLICY IF EXISTS tasks_insert_owner ON public.tasks;
CREATE POLICY tasks_insert_owner ON public.tasks
FOR INSERT
WITH CHECK (created_by = auth.uid());

-- Profiles read policy (if missing)
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

--------------------------------------------
-- Step 7: Realtime & cache
--------------------------------------------
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
  EXCEPTION WHEN duplicate_object THEN
    -- Already present, ignore
  END;
END $$;

-- Refresh PostgREST schema
NOTIFY pgrst, 'reload schema';

--------------------------------------------
-- Step 8: OID-based verification (robust)
--------------------------------------------
DO $$
DECLARE
  v_text_oid    oid;
  v_int_oid     oid;
  v_uuid_oid    oid;
  v_expected    oid[];
  v_found_oid   oid := NULL;
  v_func_def    text;
  r             RECORD;
BEGIN
  -- Get type OIDs
  SELECT 'text'::regtype::oid INTO v_text_oid;
  SELECT 'integer'::regtype::oid INTO v_int_oid;
  SELECT 'uuid'::regtype::oid INTO v_uuid_oid;
  
  -- Expected signature: [text,text,text,text,int,int,text,uuid,text,text]
  v_expected := ARRAY[v_text_oid, v_text_oid, v_text_oid, v_text_oid, 
                      v_int_oid, v_int_oid, v_text_oid, v_uuid_oid, 
                      v_text_oid, v_text_oid];

  -- Find function with matching OID signature
  FOR r IN
    SELECT p.oid, p.proargtypes
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' 
      AND p.proname = 'moderate_task_and_save'
      AND array_length(p.proargtypes, 1) = 10
  LOOP
    IF r.proargtypes = v_expected THEN
      v_found_oid := r.oid;
      EXIT;
    END IF;
  END LOOP;

  -- Fail if not found with expected signature
  IF v_found_oid IS NULL THEN
    RAISE EXCEPTION 'moderate_task_and_save not found with expected OID signature. Available signatures: %',
      (SELECT string_agg(pg_get_function_identity_arguments(p.oid), '; ')
       FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'moderate_task_and_save');
  END IF;

  -- Get function definition and check for forbidden patterns
  SELECT pg_get_functiondef(v_found_oid) INTO v_func_def;
  
  -- Guard against uid() usage (must be auth.uid())
  IF v_func_def ~* '\buid\s*\(' THEN
    RAISE EXCEPTION 'Found forbidden uid() in moderate_task_and_save function body. Use auth.uid() instead.';
  END IF;

  -- Guard against enum casts
  IF v_func_def ~* '::\s*public\.task_category' THEN
    RAISE EXCEPTION 'Found forbidden enum cast ::public.task_category in moderate_task_and_save function body.';
  END IF;

  RAISE NOTICE 'SUCCESS: moderate_task_and_save verified with correct OID signature and clean body';
END $$;

-- Final verification comment
/*
  Acceptance Tests:
  - /rest/v1/rpc/moderate_task_and_save with 10 params returns 200
  - Blocked/needs-review/approved behaviors work correctly
  - Non-owners cannot update others' tasks
  - Function body contains no uid() and no ::public.task_category
  - Re-running this migration is a no-op
*/