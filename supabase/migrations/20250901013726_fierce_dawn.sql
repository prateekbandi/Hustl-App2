/*
  # Consolidated Task System Migration

  This migration consolidates all task-related features into a single, canonical schema.
  
  ## 1. Core Features
    - Task phase tracking (none → started → on_the_way/completed → delivered/completed)
    - Task moderation system (approved/needs_review/blocked)
    - Profile relationships with proper foreign keys
    - Updated-at timestamp tracking
    - Realtime subscriptions

  ## 2. Database Objects
    - Enums: task_phase, task_moderation_status
    - Columns: tasks.phase, tasks.updated_at, moderation fields
    - Foreign Keys: tasks_created_by_fkey, tasks_assignee_id_fkey
    - RPC: update_task_phase(task_id, new_phase)
    - Trigger: trg_tasks_set_updated_at
    - RLS Policies: visibility based on moderation status and ownership
    - Realtime: public.tasks publication

  ## 3. Security
    - All policies use auth.uid() (never uid())
    - Only approved tasks visible publicly
    - Owners can always see their own tasks
    - Phase updates restricted to owner/assignee
*/

-- ============================================================================
-- 1. ENUMS
-- ============================================================================

-- Task phase enum for status tracking
DO $$ BEGIN
  CREATE TYPE public.task_phase AS ENUM ('none', 'started', 'on_the_way', 'delivered', 'completed');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- Task moderation status enum
DO $$ BEGIN
  CREATE TYPE public.task_moderation_status AS ENUM ('approved', 'needs_review', 'blocked');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- ============================================================================
-- 2. HELPER FUNCTIONS
-- ============================================================================

-- Updated-at trigger function
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 3. TABLE COLUMNS
-- ============================================================================

-- Add phase column if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'phase'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN phase public.task_phase NOT NULL DEFAULT 'none';
  END IF;
END $$;

-- Add updated_at column if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
  END IF;
END $$;

-- Add assignee_id column if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'assignee_id'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN assignee_id uuid;
  END IF;
END $$;

-- Add moderation columns if not exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'moderation_status'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN moderation_status public.task_moderation_status NOT NULL DEFAULT 'approved';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'moderation_reason'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN moderation_reason text;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'moderated_at'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN moderated_at timestamptz;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tasks' AND column_name = 'moderated_by'
  ) THEN
    ALTER TABLE public.tasks ADD COLUMN moderated_by uuid;
  END IF;
END $$;

-- ============================================================================
-- 4. INDEXES
-- ============================================================================

-- Index for moderation status filtering
CREATE INDEX IF NOT EXISTS idx_tasks_moderation_status ON public.tasks (moderation_status);

-- Index for phase filtering
CREATE INDEX IF NOT EXISTS idx_tasks_phase ON public.tasks (phase);

-- Index for updated_at ordering
CREATE INDEX IF NOT EXISTS idx_tasks_updated_at ON public.tasks (updated_at DESC);

-- ============================================================================
-- 5. FOREIGN KEYS
-- ============================================================================

-- FK to profiles for created_by (if not exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_schema = 'public' 
    AND table_name = 'tasks' 
    AND constraint_name = 'tasks_created_by_fkey'
  ) THEN
    ALTER TABLE public.tasks 
    ADD CONSTRAINT tasks_created_by_fkey 
    FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON UPDATE CASCADE ON DELETE CASCADE;
  END IF;
END $$;

-- FK to profiles for assignee_id (if not exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_schema = 'public' 
    AND table_name = 'tasks' 
    AND constraint_name = 'tasks_assignee_id_fkey'
  ) THEN
    ALTER TABLE public.tasks 
    ADD CONSTRAINT tasks_assignee_id_fkey 
    FOREIGN KEY (assignee_id) REFERENCES public.profiles(id) ON UPDATE CASCADE ON DELETE SET NULL;
  END IF;
END $$;

-- ============================================================================
-- 6. TRIGGERS
-- ============================================================================

-- Drop existing updated_at trigger if exists
DROP TRIGGER IF EXISTS trg_tasks_set_updated_at ON public.tasks;

-- Create updated_at trigger
CREATE TRIGGER trg_tasks_set_updated_at
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- 7. RLS POLICIES (Drop & Recreate with auth.uid())
-- ============================================================================

-- Enable RLS on tasks
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

