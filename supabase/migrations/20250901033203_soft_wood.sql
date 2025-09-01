/*
  # Hard-reset uid() → auth.uid() and rebuild posting/moderation RPC

  This migration performs a comprehensive cleanup and rebuild:

  1. **Phase 0**: Preflight logging of current uid() usage
  2. **Phase 1**: Drop all functions containing uid() patterns
  3. **Phase 2**: Ensure task schema with moderation columns
  4. **Phase 3**: Create legacy safety enum (not used in RPC)
  5. **Phase 4**: Rebuild RLS policies with auth.uid() only
  6. **Phase 5**: Create canonical moderate_task_and_save RPC (TEXT-only)
  7. **Phase 6**: Setup realtime and refresh PostgREST
  8. **Phase 7**: Global verification - fail if any uid() remains

  ## Key Features
  - Completely idempotent and safe to re-run
  - Uses only auth.uid() throughout (never uid())
  - Treats category as pure TEXT (no enum dependencies)
  - Comprehensive verification prevents regressions
  - Exact 10-parameter RPC signature matching client expectations
*/

-- Phase 0: Preflight logging (capture current state)
DO $$
DECLARE
    func_record RECORD;
    policy_record RECORD;
    uid_function_count INTEGER := 0;
BEGIN
    RAISE NOTICE 'Phase 0: Preflight - Scanning for uid() usage...';
    
    -- Log functions containing uid()
    FOR func_record IN 
        SELECT 
            n.nspname as schema_name,
            p.proname as function_name,
            pg_get_function_identity_arguments(p.oid) as identity_args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
        AND lower(pg_get_functiondef(p.oid)) ~ '\buid\s*\('
    LOOP
        RAISE NOTICE 'Found uid() in function: %.%(%)', 
            func_record.schema_name, 
            func_record.function_name, 
            func_record.identity_args;
        uid_function_count := uid_function_count + 1;
    END LOOP;
    
    RAISE NOTICE 'Total functions with uid(): %', uid_function_count;
    
    -- Log existing policies on tasks and profiles
    FOR policy_record IN
        SELECT schemaname, tablename, policyname
        FROM pg_policies 
        WHERE schemaname = 'public' 
        AND tablename IN ('tasks', 'profiles')
    LOOP
        RAISE NOTICE 'Found policy: %.%.%', 
            policy_record.schemaname, 
            policy_record.tablename, 
            policy_record.policyname;
    END LOOP;
END $$;

-- Phase 1: Purge all uid() functions
DO $$
DECLARE
    func_record RECORD;
    drop_count INTEGER := 0;
BEGIN
    RAISE NOTICE 'Phase 1: Dropping all functions containing uid()...';
    
    FOR func_record IN 
        SELECT 
            p.oid,
            p.proname as function_name,
            pg_get_function_identity_arguments(p.oid) as identity_args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
        AND lower(pg_get_functiondef(p.oid)) ~ '\buid\s*\('
    LOOP
        EXECUTE format('DROP FUNCTION IF EXISTS public.%s(%s)', 
            func_record.function_name, 
            func_record.identity_args);
        
        RAISE NOTICE 'Dropped function: %(%)', 
            func_record.function_name, 
            func_record.identity_args;
        drop_count := drop_count + 1;
    END LOOP;
    
    RAISE NOTICE 'Dropped % functions containing uid()', drop_count;
END $$;

-- Phase 2: Ensure moderation schema (idempotent)
DO $$
BEGIN
    RAISE NOTICE 'Phase 2: Ensuring moderation schema...';
    
    -- Create moderation status enum if missing
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_moderation_status') THEN
        CREATE TYPE public.task_moderation_status AS ENUM ('approved', 'needs_review', 'blocked');
        RAISE NOTICE 'Created enum: task_moderation_status';
    END IF;
END $$;

