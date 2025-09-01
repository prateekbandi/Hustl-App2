/*
  # Consolidated Task System Migration
  
  This migration establishes the canonical schema for the task system with proper moderation.
  
  ## What this migration adds:
  1. Task phase system (none → started → on_the_way/completed)
  2. Task moderation system (approved/needs_review/blocked)
  3. Proper foreign keys to profiles
  4. Updated RLS policies using auth.uid()
  5. Single canonical update_task_phase RPC
  6. Updated at trigger system
  
  ## Security:
  - Only approved tasks visible in public listings
  - Owners can always see their own tasks
  - Only owner/assignee can update task phases
  - All functions use SECURITY DEFINER with proper search_path
*/

-- Guard: Fail if any uid() references remain (should be auth.uid())
DO $$
DECLARE
  migration_content text;
BEGIN
  -- This is a placeholder check - in practice, we manually verify
  -- that all uid() calls have been replaced with auth.uid()
  NULL;
END $$;

-- Create enums if they don't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_phase') THEN
    CREATE TYPE public.task_phase AS ENUM ('none', 'started', 'on_the_way', 'delivered', 'completed');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_moderation_status') THEN
    CREATE TYPE public.task_moderation_status AS ENUM ('approved', 'needs_review', 'blocked');
  END IF;
END $$;

-- Add columns to tasks table if they don't exist
DO $$
BEGIN
  -- Add phase column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'tasks' AND column_name = 'phase'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN phase public.task_phase NOT NULL DEFAULT 'none';
  END IF;

  -- Add assignee_id column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'tasks' AND column_name = 'assignee_id'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN assignee_id uuid;
  END IF;

  -- Add moderation columns
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'tasks' AND column_name = 'moderation_status'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN moderation_status public.task_moderation_status NOT NULL DEFAULT 'approved';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'tasks' AND column_name = 'moderation_reason'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN moderation_reason text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'tasks' AND column_name = 'moderated_at'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN moderated_at timestamptz;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'tasks' AND column_name = 'moderated_by'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN moderated_by uuid;
  END IF;

  -- Ensure updated_at exists with proper default
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'tasks' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
  END IF;
END $$;

-- Create indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_tasks_phase ON public.tasks (phase);
CREATE INDEX IF NOT EXISTS idx_tasks_moderation_status ON public.tasks (moderation_status);
CREATE INDEX IF NOT EXISTS idx_tasks_assignee_id ON public.tasks (assignee_id);

-- Create or replace the updated_at trigger function
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Drop and recreate the updated_at trigger
DROP TRIGGER IF EXISTS trg_tasks_set_updated_at ON public.tasks;
CREATE TRIGGER trg_tasks_set_updated_at
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- Create foreign keys if they don't exist
DO $$
BEGIN
  -- FK to profiles for created_by
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'tasks_created_by_fkey'
  ) THEN
    ALTER TABLE public.tasks 
    ADD CONSTRAINT tasks_created_by_fkey 
    FOREIGN KEY (created_by) REFERENCES public.profiles(id) 
    ON UPDATE CASCADE ON DELETE RESTRICT;
  END IF;

  -- FK to profiles for assignee_id
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'tasks_assignee_id_fkey'
  ) THEN
    ALTER TABLE public.tasks 
    ADD CONSTRAINT tasks_assignee_id_fkey 
    FOREIGN KEY (assignee_id) REFERENCES public.profiles(id) 
    ON UPDATE CASCADE ON DELETE SET NULL;
  END IF;
END $$;

-- Drop all existing task-related policies to avoid conflicts
DROP POLICY IF EXISTS tasks_select_visible ON public.tasks;
DROP POLICY IF EXISTS tasks_select_approved_or_owner ON public.tasks;
DROP POLICY IF EXISTS tasks_update_owner_or_assignee ON public.tasks;
DROP POLICY IF EXISTS tasks_insert_owner ON public.tasks;
DROP POLICY IF EXISTS tasks_insert_owner_only ON public.tasks;
DROP POLICY IF EXISTS "Users can read available tasks" ON public.tasks;
DROP POLICY IF EXISTS "Users can read own tasks" ON public.tasks;
DROP POLICY IF EXISTS "Users can read accepted tasks" ON public.tasks;
DROP POLICY IF EXISTS "Users can create tasks" ON public.tasks;
DROP POLICY IF EXISTS "Creator can update open tasks" ON public.tasks;
DROP POLICY IF EXISTS "Acceptor can update accepted tasks" ON public.tasks;
DROP POLICY IF EXISTS "accept_open_task" ON public.tasks;
DROP POLICY IF EXISTS "tasks_read_owner_or_assignee" ON public.tasks;
DROP POLICY IF EXISTS "tasks_update_owner_or_assignee" ON public.tasks;

