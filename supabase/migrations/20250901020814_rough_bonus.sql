/*
  # Purge uid() from moderate_task_and_save and recreate cleanly

  1. Function Cleanup
    - Drop ALL versions of moderate_task_and_save by signature
    - Recreate single clean version with exact client signature
    - Use only auth.uid() throughout (no uid() anywhere)

  2. Policy Cleanup  
    - Drop and recreate any policies still using uid()
    - Ensure all use auth.uid() for identity checks

  3. Verification
    - Guard against any remaining uid() usage
    - Verify single function exists
    - Grant proper permissions
*/

-- Step 1: Drop ALL versions of moderate_task_and_save
-- Query all function signatures and drop them
DO $$
DECLARE
    func_record RECORD;
BEGIN
    -- Find all moderate_task_and_save functions in public schema
    FOR func_record IN 
        SELECT 
            p.proname,
            pg_get_function_identity_arguments(p.oid) as args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' 
        AND p.proname = 'moderate_task_and_save'
    LOOP
        -- Drop each function by exact signature
        EXECUTE format('DROP FUNCTION IF EXISTS public.%I(%s)', 
                      func_record.proname, 
                      func_record.args);
        RAISE NOTICE 'Dropped function: public.%(%)', func_record.proname, func_record.args;
    END LOOP;
END $$;

-- Step 2: Ensure moderation enum exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_moderation_status') THEN
        CREATE TYPE public.task_moderation_status AS ENUM ('approved', 'needs_review', 'blocked');
    END IF;
END $$;

-- Step 3: Ensure moderation columns exist on tasks
DO $$
BEGIN
    -- Add moderation_status column if missing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'tasks' 
        AND column_name = 'moderation_status'
    ) THEN
        ALTER TABLE public.tasks 
        ADD COLUMN moderation_status public.task_moderation_status NOT NULL DEFAULT 'approved';
    END IF;

    -- Add moderation_reason column if missing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'tasks' 
        AND column_name = 'moderation_reason'
    ) THEN
        ALTER TABLE public.tasks 
        ADD COLUMN moderation_reason text;
    END IF;

    -- Add moderated_at column if missing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'tasks' 
        AND column_name = 'moderated_at'
    ) THEN
        ALTER TABLE public.tasks 
        ADD COLUMN moderated_at timestamptz;
    END IF;

    -- Add moderated_by column if missing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'tasks' 
        AND column_name = 'moderated_by'
    ) THEN
        ALTER TABLE public.tasks 
        ADD COLUMN moderated_by uuid;
    END IF;
END $$;

-- Step 4: Create index on moderation_status if missing
CREATE INDEX IF NOT EXISTS idx_tasks_moderation_status 
ON public.tasks (moderation_status);

-- Step 5: Drop and recreate RLS policies to ensure they use auth.uid()
DROP POLICY IF EXISTS tasks_select_visible ON public.tasks;
DROP POLICY IF EXISTS tasks_update_owner_or_assignee ON public.tasks;
DROP POLICY IF EXISTS tasks_insert_owner ON public.tasks;

-- Recreate policies with auth.uid()
CREATE POLICY tasks_select_visible ON public.tasks
    FOR SELECT
    TO authenticated
    USING (
        moderation_status = 'approved' 
        OR created_by = auth.uid() 
        OR assignee_id = auth.uid()
    );

CREATE POLICY tasks_update_owner_or_assignee ON public.tasks
    FOR UPDATE
    TO authenticated
    USING (auth.uid() IN (created_by, assignee_id))
    WITH CHECK (auth.uid() IN (created_by, assignee_id));

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

-- Step 7: Create the moderate_task_and_save function with EXACT signature
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
    moderation_result text := 'approved';
    moderation_reason_text text := '';
    task_row public.tasks;
    current_user_id uuid;
    combined_text text;
