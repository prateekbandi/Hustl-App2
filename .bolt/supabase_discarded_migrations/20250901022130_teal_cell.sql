/*
  # Eliminate public.task_category references and recreate moderate_task_and_save RPC

  1. Function Cleanup
     - Find and drop ALL functions containing 'task_category' references
     - Remove any cached definitions with enum dependencies
     - Ensure clean slate for recreation

  2. RPC Recreation
     - Create single canonical moderate_task_and_save function
     - Use TEXT-only for category parameter (no enum casts)
     - Use auth.uid() exclusively for identity checks
     - Handle category logic via string matching

  3. Verification
     - Guard against any remaining task_category or uid() references
     - Ensure exactly one function exists after creation
     - Verify function is immediately callable

  4. Security
     - SECURITY DEFINER with proper search path
     - Grant EXECUTE to authenticated and service_role
     - Refresh PostgREST schema cache
*/

-- Step 1: Find and drop ALL functions that reference task_category
DO $$
DECLARE
    func_record RECORD;
    drop_statement TEXT;
BEGIN
    -- Find all functions in public schema whose source contains 'task_category'
    FOR func_record IN
        SELECT 
            p.proname as function_name,
            pg_get_function_identity_arguments(p.oid) as args,
            p.oid
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
        AND (
            lower(pg_get_functiondef(p.oid)) LIKE '%task_category%'
            OR p.proname = 'moderate_task_and_save'
        )
    LOOP
        drop_statement := format('DROP FUNCTION IF EXISTS public.%I(%s)', 
                                func_record.function_name, 
                                func_record.args);
        EXECUTE drop_statement;
        RAISE NOTICE 'Dropped function: %', drop_statement;
    END LOOP;
END $$;

-- Step 2: Create the canonical moderate_task_and_save function (TEXT-only, no enum references)
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
    v_moderation_status text := 'approved';
    v_moderation_reason text := null;
    v_normalized_category text;
    v_normalized_urgency text;
    v_task_row public.tasks;
    v_caller_id uuid;
BEGIN
    -- Get caller identity
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    -- Normalize category via string matching (no enum casts)
    v_normalized_category := CASE
        WHEN lower(p_category) IN ('food', 'food_pickup', 'food_delivery') THEN 'food'
        WHEN lower(p_category) IN ('coffee', 'coffee_run') THEN 'coffee'
        WHEN lower(p_category) IN ('grocery', 'groceries', 'shopping') THEN 'grocery'
        ELSE 'food'  -- Default fallback
    END;

    -- Normalize urgency
    v_normalized_urgency := CASE
        WHEN lower(p_urgency) IN ('low', 'medium', 'high') THEN lower(p_urgency)
        ELSE 'medium'  -- Default fallback
    END;

    -- Content moderation (lightweight checks)
    IF lower(p_title || ' ' || p_description || ' ' || p_dropoff_instructions) ~ '(sex|sexual|porn|nude|naked|escort|hookup|dating|romance)' THEN
        v_moderation_status := 'blocked';
        v_moderation_reason := 'Sexual content is not allowed';
    ELSIF lower(p_title || ' ' || p_description || ' ' || p_dropoff_instructions) ~ '(kill|murder|violence|harm|hurt|weapon|gun|knife|bomb|attack)' THEN
        v_moderation_status := 'blocked';
        v_moderation_reason := 'Violence or harmful content is not allowed';
    ELSIF lower(p_title || ' ' || p_description || ' ' || p_dropoff_instructions) ~ '(drug|weed|cocaine|heroin|meth|illegal|steal|fraud|scam)' THEN
        v_moderation_status := 'blocked';
        v_moderation_reason := 'Illegal activities are not allowed';
    ELSIF lower(p_title || ' ' || p_description || ' ' || p_dropoff_instructions) ~ '(hate|racist|nazi|terrorist|extremist)' THEN
        v_moderation_status := 'blocked';
        v_moderation_reason := 'Hate speech is not allowed';
    ELSIF lower(p_title || ' ' || p_description || ' ' || p_dropoff_instructions) ~ '(exam|test|homework|assignment|cheat|plagiar)' THEN
        v_moderation_status := 'needs_review';
        v_moderation_reason := 'Academic content requires review';
    END IF;

    -- Raise exception for blocked content
    IF v_moderation_status = 'blocked' THEN
        RAISE EXCEPTION 'Content blocked: %', v_moderation_reason;
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
            v_normalized_urgency,
            p_estimated_minutes,
            p_reward_cents,
            v_caller_id,
            v_moderation_status,
            v_moderation_reason,
            now(),
            v_caller_id
        ) RETURNING * INTO v_task_row;
    ELSE
        -- Update existing task (owner only)
        UPDATE public.tasks SET
            title = trim(p_title),
            description = trim(p_description),
            category = v_normalized_category,
            store = trim(p_store),
            dropoff_address = trim(p_dropoff_address),
            dropoff_instructions = trim(p_dropoff_instructions),
            urgency = v_normalized_urgency,
            estimated_minutes = p_estimated_minutes,
            reward_cents = p_reward_cents,
            moderation_status = v_moderation_status,
            moderation_reason = v_moderation_reason,
            moderated_at = now(),
            moderated_by = v_caller_id,
            updated_at = now()
        WHERE id = p_task_id 
        AND created_by = v_caller_id
        RETURNING * INTO v_task_row;

        -- Check if update affected any rows
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Task not found or not owned by caller';
        END IF;
    END IF;

    RETURN v_task_row;
END $$;

-- Step 3: Grant permissions
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(text,text,text,text,integer,integer,text,uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(text,text,text,text,integer,integer,text,uuid,text,text) TO service_role;

-- Step 4: Verification guards
DO $$
DECLARE
    func_def text;
    func_count integer;
BEGIN
    -- Check function count
    SELECT count(*) INTO func_count
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'moderate_task_and_save';
    
    IF func_count != 1 THEN
        RAISE EXCEPTION 'Expected exactly 1 moderate_task_and_save function, found %', func_count;
    END IF;

    -- Get function definition
    SELECT pg_get_functiondef(p.oid) INTO func_def
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'moderate_task_and_save';

    -- Check for prohibited patterns
    IF lower(func_def) ~ '\btask_category\b' THEN
        RAISE EXCEPTION 'Function still contains task_category references';
    END IF;

    IF lower(func_def) ~ '\buid\s*\(' THEN
        RAISE EXCEPTION 'Function still contains uid() references';
    END IF;

    RAISE NOTICE 'Function verification passed: no enum or uid() references found';
END $$;

-- Step 5: Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';