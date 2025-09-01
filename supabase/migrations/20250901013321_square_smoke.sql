/*
  # Fix uid() references to auth.uid() in moderation system

  1. Problem
    - Previous migration used uid() which doesn't exist in Supabase
    - Need to use auth.uid() instead
    - Must drop and recreate policies/functions that reference uid()

  2. Changes
    - Drop and recreate all moderation-related policies with auth.uid()
    - Drop and recreate moderation RPC functions with auth.uid()
    - Ensure proper security and grants

  3. Security
    - Maintain existing RLS behavior
    - Only approved tasks visible to public
    - Owners can always see their own tasks
    - Proper function security with DEFINER
*/

-- Drop existing policies that use uid() (if they exist)
DROP POLICY IF EXISTS "tasks_select_approved_or_owner" ON public.tasks;
DROP POLICY IF EXISTS "tasks_update_owner_or_assignee" ON public.tasks;
DROP POLICY IF EXISTS "tasks_insert_owner_only" ON public.tasks;

-- Drop existing moderation functions (if they exist)
DROP FUNCTION IF EXISTS public.moderate_task_and_save(text, text, text, text, text, text, text, integer, integer, uuid);
DROP FUNCTION IF EXISTS public.create_or_update_task_with_moderation(text, text, text, text, text, text, text, integer, integer, uuid);

-- Recreate SELECT policy: approved tasks OR own tasks
CREATE POLICY "tasks_select_approved_or_owner"
  ON public.tasks
  FOR SELECT
  TO authenticated
  USING (
    moderation_status = 'approved' 
    OR created_by = auth.uid()
  );

-- Recreate UPDATE policy: only owner or assignee can update
CREATE POLICY "tasks_update_owner_or_assignee"
  ON public.tasks
  FOR UPDATE
  TO authenticated
  USING (
    created_by = auth.uid() 
    OR assignee_id = auth.uid()
    OR accepted_by = auth.uid()
  )
  WITH CHECK (
    created_by = auth.uid() 
    OR assignee_id = auth.uid()
    OR accepted_by = auth.uid()
  );

-- Recreate INSERT policy: set created_by to current user
CREATE POLICY "tasks_insert_owner_only"
  ON public.tasks
  FOR INSERT
  TO authenticated
  WITH CHECK (created_by = auth.uid());

-- Recreate moderation function with proper auth.uid() usage
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
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_task_id uuid;
  v_moderation_status task_moderation_status;
  v_moderation_reason text;
  v_task_data jsonb;
  v_content_to_check text;
  v_blocked_terms text[];
  v_review_terms text[];
