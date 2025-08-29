export type TaskStatus = 'posted' | 'accepted' | 'in_progress' | 'completed' | 'cancelled';

export interface Task {
  id: string;
  title: string;
  description: string;
  category: string;
  store: string;
  dropoff_address: string;
  dropoff_instructions: string;
  urgency: string;
  reward_cents: number;
  estimated_minutes: number;
  created_by: string;
  task_current_status: TaskStatus;
  accepted_by?: string | null;
  accepted_at?: string | null;
  updated_at?: string | null;
  created_at: string;
}