-- Drop all existing task policies to avoid conflicts
DROP POLICY IF EXISTS "tasks_select_visible" ON public.tasks;
DROP POLICY IF EXISTS "tasks_select_approved_or_owner" ON public.tasks;
DROP POLICY IF EXISTS "tasks_update_owner_or_assignee" ON public.tasks;
DROP POLICY IF EXISTS "tasks_insert_owner" ON public.tasks;
DROP POLICY IF EXISTS "Users can read available tasks" ON public.tasks;
DROP POLICY IF EXISTS "Users can read own tasks" ON public.tasks;
DROP POLICY IF EXISTS "Users can read accepted tasks" ON public.tasks;
DROP POLICY IF EXISTS "Users can create tasks" ON public.tasks;
DROP POLICY IF EXISTS "Creator can update open tasks" ON public.tasks;
DROP POLICY IF EXISTS "Acceptor can update accepted tasks" ON public.tasks;
DROP POLICY IF EXISTS "accept_open_task" ON public.tasks;
DROP POLICY IF EXISTS "tasks_read_owner_or_assignee" ON public.tasks;
DROP POLICY IF EXISTS "tasks_update_owner_or_assignee" ON public.tasks;

-- Create canonical policies using auth.uid()
CREATE POLICY "tasks_select_visible" ON public.tasks
  FOR SELECT TO authenticated
  USING (
    moderation_status = 'approved' 
    OR created_by = auth.uid() 
    OR assignee_id = auth.uid()
  );

CREATE POLICY "tasks_update_owner_or_assignee" ON public.tasks
  FOR UPDATE TO authenticated
  USING (auth.uid() IN (created_by, assignee_id))
  WITH CHECK (auth.uid() IN (created_by, assignee_id));

CREATE POLICY "tasks_insert_owner" ON public.tasks
  FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid());

-- Profiles policies (ensure public read access)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_select_public" ON public.profiles;
DROP POLICY IF EXISTS "Anyone can read profiles" ON public.profiles;

CREATE POLICY "profiles_select_public" ON public.profiles
  FOR SELECT TO authenticated
  USING (true);

-- ============================================================================
-- 8. RPC FUNCTIONS (Drop & Recreate with auth.uid())
-- ============================================================================

-- Drop any existing update_task_phase functions
DROP FUNCTION IF EXISTS public.update_task_phase(uuid, public.task_phase);
DROP FUNCTION IF EXISTS public.update_task_phase(p_task_id uuid, p_new_phase public.task_phase);
DROP FUNCTION IF EXISTS public.update_task_phase(task_id uuid, new_phase public.task_phase);

-- Create canonical update_task_phase function
CREATE OR REPLACE FUNCTION public.update_task_phase(
  task_id uuid,
  new_phase public.task_phase
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  task_record public.tasks%ROWTYPE;
  new_status public.task_status;
  current_user_id uuid;
BEGIN
  -- Get current user
  current_user_id := auth.uid();
  IF current_user_id IS NULL THEN
    RETURN json_build_object('error', 'not_authenticated');
  END IF;

  -- Get task and verify ownership
  SELECT * INTO task_record
  FROM public.tasks
  WHERE id = task_id;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'task_not_found');
  END IF;

  -- Check authorization (owner or assignee)
  IF current_user_id NOT IN (task_record.created_by, task_record.assignee_id) THEN
    RETURN json_build_object('error', 'not_authorized');
  END IF;

  -- Check if task is already completed or cancelled
  IF task_record.status IN ('completed', 'cancelled') THEN
    RETURN json_build_object('error', 'task_already_completed');
  END IF;

  -- Validate phase transition based on category
  IF NOT is_valid_phase_transition(task_record.category, task_record.phase, new_phase) THEN
    RETURN json_build_object('error', 'invalid_phase_transition');
  END IF;

  -- Determine new status based on phase
  CASE new_phase
    WHEN 'completed', 'delivered' THEN
      new_status := 'completed';
    WHEN 'started', 'on_the_way' THEN
      new_status := 'accepted'; -- Keep as accepted for in-progress phases
    ELSE
      new_status := task_record.status; -- Keep current status
  END CASE;

  -- Update task
  UPDATE public.tasks
  SET 
    phase = new_phase,
    status = new_status,
    updated_at = now()
  WHERE id = task_id;

  -- Return updated task
  SELECT * INTO task_record FROM public.tasks WHERE id = task_id;
  
  RETURN json_build_object(
    'success', true,
    'task', row_to_json(task_record)
  );
END;
$$;

