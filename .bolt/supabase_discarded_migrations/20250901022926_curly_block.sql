/*
  # Create missing task_category enum type

  1. New Types
    - `task_category` enum with values: 'food', 'grocery', 'coffee'
  
  2. Purpose
    - Fixes the "type public.task_category does not exist" error
    - Allows the moderate_task_and_save RPC function to work properly
*/

-- Create the missing task_category enum type
CREATE TYPE IF NOT EXISTS public.task_category AS ENUM ('food', 'grocery', 'coffee');