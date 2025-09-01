/*
  # Remove enum dependency from moderate_task_and_save RPC

  1. Function Cleanup
    - Drop all versions of moderate_task_and_save that reference public.task_category
    - Remove any helper functions with enum dependencies
    - Ensure clean slate for recreation

  2. Recreation with TEXT-only
    - Create moderate_task_and_save with exact client signature
    - Use TEXT for all category handling (no enum casts)
    - Category logic via string matching only
    - Use auth.uid() exclusively for identity

  3. Security
    - SECURITY DEFINER with proper search path
    - Grant EXECUTE to authenticated and service_role
    - Verify no enum or uid() references remain

  4. Verification
    - Guard against task_category and uid() tokens
    - Ensure function is immediately callable
*/

-- Drop all versions of moderate_task_and_save by signature
DO $$
DECLARE
    func_record RECORD;
    drop_sql TEXT;
BEGIN
    -- Find all functions named moderate_task_and_save in public schema
    FOR func_record IN 
        SELECT 
            p.proname,
            pg_get_function_identity_arguments(p.oid) as args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' 
        AND p.proname = 'moderate_task_and_save'
    LOOP
        drop_sql := format('DROP FUNCTION IF EXISTS public.%I(%s)', 
                          func_record.proname, 
                          func_record.args);
        EXECUTE drop_sql;
        RAISE NOTICE 'Dropped function: %', drop_sql;
    END LOOP;
END $$;

-- Create the canonical moderate_task_and_save function with TEXT-only category
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
    v_caller_id uuid;
    v_moderation_status text;
    v_moderation_reason text;
    v_result public.tasks;
    v_content_to_check text;
    v_normalized_category text;
BEGIN
    -- Get caller identity
    v_caller_id := auth.uid();
    
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    -- Normalize category to match database values
    v_normalized_category := CASE 
        WHEN lower(trim(p_category)) IN ('food', 'food_delivery', 'food_pickup') THEN 'food'
        WHEN lower(trim(p_category)) IN ('coffee', 'coffee_run') THEN 'coffee'
        WHEN lower(trim(p_category)) IN ('grocery', 'grocery_shopping') THEN 'grocery'
        ELSE 'food'  -- Default fallback
    END;

    -- Prepare content for moderation
    v_content_to_check := trim(coalesce(p_title, '')) || ' ' || 
                         trim(coalesce(p_description, '')) || ' ' || 
                         trim(coalesce(p_dropoff_instructions, '')) || ' ' ||
                         trim(coalesce(p_store, '')) || ' ' ||
                         trim(coalesce(p_dropoff_address, ''));

    -- Content moderation
    v_moderation_status := 'approved';
    v_moderation_reason := NULL;

    -- Check for prohibited content
    IF v_content_to_check ~* '\b(sex|sexual|nude|porn|escort|hookup|dating|intimate|adult)\b' THEN
        v_moderation_status := 'blocked';
        v_moderation_reason := 'Sexual content is not allowed';
    ELSIF v_content_to_check ~* '\b(kill|murder|violence|weapon|gun|knife|bomb|attack|harm|hurt|fight|assault)\b' THEN
        v_moderation_status := 'blocked';
        v_moderation_reason := 'Violence or harmful content is not allowed';
    ELSIF v_content_to_check ~* '\b(drug|weed|marijuana|cocaine|pills|illegal|stolen|fake|scam|fraud)\b' THEN
        v_moderation_status := 'blocked';
        v_moderation_reason := 'Illegal activities are not allowed';
    ELSIF v_content_to_check ~* '\b(exam|test|homework|assignment|cheat|plagiarism|academic)\b' THEN
        v_moderation_status := 'needs_review';
        v_moderation_reason := 'Academic content requires review';
    ELSIF v_content_to_check ~* '\b(hate|racist|discrimination|offensive|inappropriate)\b' THEN
        v_moderation_status := 'blocked';
        v_moderation_reason := 'Hate speech or discrimination is not allowed';
    END IF;

    -- Raise exception for blocked content
    IF v_moderation_status = 'blocked' THEN
        RAISE EXCEPTION 'blocked: %', v_moderation_reason;
    END IF;

    -- Insert or update task
    IF p_task_id IS NULL THEN
        -- Insert new task
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
            trim(p_title),
            trim(p_description),
            v_normalized_category,
            trim(p_store),
            trim(p_dropoff_address),
            trim(p_dropoff_instructions),
            lower(trim(p_urgency)),
            p_estimated_minutes,
            p_reward_cents,
            v_caller_id,
            v_moderation_status,
            v_moderation_reason,
            now(),
            CASE WHEN v_moderation_status != 'approved' THEN v_caller_id ELSE NULL END
        ) RETURNING * INTO v_result;
    ELSE
        -- Update existing task
        UPDATE public.tasks SET
            title = trim(p_title),
            description = trim(p_description),
            category = v_normalized_category,
            store = trim(p_store),
            dropoff_address = trim(p_dropoff_address),
            dropoff_instructions = trim(p_dropoff_instructions),
            urgency = lower(trim(p_urgency)),
            estimated_minutes = p_estimated_minutes,
            reward_cents = p_reward_cents,
            moderation_status = v_moderation_status,
            moderation_reason = v_moderation_reason,
            moderated_at = now(),
            moderated_by = CASE WHEN v_moderation_status != 'approved' THEN v_caller_id ELSE NULL END,
            updated_at = now()
        WHERE id = p_task_id 
        AND created_by = v_caller_id
        RETURNING * INTO v_result;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Task not found or not owned by caller';
        END IF;
    END IF;

    RETURN v_result;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(text,text,text,text,integer,integer,text,uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(text,text,text,text,integer,integer,text,uuid,text,text) TO service_role;

-- Verify no enum or uid references remain
DO $$
DECLARE
    v_function_def text;
BEGIN
    -- Get the function definition
    SELECT pg_get_functiondef(oid) INTO v_function_def
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' 
    AND p.proname = 'moderate_task_and_save'
    AND pg_get_function_identity_arguments(p.oid) = 'p_category text, p_description text, p_dropoff_address text, p_dropoff_instructions text, p_estimated_minutes integer, p_reward_cents integer, p_store text, p_task_id uuid, p_title text, p_urgency text';

    -- Check for prohibited patterns
    IF v_function_def ~* '\buid\s*\(' THEN
        RAISE EXCEPTION 'Found leftover uid() usage in function definition';
    END IF;

    IF v_function_def ~* '\btask_category\b' THEN
        RAISE EXCEPTION 'Found task_category enum reference in function definition';
    END IF;

    RAISE NOTICE 'Function verification passed - no uid() or enum references found';
END $$;

-- Refresh schema cache
NOTIFY pgrst, 'reload schema';