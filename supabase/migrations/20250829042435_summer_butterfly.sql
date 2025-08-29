/*
  # Create task_current_status enum

  1. Enum Creation
    - Creates `task_current_status` enum with lowercase values
    - Safely adds missing enum values if enum already exists
    - No table modifications to avoid transaction conflicts

  2. Enum Values
    - `posted` - Task is available for acceptance
    - `accepted` - Task has been accepted by someone
    - `in_progress` - Task is being worked on
    - `completed` - Task has been finished
    - `cancelled` - Task has been cancelled
*/

-- Ensure enum type exists with all lowercase labels.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_current_status') THEN
    CREATE TYPE task_current_status AS ENUM (
      'posted','accepted','in_progress','completed','cancelled'
    );
  ELSE
    -- Add any missing values; safe to run multiple times.
    ALTER TYPE task_current_status ADD VALUE IF NOT EXISTS 'posted';
    ALTER TYPE task_current_status ADD VALUE IF NOT EXISTS 'accepted';
    ALTER TYPE task_current_status ADD VALUE IF NOT EXISTS 'in_progress';
    ALTER TYPE task_current_status ADD VALUE IF NOT EXISTS 'completed';
    ALTER TYPE task_current_status ADD VALUE IF NOT EXISTS 'cancelled';
  END IF;
END $$;