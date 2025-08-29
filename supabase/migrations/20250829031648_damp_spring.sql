/*
  # Fix accept_task RPC function status case

  1. Changes
    - Update accept_task function to use lowercase 'accepted' status
    - Ensure compatibility with task_current_status enum values

  2. Security
    - Maintain existing RLS policies
    - No changes to table structure or permissions
*/

CREATE OR REPLACE FUNCTION accept_task(task_id uuid, user_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  task_record record;
BEGIN
  -- Check if task exists and is available
  SELECT * INTO task_record
  FROM tasks
  WHERE id = task_id
    AND current_status = 'available'
    AND assigned_user_id IS NULL;

  IF NOT FOUND THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Task not found or not available'
    );
  END IF;

  -- Update task with accepted status (lowercase)
  UPDATE tasks
  SET 
    current_status = 'accepted',
    assigned_user_id = user_id,
    accepted_at = now()
  WHERE id = task_id;

  -- Return success response
  RETURN json_build_object(
    'success', true,
    'task_id', task_id,
    'status', 'accepted'
  );
END;
$$;