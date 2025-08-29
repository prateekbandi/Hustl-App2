import { supabase } from '../lib/supabase';
import type { Task } from '../types/task';

export async function acceptTask(taskId: string): Promise<Task> {
  const { data, error } = await supabase.rpc('accept_task', { p_task_id: taskId });
  
  if (error) {
    // Map common DB errors to friendly messages
    const msg = error.message || '';
    if (msg.includes('not_authenticated')) throw new Error('Please sign in to accept tasks.');
    if (msg.includes('task_not_found')) throw new Error('Task not found.');
    if (msg.includes('cannot_accept_own_task')) throw new Error("You can't accept your own task.");
    if (msg.includes('task_not_posted')) throw new Error('This task has already been accepted or is no longer available.');
    // Fallback (e.g., previous 22P02 enum issues)
    throw new Error('Failed to accept task. Please try again.');
  }
  
  return data as Task;
}