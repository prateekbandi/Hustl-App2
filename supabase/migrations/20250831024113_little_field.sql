/*
  # Enable Update Status Flow

  This migration adds the minimal requirements for the UpdateStatusScreen:
  
  1. New Enums
     - `task_phase` enum with values: none, started, on_the_way, delivered, completed
  
  2. Table Updates
     - Add `phase` column to tasks (default 'none')
     - Add `assignee_id` column if missing
     - Ensure `updated_at` column exists with proper trigger
  
  3. Functions & Triggers
     - `set_updated_at()` function for automatic timestamp updates
     - `update_task_phase()` RPC for category-aware phase transitions
     - Trigger to auto-update `updated_at` on task changes
  
  4. Security
     - RLS policies for owner/assignee access using auth.uid()
     - Realtime publication for live updates
*/

-- Create task_phase enum if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_phase') THEN
    CREATE TYPE public.task_phase AS ENUM ('none', 'started', 'on_the_way', 'delivered', 'completed');
  END IF;
END $$;

-- Add missing columns to tasks table
DO $$
BEGIN
  -- Add phase column if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'phase'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN phase public.task_phase NOT NULL DEFAULT 'none';
  END IF;

  -- Add assignee_id column if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'assignee_id'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN assignee_id uuid;
  END IF;

  -- Ensure updated_at column exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
  END IF;
END $$;

-- Create or replace the updated_at trigger function
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop and recreate the updated_at trigger to ensure it exists
DROP TRIGGER IF EXISTS trg_tasks_set_updated_at ON public.tasks;
CREATE TRIGGER trg_tasks_set_updated_at
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- Create or replace the update_task_phase RPC function
CREATE OR REPLACE FUNCTION public.update_task_phase(
  task_id uuid,
  new_phase public.task_phase
)
RETURNS public.tasks
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  task_row public.tasks;
  current_user_id uuid;
  new_status public.task_status;
BEGIN
  -- Get current user
  current_user_id := auth.uid();
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Lock and fetch the task
  SELECT * INTO task_row
  FROM public.tasks
  WHERE id = task_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'task_not_found';
  END IF;

  -- Check authorization (owner or assignee)
  IF task_row.created_by != current_user_id AND 
     COALESCE(task_row.assignee_id, task_row.accepted_by) != current_user_id THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  -- Validate phase transition based on category
  IF task_row.category = 'food' AND task_row.store ILIKE '%delivery%' THEN
    -- Food Delivery: none → started → on_the_way → delivered
    CASE task_row.phase
      WHEN 'none' THEN
        IF new_phase NOT IN ('started') THEN
          RAISE EXCEPTION 'invalid_phase_transition';
        END IF;
      WHEN 'started' THEN
        IF new_phase NOT IN ('on_the_way') THEN
          RAISE EXCEPTION 'invalid_phase_transition';
        END IF;
      WHEN 'on_the_way' THEN
        IF new_phase NOT IN ('delivered') THEN
          RAISE EXCEPTION 'invalid_phase_transition';
        END IF;
      WHEN 'delivered' THEN
        RAISE EXCEPTION 'task_already_completed';
      WHEN 'completed' THEN
        RAISE EXCEPTION 'task_already_completed';
      ELSE
        RAISE EXCEPTION 'invalid_current_phase';
    END CASE;
  ELSE
    -- All other categories: none → started → completed
    CASE task_row.phase
      WHEN 'none' THEN
        IF new_phase NOT IN ('started', 'completed') THEN
          RAISE EXCEPTION 'invalid_phase_transition';
        END IF;
      WHEN 'started' THEN
        IF new_phase NOT IN ('completed') THEN
          RAISE EXCEPTION 'invalid_phase_transition';
        END IF;
      WHEN 'completed' THEN
        RAISE EXCEPTION 'task_already_completed';
      ELSE
        RAISE EXCEPTION 'invalid_current_phase';
    END CASE;
  END IF;

  -- Determine new status based on phase
  CASE new_phase
    WHEN 'none' THEN
      new_status := 'open';
    WHEN 'started', 'on_the_way' THEN
      new_status := 'accepted';
    WHEN 'delivered', 'completed' THEN
      new_status := 'completed';
    ELSE
      new_status := task_row.status;
  END CASE;

  -- Update the task
  UPDATE public.tasks
  SET 
    phase = new_phase,
    status = new_status,
    updated_at = now()
  WHERE id = task_id;

  -- Return updated task
  SELECT * INTO task_row
  FROM public.tasks
  WHERE id = task_id;

  RETURN task_row;
END;
$$;

-- Enable RLS on tasks if not already enabled
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to recreate with correct auth.uid() usage
DROP POLICY IF EXISTS "tasks_read_owner_or_assignee" ON public.tasks;
DROP POLICY IF EXISTS "tasks_update_owner_or_assignee" ON public.tasks;

-- Create read policy for owner or assignee
CREATE POLICY "tasks_read_owner_or_assignee"
  ON public.tasks
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = created_by OR 
    auth.uid() = COALESCE(assignee_id, accepted_by)
  );

-- Create update policy for owner or assignee
CREATE POLICY "tasks_update_owner_or_assignee"
  ON public.tasks
  FOR UPDATE
  TO authenticated
  USING (
    auth.uid() = created_by OR 
    auth.uid() = COALESCE(assignee_id, accepted_by)
  )
  WITH CHECK (
    auth.uid() = created_by OR 
    auth.uid() = COALESCE(assignee_id, accepted_by)
  );

-- Ensure tasks table is in realtime publication
DO $$
BEGIN
  -- Add tasks to realtime publication if not already present
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'tasks'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
  END IF;
EXCEPTION
  WHEN others THEN
    -- Publication might not exist or other error, continue
    NULL;
END $$;