BEGIN
    -- Get current user
    current_user_id := auth.uid();
    
    -- Require authentication
    IF current_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    -- Combine all text fields for moderation
    combined_text := COALESCE(p_title, '') || ' ' || 
                    COALESCE(p_description, '') || ' ' || 
                    COALESCE(p_dropoff_instructions, '') || ' ' ||
                    COALESCE(p_store, '') || ' ' ||
                    COALESCE(p_dropoff_address, '');
    
    -- Convert to lowercase for case-insensitive matching
    combined_text := LOWER(combined_text);

    -- Content moderation checks
    IF combined_text ~ '\b(sex|sexual|porn|nude|naked|escort|hookup|dating|intimate|adult)\b' THEN
        moderation_result := 'blocked';
        moderation_reason_text := 'Sexual content is not allowed';
    ELSIF combined_text ~ '\b(kill|murder|violence|fight|beat|assault|weapon|gun|knife|bomb|explosive)\b' THEN
        moderation_result := 'blocked';
        moderation_reason_text := 'Violence or harmful content is not allowed';
    ELSIF combined_text ~ '\b(drug|weed|marijuana|cocaine|pills|molly|ecstasy|alcohol|beer|liquor|vape)\b' THEN
        moderation_result := 'blocked';
        moderation_reason_text := 'Illegal substances are not allowed';
    ELSIF combined_text ~ '\b(hate|racist|nazi|terrorist|extremist|radical)\b' THEN
        moderation_result := 'blocked';
        moderation_reason_text := 'Hate speech is not allowed';
    ELSIF combined_text ~ '\b(exam|test|quiz|homework|assignment|essay|paper|cheat|plagiarism)\b' THEN
        moderation_result := 'needs_review';
        moderation_reason_text := 'Academic content requires review';
    ELSIF combined_text ~ '\b(urgent|emergency|asap|now|immediately|help)\b' THEN
        moderation_result := 'needs_review';
        moderation_reason_text := 'Urgent requests require review';
    END IF;

    -- Reject blocked content immediately
    IF moderation_result = 'blocked' THEN
        RAISE EXCEPTION 'Content blocked: %', moderation_reason_text;
    END IF;

    -- Handle create vs update
    IF p_task_id IS NULL THEN
        -- INSERT new task
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
            current_user_id,
            moderation_result::public.task_moderation_status,
            CASE WHEN moderation_reason_text != '' THEN moderation_reason_text ELSE NULL END,
            now(),
            CASE WHEN moderation_result != 'approved' THEN current_user_id ELSE NULL END
        )
        RETURNING * INTO task_row;
    ELSE
        -- UPDATE existing task (only if owned by caller)
        UPDATE public.tasks 
        SET 
            title = p_title,
            description = p_description,
            category = p_category::public.task_category,
            store = p_store,
            dropoff_address = p_dropoff_address,
            dropoff_instructions = p_dropoff_instructions,
            urgency = p_urgency::public.task_urgency,
            estimated_minutes = p_estimated_minutes,
            reward_cents = p_reward_cents,
            moderation_status = moderation_result::public.task_moderation_status,
            moderation_reason = CASE WHEN moderation_reason_text != '' THEN moderation_reason_text ELSE NULL END,
            moderated_at = now(),
            moderated_by = CASE WHEN moderation_result != 'approved' THEN current_user_id ELSE NULL END,
            updated_at = now()
        WHERE id = p_task_id 
        AND created_by = current_user_id
        RETURNING * INTO task_row;

        -- Check if update affected any rows
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Task not found or not owned by caller';
        END IF;
    END IF;

    RETURN task_row;
END;
$$;

-- Step 8: Grant permissions
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(
    text, text, text, text, integer, integer, text, uuid, text, text
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(
    text, text, text, text, integer, integer, text, uuid, text, text
) TO service_role;

-- Step 9: Ensure RLS is enabled on tasks
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

-- Step 10: Add tasks to realtime publication if not already present
DO $$
BEGIN
    -- Check if tasks is already in the publication
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND tablename = 'tasks'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
    END IF;
END $$;

-- Step 11: Verification guard - check for any remaining references
DO $$
DECLARE
    func_def text;
    remaining_count integer;
BEGIN
    -- Get the function definition
    SELECT pg_get_functiondef(oid) INTO func_def
    FROM pg_proc 
    WHERE proname = 'moderate_task_and_save' 
    AND pronamespace = 'public'::regnamespace;
    
    -- Check for any remaining references (case insensitive)
    IF func_def ~* '\buid\s*\(' THEN
        RAISE EXCEPTION 'P0001: Found leftover usage in function definition';
    END IF;
    
    -- Verify exactly one function exists
    SELECT COUNT(*) INTO remaining_count
    FROM pg_proc 
    WHERE proname = 'moderate_task_and_save' 
    AND pronamespace = 'public'::regnamespace;
    
    IF remaining_count != 1 THEN
        RAISE EXCEPTION 'Expected exactly 1 moderate_task_and_save function, found %', remaining_count;
    END IF;
    
    RAISE NOTICE 'Function verification passed: clean moderate_task_and_save created';
END $$;