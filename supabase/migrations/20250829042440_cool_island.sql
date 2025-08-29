/*
  # Tasks table updates and accept_task RPC function

  1. Function Cleanup
    - Drops all existing accept_task function overloads
    - Prevents signature conflicts

  2. Table Updates
    - Adds task_current_status column with default 'posted'
    - Adds accepted_by and accepted_at columns for tracking
    - Adds updated_at column for timestamp tracking
    - Creates index for fast status lookups

  3. Accept Task RPC
    - Atomic function with row locking to prevent race conditions
    - Validates user permissions and task state
    - Updates task status and tracking fields
    - Returns updated task record

  4. Security
    - Only authenticated users can execute function
    - Anonymous users are explicitly denied access
*/

-- Drop any legacy accept_task overloads so we can recreate a single canonical version
DROP FUNCTION IF EXISTS public.accept_task(uuid);
DROP FUNCTION IF EXISTS public.accept_task(uuid, uuid);

-- Ensure tasks columns exist (now safe to use enum values)
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS task_current_status task_current_status NOT NULL DEFAULT 'posted';

ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS accepted_by uuid,
  ADD COLUMN IF NOT EXISTS accepted_at timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz;

-- Fast lookup by status
CREATE INDEX IF NOT EXISTS tasks_status_idx ON public.tasks (task_current_status);

-- Canonical RPC: accept_task(task_id uuid)
CREATE OR REPLACE FUNCTION public.accept_task(task_id uuid)
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
  SELECT * INTO v_row FROM public.tasks WHERE id = task_id FOR UPDATE;
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
      updated_at  = now()
  WHERE id = task_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

-- Permissions
REVOKE ALL ON FUNCTION public.accept_task(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.accept_task(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.accept_task(uuid) TO authenticated;