-- Add required columns to tasks table (idempotent)
DO $$
BEGIN
    -- Core task columns
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'title') THEN
        ALTER TABLE public.tasks ADD COLUMN title text;
        RAISE NOTICE 'Added column: tasks.title';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'description') THEN
        ALTER TABLE public.tasks ADD COLUMN description text;
        RAISE NOTICE 'Added column: tasks.description';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'category') THEN
        ALTER TABLE public.tasks ADD COLUMN category text;
        RAISE NOTICE 'Added column: tasks.category';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'urgency') THEN
        ALTER TABLE public.tasks ADD COLUMN urgency text;
        RAISE NOTICE 'Added column: tasks.urgency';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'dropoff_address') THEN
        ALTER TABLE public.tasks ADD COLUMN dropoff_address text;
        RAISE NOTICE 'Added column: tasks.dropoff_address';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'dropoff_instructions') THEN
        ALTER TABLE public.tasks ADD COLUMN dropoff_instructions text;
        RAISE NOTICE 'Added column: tasks.dropoff_instructions';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'store') THEN
        ALTER TABLE public.tasks ADD COLUMN store text;
        RAISE NOTICE 'Added column: tasks.store';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'estimated_minutes') THEN
        ALTER TABLE public.tasks ADD COLUMN estimated_minutes integer;
        RAISE NOTICE 'Added column: tasks.estimated_minutes';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'reward_cents') THEN
        ALTER TABLE public.tasks ADD COLUMN reward_cents integer;
        RAISE NOTICE 'Added column: tasks.reward_cents';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'created_by') THEN
        ALTER TABLE public.tasks ADD COLUMN created_by uuid;
        RAISE NOTICE 'Added column: tasks.created_by';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'assignee_id') THEN
        ALTER TABLE public.tasks ADD COLUMN assignee_id uuid;
        RAISE NOTICE 'Added column: tasks.assignee_id';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'updated_at') THEN
        ALTER TABLE public.tasks ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
        RAISE NOTICE 'Added column: tasks.updated_at';
    END IF;
    
    -- Moderation columns
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'moderation_status') THEN
        ALTER TABLE public.tasks ADD COLUMN moderation_status public.task_moderation_status NOT NULL DEFAULT 'approved';
        RAISE NOTICE 'Added column: tasks.moderation_status';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'moderation_reason') THEN
        ALTER TABLE public.tasks ADD COLUMN moderation_reason text;
        RAISE NOTICE 'Added column: tasks.moderation_reason';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'moderated_at') THEN
        ALTER TABLE public.tasks ADD COLUMN moderated_at timestamptz;
        RAISE NOTICE 'Added column: tasks.moderated_at';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tasks' AND column_name = 'moderated_by') THEN
        ALTER TABLE public.tasks ADD COLUMN moderated_by uuid;
        RAISE NOTICE 'Added column: tasks.moderated_by';
    END IF;
END $$;

-- Backfill moderation status
UPDATE public.tasks 
SET moderation_status = 'approved' 
WHERE moderation_status IS NULL;

-- Create index if missing
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_tasks_moderation_status') THEN
        CREATE INDEX idx_tasks_moderation_status ON public.tasks (moderation_status);
        RAISE NOTICE 'Created index: idx_tasks_moderation_status';
    END IF;
END $$;

-- Create updated_at trigger function (auth.uid() only)
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END $$;

-- Drop and recreate trigger
DROP TRIGGER IF EXISTS trg_tasks_set_updated_at ON public.tasks;
CREATE TRIGGER trg_tasks_set_updated_at
    BEFORE UPDATE ON public.tasks
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

RAISE NOTICE 'Created updated_at trigger';

-- Phase 3: Legacy safety enum (not used in RPC)
DO $$
BEGIN
    RAISE NOTICE 'Phase 3: Creating legacy safety enum...';
    
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_category') THEN
        CREATE TYPE public.task_category AS ENUM ('food_delivery', 'food_pickup', 'workout', 'errand', 'other');
        RAISE NOTICE 'Created legacy enum: task_category (not used in RPC)';
    END IF;
END $$;

-- Phase 4: Rebuild RLS with auth.uid() only
DO $$
BEGIN
    RAISE NOTICE 'Phase 4: Rebuilding RLS policies...';
    
    -- Enable RLS
    ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
    
    -- Drop existing policies
    DROP POLICY IF EXISTS tasks_select_visible ON public.tasks;
    DROP POLICY IF EXISTS tasks_update_owner_or_assignee ON public.tasks;
    DROP POLICY IF EXISTS tasks_insert_owner ON public.tasks;
    DROP POLICY IF EXISTS profiles_select_public ON public.profiles;
    
    -- Recreate policies with auth.uid()
    CREATE POLICY tasks_select_visible ON public.tasks
        FOR SELECT
        TO authenticated
        USING (moderation_status = 'approved' OR auth.uid() = created_by OR auth.uid() = assignee_id);
    
    CREATE POLICY tasks_update_owner_or_assignee ON public.tasks
        FOR UPDATE
        TO authenticated
        USING (auth.uid() = created_by OR auth.uid() = assignee_id)
        WITH CHECK (auth.uid() = created_by OR auth.uid() = assignee_id);
    
    CREATE POLICY tasks_insert_owner ON public.tasks
        FOR INSERT
        TO authenticated
        WITH CHECK (created_by = auth.uid());
    
    -- Profiles read policy
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'profiles' AND policyname = 'profiles_select_public') THEN
        ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
        CREATE POLICY profiles_select_public ON public.profiles
            FOR SELECT
            TO authenticated
            USING (true);
    END IF;
    
    RAISE NOTICE 'Recreated RLS policies with auth.uid()';
