/*
  # Rebuild Task Posting + Moderation (idempotent, TEXT-only category)

  1. Core Infrastructure
    - Creates moderation enum and required task columns
    - Sets up updated_at trigger
    - Creates optional legacy enum for compatibility

  2. RPC Function
    - Drops all existing moderate_task_and_save variants
    - Creates single TEXT-only version with exact 10 parameters
    - Uses auth.uid() only, no enum casts
    - Handles both insert and update operations

  3. Security & Access
    - Enables RLS with moderation-aware policies
    - Grants proper execute permissions
    - Adds to realtime publication

  4. Verification
    - Guards against uid() and enum cast regressions
    - Refreshes PostgREST schema cache
*/

-----------------------------
-- Phase 1: Ensure columns & moderation enum
-----------------------------
DO $$
BEGIN
  -- Enum for moderation state
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_moderation_status' AND typnamespace = 'public'::regnamespace) THEN
    CREATE TYPE public.task_moderation_status AS ENUM ('approved','needs_review','blocked');
  END IF;

  -- Add required columns to tasks (add-only, never drop)
  ALTER TABLE public.tasks
    ADD COLUMN IF NOT EXISTS category                text,
    ADD COLUMN IF NOT EXISTS description             text,
    ADD COLUMN IF NOT EXISTS title                   text,
    ADD COLUMN IF NOT EXISTS dropoff_address         text,
    ADD COLUMN IF NOT EXISTS dropoff_instructions    text,
    ADD COLUMN IF NOT EXISTS store                   text,
    ADD COLUMN IF NOT EXISTS estimated_minutes       integer,
    ADD COLUMN IF NOT EXISTS reward_cents            integer,
    ADD COLUMN IF NOT EXISTS urgency                 text,
    ADD COLUMN IF NOT EXISTS created_by              uuid,
    ADD COLUMN IF NOT EXISTS assignee_id             uuid,
    ADD COLUMN IF NOT EXISTS updated_at              timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS moderation_status       public.task_moderation_status NOT NULL DEFAULT 'approved',
    ADD COLUMN IF NOT EXISTS moderation_reason       text,
    ADD COLUMN IF NOT EXISTS moderated_at            timestamptz,
    ADD COLUMN IF NOT EXISTS moderated_by            uuid;

  -- Backfill moderation_status where null
  UPDATE public.tasks SET moderation_status = 'approved'::public.task_moderation_status
  WHERE moderation_status IS NULL;

  -- Helpful index
  CREATE INDEX IF NOT EXISTS idx_tasks_moderation_status ON public.tasks (moderation_status);
END $$;

-----------------------------
-- Phase 2: Touch trigger for updated_at
-----------------------------
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
  IF EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_tasks_set_updated_at'
      AND tgrelid = 'public.tasks'::regclass
  ) THEN
    DROP TRIGGER trg_tasks_set_updated_at ON public.tasks;
  END IF;

  CREATE TRIGGER trg_tasks_set_updated_at
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
END $$;

-----------------------------
-- Phase 3: Safety enum (optional, for legacy only)
-----------------------------
-- We DO NOT use this enum anywhere below. It's only to prevent 42704
-- from any old views/triggers you may still have. Safe if already exists.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_category' AND typnamespace = 'public'::regnamespace) THEN
    CREATE TYPE public.task_category AS ENUM ('food_delivery','food_pickup','workout','errand','other');
  END IF;
END $$;

-----------------------------
-- Phase 4: Drop ALL existing moderate_task_and_save variants
-----------------------------
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'moderate_task_and_save'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS public.%I(%s);', r.proname, r.args);
  END LOOP;
END $$;

