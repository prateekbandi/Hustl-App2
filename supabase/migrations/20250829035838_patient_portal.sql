/*
  # Fix accept_task function signature clash

  1. Drop conflicting function overloads
  2. Create clean single-parameter RPC function
  3. Add backward compatibility wrapper
  4. Ensure proper permissions

  This resolves the PostgREST function signature conflict and ensures
  atomic task acceptance with proper concurrency control.
*/

-- 1) Drop old function overloads that conflict
DROP FUNCTION IF EXISTS public.accept_task(uuid);
DROP FUNCTION IF EXISTS public.accept_task(uuid, uuid);
DROP FUNCTION IF EXISTS public.accept_task(p_task_id uuid);
DROP FUNCTION IF EXISTS public.accept_task(p_task_id uuid, p_user_id uuid);

-- 2) Create the definitive RPC (single param)
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

  -- lock row to avoid double-accept
  SELECT * INTO v_row FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'task_not_found';
  END IF;

  IF v_row.created_by = v_user THEN
    RAISE EXCEPTION 'cannot_accept_own_task';
  END IF;

  IF v_row.current_status <> 'accepted' OR v_row.status <> 'open' THEN
    RAISE EXCEPTION 'task_not_posted';
  END IF;

  UPDATE public.tasks
  SET current_status = 'accepted'::task_current_status,
      status = 'accepted'::task_status,
      accepted_by = v_user,
      accepted_at = now(),
      updated_at = now()
  WHERE id = p_task_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

-- 3) Permissions
GRANT EXECUTE ON FUNCTION public.accept_task(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.accept_task(uuid) FROM anon;

-- 4) Back-compat wrapper for any 2-arg calls
CREATE OR REPLACE FUNCTION public.accept_task(p_task_id uuid, _unused uuid)
RETURNS public.tasks
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.accept_task(p_task_id);
$$;

GRANT EXECUTE ON FUNCTION public.accept_task(uuid, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.accept_task(uuid, uuid) FROM anon;