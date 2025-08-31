/*
  # Add Task Phase System

  1. New Enums
    - `task_phase` enum for tracking task progress phases
  
  2. New Tables
    - `task_progress` for logging phase changes with actor tracking
  
  3. Schema Changes
    - Add `phase` column to tasks table
    - Add `assignee_id` column to tasks table for proper tracking
  
  4. RPC Functions
    - `update_task_phase()` for category-aware phase transitions
    - `get_task_progress_history()` for viewing phase change history
  
  5. Security
    - Enable RLS on task_progress table
    - Add policies for owner/assignee access only
    - Update existing task policies to use auth.uid()
*/

-- Create task_phase enum
DO $$ BEGIN
  CREATE TYPE task_phase AS ENUM ('none', 'started', 'picked_up', 'on_the_way', 'delivered', 'completed');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- Add phase column to tasks if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tasks' AND column_name = 'phase'
  ) THEN
    ALTER TABLE tasks ADD COLUMN phase task_phase NOT NULL DEFAULT 'none';
  END IF;
END $$;

-- Add assignee_id column to tasks if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tasks' AND column_name = 'assignee_id'
  ) THEN
    ALTER TABLE tasks ADD COLUMN assignee_id uuid;
  END IF;
END $$;

-- Create task_progress table if not exists
CREATE TABLE IF NOT EXISTS task_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  phase task_phase NOT NULL,
  actor_id uuid NOT NULL,
  note text DEFAULT '',
  created_at timestamptz DEFAULT now()
);

-- Add indexes for task_progress
CREATE INDEX IF NOT EXISTS idx_task_progress_task_id ON task_progress(task_id);
CREATE INDEX IF NOT EXISTS idx_task_progress_created_at ON task_progress(created_at DESC);

-- Enable RLS on task_progress
ALTER TABLE task_progress ENABLE ROW LEVEL SECURITY;

-- RLS policies for task_progress
CREATE POLICY "task_progress_insert_for_task_members"
  ON task_progress
  FOR INSERT
  TO public
  WITH CHECK (
    actor_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM tasks t
      WHERE t.id = task_progress.task_id
      AND (t.created_by = auth.uid() OR t.assignee_id = auth.uid())
    )
  );

CREATE POLICY "task_progress_select_for_task_members"
  ON task_progress
  FOR SELECT
  TO public
  USING (
    EXISTS (
      SELECT 1 FROM tasks t
      WHERE t.id = task_progress.task_id
      AND (t.created_by = auth.uid() OR t.assignee_id = auth.uid())
    )
  );

-- Update task_phase function with category-aware transitions
CREATE OR REPLACE FUNCTION update_task_phase(
  p_task_id uuid,
  p_new_phase task_phase
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_task tasks%ROWTYPE;
  v_current_phase task_phase;
  v_category text;
  v_allowed_transitions task_phase[];
  v_new_status task_status;
BEGIN
  -- Get current task
  SELECT * INTO v_task
  FROM tasks
  WHERE id = p_task_id;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'task_not_found');
  END IF;

  -- Check authorization
  IF auth.uid() IS NULL THEN
    RETURN json_build_object('error', 'not_authenticated');
  END IF;

  IF auth.uid() != v_task.created_by AND auth.uid() != v_task.assignee_id THEN
    RETURN json_build_object('error', 'not_authorized');
  END IF;

  -- Check if task is in a final state
  IF v_task.status IN ('completed', 'cancelled') THEN
    RETURN json_build_object('error', 'task_already_final');
  END IF;

  v_current_phase := v_task.phase;
  v_category := v_task.category;

  -- Define allowed transitions based on category
  IF v_category = 'food' AND v_task.store ILIKE '%delivery%' THEN
    -- Food Delivery: none → started → on_the_way → delivered → completed
    v_allowed_transitions := ARRAY['none', 'started', 'on_the_way', 'delivered', 'completed']::task_phase[];
  ELSIF v_category = 'food' THEN
    -- Food Pickup: none → started → picked_up → completed
    v_allowed_transitions := ARRAY['none', 'started', 'picked_up', 'completed']::task_phase[];
  ELSE
    -- Default (workout, etc.): none → started → completed
    v_allowed_transitions := ARRAY['none', 'started', 'completed']::task_phase[];
  END IF;

  -- Validate transition
  DECLARE
    v_current_index int;
    v_new_index int;
  BEGIN
    SELECT array_position(v_allowed_transitions, v_current_phase) INTO v_current_index;
    SELECT array_position(v_allowed_transitions, p_new_phase) INTO v_new_index;

    IF v_current_index IS NULL OR v_new_index IS NULL THEN
      RETURN json_build_object('error', 'invalid_phase');
    END IF;

    -- Only allow forward transitions (or same phase)
    IF v_new_index <= v_current_index THEN
      RETURN json_build_object('error', 'invalid_phase_transition');
    END IF;

    -- Don't allow skipping phases (except for start & complete)
    IF v_new_index > v_current_index + 1 AND NOT (v_current_phase = 'none' AND p_new_phase = 'completed') THEN
      RETURN json_build_object('error', 'cannot_skip_phases');
    END IF;
  END;

  -- Determine new status
  IF p_new_phase = 'completed' THEN
    v_new_status := 'completed';
  ELSIF p_new_phase = 'none' THEN
    v_new_status := v_task.status; -- Keep current status
  ELSE
    v_new_status := 'accepted'; -- In progress
  END IF;

  -- Update task
  UPDATE tasks
  SET 
    phase = p_new_phase,
    status = v_new_status,
    updated_at = now()
  WHERE id = p_task_id;

  -- Log progress
  INSERT INTO task_progress (task_id, phase, actor_id)
  VALUES (p_task_id, p_new_phase, auth.uid());

  -- Return updated task
  SELECT * INTO v_task FROM tasks WHERE id = p_task_id;
  
  RETURN json_build_object(
    'success', true,
    'task', row_to_json(v_task)
  );
END;
$$;

-- Get task progress history function
CREATE OR REPLACE FUNCTION get_task_progress_history(
  p_task_id uuid
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_task tasks%ROWTYPE;
  v_progress_data json;
BEGIN
  -- Get task and check authorization
  SELECT * INTO v_task FROM tasks WHERE id = p_task_id;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'task_not_found');
  END IF;

  IF auth.uid() IS NULL THEN
    RETURN json_build_object('error', 'not_authenticated');
  END IF;

  IF auth.uid() != v_task.created_by AND auth.uid() != v_task.assignee_id THEN
    RETURN json_build_object('error', 'not_authorized');
  END IF;

  -- Get progress history with actor names
  SELECT json_agg(
    json_build_object(
      'id', tp.id,
      'phase', tp.phase,
      'actor_name', COALESCE(p.full_name, p.username, 'User'),
      'note', tp.note,
      'created_at', tp.created_at
    ) ORDER BY tp.created_at DESC
  ) INTO v_progress_data
  FROM task_progress tp
  LEFT JOIN profiles p ON p.id = tp.actor_id
  WHERE tp.task_id = p_task_id;

  RETURN json_build_object(
    'success', true,
    'data', COALESCE(v_progress_data, '[]'::json)
  );
END;
$$;