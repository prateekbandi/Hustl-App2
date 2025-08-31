/*
  # Fix uid() function references

  1. Problem
    - SQL is failing with ERROR: function uid() does not exist
    - In Supabase, the correct helper is auth.uid() (returns the current user's UUID)

  2. Solution
    - Drop and recreate all RLS policies using auth.uid()
    - Update all RPC functions to use auth.uid()
    - Ensure proper authorization checks throughout

  3. Security
    - Maintain existing access patterns
    - Only task owners and assignees can read/update their tasks
    - Only chat participants can access messages
*/

-- Drop existing policies that use uid()
DROP POLICY IF EXISTS "tasks_read_owner_or_assignee" ON tasks;
DROP POLICY IF EXISTS "tasks_update_owner_or_assignee" ON tasks;
DROP POLICY IF EXISTS "accept_open_task" ON tasks;
DROP POLICY IF EXISTS "task_progress_insert_for_task_members" ON task_progress;
DROP POLICY IF EXISTS "task_progress_select_for_task_members" ON task_progress;
DROP POLICY IF EXISTS "cm_select_own" ON chat_members;
DROP POLICY IF EXISTS "cm_update_own" ON chat_members;
DROP POLICY IF EXISTS "msg_read_if_member" ON chat_messages;
DROP POLICY IF EXISTS "msg_send_if_member" ON chat_messages;
DROP POLICY IF EXISTS "cr_select_if_member" ON chat_rooms;
DROP POLICY IF EXISTS "reads_insert_if_member" ON message_reads;
DROP POLICY IF EXISTS "reads_select_if_member" ON message_reads;
DROP POLICY IF EXISTS "rater can insert" ON task_reviews;
DROP POLICY IF EXISTS "rater can update own" ON task_reviews;

-- Recreate policies using auth.uid()
CREATE POLICY "tasks_read_owner_or_assignee"
  ON tasks
  FOR SELECT
  TO public
  USING (
    (auth.uid() = created_by) OR 
    (auth.uid() = COALESCE(assignee_id, '00000000-0000-0000-0000-000000000000'::uuid))
  );

CREATE POLICY "tasks_update_owner_or_assignee"
  ON tasks
  FOR UPDATE
  TO public
  USING (
    (auth.uid() = created_by) OR 
    (auth.uid() = COALESCE(assignee_id, '00000000-0000-0000-0000-000000000000'::uuid))
  )
  WITH CHECK (
    (auth.uid() = created_by) OR 
    (auth.uid() = COALESCE(assignee_id, '00000000-0000-0000-0000-000000000000'::uuid))
  );

CREATE POLICY "accept_open_task"
  ON tasks
  FOR UPDATE
  TO public
  USING ((status = 'open'::task_status) AND (created_by <> auth.uid()))
  WITH CHECK ((assignee_id = auth.uid()) AND (status = 'accepted'::task_status));

CREATE POLICY "task_progress_insert_for_task_members"
  ON task_progress
  FOR INSERT
  TO public
  WITH CHECK (
    (actor_id = auth.uid()) AND 
    (EXISTS (
      SELECT 1 FROM tasks t 
      WHERE t.id = task_progress.task_id 
      AND ((t.created_by = auth.uid()) OR (t.assignee_id = auth.uid()))
    ))
  );

CREATE POLICY "task_progress_select_for_task_members"
  ON task_progress
  FOR SELECT
  TO public
  USING (
    EXISTS (
      SELECT 1 FROM tasks t 
      WHERE t.id = task_progress.task_id 
      AND ((t.created_by = auth.uid()) OR (t.assignee_id = auth.uid()))
    )
  );

CREATE POLICY "cm_select_own"
  ON chat_members
  FOR SELECT
  TO public
  USING (user_id = auth.uid());

CREATE POLICY "cm_update_own"
  ON chat_members
  FOR UPDATE
  TO public
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "msg_read_if_member"
  ON chat_messages
  FOR SELECT
  TO public
  USING (
    EXISTS (
      SELECT 1 FROM chat_members m 
      WHERE m.room_id = chat_messages.room_id 
      AND m.user_id = auth.uid()
    )
  );

CREATE POLICY "msg_send_if_member"
  ON chat_messages
  FOR INSERT
  TO public
  WITH CHECK (
    (sender_id = auth.uid()) AND 
    (EXISTS (
      SELECT 1 FROM chat_members m 
      WHERE m.room_id = chat_messages.room_id 
      AND m.user_id = auth.uid()
    ))
  );

CREATE POLICY "cr_select_if_member"
  ON chat_rooms
  FOR SELECT
  TO public
  USING (
    EXISTS (
      SELECT 1 FROM chat_members m 
      WHERE m.room_id = chat_rooms.id 
      AND m.user_id = auth.uid()
    )
  );

