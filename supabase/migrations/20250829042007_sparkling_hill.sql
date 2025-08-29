/*
  # Canonical Accept Task Function

  This migration creates a single, reliable accept_task RPC function by:
  
  1. Dropping all existing accept_task function overloads to eliminate signature conflicts
  2. Ensuring the task_current_status enum exists with lowercase values
  3. Adding required columns to tasks table if missing
  4. Creating one canonical accept_task(task_id uuid) function with atomic row locking
  5. Setting proper permissions for authenticated users only

  ## Changes Made
  - Drops any conflicting function signatures
  - Creates task_current_status enum with values: posted, accepted, in_progress, completed, cancelled
  - Adds task_current_status, accepted_by, accepted_at columns if missing
  - Creates atomic accept_task function with concurrency protection
  - Sets proper security permissions

  ## Security
  - Function runs with SECURITY DEFINER for proper access
  - Only authenticated users can execute
  - Row-level locking prevents race conditions
*/

-- 1) Drop any existing accept_task overloads
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT n.nspname AS schema_name,
           p.proname  AS func_name,
           pg_get_function_identity_arguments(p.oid) AS arg_types
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'accept_task'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %I.%I(%s);', r.schema_name, r.func_name, r.arg_types);
  END LOOP;
END $$;

-- 2) Ensure enum exists (lowercase labels)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t WHERE t.typname = 'task_current_status') THEN
    CREATE TYPE task_current_status AS ENUM ('posted','accepted','in_progress','completed','cancelled');
  END IF;

  -- Add labels if any are missing (ignore if already exist)
  BEGIN ALTER TYPE task_current_status ADD VALUE 'posted';       EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER TYPE task_current_status ADD VALUE 'accepted';     EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER TYPE task_current_status ADD VALUE 'in_progress';  EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER TYPE task_current_status ADD VALUE 'completed';    EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER TYPE task_current_status ADD VALUE 'cancelled';    EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

-- 3) Ensure tasks table has required columns
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'tasks' AND column_name = 'task_current_status'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN task_current_status task_current_status NOT NULL DEFAULT 'posted';
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

-- Fast lookup by status
CREATE INDEX IF NOT EXISTS tasks_status_idx ON public.tasks (task_current_status);

-- 4) Canonical RPC: accept_task(task_id uuid)
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

  -- Lock the row to avoid double-accept
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

-- 5) Permissions
REVOKE ALL ON FUNCTION public.accept_task(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.accept_task(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.accept_task(uuid) TO authenticated;