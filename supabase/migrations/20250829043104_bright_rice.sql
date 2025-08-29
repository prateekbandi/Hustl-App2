/*
  # Create task_current_status enum

  1. New Types
    - `task_current_status` enum with lowercase values:
      - `posted` - Task is available for acceptance
      - `accepted` - Task has been accepted by someone
      - `in_progress` - Task work has started
      - `completed` - Task is finished
      - `cancelled` - Task was cancelled

  2. Notes
    - This migration only creates the enum type
    - No table changes to avoid transaction conflicts
    - Safe to run multiple times (idempotent)
*/

-- Ensure enum type exists with all lowercase labels
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_current_status') THEN
    CREATE TYPE task_current_status AS ENUM (
      'posted','accepted','in_progress','completed','cancelled'
    );
  ELSE
    -- Add any missing values; safe to run multiple times
    ALTER TYPE task_current_status ADD VALUE IF NOT EXISTS 'posted';
    ALTER TYPE task_current_status ADD VALUE IF NOT EXISTS 'accepted';
    ALTER TYPE task_current_status ADD VALUE IF NOT EXISTS 'in_progress';
    ALTER TYPE task_current_status ADD VALUE IF NOT EXISTS 'completed';
    ALTER TYPE task_current_status ADD VALUE IF NOT EXISTS 'cancelled';
  END IF;
END $$;