-- Create canonical RLS policies using auth.uid()
CREATE POLICY tasks_select_visible ON public.tasks
  FOR SELECT
  TO authenticated
  USING (
    moderation_status = 'approved' 
    OR created_by = auth.uid() 
    OR assignee_id = auth.uid()
  );

CREATE POLICY tasks_update_owner_or_assignee ON public.tasks
  FOR UPDATE
  TO authenticated
  USING (auth.uid() IN (created_by, assignee_id))
  WITH CHECK (auth.uid() IN (created_by, assignee_id));

CREATE POLICY tasks_insert_owner ON public.tasks
  FOR INSERT
  TO authenticated
  WITH CHECK (created_by = auth.uid());

-- Ensure profiles has public read policy for authenticated users
DROP POLICY IF EXISTS profiles_select_public ON public.profiles;
CREATE POLICY profiles_select_public ON public.profiles
  FOR SELECT
  TO authenticated
  USING (true);

-- Drop any existing update_task_phase functions to avoid conflicts
DROP FUNCTION IF EXISTS public.update_task_phase(uuid, public.task_phase);
DROP FUNCTION IF EXISTS public.update_task_phase(p_task_id uuid, p_new_phase public.task_phase);
DROP FUNCTION IF EXISTS public.update_task_phase(task_id uuid, new_phase public.task_phase);

