/*
  # Add Task Moderation System

  1. New Enum
    - `task_moderation_status` with values: 'approved', 'needs_review', 'blocked'

  2. New Columns on tasks table
    - `moderation_status` (enum, default 'approved')
    - `moderation_reason` (text, nullable)
    - `moderated_at` (timestamptz, nullable)
    - `moderated_by` (uuid, nullable)

  3. Security Updates
    - Update RLS policies to only show approved tasks in public listings
    - Allow task owners to always see their own tasks regardless of status
    - Prevent task acceptance unless approved

  4. Indexes
    - Add index on moderation_status for efficient filtering
*/

-- Create moderation status enum
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_moderation_status') THEN
    CREATE TYPE task_moderation_status AS ENUM ('approved', 'needs_review', 'blocked');
  END IF;
END $$;

-- Add moderation columns to tasks table
DO $$
BEGIN
  -- Add moderation_status column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tasks' AND column_name = 'moderation_status'
  ) THEN
    ALTER TABLE tasks ADD COLUMN moderation_status task_moderation_status NOT NULL DEFAULT 'approved';
  END IF;

  -- Add moderation_reason column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tasks' AND column_name = 'moderation_reason'
  ) THEN
    ALTER TABLE tasks ADD COLUMN moderation_reason text;
  END IF;

  -- Add moderated_at column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tasks' AND column_name = 'moderated_at'
  ) THEN
    ALTER TABLE tasks ADD COLUMN moderated_at timestamptz;
  END IF;

  -- Add moderated_by column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tasks' AND column_name = 'moderated_by'
  ) THEN
    ALTER TABLE tasks ADD COLUMN moderated_by uuid;
  END IF;
END $$;

-- Add index for efficient moderation status filtering
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE indexname = 'idx_tasks_moderation_status'
  ) THEN
    CREATE INDEX idx_tasks_moderation_status ON tasks (moderation_status);
  END IF;
END $$;

-- Update RLS policies for moderation
DROP POLICY IF EXISTS "Users can read available tasks" ON tasks;
CREATE POLICY "Users can read available tasks"
  ON tasks FOR SELECT
  TO authenticated
  USING (
    (status = 'open' AND created_by <> uid() AND moderation_status = 'approved')
  );

-- Allow task owners to always see their own tasks regardless of moderation status
DROP POLICY IF EXISTS "Users can read own tasks" ON tasks;
CREATE POLICY "Users can read own tasks"
  ON tasks FOR SELECT
  TO authenticated
  USING (created_by = uid());

-- Prevent accepting tasks unless approved
DROP POLICY IF EXISTS "accept_open_task" ON tasks;
CREATE POLICY "accept_open_task"
  ON tasks FOR UPDATE
  TO public
  USING (
    status = 'open' 
    AND created_by <> uid() 
    AND moderation_status = 'approved'
  )
  WITH CHECK (
    accepted_by = uid() 
    AND status = 'accepted'
  );

-- Add is_admin column to profiles if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'is_admin'
  ) THEN
    ALTER TABLE profiles ADD COLUMN is_admin boolean NOT NULL DEFAULT false;
  END IF;
END $$;