-- Helper function for phase transition validation
CREATE OR REPLACE FUNCTION public.is_valid_phase_transition(
  category text,
  current_phase public.task_phase,
  new_phase public.task_phase
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  -- Food delivery flow: none → started → on_the_way → delivered
  IF category = 'food' AND current_phase = 'none' AND new_phase = 'started' THEN
    RETURN true;
  END IF;
  IF category = 'food' AND current_phase = 'started' AND new_phase IN ('on_the_way', 'completed') THEN
    RETURN true;
  END IF;
  IF category = 'food' AND current_phase = 'on_the_way' AND new_phase = 'delivered' THEN
    RETURN true;
  END IF;

  -- Other categories: none → started → completed
  IF category != 'food' AND current_phase = 'none' AND new_phase = 'started' THEN
    RETURN true;
  END IF;
  IF category != 'food' AND current_phase = 'started' AND new_phase = 'completed' THEN
    RETURN true;
  END IF;

  -- Allow direct completion from any phase (emergency completion)
  IF new_phase = 'completed' THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

-- Drop any existing moderation functions
DROP FUNCTION IF EXISTS public.moderate_task_and_save(text, text, text, text, text, text, text, integer, integer, uuid);

-- Create moderation function (simplified for this consolidation)
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
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id uuid;
  new_task_id uuid;
  moderation_result text;
  moderation_reason_text text;
BEGIN
  -- Get current user
  current_user_id := auth.uid();
  IF current_user_id IS NULL THEN
    RETURN json_build_object('error', 'not_authenticated');
  END IF;

  -- Simple keyword-based moderation (placeholder)
  -- In production, this would call external moderation service
  moderation_result := 'approved';
  moderation_reason_text := NULL;

  -- Basic keyword screening
  IF p_title ~* '\b(sex|nude|escort|hookup|drug|weapon|kill|assault)\b' OR
     p_description ~* '\b(sex|nude|escort|hookup|drug|weapon|kill|assault)\b' THEN
    moderation_result := 'blocked';
    moderation_reason_text := 'Content violates community guidelines';
  END IF;

  -- Insert or update task
  IF p_task_id IS NULL THEN
    -- Create new task
    INSERT INTO public.tasks (
      title, description, dropoff_instructions, store, dropoff_address,
      category, urgency, estimated_minutes, reward_cents,
      created_by, moderation_status, moderation_reason, moderated_at
    ) VALUES (
      p_title, p_description, p_dropoff_instructions, p_store, p_dropoff_address,
      p_category::public.task_category, p_urgency::public.task_urgency, 
      p_estimated_minutes, p_reward_cents,
      current_user_id, moderation_result::public.task_moderation_status, 
      moderation_reason_text, now()
    ) RETURNING id INTO new_task_id;
  ELSE
    -- Update existing task (for edit & resubmit)
    UPDATE public.tasks
    SET 
      title = p_title,
      description = p_description,
      dropoff_instructions = p_dropoff_instructions,
      store = p_store,
      dropoff_address = p_dropoff_address,
      category = p_category::public.task_category,
      urgency = p_urgency::public.task_urgency,
      estimated_minutes = p_estimated_minutes,
      reward_cents = p_reward_cents,
      moderation_status = moderation_result::public.task_moderation_status,
      moderation_reason = moderation_reason_text,
      moderated_at = now(),
      updated_at = now()
    WHERE id = p_task_id AND created_by = current_user_id
    RETURNING id INTO new_task_id;

    IF new_task_id IS NULL THEN
      RETURN json_build_object('error', 'task_not_found_or_not_owner');
    END IF;
  END IF;

  RETURN json_build_object(
    'status', moderation_result,
    'reason', moderation_reason_text,
    'task_id', COALESCE(new_task_id, p_task_id)
  );
END;
$$;

-- ============================================================================
-- 9. TRIGGERS
-- ============================================================================

-- Drop existing updated_at triggers to avoid duplicates
DROP TRIGGER IF EXISTS trg_tasks_set_updated_at ON public.tasks;
DROP TRIGGER IF EXISTS update_tasks_updated_at ON public.tasks;

-- Create canonical updated_at trigger
CREATE TRIGGER trg_tasks_set_updated_at
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- 10. GRANTS
-- ============================================================================

-- Grant execute permissions on functions
GRANT EXECUTE ON FUNCTION public.update_task_phase(uuid, public.task_phase) TO authenticated;
GRANT EXECUTE ON FUNCTION public.moderate_task_and_save(text, text, text, text, text, text, text, integer, integer, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_valid_phase_transition(text, public.task_phase, public.task_phase) TO authenticated;

-- ============================================================================
-- 11. REALTIME
-- ============================================================================

-- Add tasks to realtime publication if not already present
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND schemaname = 'public' 
    AND tablename = 'tasks'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
  END IF;
END $$;

-- ============================================================================
-- 12. DATA BACKFILLS (Safe)
-- ============================================================================

-- Set default phase for existing tasks
UPDATE public.tasks 
SET phase = 'none' 
WHERE phase IS NULL;

-- Set default moderation status for existing tasks
UPDATE public.tasks 
SET moderation_status = 'approved' 
WHERE moderation_status IS NULL;