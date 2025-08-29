/*
  # Fix accept_task function signature conflict

  1. Drop all existing accept_task function overloads
  2. Create single clean accept_task function with proper parameter name
  3. Set correct permissions

  This resolves the 42P13 error by eliminating signature conflicts.
*/

-- See what's there (for debugging)
SELECT n.nspname AS schema,
       p.proname  AS name,
       pg_get_function_identity_arguments(p.oid) AS args,
       p.proargnames
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.proname = 'accept_task';

-- Drop ALL existing accept_task overloads
DROP FUNCTION IF EXISTS public.accept_task(uuid);
DROP FUNCTION IF EXISTS public.accept_task(uuid, uuid);
DROP FUNCTION IF EXISTS public.accept_task(p_task_id uuid);
DROP FUNCTION IF EXISTS public.accept_task(p_task_id uuid, p_user_id uuid);

-- Create single, canonical RPC function
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

  -- Lock row to prevent double-accept
  SELECT * INTO v_row FROM public.tasks WHERE id = task_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'task_not_found';
  END IF;

  IF v_row.created_by = v_user THEN
    RAISE EXCEPTION 'cannot_accept_own_task';
  END IF;

  IF v_row.current_status <> 'accepted' AND v_row.status <> 'open' THEN
    RAISE EXCEPTION 'task_not_posted';
  END IF;

  UPDATE public.tasks
  SET current_status = 'accepted'::task_current_status,
      accepted_by = v_user,
      last_status_update = now(),
      updated_at = now()
  WHERE id = task_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

-- Set permissions
GRANT EXECUTE ON FUNCTION public.accept_task(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.accept_task(uuid) FROM anon;