END $$;

-- Phase 5: Rebuild the RPC (TEXT-only, exact client params, no uid() anywhere)
DO $$
DECLARE
    func_record RECORD;
    drop_count INTEGER := 0;
BEGIN
    RAISE NOTICE 'Phase 5: Rebuilding moderate_task_and_save RPC...';
    
    -- Drop all existing moderate_task_and_save functions
    FOR func_record IN 
        SELECT 
            p.proname as function_name,
            pg_get_function_identity_arguments(p.oid) as identity_args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
        AND p.proname = 'moderate_task_and_save'
    LOOP
        EXECUTE format('DROP FUNCTION IF EXISTS public.%s(%s)', 
            func_record.function_name, 
            func_record.identity_args);
        
        RAISE NOTICE 'Dropped function: %(%)', 
            func_record.function_name, 
            func_record.identity_args;
        drop_count := drop_count + 1;
    END LOOP;
    
    RAISE NOTICE 'Dropped % moderate_task_and_save functions', drop_count;
END $$;

-- Create the canonical moderate_task_and_save function
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
    v_moderation_status public.task_moderation_status;
    v_moderation_reason text;
    v_category text;
    v_result public.tasks;
BEGIN
    -- Get authenticated user ID
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING HINT = 'User must be authenticated';
    END IF;
    
    -- Normalize category (default to 'other', treat as TEXT only)
    v_category := COALESCE(NULLIF(trim(p_category), ''), 'other');
    
    -- Lightweight synchronous moderation
    v_moderation_status := 'approved';
    v_moderation_reason := NULL;
    
    -- Check for blocked content (sexual, violence, drugs)
    IF lower(p_title || ' ' || COALESCE(p_description, '')) ~ '\b(sex|sexual|porn|nude|naked|escort|prostitut|drug|cocaine|heroin|meth|weed|marijuana|cannabis|gun|weapon|knife|bomb|kill|murder|assault|rape)\b' THEN
        v_moderation_status := 'blocked';
        v_moderation_reason := 'Content violates community guidelines';
    -- Check for spam patterns
    ELSIF lower(p_title || ' ' || COALESCE(p_description, '')) ~ '\b(free money|get rich|click here|buy now|limited time|act now|guaranteed|miracle|amazing deal)\b' THEN
        v_moderation_status := 'needs_review';
        v_moderation_reason := 'Potential spam content detected';
    END IF;
    
    IF p_task_id IS NULL THEN
        -- Insert new task
        INSERT INTO public.tasks (
            title,
            description,
            category,
            urgency,
            dropoff_address,
            dropoff_instructions,
            store,
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
            v_category,
            COALESCE(NULLIF(trim(p_urgency), ''), 'medium'),
            p_dropoff_address,
            p_dropoff_instructions,
            p_store,
            COALESCE(p_estimated_minutes, 30),
            COALESCE(p_reward_cents, 200),
            v_user_id,
            v_moderation_status,
            v_moderation_reason,
            CASE WHEN v_moderation_status != 'approved' THEN now() ELSE NULL END,
            CASE WHEN v_moderation_status != 'approved' THEN v_user_id ELSE NULL END
        ) RETURNING * INTO v_result;
        
    ELSE
        -- Update existing task (only if owned by user)
        UPDATE public.tasks SET
            title = p_title,
            description = p_description,
            category = v_category,
            urgency = COALESCE(NULLIF(trim(p_urgency), ''), 'medium'),
            dropoff_address = p_dropoff_address,
            dropoff_instructions = p_dropoff_instructions,
            store = p_store,
            estimated_minutes = COALESCE(p_estimated_minutes, 30),
            reward_cents = COALESCE(p_reward_cents, 200),
            moderation_status = v_moderation_status,
            moderation_reason = v_moderation_reason,
            moderated_at = CASE WHEN v_moderation_status != 'approved' THEN now() ELSE NULL END,
            moderated_by = CASE WHEN v_moderation_status != 'approved' THEN v_user_id ELSE NULL END,
            updated_at = now()
        WHERE id = p_task_id AND created_by = v_user_id
        RETURNING * INTO v_result;
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'not_authorized' USING HINT = 'Task not found or not owned by user';
        END IF;
    END IF;
    
    RETURN v_result;