CREATE POLICY "reads_insert_if_member"
  ON message_reads
  FOR INSERT
  TO public
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM chat_messages ms
      JOIN chat_members m ON m.room_id = ms.room_id
      WHERE ms.id = message_reads.message_id 
      AND m.user_id = auth.uid()
    )
  );

CREATE POLICY "reads_select_if_member"
  ON message_reads
  FOR SELECT
  TO public
  USING (
    EXISTS (
      SELECT 1 FROM chat_messages ms
      JOIN chat_members m ON m.room_id = ms.room_id
      WHERE ms.id = message_reads.message_id 
      AND m.user_id = auth.uid()
    )
  );

CREATE POLICY "rater_can_insert"
  ON task_reviews
  FOR INSERT
  TO public
  WITH CHECK (auth.uid() = rater_id);

CREATE POLICY "rater_can_update_own"
  ON task_reviews
  FOR UPDATE
  TO public
  USING (auth.uid() = rater_id);

-- Update RPC functions to use auth.uid()
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
BEGIN
  -- Get current task with auth check
  SELECT * INTO v_task
  FROM tasks
  WHERE id = p_task_id
  AND ((created_by = auth.uid()) OR (assignee_id = auth.uid()));

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Task not found or not authorized');
  END IF;

  v_current_phase := COALESCE(v_task.phase, 'none');
  v_category := v_task.category;

  -- Define allowed transitions based on category
  CASE v_category
    WHEN 'food' THEN
      CASE v_current_phase
        WHEN 'none' THEN v_allowed_transitions := ARRAY['started'];
        WHEN 'started' THEN v_allowed_transitions := ARRAY['picked_up'];
        WHEN 'picked_up' THEN v_allowed_transitions := ARRAY['completed'];
        ELSE v_allowed_transitions := ARRAY[]::task_phase[];
      END CASE;
    WHEN 'grocery' THEN
      CASE v_current_phase
        WHEN 'none' THEN v_allowed_transitions := ARRAY['started'];
        WHEN 'started' THEN v_allowed_transitions := ARRAY['on_the_way'];
        WHEN 'on_the_way' THEN v_allowed_transitions := ARRAY['completed'];
        ELSE v_allowed_transitions := ARRAY[]::task_phase[];
      END CASE;
    ELSE -- Default (workout, coffee, etc.)
      CASE v_current_phase
        WHEN 'none' THEN v_allowed_transitions := ARRAY['started', 'completed'];
        WHEN 'started' THEN v_allowed_transitions := ARRAY['completed'];
        ELSE v_allowed_transitions := ARRAY[]::task_phase[];
      END CASE;
  END CASE;

  -- Check if transition is allowed
  IF NOT (p_new_phase = ANY(v_allowed_transitions)) THEN
    RETURN json_build_object('error', 'Invalid phase transition');
  END IF;

  -- Update task phase and status
  UPDATE tasks
  SET 
    phase = p_new_phase,
    status = CASE 
      WHEN p_new_phase = 'completed' THEN 'completed'::task_status
      WHEN p_new_phase IN ('started', 'picked_up', 'on_the_way') THEN 'accepted'::task_status
      ELSE status
    END,
    updated_at = now()
  WHERE id = p_task_id;

  -- Log the phase change
  INSERT INTO task_progress (task_id, phase, actor_id)
  VALUES (p_task_id, p_new_phase, auth.uid());

  -- Return updated task
  SELECT * INTO v_task FROM tasks WHERE id = p_task_id;
  RETURN json_build_object('success', true, 'task', row_to_json(v_task));
END;
$$;

