/*
  # Rebuild Task Posting + Moderation (Robust, Signature-Agnostic)

  This migration ensures task posting works immediately by:
  1. Creating all required columns and moderation infrastructure
  2. Rebuilding the moderate_task_and_save RPC with TEXT-only parameters
  3. Setting up proper RLS policies using auth.uid()
  4. Verifying success with type-aware checks (not brittle string matching)

  ## What this creates:
  - Moderation enum and columns on tasks table
  - Updated_at trigger for tasks
  - Safety enum for legacy compatibility (not used in RPC)
  - Single canonical moderate_task_and_save function with 10 TEXT/integer parameters
  - Minimal RLS policies for security
  - Realtime publication setup

  ## Verification:
  - Type-aware function signature verification
  - Guards against uid() and enum cast regressions
  - Ensures PostgREST schema refresh
*/

--------------------------------------------
-- Step 1: Ensure columns & moderation enum
--------------------------------------------
DO $$
BEGIN
  -- Create moderation enum if missing
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_moderation_status' AND typnamespace = 'public'::regnamespace) THEN
    CREATE TYPE public.task_moderation_status AS ENUM ('approved','needs_review','blocked');
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
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_tasks_moderation_status') THEN
    CREATE INDEX idx_tasks_moderation_status ON public.tasks (moderation_status);
  END IF;
END $$;

--------------------------
-- Step 2: Touch trigger
--------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- Drop and recreate trigger
DROP TRIGGER IF EXISTS trg_tasks_set_updated_at ON public.tasks;
CREATE TRIGGER trg_tasks_set_updated_at
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

---------------------------------------
-- Step 3: Safety enum (legacy only)
---------------------------------------
DO $$
BEGIN
  -- Create legacy enum to prevent 42704 errors from old objects
  -- The RPC below will NOT reference this enum at all
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_category' AND typnamespace = 'public'::regnamespace) THEN
    CREATE TYPE public.task_category AS ENUM ('food_delivery','food_pickup','workout','errand','other');
  END IF;
END $$;

------------------------------------------------------
-- Step 4: RPC rebuild (TEXT-only, exact signature)
------------------------------------------------------
DO $$
DECLARE
  r RECORD;
BEGIN
  -- Drop all existing variants by signature
  FOR r IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'moderate_task_and_save'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS public.%I(%s);', r.proname, r.args);
  END LOOP;
END $$;

-- Create canonical function with exact parameter order
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

  -- Normalize category as TEXT (no enum casts)
  p_category := coalesce(nullif(trim(p_category), ''), 'other');
  
  -- Lightweight synchronous moderation
  IF (coalesce(p_title,'') ~* '(sexual|escort|nude|porn|hookup|sex)'
     OR coalesce(p_description,'') ~* '(sexual|escort|nude|porn|hookup|sex)') THEN
    v_status := 'blocked'; 
    v_reason := 'Sexual content not allowed';
  ELSIF (coalesce(p_title,'') ~* '(kill|assault|beat up|weapon|gun|knife|violence)'
     OR  coalesce(p_description,'') ~* '(kill|assault|beat up|weapon|gun|knife|violence)') THEN
    v_status := 'blocked'; 
    v_reason := 'Violence/weapon content not allowed';
  ELSIF (coalesce(p_title,'') ~* '(drugs|cocaine|heroin|fentanyl|marijuana|weed)'
     OR  coalesce(p_description,'') ~* '(drugs|cocaine|heroin|fentanyl|marijuana|weed)') THEN
    v_status := 'blocked'; 
    v_reason := 'Illegal drug content not allowed';
  ELSIF (coalesce(p_title,'') ~* '(spam|fake|scam|fraud)'
     OR  coalesce(p_description,'') ~* '(spam|fake|scam|fraud)') THEN
    v_status := 'needs_review'; 
    v_reason := 'Possible spam or fraudulent content';
  END IF;

  IF p_task_id IS NULL THEN
    -- INSERT path: create new task
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
    -- UPDATE path: owner only
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

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(
  text, text, text, text, integer, integer, text, uuid, text, text
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(
  text, text, text, text, integer, integer, text, uuid, text, text
) TO service_role;

-----------------------
-- Step 5: RLS setup
-----------------------
DO $$
BEGIN
  -- Enable RLS
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

-- Ensure profiles are readable for user embeds
DROP POLICY IF EXISTS profiles_select_public ON public.profiles;
CREATE POLICY profiles_select_public ON public.profiles
FOR SELECT
USING (true);

-------------------------------
-- Step 6: Realtime & cache
-------------------------------
DO $$
BEGIN
  -- Add tasks to realtime publication (safe if already exists)
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
  EXCEPTION WHEN duplicate_object THEN
    -- Already present, continue
  END;
END $$;

-- Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';

---------------------------------------------------
-- Step 7: Robust verification (type-aware check)
---------------------------------------------------
DO $$
DECLARE
  v_function_oid oid;
  v_function_def text;
  v_arg_types    oid[];
  v_expected_types text[] := ARRAY['text','text','text','text','int4','int4','text','uuid','text','text'];
  v_actual_types text[];
  r RECORD;
  v_found boolean := false;
BEGIN
  -- Find function with exact type signature (not string matching)
  FOR r IN
    SELECT p.oid, p.proargtypes
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' 
      AND p.proname = 'moderate_task_and_save'
      AND array_length(p.proargtypes, 1) = 10
  LOOP
    -- Convert OID array to type names
    SELECT array_agg(format_type(unnest, NULL) ORDER BY ordinality)
    INTO v_actual_types
    FROM unnest(r.proargtypes) WITH ORDINALITY;
    
    -- Check if types match expected signature
    IF v_actual_types = v_expected_types THEN
      v_function_oid := r.oid;
      v_found := true;
      EXIT;
    END IF;
  END LOOP;

  -- Fail if no matching function found
  IF NOT v_found THEN
    RAISE EXCEPTION 'moderate_task_and_save not found with expected signature [text,text,text,text,int4,int4,text,uuid,text,text]. Available signatures: %',
      (SELECT string_agg(pg_get_function_identity_arguments(p.oid), '; ')
       FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'moderate_task_and_save');
  END IF;

  -- Get function definition and verify it's clean
  SELECT pg_get_functiondef(v_function_oid) INTO v_function_def;
  
  -- Guard against regressions
  IF v_function_def ~ '\buid\s*\(' THEN
    RAISE EXCEPTION 'Found forbidden uid() in moderate_task_and_save function body';
  END IF;

  IF v_function_def ~ '::\s*public\.task_category' THEN
    RAISE EXCEPTION 'Found forbidden enum cast ::public.task_category in moderate_task_and_save function body';
  END IF;

  -- Success
  RAISE NOTICE 'moderate_task_and_save successfully verified: 10 params, no uid(), no enum casts';
END $$;

/*
  ## Acceptance Tests (verify after applying):
  
  1. POST /rest/v1/rpc/moderate_task_and_save with 10 params returns 200
  2. Spammy/unsafe content returns needs_review/blocked status
  3. Approved posts visible to other users; pending/blocked visible to poster only
  4. Function verification confirms correct types and clean body
  5. Re-running this migration is a no-op (fully idempotent)
*/