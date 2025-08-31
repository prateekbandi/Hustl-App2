/*
  # Add Task Conversations System

  1. New Tables
    - `task_progress` - Event log for task phase changes
      - `id` (uuid, primary key)
      - `task_id` (uuid, foreign key to tasks)
      - `phase` (task_phase enum)
      - `actor_id` (uuid, foreign key to profiles)
      - `note` (text, optional)
      - `created_at` (timestamp)

  2. New Columns
    - `tasks.phase` - Current task phase (task_phase enum)

  3. New Enums
    - `task_phase` - none, started, picked_up, on_the_way, completed

  4. RPC Functions
    - `update_task_phase()` - Updates task phase with validation
    - `get_task_progress_history()` - Gets phase change history
    - `ensure_room_for_task()` - Creates chat room for task if needed
    - `get_chat_participant_profile()` - Gets other participant's profile

  5. Security
    - Enable RLS on all new tables
    - Add policies for task participants only
    - Update existing chat policies
*/

-- Create task_phase enum
DO $$ BEGIN
  CREATE TYPE task_phase AS ENUM ('none', 'started', 'picked_up', 'on_the_way', 'completed');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- Add phase column to tasks
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
    ALTER TABLE tasks ADD COLUMN assignee_id uuid REFERENCES profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Create task_progress table