BEGIN
  -- Get authenticated user
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'blocked',
      'error', 'Authentication required',
      'task_id', NULL
    );
  END IF;

  -- Combine all text content for moderation
  v_content_to_check := LOWER(
    COALESCE(p_title, '') || ' ' ||
    COALESCE(p_description, '') || ' ' ||
    COALESCE(p_dropoff_instructions, '') || ' ' ||
    COALESCE(p_store, '') || ' ' ||
    COALESCE(p_dropoff_address, '')
  );

  -- Remove punctuation and normalize
  v_content_to_check := REGEXP_REPLACE(v_content_to_check, '[^\w\s]', ' ', 'g');
  v_content_to_check := REGEXP_REPLACE(v_content_to_check, '\s+', ' ', 'g');

  -- Hard block terms (sexual content, violence, illegal)
  v_blocked_terms := ARRAY[
    'sex', 'sexual', 'nude', 'naked', 'hookup', 'escort', 'prostitute',
    'kill', 'murder', 'assault', 'beat up', 'threaten', 'violence',
    'gun', 'weapon', 'knife', 'bomb', 'explosive',
    'cocaine', 'heroin', 'meth', 'fentanyl', 'drugs', 'weed', 'marijuana',
    'fake id', 'forged', 'stolen', 'hack', 'doxx', 'leak address',
    'suicide', 'self harm', 'kill myself'
  ];

  -- Soft review terms (potentially problematic)
  v_review_terms := ARRAY[
    'adult', 'mature', 'private', 'discreet', 'cash only',
    'fight', 'revenge', 'payback', 'get back at',
    'alcohol', 'beer', 'vodka', 'whiskey',
    'prescription', 'pills', 'medication'
  ];

  -- Check for blocked content
  FOR i IN 1..array_length(v_blocked_terms, 1) LOOP
    IF v_content_to_check ~ ('\y' || v_blocked_terms[i] || '\y') THEN
      RETURN jsonb_build_object(
        'status', 'blocked',
        'reason', 'Content violates community guidelines: ' || v_blocked_terms[i],
        'task_id', NULL
      );
    END IF;
  END LOOP;

  -- Check for review content
  v_moderation_status := 'approved';
  v_moderation_reason := NULL;
  
  FOR i IN 1..array_length(v_review_terms, 1) LOOP
    IF v_content_to_check ~ ('\y' || v_review_terms[i] || '\y') THEN
      v_moderation_status := 'needs_review';
      v_moderation_reason := 'Flagged for review: ' || v_review_terms[i];
      EXIT; -- First match wins
    END IF;
  END LOOP;

  -- Insert or update task
  IF p_task_id IS NULL THEN
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
      moderated_at
    ) VALUES (
      p_title,
      p_description,
      p_dropoff_instructions,
      p_store,
      p_dropoff_address,
      p_category::task_category,
      p_urgency::task_urgency,
      p_estimated_minutes,
      p_reward_cents,
      v_user_id,
      v_moderation_status,
      v_moderation_reason,
      NOW()
    )
    RETURNING id INTO v_task_id;
  ELSE
    -- Update existing task (only if owner)
    UPDATE public.tasks 
    SET 
      title = p_title,
      description = p_description,
      dropoff_instructions = p_dropoff_instructions,
      store = p_store,
      dropoff_address = p_dropoff_address,
      category = p_category::task_category,
      urgency = p_urgency::task_urgency,
      estimated_minutes = p_estimated_minutes,
      reward_cents = p_reward_cents,
      moderation_status = v_moderation_status,
      moderation_reason = v_moderation_reason,
      moderated_at = NOW(),
      updated_at = NOW()
    WHERE id = p_task_id 
      AND created_by = v_user_id
    RETURNING id INTO v_task_id;
    
    IF v_task_id IS NULL THEN
      RETURN jsonb_build_object(
        'status', 'blocked',
        'error', 'Task not found or not authorized to edit',
        'task_id', NULL
      );
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

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save TO authenticated;
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save TO service_role;

-- Create admin moderation function for manual review
CREATE OR REPLACE FUNCTION public.admin_moderate_task(
  p_task_id uuid,
  p_new_status task_moderation_status,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_is_admin boolean;
  v_task_exists boolean;
BEGIN
  -- Get authenticated user
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Authentication required');
  END IF;

  -- Check if user is admin (assuming profiles.is_admin exists)
  SELECT COALESCE(is_admin, false) INTO v_is_admin
  FROM public.profiles 
  WHERE id = v_user_id;
  
  IF NOT COALESCE(v_is_admin, false) THEN
    RETURN jsonb_build_object('error', 'Admin access required');
  END IF;

  -- Check if task exists
  SELECT EXISTS(SELECT 1 FROM public.tasks WHERE id = p_task_id) INTO v_task_exists;
  
  IF NOT v_task_exists THEN
    RETURN jsonb_build_object('error', 'Task not found');
  END IF;

  -- Update moderation status
  UPDATE public.tasks 
  SET 
    moderation_status = p_new_status,
    moderation_reason = p_reason,
    moderated_at = NOW(),
    moderated_by = v_user_id,
    updated_at = NOW()
  WHERE id = p_task_id;

  RETURN jsonb_build_object(
    'success', true,
    'status', p_new_status,
    'task_id', p_task_id
  );
END;
$$;

-- Grant admin function to service role only
GRANT EXECUTE ON FUNCTION public.admin_moderate_task TO service_role;