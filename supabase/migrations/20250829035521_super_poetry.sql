/*
  # Implement reliable Accept Task behavior

  This migration creates a robust accept_task function with:
  1. Proper lowercase enum values (posted, accepted, in_progress, completed, cancelled)
  2. Atomic operations with row locking to prevent race conditions
  3. Business logic validation (no self-acceptance, only posted tasks)
  4. Friendly error messages for common failures
  5. Returns updated task record to client

  ## Changes Made
  1. Ensure task_current_status enum exists with lowercase values
  2. Add missing columns to tasks table if needed
  3. Create atomic accept_task RPC function
  4. Add proper indexing for performance
  5. Grant appropriate permissions
*/

-- 1) Ensure lowercase enum values exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t WHERE t.typname = 'task_current_status') THEN
    CREATE TYPE task_current_status AS ENUM ('posted','accepted','in_progress','completed','cancelled');
  END IF;

  -- Add missing lowercase labels if needed (safe, additive)
  BEGIN
    ALTER TYPE task_current_status ADD VALUE IF NOT EXISTS 'posted';
    ALTER TYPE task_current_status ADD VALUE IF NOT EXISTS 'accepted';
    ALTER TYPE task_current_status ADD VALUE IF NOT EXISTS 'in_progress';
    ALTER TYPE task_current_status ADD VALUE IF NOT EXISTS 'completed';
    ALTER TYPE task_current_status ADD VALUE IF NOT EXISTS 'cancelled';
  EXCEPTION WHEN duplicate_object THEN
    -- ignore
  END;
END $$;

-- 2) Tasks table columns (add if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'tasks' AND column_name = 'task_current_status'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN task_current_status task_current_status DEFAULT 'posted' NOT NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'tasks' AND column_name = 'accepted_by'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN accepted_by uuid;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'tasks' AND column_name = 'accepted_at'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN accepted_at timestamptz;
  END IF;
END $$;

-- 3) Fast lookup index
CREATE INDEX IF NOT EXISTS tasks_status_idx ON public.tasks (task_current_status);

-- 4) RPC: accept_task – atomic, concurrency-safe
CREATE OR REPLACE FUNCTION public.accept_task(p_task_id uuid)
RETURNS public.tasks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_row  public.tasks;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Lock the row to prevent double-accept
  SELECT * INTO v_row FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'task_not_found';
  END IF;

  IF v_row.created_by = v_user THEN
    RAISE EXCEPTION 'cannot_accept_own_task';
  END IF;

  IF v_row.task_current_status <> 'posted' THEN
    RAISE EXCEPTION 'task_not_posted';
  END IF;

  UPDATE public.tasks
  SET task_current_status = 'accepted'::task_current_status,
      accepted_by = v_user,
      accepted_at = now(),
      updated_at = now()
  WHERE id = p_task_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

-- 5) Permissions: allow authenticated to execute; RLS stays strict
GRANT EXECUTE ON FUNCTION public.accept_task(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.accept_task(uuid) FROM anon;

-- 6) Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';