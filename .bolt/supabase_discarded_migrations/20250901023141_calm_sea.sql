/*
  # Create missing task_category enum type

  1. New Types
    - `task_category` enum with values: 'food', 'grocery', 'coffee'
  
  2. Purpose
    - Resolves "type public.task_category does not exist" error
    - Matches the check constraint on tasks.category column
    - Enables moderate_task_and_save RPC function to work properly
*/

-- Create the missing task_category enum type
CREATE TYPE IF NOT EXISTS public.task_category AS ENUM ('food', 'grocery', 'coffee');

-- Refresh the schema cache to make the type immediately available
NOTIFY pgrst, 'reload schema';