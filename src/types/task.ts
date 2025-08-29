export type TaskStatus = 'posted' | 'accepted' | 'in_progress' | 'completed' | 'cancelled';

export interface Task {
  id: string;
  title: string;
  description?: string | null;
  created_by: string;
  accepted_by?: string | null;
  task_current_status: TaskStatus;
  accepted_at?: string | null;
  updated_at?: string | null;
  store?: string;
  dropoff_address?: string;
  reward_cents?: number;
  estimated_minutes?: number;
  urgency?: string;
  category?: string;
}