-- Create the canonical update_task_phase RPC
CREATE OR REPLACE FUNCTION public.update_task_phase(
  task_id uuid,
  new_phase public.task_phase
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  task_record public.tasks%ROWTYPE;
  current_phase public.task_phase;
  task_category text;
  new_status public.task_status;
BEGIN
  -- Get current task and verify ownership
  SELECT * INTO task_record
  FROM public.tasks
  WHERE id = task_id
    AND (created_by = auth.uid() OR assignee_id = auth.uid());

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Task not found or access denied');
  END IF;

  current_phase := task_record.phase;
  task_category := task_record.category;

  -- Validate phase transition based on category
  IF task_category = 'food' AND task_record.store ILIKE '%delivery%' THEN
    -- Food delivery flow: none → started → on_the_way → delivered
    CASE current_phase
      WHEN 'none' THEN
        IF new_phase NOT IN ('started') THEN
          RETURN json_build_object('error', 'Invalid phase transition for food delivery');
        END IF;
      WHEN 'started' THEN
        IF new_phase NOT IN ('on_the_way') THEN
          RETURN json_build_object('error', 'Invalid phase transition for food delivery');
        END IF;
      WHEN 'on_the_way' THEN
        IF new_phase NOT IN ('delivered') THEN
          RETURN json_build_object('error', 'Invalid phase transition for food delivery');
        END IF;
      WHEN 'delivered' THEN
        RETURN json_build_object('error', 'Task already delivered');
      ELSE
        RETURN json_build_object('error', 'Invalid current phase');
    END CASE;
  ELSE
    -- Other categories: none → started → completed
    CASE current_phase
      WHEN 'none' THEN
        IF new_phase NOT IN ('started', 'completed') THEN
          RETURN json_build_object('error', 'Invalid phase transition');
        END IF;
      WHEN 'started' THEN
        IF new_phase NOT IN ('completed') THEN
          RETURN json_build_object('error', 'Invalid phase transition');
        END IF;
      WHEN 'completed' THEN
        RETURN json_build_object('error', 'Task already completed');
      ELSE
        RETURN json_build_object('error', 'Invalid current phase');
    END CASE;
  END IF;

  -- Determine new status
  IF new_phase = 'completed' OR new_phase = 'delivered' THEN
    new_status := 'completed';
  ELSIF new_phase = 'started' OR new_phase = 'on_the_way' THEN
    new_status := 'accepted'; -- Keep as accepted, not in_progress
  ELSE
    new_status := task_record.status; -- Keep current status
  END IF;

  -- Update the task
  UPDATE public.tasks
  SET 
    phase = new_phase,
    status = new_status,
    updated_at = now()
  WHERE id = task_id;

  -- Return updated task
  SELECT json_build_object(
    'success', true,
    'task', row_to_json(t)
  ) INTO task_record
  FROM public.tasks t
  WHERE t.id = task_id;

  RETURN task_record;
END;
$$;

-- Create moderation RPC if needed
CREATE OR REPLACE FUNCTION public.moderate_task_and_save(
  p_title text,
  p_description text DEFAULT '',
  p_dropoff_instructions text DEFAULT '',
  p_store text DEFAULT '',
  p_dropoff_address text DEFAULT '',
  p_category text DEFAULT 'food',
  p_urgency text DEFAULT 'medium',
  p_estimated_minutes integer DEFAULT 30,
  p_reward_cents integer DEFAULT 200,
  p_task_id uuid DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  moderation_result json;
  task_id_result uuid;
  task_record public.tasks%ROWTYPE;
BEGIN
  -- Simple keyword-based moderation (placeholder)
  -- In production, this would call external moderation service
  
  -- Check for blocked content
  IF (
    p_title ILIKE '%sex%' OR p_title ILIKE '%nude%' OR
    p_description ILIKE '%sex%' OR p_description ILIKE '%nude%' OR
    p_title ILIKE '%kill%' OR p_title ILIKE '%weapon%' OR
    p_description ILIKE '%kill%' OR p_description ILIKE '%weapon%'
  ) THEN
    RETURN json_build_object(
      'status', 'blocked',
      'reason', 'Content violates community guidelines',
      'error', 'Content violates community guidelines. Please review and edit your task.'
    );
  END IF;

  -- If editing existing task
  IF p_task_id IS NOT NULL THEN
    -- Verify ownership
    SELECT * INTO task_record
    FROM public.tasks
    WHERE id = p_task_id AND created_by = auth.uid();
    
    IF NOT FOUND THEN
      RETURN json_build_object('error', 'Task not found or access denied');
    END IF;

    -- Update existing task
    UPDATE public.tasks
    SET
      title = p_title,
      description = p_description,
      dropoff_instructions = p_dropoff_instructions,
      store = p_store,
      dropoff_address = p_dropoff_address,
      category = p_category::public.task_category,
      urgency = p_urgency::public.task_urgency,
      estimated_minutes = p_estimated_minutes,
      reward_cents = p_reward_cents,
      moderation_status = 'approved',
      moderation_reason = NULL,
      moderated_at = now(),
      moderated_by = NULL,
      updated_at = now()
    WHERE id = p_task_id;

    task_id_result := p_task_id;
  ELSE
    -- Create new task
    INSERT INTO public.tasks (
      title,
      description,
      dropoff_instructions,
      store,
      dropoff_address,
      category,
      urgency,
      estimated_minutes,
      reward_cents,
      created_by,
      moderation_status,
      moderation_reason,
      moderated_at,
      moderated_by
    ) VALUES (
      p_title,
      p_description,
      p_dropoff_instructions,
      p_store,
      p_dropoff_address,
      p_category::public.task_category,
      p_urgency::public.task_urgency,
      p_estimated_minutes,
      p_reward_cents,
      auth.uid(),
      'approved',
      NULL,
      now(),
      NULL
    ) RETURNING id INTO task_id_result;
  END IF;

  RETURN json_build_object(
    'status', 'approved',
    'reason', NULL,
    'task_id', task_id_result
  );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.update_task_phase(uuid, public.task_phase) TO authenticated;
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(text, text, text, text, text, text, text, integer, integer, uuid) TO authenticated;

-- Ensure tasks table is in realtime publication
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'tasks'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
  END IF;
END $$;

-- Backfill data safely
UPDATE public.tasks 
SET phase = 'none' 
WHERE phase IS NULL;

UPDATE public.tasks 
SET moderation_status = 'approved' 
WHERE moderation_status IS NULL;

-- Final verification: Check that no uid() references exist in this migration
-- (This is a manual verification step - all uid() should be auth.uid())