/*
  # Fix accept_task function signature clash

  1. Drop all existing accept_task function overloads
  2. Create single clean function with correct parameter name
  3. Grant proper permissions

  This resolves the 42P13 error by eliminating all conflicting function signatures.
*/

-- 0) See what's there (for debugging)
-- SELECT n.nspname AS schema,
--        p.proname  AS name,
--        pg_get_function_identity_arguments(p.oid) AS args,
--        p.proargnames
-- FROM pg_proc p
-- JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE p.proname = 'accept_task';

-- 1) Drop ALL existing accept_task overloads (any arg list)
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'accept_task'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %I.%I(%s);', r.nspname, r.proname, r.args);
  END LOOP;
END $$;

-- 2) Recreate a single definitive RPC (keep param name `task_id`)
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

  SELECT * INTO v_row FROM public.tasks WHERE id = task_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'task_not_found';
  END IF;

  IF v_row.created_by = v_user THEN
    RAISE EXCEPTION 'cannot_accept_own_task';
  END IF;

  IF v_row.current_status <> 'accepted' THEN
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

GRANT EXECUTE ON FUNCTION public.accept_task(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.accept_task(uuid) FROM anon;