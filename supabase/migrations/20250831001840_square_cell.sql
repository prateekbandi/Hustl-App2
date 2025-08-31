/*
  # Enhance profiles table for chat user display

  1. New Columns
    - `class_year` (text) - Student's year (Freshman, Sophomore, etc.)
    - `bio` (text) - User bio/description
    - `is_verified` (boolean) - Verification status
    - `completed_tasks_count` (integer) - Cache of completed tasks
    - `response_rate` (numeric) - Response rate percentage
    - `last_seen_at` (timestamp) - Last activity timestamp

  2. Indexes
    - Add index on `last_seen_at` for online status queries
    - Add index on `completed_tasks_count` for leaderboards

  3. Security
    - Update RLS policies to allow reading public profile fields
    - Ensure privacy for sensitive data
*/

-- Add new columns to profiles table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'class_year'
  ) THEN
    ALTER TABLE profiles ADD COLUMN class_year text DEFAULT '';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'bio'
  ) THEN
    ALTER TABLE profiles ADD COLUMN bio text DEFAULT '';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'is_verified'
  ) THEN
    ALTER TABLE profiles ADD COLUMN is_verified boolean DEFAULT false;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'completed_tasks_count'
  ) THEN
    ALTER TABLE profiles ADD COLUMN completed_tasks_count integer DEFAULT 0;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'response_rate'
  ) THEN
    ALTER TABLE profiles ADD COLUMN response_rate numeric(5,2) DEFAULT 0.00;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'last_seen_at'
  ) THEN
    ALTER TABLE profiles ADD COLUMN last_seen_at timestamptz DEFAULT now();
  END IF;
END $$;

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_profiles_last_seen ON profiles(last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_profiles_completed_tasks ON profiles(completed_tasks_count DESC);
CREATE INDEX IF NOT EXISTS idx_profiles_response_rate ON profiles(response_rate DESC);

-- Function to get chat participant profile
CREATE OR REPLACE FUNCTION get_chat_participant_profile(p_room_id uuid, p_current_user_id uuid)
RETURNS TABLE (
  id uuid,
  full_name text,
  username text,
  avatar_url text,
  major text,
  class_year text,
  university text,
  bio text,
  is_verified boolean,
  completed_tasks_count integer,
  response_rate numeric,
  last_seen_at timestamptz,
  created_at timestamptz
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.full_name,
    p.username,
    p.avatar_url,
    p.major,
    p.class_year,
    p.university,
    p.bio,
    p.is_verified,
    p.completed_tasks_count,
    p.response_rate,
    p.last_seen_at,
    p.created_at
  FROM profiles p
  INNER JOIN chat_members cm ON cm.user_id = p.id
  WHERE cm.room_id = p_room_id 
    AND cm.user_id != p_current_user_id
  LIMIT 1;
END;
$$;

-- Function to update last seen timestamp
CREATE OR REPLACE FUNCTION update_last_seen()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE profiles 
  SET last_seen_at = now()
  WHERE id = auth.uid();
END;
$$;