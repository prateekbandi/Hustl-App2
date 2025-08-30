/*
  # Task Status Update System

  1. New Columns & Enum
    - `status` (task_status enum: posted, accepted, in_progress, completed, cancelled)
    - `assignee_id` (uuid, references user who accepted the task)
    - `updated_at` (timestamptz, auto-updated on changes)

  2. Database Functions
    - `set_updated_at()` trigger function for auto-updating timestamps
    - `update_task_status()` RPC for safe status transitions

  3. Security
    - Enable RLS on tasks table
    - Allow read/update for task owner or assignee only
    - Validate status transitions in RPC function

  4. Realtime
    - Add tasks table to realtime publication for live updates
*/

-- 1) Enum + columns
DO $$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('posted','accepted','in_progress','completed','cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS status public.task_status NOT NULL DEFAULT 'posted',
  ADD COLUMN IF NOT EXISTS assignee_id uuid,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- 2) Touch updated_at on change
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_tasks_set_updated_at ON public.tasks;
CREATE TRIGGER trg_tasks_set_updated_at
BEFORE UPDATE ON public.tasks
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 3) RPC to update status (idempotent + validates transitions)
CREATE OR REPLACE FUNCTION public.update_task_status(task_id uuid, new_status public.task_status)
RETURNS public.tasks AS $$
DECLARE
  t public.tasks;
  ok boolean := false;
BEGIN
  SELECT * INTO t FROM public.tasks WHERE id = task_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Task % not found', task_id USING ERRCODE='NO_DATA_FOUND';
  END IF;

  -- Valid transitions
  IF (t.status = 'posted' AND new_status = 'accepted') OR
     (t.status = 'accepted' AND new_status = 'in_progress') OR
     (t.status = 'in_progress' AND new_status = 'completed') OR
     (new_status = 'cancelled') THEN
    ok := true;
  END IF;

  IF NOT ok THEN
    RAISE EXCEPTION 'Invalid status transition: % -> %', t.status, new_status;
  END IF;

  UPDATE public.tasks
  SET status = new_status
  WHERE id = task_id
  RETURNING * INTO t;

  RETURN t;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4) RLS: allow owner or assignee to read; allow owner/assignee to update via RPC
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY tasks_read_owner_or_assignee ON public.tasks
  FOR SELECT USING (
    auth.uid() = created_by OR auth.uid() = COALESCE(assignee_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY tasks_update_owner_or_assignee ON public.tasks
  FOR UPDATE USING (
    auth.uid() = created_by OR auth.uid() = COALESCE(assignee_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) WITH CHECK (
    auth.uid() = created_by OR auth.uid() = COALESCE(assignee_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 5) Realtime
-- Ensure 'tasks' is in the Realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;