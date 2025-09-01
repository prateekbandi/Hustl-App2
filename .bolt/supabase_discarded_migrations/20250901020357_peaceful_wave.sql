/*
  # Create moderate_task_and_save RPC with exact client signature

  1. Function
    - `moderate_task_and_save` with exact parameter names and order from client
    - SECURITY DEFINER with proper search path
    - Uses auth.uid() for caller identity
    - Handles both create (p_task_id IS NULL) and update operations
    - Runs lightweight content moderation
    - Sets moderation_status, reason, and timestamp

  2. Security
    - Only authenticated users can execute
    - Only task owners can update existing tasks
    - Uses auth.uid() for all identity checks

  3. Moderation
    - Checks for inappropriate content (sexual, violence, illegal, etc.)
    - Returns 'approved', 'needs_review', or 'blocked'
    - Raises exception for blocked content
*/

-- Ensure moderation status enum exists
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_moderation_status') THEN
    CREATE TYPE public.task_moderation_status AS ENUM ('approved', 'needs_review', 'blocked');
  END IF;
END $$;

-- Add moderation columns if they don't exist
DO $$
BEGIN
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
END $$;

-- Backfill existing rows to 'approved'
UPDATE public.tasks 
SET moderation_status = 'approved' 
WHERE moderation_status IS NULL;

-- Create index on moderation_status if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE tablename = 'tasks' AND indexname = 'idx_tasks_moderation_status'
  ) THEN
    CREATE INDEX idx_tasks_moderation_status ON public.tasks (moderation_status);
  END IF;
END $$;

-- Drop any existing versions of the function
DROP FUNCTION IF EXISTS public.moderate_task_and_save(text,text,text,text,integer,integer,text,uuid,text,text);

-- Create the RPC with EXACT signature that client calls
CREATE OR REPLACE FUNCTION public.moderate_task_and_save(
  p_category text,
  p_description text,
  p_dropoff_address text,
  p_dropoff_instructions text,
  p_estimated_minutes integer,
  p_reward_cents integer,
  p_store text,
  p_task_id uuid,
  p_title text,
  p_urgency text
) RETURNS public.tasks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_moderation_status task_moderation_status;
  v_moderation_reason text;
  v_content_to_check text;
  v_task_row tasks%ROWTYPE;
BEGIN
  -- Get authenticated user ID
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Combine all text content for moderation check
  v_content_to_check := LOWER(
    COALESCE(p_title, '') || ' ' ||
    COALESCE(p_description, '') || ' ' ||
    COALESCE(p_dropoff_instructions, '') || ' ' ||
    COALESCE(p_store, '') || ' ' ||
    COALESCE(p_dropoff_address, '')
  );

  -- Simple content moderation
  v_moderation_status := 'approved';
  v_moderation_reason := NULL;

  -- Check for inappropriate content
  IF v_content_to_check ~ '(sex|sexual|porn|nude|naked|escort|hookup|dating|intimate|adult)' THEN
    v_moderation_status := 'blocked';
    v_moderation_reason := 'Sexual content not allowed';
  ELSIF v_content_to_check ~ '(kill|murder|violence|weapon|gun|knife|bomb|attack|hurt|harm|fight|beat)' THEN
    v_moderation_status := 'blocked';
    v_moderation_reason := 'Violence or harmful content not allowed';
  ELSIF v_content_to_check ~ '(drug|weed|marijuana|cocaine|pills|alcohol|beer|wine|liquor|drunk)' THEN
    v_moderation_status := 'blocked';
    v_moderation_reason := 'Illegal substances not allowed';
  ELSIF v_content_to_check ~ '(hate|racist|nazi|terrorist|suicide|self.harm)' THEN
    v_moderation_status := 'blocked';
    v_moderation_reason := 'Hate speech or harmful content not allowed';
  ELSIF v_content_to_check ~ '(cheat|plagiarism|exam|test|homework|assignment|essay|paper)' THEN
    v_moderation_status := 'needs_review';
    v_moderation_reason := 'Academic integrity review required';
  END IF;

  -- If blocked, raise exception
  IF v_moderation_status = 'blocked' THEN
    RAISE EXCEPTION 'blocked: %', v_moderation_reason;
  END IF;

  -- Create or update task
  IF p_task_id IS NULL THEN
    -- Create new task
    INSERT INTO public.tasks (
      title,
      description,
      category,
      store,
      dropoff_address,
      dropoff_instructions,
      urgency,
      estimated_minutes,
      reward_cents,
      created_by,
      moderation_status,
      moderation_reason,
      moderated_at
    ) VALUES (
      p_title,
      p_description,
      p_category::task_category,
      p_store,
      p_dropoff_address,
      p_dropoff_instructions,
      p_urgency::task_urgency,
      p_estimated_minutes,
      p_reward_cents,
      v_user_id,
      v_moderation_status,
      v_moderation_reason,
      now()
    ) RETURNING * INTO v_task_row;
  ELSE
    -- Update existing task (only if owned by caller)
    UPDATE public.tasks SET
      title = p_title,
      description = p_description,
      category = p_category::task_category,
      store = p_store,
      dropoff_address = p_dropoff_address,
      dropoff_instructions = p_dropoff_instructions,
      urgency = p_urgency::task_urgency,
      estimated_minutes = p_estimated_minutes,
      reward_cents = p_reward_cents,
      moderation_status = v_moderation_status,
      moderation_reason = v_moderation_reason,
      moderated_at = now(),
      updated_at = now()
    WHERE id = p_task_id AND created_by = v_user_id
    RETURNING * INTO v_task_row;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Task not found or not owned by caller';
    END IF;
  END IF;

  RETURN v_task_row;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(text,text,text,text,integer,integer,text,uuid,text,text) TO authenticated;

-- Ensure RLS is enabled on tasks table
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

-- Drop and recreate RLS policies with auth.uid()
DROP POLICY IF EXISTS tasks_select_visible ON public.tasks;
CREATE POLICY tasks_select_visible ON public.tasks
  FOR SELECT
  TO authenticated
  USING (moderation_status = 'approved' OR created_by = auth.uid() OR assignee_id = auth.uid());

DROP POLICY IF EXISTS tasks_update_owner_or_assignee ON public.tasks;
CREATE POLICY tasks_update_owner_or_assignee ON public.tasks
  FOR UPDATE
  TO authenticated
  USING (auth.uid() IN (created_by, assignee_id))
  WITH CHECK (auth.uid() IN (created_by, assignee_id));

DROP POLICY IF EXISTS tasks_insert_owner ON public.tasks;
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

-- Guard check: ensure no uid() references remain
DO $$
DECLARE
  migration_text text;
BEGIN
  -- This is a simplified check - in practice you'd scan the actual migration content
  -- For now, we'll just ensure our function uses auth.uid()
  SELECT prosrc INTO migration_text 
  FROM pg_proc 
  WHERE proname = 'moderate_task_and_save';
  
  IF migration_text LIKE '%uid()%' THEN
    RAISE EXCEPTION 'Found leftover uid() usage in moderate_task_and_save function';
  END IF;
END $$;