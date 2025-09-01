/*
  # Purge uid() from moderate_task_and_save function

  1. Complete Function Purge
    - Drop ALL versions of moderate_task_and_save by signature
    - Remove any cached definitions that might contain uid()
    
  2. Clean Recreation
    - Create single canonical function with exact client signature
    - Use only auth.uid() throughout (never uid())
    - SECURITY DEFINER with proper search path
    
  3. Verification
    - Guard check to ensure no uid() patterns remain
    - Verify exactly one function exists
    - Grant proper permissions
*/

-- Step 1: Complete purge of ALL moderate_task_and_save variants
DO $$
DECLARE
    func_record RECORD;
    drop_statement TEXT;
BEGIN
    -- Find and drop ALL functions named moderate_task_and_save in public schema
    FOR func_record IN 
        SELECT 
            p.proname,
            pg_get_function_identity_arguments(p.oid) as args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' 
        AND p.proname = 'moderate_task_and_save'
    LOOP
        drop_statement := format('DROP FUNCTION IF EXISTS public.%I(%s)', 
                                func_record.proname, 
                                func_record.args);
        EXECUTE drop_statement;
        RAISE NOTICE 'Dropped function: %', drop_statement;
    END LOOP;
END $$;

-- Step 2: Create canonical function with exact client signature
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
)
RETURNS public.tasks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_moderation_status public.task_moderation_status := 'approved';
    v_moderation_reason text := null;
    v_caller_id uuid;
    v_task public.tasks;
    v_content_check text;
BEGIN
    -- Get caller identity
    v_caller_id := auth.uid();
    
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    -- Normalize and prepare content for moderation
    v_content_check := lower(trim(coalesce(p_title, '') || ' ' || coalesce(p_description, '') || ' ' || coalesce(p_dropoff_instructions, '')));
    
    -- Content moderation checks
    IF v_content_check ~ '(sex|sexual|porn|nude|naked|escort|hookup|dating|intimate)' THEN
        v_moderation_status := 'blocked';
        v_moderation_reason := 'Sexual content is not allowed';
    ELSIF v_content_check ~ '(kill|murder|violence|harm|hurt|fight|weapon|gun|knife|bomb|attack)' THEN
        v_moderation_status := 'blocked';
        v_moderation_reason := 'Violence or harmful content is not allowed';
    ELSIF v_content_check ~ '(drug|weed|marijuana|cocaine|pills|alcohol|beer|liquor|vape|smoke)' THEN
        v_moderation_status := 'blocked';
        v_moderation_reason := 'Illegal substances are not allowed';
    ELSIF v_content_check ~ '(hate|racist|nazi|terrorist|extremist|radical)' THEN
        v_moderation_status := 'blocked';
        v_moderation_reason := 'Hate speech is not allowed';
    ELSIF v_content_check ~ '(cheat|plagiarism|exam|test|homework|assignment|essay|paper)' AND v_content_check ~ '(sell|buy|complete|write|do)' THEN
        v_moderation_status := 'needs_review';
        v_moderation_reason := 'Academic integrity concern';
    ELSIF length(v_content_check) < 10 THEN
        v_moderation_status := 'needs_review';
        v_moderation_reason := 'Content too short for review';
    END IF;

    -- Raise exception for blocked content
    IF v_moderation_status = 'blocked' THEN
        RAISE EXCEPTION 'blocked: %', v_moderation_reason;
    END IF;

    -- Insert or update based on p_task_id
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
            moderated_at,
            moderated_by
        ) VALUES (
            p_title,
            p_description,
            p_category::public.task_category,
            p_store,
            p_dropoff_address,
            p_dropoff_instructions,
            p_urgency::public.task_urgency,
            p_estimated_minutes,
            p_reward_cents,
            v_caller_id,
            v_moderation_status,
            v_moderation_reason,
            now(),
            CASE WHEN v_moderation_status != 'approved' THEN v_caller_id ELSE NULL END
        )
        RETURNING * INTO v_task;
    ELSE
        -- Update existing task (owner only)
        UPDATE public.tasks SET
            title = p_title,
            description = p_description,
            category = p_category::public.task_category,
            store = p_store,
            dropoff_address = p_dropoff_address,
            dropoff_instructions = p_dropoff_instructions,
            urgency = p_urgency::public.task_urgency,
            estimated_minutes = p_estimated_minutes,
            reward_cents = p_reward_cents,
            moderation_status = v_moderation_status,
            moderation_reason = v_moderation_reason,
            moderated_at = now(),
            moderated_by = CASE WHEN v_moderation_status != 'approved' THEN v_caller_id ELSE NULL END,
            updated_at = now()
        WHERE id = p_task_id 
        AND created_by = v_caller_id
        RETURNING * INTO v_task;
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Task not found or not owned by caller';
        END IF;
    END IF;

    RETURN v_task;
END;
$$;

-- Step 3: Grant permissions
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(text,text,text,text,integer,integer,text,uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(text,text,text,text,integer,integer,text,uuid,text,text) TO service_role;

-- Step 4: Verification guard
DO $$
DECLARE
    func_def text;
BEGIN
    -- Get the function definition
    SELECT pg_get_functiondef(oid) INTO func_def
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' 
    AND p.proname = 'moderate_task_and_save'
    AND pg_get_function_identity_arguments(p.oid) = 'p_category text, p_description text, p_dropoff_address text, p_dropoff_instructions text, p_estimated_minutes integer, p_reward_cents integer, p_store text, p_task_id uuid, p_title text, p_urgency text';
    
    IF func_def IS NULL THEN
        RAISE EXCEPTION 'Function moderate_task_and_save was not created properly';
    END IF;
    
    -- Check for any uid() usage (the guard that was failing)
    IF func_def ~* '\buid\s*\(' THEN
        RAISE EXCEPTION 'Found leftover uid() usage in moderate_task_and_save function';
    END IF;
    
    RAISE NOTICE 'Function moderate_task_and_save created successfully without uid() references';
END $$;

-- Step 5: Ensure RLS policies use auth.uid() (recreate if needed)
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

-- Step 6: Ensure profiles has public read policy
DROP POLICY IF EXISTS profiles_select_public ON public.profiles;
CREATE POLICY profiles_select_public ON public.profiles
    FOR SELECT
    TO authenticated
    USING (true);

-- Step 7: Schema cache refresh (trigger PostgREST reload)
COMMENT ON FUNCTION public.moderate_task_and_save(text,text,text,text,integer,integer,text,uuid,text,text) IS 'Content moderation and task creation/update - uses auth.uid() only';