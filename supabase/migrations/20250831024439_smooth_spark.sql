/*
  # Enable Update Status Flow

  1. Schema Updates
    - Add task_phase enum if missing
    - Add phase column to tasks table
    - Add assignee_id column if missing
    - Add updated_at trigger

  2. RPC Functions
    - Drop and recreate update_task_phase with correct parameter names
    - Category-aware phase transitions
    - Forward-only validation

  3. Security
    - Enable RLS on tasks table
    - Add policies for owner/assignee access
    - Add realtime publication
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
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Drop existing trigger if it exists, then recreate
DROP TRIGGER IF EXISTS trg_tasks_set_updated_at ON public.tasks;
CREATE TRIGGER trg_tasks_set_updated_at
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- Drop existing update_task_phase function by signature
DROP FUNCTION IF EXISTS public.update_task_phase(uuid, public.task_phase);
DROP FUNCTION IF EXISTS public.update_task_phase(p_task_id uuid, p_new_phase public.task_phase);

-- Create the update_task_phase RPC with correct parameter names
CREATE OR REPLACE FUNCTION public.update_task_phase(
  task_id uuid,
  new_phase public.task_phase
)
RETURNS public.tasks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

  -- Check if task is already completed or cancelled
  IF task_row.status IN ('completed', 'cancelled') THEN
    RAISE EXCEPTION 'task_already_completed';
  END IF;

  -- Validate phase transition based on category
  IF task_row.category = 'food' AND (task_row.store ILIKE '%delivery%' OR task_row.category = 'food_delivery') THEN
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

  -- Map phase to status
  CASE new_phase
    WHEN 'started', 'on_the_way' THEN
      new_status := 'accepted'::public.task_status; -- Keep as accepted, use phase for granular tracking
    WHEN 'delivered', 'completed' THEN
      new_status := 'completed'::public.task_status;
    ELSE
      new_status := task_row.status; -- Keep current status
  END CASE;

  -- Update the task
  UPDATE public.tasks
  SET 
    phase = new_phase,
    status = new_status,
    updated_at = now()
  WHERE id = task_id;

  -- Return updated row
  SELECT * INTO task_row FROM public.tasks WHERE id = task_id;
  RETURN task_row;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.update_task_phase(uuid, public.task_phase) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_task_phase(uuid, public.task_phase) TO service_role;

-- Enable RLS on tasks table
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "tasks_read_owner_or_assignee" ON public.tasks;
DROP POLICY IF EXISTS "tasks_update_owner_or_assignee" ON public.tasks;

-- Create RLS policies for owner/assignee access
CREATE POLICY "tasks_read_owner_or_assignee"
  ON public.tasks
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = created_by OR 
    auth.uid() = COALESCE(assignee_id, accepted_by)
  );

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
    -- Publication might not exist or other issues, continue silently
    NULL;
END $$;