CREATE OR REPLACE FUNCTION ensure_room_for_task(p_task_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_task tasks%ROWTYPE;
  v_room_id uuid;
  v_owner_id uuid;
  v_assignee_id uuid;
BEGIN
  -- Get task and verify access
  SELECT * INTO v_task
  FROM tasks
  WHERE id = p_task_id
  AND ((created_by = auth.uid()) OR (assignee_id = auth.uid()));

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Task not found or not authorized');
  END IF;

  v_owner_id := v_task.created_by;
  v_assignee_id := v_task.assignee_id;

  -- Check if room already exists
  SELECT id INTO v_room_id
  FROM chat_rooms
  WHERE task_id = p_task_id;

  IF FOUND THEN
    RETURN json_build_object(
      'id', v_room_id,
      'task_id', p_task_id,
      'created_at', now(),
      'last_message', null,
      'last_message_at', null
    );
  END IF;

  -- Create new room
  INSERT INTO chat_rooms (task_id)
  VALUES (p_task_id)
  RETURNING id INTO v_room_id;

  -- Add both participants
  INSERT INTO chat_members (room_id, user_id, unread_count, last_read_at)
  VALUES 
    (v_room_id, v_owner_id, 0, now()),
    (v_room_id, v_assignee_id, 0, now())
  ON CONFLICT (room_id, user_id) DO NOTHING;

  RETURN json_build_object(
    'id', v_room_id,
    'task_id', p_task_id,
    'created_at', now(),
    'last_message', null,
    'last_message_at', null
  );
END;
$$;

CREATE OR REPLACE FUNCTION get_task_progress_history(p_task_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result json;
BEGIN
  -- Verify access to task
  IF NOT EXISTS (
    SELECT 1 FROM tasks 
    WHERE id = p_task_id 
    AND ((created_by = auth.uid()) OR (assignee_id = auth.uid()))
  ) THEN
    RETURN json_build_object('error', 'Task not found or not authorized');
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
  ) INTO v_result
  FROM task_progress tp
  LEFT JOIN profiles p ON p.id = tp.actor_id
  WHERE tp.task_id = p_task_id;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;

CREATE OR REPLACE FUNCTION get_chat_participant_profile(
  p_room_id uuid,
  p_current_user_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_other_user_id uuid;
  v_result json;
BEGIN
  -- Verify current user is a member of this room
  IF NOT EXISTS (
    SELECT 1 FROM chat_members 
    WHERE room_id = p_room_id 
    AND user_id = auth.uid()
  ) THEN
    RETURN json_build_object('error', 'Not authorized to view this chat');
  END IF;

  -- Get the other participant's ID
  SELECT user_id INTO v_other_user_id
  FROM chat_members
  WHERE room_id = p_room_id
  AND user_id != auth.uid()
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Other participant not found');
  END IF;

  -- Get their profile
  SELECT json_build_array(
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
  WHERE p.id = v_other_user_id;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;

CREATE OR REPLACE FUNCTION mark_room_read(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Verify user is a member of this room
  IF NOT EXISTS (
    SELECT 1 FROM chat_members 
    WHERE room_id = p_room_id 
    AND user_id = auth.uid()
  ) THEN
    RETURN;
  END IF;

  -- Update last read timestamp and reset unread count
  UPDATE chat_members
  SET 
    last_read_at = now(),
    unread_count = 0
  WHERE room_id = p_room_id
  AND user_id = auth.uid();

  -- Mark all messages in this room as read by this user
  INSERT INTO message_reads (message_id, user_id, read_at)
  SELECT cm.id, auth.uid(), now()
  FROM chat_messages cm
  WHERE cm.room_id = p_room_id
  AND NOT EXISTS (
    SELECT 1 FROM message_reads mr 
    WHERE mr.message_id = cm.id 
    AND mr.user_id = auth.uid()
  )
  ON CONFLICT (message_id, user_id) DO NOTHING;
END;
$$;

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
      'other_id', other_member.user_id,
      'other_name', other_profile.full_name,
      'other_avatar_url', other_profile.avatar_url,
      'other_major', other_profile.major,
      'last_message', cr.last_message,
      'last_message_at', cr.last_message_at,
      'unread_count', COALESCE(my_member.unread_count, 0)
    ) ORDER BY cr.last_message_at DESC NULLS LAST
  ) INTO v_result
  FROM chat_rooms cr
  JOIN chat_members my_member ON my_member.room_id = cr.id AND my_member.user_id = auth.uid()
  JOIN chat_members other_member ON other_member.room_id = cr.id AND other_member.user_id != auth.uid()
  LEFT JOIN profiles other_profile ON other_profile.id = other_member.user_id;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;

-- Update accept_task function to use auth.uid()
CREATE OR REPLACE FUNCTION accept_task(task_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_task tasks%ROWTYPE;
  v_updated_task tasks%ROWTYPE;
BEGIN
  -- Check if user is authenticated
  IF auth.uid() IS NULL THEN
    RETURN json_build_object('error', 'not_authenticated');
  END IF;

  -- Get the task with row-level security
  SELECT * INTO v_task
  FROM tasks
  WHERE id = task_id
  AND status = 'open'::task_status
  AND created_by != auth.uid();

  IF NOT FOUND THEN
    -- Check if task exists but is not available
    IF EXISTS (SELECT 1 FROM tasks WHERE id = task_id AND created_by = auth.uid()) THEN
      RETURN json_build_object('error', 'cannot_accept_own_task');
    ELSIF EXISTS (SELECT 1 FROM tasks WHERE id = task_id AND status != 'open'::task_status) THEN
      RETURN json_build_object('error', 'task_not_posted');
    ELSE
      RETURN json_build_object('error', 'task_not_found');
    END IF;
  END IF;

  -- Atomic update with race condition protection
  UPDATE tasks
  SET 
    status = 'accepted'::task_status,
    assignee_id = auth.uid(),
    accepted_at = now(),
    updated_at = now()
  WHERE id = task_id
  AND status = 'open'::task_status
  AND created_by != auth.uid()
  RETURNING * INTO v_updated_task;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'task_not_posted');
  END IF;

  RETURN row_to_json(v_updated_task);
END;
$$;