-- Create moderation function
CREATE OR REPLACE FUNCTION moderate_task_and_save(
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
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_moderation_status task_moderation_status;
  v_moderation_reason text;
  v_task_data jsonb;
  v_task_id uuid;
  v_user_id uuid;
BEGIN
  -- Get current user
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Authentication required');
  END IF;

  -- Combine all text for moderation
  v_task_data := jsonb_build_object(
    'title', COALESCE(p_title, ''),
    'description', COALESCE(p_description, ''),
    'instructions', COALESCE(p_dropoff_instructions, ''),
    'store', COALESCE(p_store, ''),
    'address', COALESCE(p_dropoff_address, '')
  );

  -- Run moderation logic
  SELECT status, reason INTO v_moderation_status, v_moderation_reason
  FROM moderate_content(v_task_data);

  -- Insert or update task
  IF p_task_id IS NULL THEN
    -- Create new task
    INSERT INTO tasks (
      title, description, dropoff_instructions, store, dropoff_address,
      category, urgency, estimated_minutes, reward_cents, created_by,
      moderation_status, moderation_reason, moderated_at
    ) VALUES (
      p_title, p_description, p_dropoff_instructions, p_store, p_dropoff_address,
      p_category::text, p_urgency::text, p_estimated_minutes, p_reward_cents, v_user_id,
      v_moderation_status, v_moderation_reason, now()
    ) RETURNING id INTO v_task_id;
  ELSE
    -- Update existing task
    UPDATE tasks SET
      title = p_title,
      description = p_description,
      dropoff_instructions = p_dropoff_instructions,
      store = p_store,
      dropoff_address = p_dropoff_address,
      category = p_category::text,
      urgency = p_urgency::text,
      estimated_minutes = p_estimated_minutes,
      reward_cents = p_reward_cents,
      moderation_status = v_moderation_status,
      moderation_reason = v_moderation_reason,
      moderated_at = now(),
      updated_at = now()
    WHERE id = p_task_id AND created_by = v_user_id
    RETURNING id INTO v_task_id;
    
    IF v_task_id IS NULL THEN
      RETURN jsonb_build_object('error', 'Task not found or not authorized');
    END IF;
  END IF;

  -- Return result
  RETURN jsonb_build_object(
    'status', v_moderation_status,
    'reason', v_moderation_reason,
    'task_id', v_task_id
  );
END;
$$;

-- Create content moderation function
CREATE OR REPLACE FUNCTION moderate_content(content jsonb)
RETURNS TABLE(status task_moderation_status, reason text)
LANGUAGE plpgsql
AS $$
DECLARE
  v_combined_text text;
  v_normalized_text text;
BEGIN
  -- Combine all text fields
  v_combined_text := COALESCE(content->>'title', '') || ' ' ||
                    COALESCE(content->>'description', '') || ' ' ||
                    COALESCE(content->>'instructions', '') || ' ' ||
                    COALESCE(content->>'store', '') || ' ' ||
                    COALESCE(content->>'address', '');
  
  -- Normalize text (lowercase, remove punctuation)
  v_normalized_text := lower(regexp_replace(v_combined_text, '[^\w\s]', ' ', 'g'));
  v_normalized_text := regexp_replace(v_normalized_text, '\s+', ' ', 'g');

  -- Hard block patterns (sexual content, violence, illegal)
  IF v_normalized_text ~ '\b(sex|sexual|nude|naked|hookup|escort|prostitut|adult service|sexual favor)\b' OR
     v_normalized_text ~ '\b(kill|murder|assault|beat up|threaten|weapon|gun|knife|bomb)\b' OR
     v_normalized_text ~ '\b(cocaine|heroin|meth|fentanyl|drug deal|weed sale|fake id|stolen)\b' OR
     v_normalized_text ~ '\b(hack|doxx|leak address|ssn|social security)\b' THEN
    
    status := 'blocked';
    reason := 'Content violates community guidelines';
    RETURN NEXT;
    RETURN;
  END IF;

  -- Soft review patterns (potentially problematic)
  IF v_normalized_text ~ '\b(adult|mature|private|personal|secret|confidential)\b' OR
     v_normalized_text ~ '\b(party|alcohol|drink|beer|wine)\b' OR
     v_normalized_text ~ '\b(cash only|no questions|discrete|discreet)\b' THEN
    
    status := 'needs_review';
    reason := 'Flagged for manual review';
    RETURN NEXT;
    RETURN;
  END IF;

  -- Default: approved
  status := 'approved';
  reason := NULL;
  RETURN NEXT;
END;
$$;

-- Grant necessary permissions
GRANT EXECUTE ON FUNCTION moderate_task_and_save TO authenticated;
GRANT EXECUTE ON FUNCTION moderate_content TO authenticated;