CREATE TABLE IF NOT EXISTS task_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  phase task_phase NOT NULL,
  actor_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  note text DEFAULT '',
  created_at timestamptz DEFAULT now()
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_task_progress_task_id ON task_progress(task_id);
CREATE INDEX IF NOT EXISTS idx_task_progress_created_at ON task_progress(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tasks_phase ON tasks(phase);

-- Enable RLS
ALTER TABLE task_progress ENABLE ROW LEVEL SECURITY;

-- RLS Policies for task_progress
CREATE POLICY "task_progress_select_for_task_members"
  ON task_progress FOR SELECT
  TO public
  USING (
    EXISTS (
      SELECT 1 FROM tasks t
      WHERE t.id = task_progress.task_id
      AND (t.created_by = uid() OR t.assignee_id = uid())
    )
  );

CREATE POLICY "task_progress_insert_for_task_members"
  ON task_progress FOR INSERT
  TO public
  WITH CHECK (
    actor_id = uid() AND
    EXISTS (
      SELECT 1 FROM tasks t
      WHERE t.id = task_progress.task_id
      AND (t.created_by = uid() OR t.assignee_id = uid())
    )
  );

-- Update task policies to include assignee_id
DROP POLICY IF EXISTS "tasks_read_owner_or_assignee" ON tasks;
CREATE POLICY "tasks_read_owner_or_assignee"
  ON tasks FOR SELECT
  TO public
  USING (
    uid() = created_by OR 
    uid() = COALESCE(assignee_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

DROP POLICY IF EXISTS "tasks_update_owner_or_assignee" ON tasks;
CREATE POLICY "tasks_update_owner_or_assignee"
  ON tasks FOR UPDATE
  TO public
  USING (
    uid() = created_by OR 
    uid() = COALESCE(assignee_id, '00000000-0000-0000-0000-000000000000'::uuid)
  )
  WITH CHECK (
    uid() = created_by OR 
    uid() = COALESCE(assignee_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

-- RPC: Update task phase with category validation
CREATE OR REPLACE FUNCTION update_task_phase(
  p_task_id uuid,
  p_new_phase task_phase
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_task tasks%ROWTYPE;
  v_current_phase task_phase;
  v_valid_transitions task_phase[];
  v_new_status task_status;
BEGIN
  -- Get current task
  SELECT * INTO v_task FROM tasks WHERE id = p_task_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Task not found');
  END IF;
  
  -- Check authorization
  IF v_task.created_by != uid() AND COALESCE(v_task.assignee_id, '00000000-0000-0000-0000-000000000000'::uuid) != uid() THEN
    RETURN json_build_object('error', 'Not authorized to update this task');
  END IF;
  
  -- Check if task is in a final state
  IF v_task.status IN ('completed', 'cancelled') THEN
    RETURN json_build_object('error', 'Cannot update completed or cancelled tasks');
  END IF;
  
  v_current_phase := COALESCE(v_task.phase, 'none');
  
  -- Define valid transitions based on category
  CASE v_task.category
    WHEN 'food' THEN
      v_valid_transitions := ARRAY['none', 'started', 'picked_up', 'completed'];
    WHEN 'grocery' THEN
      v_valid_transitions := ARRAY['none', 'started', 'on_the_way', 'completed'];
    ELSE
      v_valid_transitions := ARRAY['none', 'started', 'completed'];
  END CASE;
  
  -- Validate transition
  IF p_new_phase = ANY(v_valid_transitions) THEN
    -- Check if it's a valid forward transition
    IF array_position(v_valid_transitions, p_new_phase) <= array_position(v_valid_transitions, v_current_phase) THEN
      RETURN json_build_object('error', 'Invalid phase transition');
    END IF;
  ELSE
    RETURN json_build_object('error', 'Invalid phase for this category');
  END IF;
  
  -- Determine new status
  CASE p_new_phase
    WHEN 'completed' THEN v_new_status := 'completed';
    WHEN 'none' THEN v_new_status := v_task.status; -- Keep current status
    ELSE v_new_status := 'accepted'; -- In progress
  END CASE;
  
  -- Update task
  UPDATE tasks 
  SET 
    phase = p_new_phase,
    status = v_new_status,
    updated_at = now()
  WHERE id = p_task_id;
  
  -- Log progress
  INSERT INTO task_progress (task_id, phase, actor_id)
  VALUES (p_task_id, p_new_phase, uid());
  
  -- Return updated task
  SELECT json_build_object(
    'success', true,
    'task', row_to_json(t)
  ) INTO v_task
  FROM tasks t WHERE t.id = p_task_id;
  
  RETURN v_task;
END;
$$;

-- RPC: Get task progress history
CREATE OR REPLACE FUNCTION get_task_progress_history(p_task_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result json;
BEGIN
  -- Check if user can access this task
  IF NOT EXISTS (
    SELECT 1 FROM tasks 
    WHERE id = p_task_id 
    AND (created_by = uid() OR assignee_id = uid())
  ) THEN
    RETURN json_build_object('error', 'Not authorized');
  END IF;
  
  SELECT json_agg(
    json_build_object(
      'id', tp.id,
      'phase', tp.phase,
      'actor_name', COALESCE(p.full_name, p.username, 'User'),
      'note', tp.note,
      'created_at', tp.created_at
    ) ORDER BY tp.created_at DESC
  ) INTO v_result
  FROM task_progress tp
  JOIN profiles p ON p.id = tp.actor_id
  WHERE tp.task_id = p_task_id;
  
  RETURN json_build_object('data', COALESCE(v_result, '[]'::json));
END;
$$;

-- RPC: Ensure chat room exists for task
CREATE OR REPLACE FUNCTION ensure_room_for_task(p_task_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_task tasks%ROWTYPE;
  v_room_id uuid;
  v_result json;
BEGIN
  -- Get task details
  SELECT * INTO v_task FROM tasks WHERE id = p_task_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Task not found');
  END IF;
  
  -- Check authorization (owner or assignee)
  IF v_task.created_by != uid() AND COALESCE(v_task.assignee_id, '00000000-0000-0000-0000-000000000000'::uuid) != uid() THEN
    RETURN json_build_object('error', 'Not authorized');
  END IF;
  
  -- Check if room already exists
  SELECT id INTO v_room_id FROM chat_rooms WHERE task_id = p_task_id;
  
  IF FOUND THEN
    SELECT row_to_json(cr) INTO v_result FROM chat_rooms cr WHERE cr.id = v_room_id;
    RETURN v_result;
  END IF;
  
  -- Create new room
  INSERT INTO chat_rooms (task_id) VALUES (p_task_id) RETURNING id INTO v_room_id;
  
  -- Add participants (owner and assignee)
  INSERT INTO chat_members (room_id, user_id) VALUES 
    (v_room_id, v_task.created_by),
    (v_room_id, v_task.assignee_id)
  ON CONFLICT (room_id, user_id) DO NOTHING;
  
  -- Return new room
  SELECT row_to_json(cr) INTO v_result FROM chat_rooms cr WHERE cr.id = v_room_id;
  RETURN v_result;
END;
$$;

-- RPC: Get chat participant profile (other user in 1:1 chat)
CREATE OR REPLACE FUNCTION get_chat_participant_profile(
  p_room_id uuid,
  p_current_user_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result json;
BEGIN
  -- Check if current user is a member of this room
  IF NOT EXISTS (
    SELECT 1 FROM chat_members 
    WHERE room_id = p_room_id AND user_id = p_current_user_id
  ) THEN
    RETURN json_build_object('error', 'Not authorized');
  END IF;
  
  -- Get the other participant's profile
  SELECT json_agg(
    json_build_object(
      'id', p.id,
      'full_name', p.full_name,
      'username', p.username,
      'avatar_url', p.avatar_url,
      'major', p.major,
      'class_year', p.class_year,
      'university', p.university,
      'bio', p.bio,
      'is_verified', p.is_verified,
      'completed_tasks_count', p.completed_tasks_count,
      'response_rate', p.response_rate,
      'last_seen_at', p.last_seen_at,
      'created_at', p.created_at
    )
  ) INTO v_result
  FROM profiles p
  JOIN chat_members cm ON cm.user_id = p.id
  WHERE cm.room_id = p_room_id 
  AND cm.user_id != p_current_user_id;
  
  RETURN COALESCE(v_result, '[]'::json);
END;
$$;

-- RPC: Get chat inbox with unread counts
CREATE OR REPLACE FUNCTION get_chat_inbox()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result json;
BEGIN
  SELECT json_agg(
    json_build_object(
      'room_id', cr.id,
      'task_id', cr.task_id,
      'other_id', other_profile.id,
      'other_name', other_profile.full_name,
      'other_avatar_url', other_profile.avatar_url,
      'other_major', other_profile.major,
      'last_message', cr.last_message,
      'last_message_at', cr.last_message_at,
      'unread_count', COALESCE(cm.unread_count, 0)
    ) ORDER BY cr.last_message_at DESC NULLS LAST
  ) INTO v_result
  FROM chat_rooms cr
  JOIN chat_members cm ON cm.room_id = cr.id AND cm.user_id = uid()
  JOIN chat_members other_cm ON other_cm.room_id = cr.id AND other_cm.user_id != uid()
  JOIN profiles other_profile ON other_profile.id = other_cm.user_id;
  
  RETURN COALESCE(v_result, '[]'::json);
END;
$$;

-- RPC: Mark room as read
CREATE OR REPLACE FUNCTION mark_room_read(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Check if user is a member
  IF NOT EXISTS (
    SELECT 1 FROM chat_members 
    WHERE room_id = p_room_id AND user_id = uid()
  ) THEN
    RETURN;
  END IF;
  
  -- Update unread count and last read timestamp
  UPDATE chat_members 
  SET 
    unread_count = 0,
    last_read_at = now()
  WHERE room_id = p_room_id AND user_id = uid();
END;
$$;

-- Function to update last seen timestamp
CREATE OR REPLACE FUNCTION update_last_seen()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE profiles 
  SET last_seen_at = now()
  WHERE id = uid();
END;
$$;

-- Trigger to update unread counts when messages are inserted
CREATE OR REPLACE FUNCTION trg_after_message()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Update last message info on room
  UPDATE chat_rooms 
  SET 
    last_message = NEW.text,
    last_message_at = NEW.created_at
  WHERE id = NEW.room_id;
  
  -- Increment unread count for all members except sender
  UPDATE chat_members 
  SET unread_count = unread_count + 1
  WHERE room_id = NEW.room_id 
  AND user_id != NEW.sender_id;
  
  RETURN NEW;
END;
$$;

-- Trigger to mark sender as having read their own message
CREATE OR REPLACE FUNCTION trg_message_sender_seen()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Update sender's last_read_at to this message time
  UPDATE chat_members 
  SET last_read_at = NEW.created_at
  WHERE room_id = NEW.room_id 
  AND user_id = NEW.sender_id;
  
  RETURN NEW;
END;
$$;