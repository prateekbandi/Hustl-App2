/*
  # Add reviews table for task feedback

  1. New Tables
    - `reviews`
      - `id` (uuid, primary key)
      - `task_id` (uuid, foreign key to tasks)
      - `reviewer_id` (uuid, references profiles)
      - `reviewee_id` (uuid, references profiles)
      - `rating` (integer, 1-5 stars)
      - `comment` (text, optional feedback)
      - `created_at` (timestamp)

  2. Security
    - Enable RLS on `reviews` table
    - Add policy for users to insert their own reviews
    - Add policy for users to read reviews they're involved in

  3. Indexes
    - Index on task_id for quick lookups
    - Index on reviewer_id and reviewee_id for user queries
    - Unique constraint on (task_id, reviewer_id) to prevent duplicate reviews
*/

-- Create reviews table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  reviewer_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reviewee_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rating integer NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment text DEFAULT '',
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_reviews_task_id ON public.reviews(task_id);
CREATE INDEX IF NOT EXISTS idx_reviews_reviewer_id ON public.reviews(reviewer_id);
CREATE INDEX IF NOT EXISTS idx_reviews_reviewee_id ON public.reviews(reviewee_id);
CREATE INDEX IF NOT EXISTS idx_reviews_created_at ON public.reviews(created_at DESC);

-- Unique constraint to prevent duplicate reviews per task
CREATE UNIQUE INDEX IF NOT EXISTS reviews_unique_per_task_reviewer 
ON public.reviews(task_id, reviewer_id);

-- RLS Policies
CREATE POLICY "Users can insert their own reviews"
  ON public.reviews
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = reviewer_id);

CREATE POLICY "Users can read reviews they're involved in"
  ON public.reviews
  FOR SELECT
  TO authenticated
  USING (auth.uid() = reviewer_id OR auth.uid() = reviewee_id);

-- RPC to check if user can review a task
CREATE OR REPLACE FUNCTION public.can_review_task(p_task_id uuid)
RETURNS TABLE(can_review boolean, other_user_id uuid, reason text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  task_record public.tasks%ROWTYPE;
  existing_review_count integer;
  other_id uuid;
BEGIN
  -- Get task details
  SELECT * INTO task_record
  FROM public.tasks
  WHERE id = p_task_id;

  -- Check if task exists and is completed
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, null::uuid, 'Task not found';
    RETURN;
  END IF;

  IF task_record.status != 'completed' THEN
    RETURN QUERY SELECT false, null::uuid, 'Task not completed yet';
    RETURN;
  END IF;

  -- Determine other participant
  IF auth.uid() = task_record.created_by THEN
    other_id := task_record.assignee_id;
  ELSIF auth.uid() = task_record.assignee_id THEN
    other_id := task_record.created_by;
  ELSE
    RETURN QUERY SELECT false, null::uuid, 'Not authorized to review this task';
    RETURN;
  END IF;

  IF other_id IS NULL THEN
    RETURN QUERY SELECT false, null::uuid, 'No other participant found';
    RETURN;
  END IF;

  -- Check for existing review
  SELECT COUNT(*) INTO existing_review_count
  FROM public.reviews
  WHERE task_id = p_task_id 
    AND reviewer_id = auth.uid()
    AND reviewee_id = other_id;

  IF existing_review_count > 0 THEN
    RETURN QUERY SELECT false, other_id, 'Already reviewed';
    RETURN;
  END IF;

  RETURN QUERY SELECT true, other_id, 'Can review';
END;
$$;

-- RPC to submit a review
CREATE OR REPLACE FUNCTION public.submit_task_review(
  p_task_id uuid,
  p_rating integer,
  p_comment text DEFAULT ''
)
RETURNS TABLE(success boolean, error_message text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  review_check_result RECORD;
BEGIN
  -- Validate the review request
  SELECT * INTO review_check_result
  FROM public.can_review_task(p_task_id);

  IF NOT review_check_result.can_review THEN
    RETURN QUERY SELECT false, review_check_result.reason;
    RETURN;
  END IF;

  -- Insert the review
  INSERT INTO public.reviews (task_id, reviewer_id, reviewee_id, rating, comment)
  VALUES (p_task_id, auth.uid(), review_check_result.other_user_id, p_rating, p_comment);

  RETURN QUERY SELECT true, 'Review submitted successfully';
END;
$$;