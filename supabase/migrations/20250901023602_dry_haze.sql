/*
  # Unbreak moderate_task_and_save RPC

  1. Create Missing Enum
     - Create `public.task_category` enum if it doesn't exist
     - Add missing enum values safely

  2. Recreate RPC Function
     - Drop all existing `moderate_task_and_save` variants
     - Create single TEXT-only version with exact parameter signature
     - Use `auth.uid()` for identity (no `uid()` anywhere)
     - Handle category as TEXT with enum conversion internally

  3. Security & Permissions
     - SECURITY DEFINER with proper search path
     - Grant EXECUTE to authenticated and service_role
     - Refresh PostgREST schema cache

  4. Verification
     - Check function definition for prohibited patterns
     - Ensure RPC is immediately callable
*/

-- Phase A: Create enum if missing (idempotent)
DO $$
BEGIN
    -- Create the enum type if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_category' AND typnamespace = 'public'::regnamespace) THEN
        CREATE TYPE public.task_category AS ENUM (
            'food',
            'grocery', 
            'coffee'
        );
    END IF;
    
    -- Add missing values if they don't exist
    IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_category' AND typnamespace = 'public'::regnamespace) THEN
        -- Add 'food' if not exists
        BEGIN
            ALTER TYPE public.task_category ADD VALUE IF NOT EXISTS 'food';
        EXCEPTION WHEN duplicate_object THEN
            -- Value already exists, continue
        END;
        
        -- Add 'grocery' if not exists  
        BEGIN
            ALTER TYPE public.task_category ADD VALUE IF NOT EXISTS 'grocery';
        EXCEPTION WHEN duplicate_object THEN
            -- Value already exists, continue
        END;
        
        -- Add 'coffee' if not exists
        BEGIN
            ALTER TYPE public.task_category ADD VALUE IF NOT EXISTS 'coffee';
        EXCEPTION WHEN duplicate_object THEN
            -- Value already exists, continue
        END;
    END IF;
END $$;

-- Phase B: Drop all existing moderate_task_and_save variants
DO $$
DECLARE
    func_record RECORD;
BEGIN
    -- Find and drop all functions named moderate_task_and_save
    FOR func_record IN 
        SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' 
        AND p.proname = 'moderate_task_and_save'
    LOOP
        EXECUTE format('DROP FUNCTION IF EXISTS public.%I(%s)', 
                      func_record.proname, 
                      func_record.args);
    END LOOP;
END $$;

-- Phase C: Create canonical RPC function (TEXT-only parameters)
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
    v_user_id uuid;
    v_moderation_status text := 'approved';
    v_moderation_reason text := NULL;
    v_result public.tasks;
    v_category_enum public.task_category;
BEGIN
    -- Get authenticated user ID
    v_user_id := auth.uid();
    
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;
    
    -- Basic content moderation
    IF p_title ILIKE '%spam%' OR p_description ILIKE '%spam%' THEN
        v_moderation_status := 'needs_review';
        v_moderation_reason := 'Contains flagged content';
    ELSIF p_title ILIKE '%illegal%' OR p_description ILIKE '%illegal%' THEN
        v_moderation_status := 'blocked';
        v_moderation_reason := 'Contains prohibited content';
    END IF;
    
    -- Map TEXT category to enum value
    CASE lower(p_category)
        WHEN 'food' THEN v_category_enum := 'food';
        WHEN 'grocery' THEN v_category_enum := 'grocery';
        WHEN 'coffee' THEN v_category_enum := 'coffee';
        WHEN 'car' THEN v_category_enum := 'food'; -- Map to existing
        WHEN 'workout' THEN v_category_enum := 'food'; -- Map to existing
        WHEN 'study' THEN v_category_enum := 'food'; -- Map to existing
        WHEN 'custom' THEN v_category_enum := 'food'; -- Map to existing
        ELSE v_category_enum := 'food'; -- Default fallback
    END CASE;
    
    IF p_task_id IS NULL THEN
        -- Insert new task
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
            moderated_at,
            moderated_by
        ) VALUES (
            p_title,
            p_description,
            p_dropoff_instructions,
            p_store,
            p_dropoff_address,
            v_category_enum,
            p_urgency,
            p_estimated_minutes,
            p_reward_cents,
            v_user_id,
            v_moderation_status::task_moderation_status,
            v_moderation_reason,
            CASE WHEN v_moderation_status != 'approved' THEN NOW() ELSE NULL END,
            CASE WHEN v_moderation_status != 'approved' THEN v_user_id ELSE NULL END
        ) RETURNING * INTO v_result;
    ELSE
        -- Update existing task
        UPDATE public.tasks SET
            title = p_title,
            description = p_description,
            dropoff_instructions = p_dropoff_instructions,
            store = p_store,
            dropoff_address = p_dropoff_address,
            category = v_category_enum,
            urgency = p_urgency,
            estimated_minutes = p_estimated_minutes,
            reward_cents = p_reward_cents,
            moderation_status = v_moderation_status::task_moderation_status,
            moderation_reason = v_moderation_reason,
            moderated_at = CASE WHEN v_moderation_status != 'approved' THEN NOW() ELSE moderated_at END,
            moderated_by = CASE WHEN v_moderation_status != 'approved' THEN v_user_id ELSE moderated_by END,
            updated_at = NOW()
        WHERE id = p_task_id AND created_by = v_user_id
        RETURNING * INTO v_result;
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Task not found or not authorized to update';
        END IF;
    END IF;
    
    RETURN v_result;
END $$;

-- Phase D: Grant permissions
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(text, text, text, text, integer, integer, text, uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(text, text, text, text, integer, integer, text, uuid, text, text) TO service_role;

-- Phase E: Verification guards
DO $$
DECLARE
    func_def text;
    func_count integer;
BEGIN
    -- Check that exactly one function exists
    SELECT COUNT(*) INTO func_count
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
    IF lower(func_def) ~ '\buid\s*\(' THEN
        RAISE EXCEPTION 'Found leftover uid() usage in moderate_task_and_save function';
    END IF;
END $$;

-- Phase F: Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';