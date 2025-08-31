/*
  # Task Phase System for Category-Aware Status Updates

  1. New Types
    - `task_phase` enum for granular progress tracking
    - Maps to category-specific workflows

  2. New Tables
    - `task_progress` - Event log for phase changes
    - Tracks who changed what and when

  3. New Columns
    - `tasks.phase` - Current phase of the task
    - Links to category-specific workflows

  4. Functions
    - `update_task_phase()` - Validates transitions and updates phase
    - `get_task_progress_history()` - Retrieves phase change history

  5. Security
    - RLS policies for task owners and assignees
    - Realtime enabled for live updates

  6. Category Workflows
    - Food Pickup: none → started → picked_up → completed
    - Food Delivery: none → started → on_the_way → completed  
    - Workout Partner: none → started → completed
    - Default: none → started → completed
*/

-- 1) Create task_phase enum
DO $$ BEGIN
  CREATE TYPE public.task_phase AS ENUM ('none', 'started', 'picked_up', 'on_the_way', 'completed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 2) Add phase column to tasks
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tasks' AND column_name = 'phase'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN phase public.task_phase NOT NULL DEFAULT 'none';
  END IF;
END $$;

-- 3) Create task_progress event log table
CREATE TABLE IF NOT EXISTS public.task_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  phase public.task_phase NOT NULL,
  actor_id uuid NOT NULL,
  note text DEFAULT '',
  created_at timestamptz DEFAULT now()
);

-- 4) Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_task_progress_task_id ON public.task_progress(task_id);
CREATE INDEX IF NOT EXISTS idx_task_progress_created_at ON public.task_progress(created_at DESC);

-- 5) RPC function to update task phase with category validation
CREATE OR REPLACE FUNCTION public.update_task_phase(
  p_task_id uuid,
  p_new_phase public.task_phase
)
RETURNS public.tasks AS $$
DECLARE
  task_record public.tasks;
  valid_transition boolean := false;
  new_status public.task_status;
BEGIN
  -- Get current task with row lock
  SELECT * INTO task_record 
  FROM public.tasks 
  WHERE id = p_task_id 
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'task_not_found' USING ERRCODE = 'NO_DATA_FOUND';
  END IF;

  -- Check authorization (owner or assignee)
  IF auth.uid() != task_record.created_by AND auth.uid() != COALESCE(task_record.assignee_id, '00000000-0000-0000-0000-000000000000'::uuid) THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'INSUFFICIENT_PRIVILEGE';
  END IF;

  -- Validate transitions based on category
  CASE task_record.category
    WHEN 'food' THEN
      -- Food Pickup: none → started → picked_up → completed
      IF (task_record.phase = 'none' AND p_new_phase = 'started') OR
         (task_record.phase = 'started' AND p_new_phase = 'picked_up') OR
         (task_record.phase = 'picked_up' AND p_new_phase = 'completed') OR
         (task_record.phase = 'none' AND p_new_phase = 'completed') -- Start & Complete
      THEN
        valid_transition := true;
      END IF;
    
    WHEN 'grocery' THEN
      -- Food Delivery: none → started → on_the_way → completed
      IF (task_record.phase = 'none' AND p_new_phase = 'started') OR
         (task_record.phase = 'started' AND p_new_phase = 'on_the_way') OR
         (task_record.phase = 'on_the_way' AND p_new_phase = 'completed') OR
         (task_record.phase = 'none' AND p_new_phase = 'completed') -- Start & Complete
      THEN
        valid_transition := true;
      END IF;
    
    ELSE
      -- Default (Workout Partner, etc.): none → started → completed
      IF (task_record.phase = 'none' AND p_new_phase = 'started') OR
         (task_record.phase = 'started' AND p_new_phase = 'completed') OR
         (task_record.phase = 'none' AND p_new_phase = 'completed') -- Start & Complete
      THEN
        valid_transition := true;
      END IF;
  END CASE;

  IF NOT valid_transition THEN
    RAISE EXCEPTION 'invalid_phase_transition' USING ERRCODE = 'INVALID_PARAMETER_VALUE';
  END IF;

  -- Determine new status based on phase
  CASE p_new_phase
    WHEN 'none' THEN new_status := 'posted';
    WHEN 'started', 'picked_up', 'on_the_way' THEN new_status := 'in_progress';
    WHEN 'completed' THEN new_status := 'completed';
    ELSE new_status := task_record.status;
  END CASE;

  -- Update task
  UPDATE public.tasks
  SET 
    phase = p_new_phase,
    status = new_status,
    updated_at = now()
  WHERE id = p_task_id
  RETURNING * INTO task_record;

  -- Log the phase change
  INSERT INTO public.task_progress (task_id, phase, actor_id)
  VALUES (p_task_id, p_new_phase, auth.uid());

  RETURN task_record;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6) RPC function to get task progress history
CREATE OR REPLACE FUNCTION public.get_task_progress_history(p_task_id uuid)
RETURNS TABLE(
  id uuid,
  phase public.task_phase,
  actor_name text,
  note text,
  created_at timestamptz
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    tp.id,
    tp.phase,
    COALESCE(p.full_name, p.username, 'User') as actor_name,
    tp.note,
    tp.created_at
  FROM public.task_progress tp
  LEFT JOIN public.profiles p ON p.id = tp.actor_id
  WHERE tp.task_id = p_task_id
  ORDER BY tp.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7) Enable RLS on task_progress
ALTER TABLE public.task_progress ENABLE ROW LEVEL SECURITY;

-- 8) RLS policies for task_progress
CREATE POLICY "task_progress_select_for_task_members" ON public.task_progress
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_progress.task_id
    AND (t.created_by = auth.uid() OR t.assignee_id = auth.uid())
  )
);

CREATE POLICY "task_progress_insert_for_task_members" ON public.task_progress
FOR INSERT WITH CHECK (
  actor_id = auth.uid() AND
  EXISTS (
    SELECT 1 FROM public.tasks t
    WHERE t.id = task_progress.task_id
    AND (t.created_by = auth.uid() OR t.assignee_id = auth.uid())
  )
);

-- 9) Add task_progress to realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.task_progress;