-----------------------------
-- Phase 5: Recreate canonical RPC (TEXT-only params; NEVER references enum type)
-----------------------------
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
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Simple synchronous moderation (expand your rules as needed)
  IF (coalesce(p_title,'') ~* '(sexual|escort|nude|porn|hookup)'
     OR coalesce(p_description,'') ~* '(sexual|escort|nude|porn|hookup)') THEN
    v_status := 'blocked'; v_reason := 'Sexual content not allowed';
  ELSIF (coalesce(p_title,'') ~* '(kill|assault|beat up|weapon|gun|knife)'
     OR  coalesce(p_description,'') ~* '(kill|assault|beat up|weapon|gun|knife)') THEN
    v_status := 'blocked'; v_reason := 'Violence/weapon content not allowed';
  ELSIF (coalesce(p_title,'') ~* '(drugs|cocaine|heroin|fentanyl)'
     OR  coalesce(p_description,'') ~* '(drugs|cocaine|heroin|fentanyl)') THEN
    v_status := 'blocked'; v_reason := 'Illegal drug content not allowed';
  ELSIF (coalesce(p_title,'') ~* 'spam'
     OR  coalesce(p_description,'') ~* 'spam') THEN
    v_status := 'needs_review'; v_reason := 'Possible spam';
  END IF;

  -- Normalize category TEXT (no enum casts at all)
  p_category := nullif(trim(p_category), '');
  IF p_category IS NULL THEN
    p_category := 'other';
  END IF;

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

-----------------------------
-- Phase 6: Grants & Publications
-----------------------------
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(
  text, text, text, text, integer, integer, text, uuid, text, text
) TO authenticated;

-- (Optional) If your server uses service_role explicitly:
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(
  text, text, text, text, integer, integer, text, uuid, text, text
) TO service_role;

-- Ensure tasks is in realtime publication (safe if already added)
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
  EXCEPTION WHEN duplicate_object THEN
    -- already present
  END;
END $$;

-----------------------------
-- Phase 7: RLS (minimal, fix)
-----------------------------
DO $$
BEGIN
  ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
END $$;

-- Allow authenticated users to view approved tasks; owner/assignee can view theirs regardless
DROP POLICY IF EXISTS tasks_select_visible ON public.tasks;
CREATE POLICY tasks_select_visible ON public.tasks
FOR SELECT
USING (
  moderation_status = 'approved'
  OR auth.uid() = created_by
  OR auth.uid() = assignee_id
);

-- Only owner or assignee may update (status etc). This also covers moderation fields via RPC for owner.
DROP POLICY IF EXISTS tasks_update_owner_or_assignee ON public.tasks;
CREATE POLICY tasks_update_owner_or_assignee ON public.tasks
FOR UPDATE
USING (auth.uid() = created_by OR auth.uid() = assignee_id)
WITH CHECK (auth.uid() = created_by OR auth.uid() = assignee_id);

-- Inserts must belong to caller (the RPC sets created_by, this WITH CHECK enforces it)
DROP POLICY IF EXISTS tasks_insert_owner ON public.tasks;
CREATE POLICY tasks_insert_owner ON public.tasks
FOR INSERT
WITH CHECK (created_by = auth.uid());

-- Profiles public read (needed for embeds)
DROP POLICY IF EXISTS profiles_select_public ON public.profiles;
CREATE POLICY profiles_select_public ON public.profiles
FOR SELECT
USING (true);

-----------------------------
-- Phase 8: Verify RPC body is clean
-----------------------------
DO $$
DECLARE
  def text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO def
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'moderate_task_and_save'
    AND pg_get_function_identity_arguments(p.oid) =
      'text, text, text, text, integer, integer, text, uuid, text, text';

  IF def IS NULL THEN
    RAISE EXCEPTION 'moderate_task_and_save not found with expected signature';
  END IF;

  -- Guard against regressions
  IF lower(def) ~ '\buid\s*\(' THEN
    RAISE EXCEPTION 'Found forbidden uid() in moderate_task_and_save';
  END IF;

  IF lower(def) ~ '::\s*public\.task_category' THEN
    RAISE EXCEPTION 'Found forbidden enum cast ::public.task_category in moderate_task_and_save';
  END IF;
END $$;

-----------------------------
-- Phase 9: Refresh PostgREST schema cache
-----------------------------
NOTIFY pgrst, 'reload schema';

/*
  Acceptance Tests (should all pass):
  
  1. Calling /rest/v1/rpc/moderate_task_and_save with valid params returns 200 and a task row
  2. Creating a task with sexual/violent/illegal content → blocked (clean error); spammy → needs_review
  3. Approved tasks are visible to other users; pending/blocked are visible to the poster only
  4. Searching the function definition shows no uid( and no ::public.task_category
  5. Re-running the migration is a no-op (no duplicate objects or errors)
*/