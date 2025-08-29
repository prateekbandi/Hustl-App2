/*
  # Fix accept_task RPC function enum case and parameters

  1. Changes
    - Fix accept_task function to use correct lowercase enum values
    - Update parameter names to match client calls (p_task_id, p_user_id)
    - Use 'open' status instead of 'available' 
    - Set status to 'accepted' (lowercase) to match enum

  2. Security
    - Maintain existing RLS policies
    - Keep SECURITY DEFINER for proper permissions
*/

CREATE OR REPLACE FUNCTION accept_task(p_task_id uuid, p_user_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  task_record record;
BEGIN
  -- Check if task exists and is available for acceptance
  SELECT * INTO task_record
  FROM tasks
  WHERE id = p_task_id
    AND status = 'open'
    AND accepted_by IS NULL;

  IF NOT FOUND THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Task not found or not available'
    );
  END IF;

  -- Update task with accepted status (lowercase to match enum)
  UPDATE tasks
  SET 
    status = 'accepted',
    accepted_by = p_user_id,
    updated_at = now()
  WHERE id = p_task_id;

  -- Return the updated task
  SELECT * INTO task_record
  FROM tasks
  WHERE id = p_task_id;

  -- Return success response with task data
  RETURN json_build_object(
    'success', true,
    'data', row_to_json(task_record)
  );
END;
$$;