END $$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save TO authenticated;
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save TO service_role;

RAISE NOTICE 'Created canonical moderate_task_and_save function';

-- Phase 3: Legacy safety enum (not used in RPC)
DO $$
BEGIN
    RAISE NOTICE 'Phase 3: Creating legacy safety enum...';
    
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_category') THEN
        CREATE TYPE public.task_category AS ENUM ('food_delivery', 'food_pickup', 'workout', 'errand', 'other');
        RAISE NOTICE 'Created legacy enum: task_category (not used in RPC)';
    END IF;
END $$;

-- Phase 6: Realtime & cache
DO $$
BEGIN
    RAISE NOTICE 'Phase 6: Setting up realtime and refreshing cache...';
    
    -- Add tasks to realtime publication (safe if already exists)
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
        RAISE NOTICE 'Added public.tasks to realtime publication';
    EXCEPTION WHEN duplicate_object THEN
        RAISE NOTICE 'public.tasks already in realtime publication';
    END;
    
    -- Refresh PostgREST schema cache
    NOTIFY pgrst, 'reload schema';
    RAISE NOTICE 'Refreshed PostgREST schema cache';
END $$;

-- Phase 7: Global verification (fail fast if any uid() remains)
DO $$
DECLARE
    func_record RECORD;
    uid_function_count INTEGER := 0;
    moderate_function_count INTEGER := 0;
    function_body text;
    offending_functions text := '';
BEGIN
    RAISE NOTICE 'Phase 7: Global verification...';
    
    -- Scan for any remaining uid() usage
    FOR func_record IN 
        SELECT 
            p.proname as function_name,
            pg_get_function_identity_arguments(p.oid) as identity_args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
        AND lower(pg_get_functiondef(p.oid)) ~ '\buid\s*\('
    LOOP
        uid_function_count := uid_function_count + 1;
        offending_functions := offending_functions || format('%s(%s), ', 
            func_record.function_name, 
            func_record.identity_args);
    END LOOP;
    
    IF uid_function_count > 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: % functions still contain uid(): %', 
            uid_function_count, 
            trim(trailing ', ' from offending_functions);
    END IF;
    
    -- Count moderate_task_and_save functions with 10 arguments
    SELECT COUNT(*) INTO moderate_function_count
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
    AND p.proname = 'moderate_task_and_save'
    AND p.pronargs = 10;
    
    IF moderate_function_count = 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: No moderate_task_and_save function with 10 arguments found';
    ELSIF moderate_function_count > 1 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: Multiple moderate_task_and_save functions with 10 arguments found: %', moderate_function_count;
    END IF;
    
    -- Verify the function body
    SELECT pg_get_functiondef(p.oid) INTO function_body
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
    AND p.proname = 'moderate_task_and_save'
    AND p.pronargs = 10
    LIMIT 1;
    
    IF lower(function_body) ~ '\buid\s*\(' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: moderate_task_and_save function body contains forbidden uid()';
    END IF;
    
    IF lower(function_body) ~ '::public\.task_category' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: moderate_task_and_save function body contains forbidden enum cast ::public.task_category';
    END IF;
    
    RAISE NOTICE 'VERIFICATION PASSED: All uid() usage eliminated, moderate_task_and_save function is clean';
END $$;

RAISE NOTICE 'Migration completed successfully - task posting should now work';

/*
  ## Acceptance Tests (verify after applying)
  
  1. **RPC Endpoint Test**:
     ```
     POST /rest/v1/rpc/moderate_task_and_save
     {
       "p_category": "food",
       "p_description": "Pick up my lunch",
       "p_dropoff_address": "Dorm Room 123",
       "p_dropoff_instructions": "Leave at door",
       "p_estimated_minutes": 20,
       "p_reward_cents": 300,
       "p_store": "Chipotle",
       "p_task_id": null,
       "p_title": "Lunch pickup",
       "p_urgency": "medium"
     }
     ```
     Should return 200 with task row.
  
  2. **Moderation Test**:
     - Sexual/violent content → blocked
     - Spam patterns → needs_review  
     - Clean content → approved
  
  3. **RLS Test**:
     - Approved tasks visible to all authenticated users
     - Blocked/needs_review tasks visible only to creator
     - Only task owner/assignee can update
  
  4. **Verification Test**:
     - Exactly 1 moderate_task_and_save function with 10 arguments
     - Function body contains no uid() patterns
     - Function body contains no ::public.task_category casts
  
  5. **Idempotency Test**:
     - Re-running migration produces no errors
     - No duplicate objects created
*/