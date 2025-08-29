import { supabase } from '../lib/supabase';
import type { Task, TaskStatus } from '../types/task';

export async function acceptTask(taskId: string): Promise<Task> {
  const { data, error } = await supabase.rpc('accept_task', { task_id: taskId });
  
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

export async function updateTaskStatus(taskId: string, next: TaskStatus): Promise<Task> {
  // Prefer RPC if available
  const rpc = await supabase.rpc('update_task_status', { task_id: taskId, next_status: next });
  if (!rpc.error && rpc.data) return rpc.data as Task;

  // Fallback: direct update (assumes RLS allows accepted_by or created_by to update)
  const { data, error } = await supabase
    .from('tasks')
    .update({ task_current_status: next, updated_at: new Date().toISOString() })
    .eq('id', taskId)
    .select('*')
    .single();

  if (error) {
    throw new Error(error.message || 'Failed to update status.');
  }
  return data as Task;
}

export async function getTask(taskId: string): Promise<Task> {
  const { data, error } = await supabase
    .from('tasks')
    .select('*')
    .eq('id', taskId)
    .single();
  if (error) throw new Error(error.message);
  return data as Task;
}