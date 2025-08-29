import { supabase } from './supabase';
import type { Task, CreateTaskData, TaskStatus, TaskCategory, TaskUrgency, TaskCurrentStatus, TaskStatusHistory, UpdateTaskStatusData } from '@/types/database';

/**
 * Safe Task Repository - Eliminates 406 PGRST116 errors completely
 * 
 * Rules:
 * 1. NEVER use .single() or .maybeSingle() - always use .limit(1) + [0]
 * 2. Fetch by ID uses ONLY id filter, no status/created_by filters
 * 3. All single fetches return null for 0 rows (never throw)
 * 4. Business logic validation happens in application code
 * 5. Atomic updates use RPC functions for race condition protection
 */
export class TaskRepo {
  /**
   * Safe single task fetch - NEVER returns 406 PGRST116
   * Only filters by ID, returns null if not found
   */
  static async getTaskByIdSafe(taskId: string): Promise<{ data: Task | null; error: string | null }> {
    try {
      const { data, error } = await supabase
        .from('tasks')
        .select('*')
        .eq('id', taskId)
        .limit(1);

      if (error) {
        return { data: null, error: error.message };
      }

      const task = data?.[0] ?? null;
      return { data: task, error: null };
    } catch (error) {
      return { data: null, error: 'Network error. Please check your connection.' };
    }
  }

  /**
   * Get available tasks (open tasks not created by current user)
   * Safe list query - never uses .single()
   */
  static async listOpenTasks(userId: string, limit: number = 20, offset: number = 0): Promise<{ data: Task[] | null; error: string | null }> {
    try {
      const { data, error } = await supabase
        .from('tasks')
        .select('*')
        .eq('status', 'open')
        .neq('created_by', userId)
        .order('created_at', { ascending: false })
        .range(offset, offset + limit - 1);

      if (error) {
        return { data: null, error: error.message };
      }

      return { data: data || [], error: null };
    } catch (error) {
      return { data: null, error: 'Network error. Please check your connection.' };
    }
  }

  /**
   * Get tasks user is doing (accepted by current user)
   * Safe list query - never uses .single()
   */
  static async listUserDoingTasks(userId: string): Promise<{ data: Task[] | null; error: string | null }> {
    try {
      const { data, error } = await supabase
        .from('tasks')
        .select('*')
        .eq('accepted_by', userId)
        .in('status', ['accepted', 'completed'])
        .order('updated_at', { ascending: false });

      if (error) {
        return { data: null, error: error.message };
      }

      return { data: data || [], error: null };
    } catch (error) {
      return { data: null, error: 'Network error. Please check your connection.' };
    }
  }

  /**
   * Get user's posted tasks (created by current user, any status)
   * Safe list query - never uses .single()
   */
  static async listUserPostedTasks(userId: string): Promise<{ data: Task[] | null; error: string | null }> {
    try {
      const { data, error } = await supabase
        .from('tasks')
        .select('*')
        .eq('created_by', userId)
        .order('created_at', { ascending: false });

      if (error) {
        return { data: null, error: error.message };
      }

      return { data: data || [], error: null };
    } catch (error) {
      return { data: null, error: 'Network error. Please check your connection.' };
    }
  }

  /**
   * Create a new task
   * Safe creation - uses .limit(1) + [0] for response
   */
  static async createTask(taskData: CreateTaskData, userId: string): Promise<{ data: Task | null; error: string | null }> {
    try {
      const { data, error } = await supabase
        .from('tasks')
        .insert({
          ...taskData,
          created_by: userId,
          status: 'open' as TaskStatus,
        })
        .select()
        .limit(1);

      if (error) {
        return { data: null, error: error.message };
      }

      const task = data?.[0] ?? null;
      if (!task) {
        return { data: null, error: 'Failed to create task. Please try again.' };
      }

      return { data: task, error: null };
    } catch (error) {
      return { data: null, error: 'Network error. Please check your connection.' };
    }
  }

  /**
   * Accept a task using atomic RPC function
   * Uses new atomic RPC function with proper enum values and error handling
   */
  static async acceptTask(taskId: string, userId: string): Promise<{ data: Task | null; error: string | null }> {
    try {
      // Use new atomic RPC function (only needs task ID, user comes from auth.uid())
      const { data, error } = await supabase.rpc('accept_task', { 
        p_task_id: taskId
      });

      if (error) {
        // Map common DB errors to friendly messages
        const msg = error.message || '';
        if (msg.includes('not_authenticated')) {
          return { data: null, error: 'Please sign in to accept tasks.' };
        }
        if (msg.includes('task_not_found')) {
          return { data: null, error: 'Task not found.' };
        }
        if (msg.includes('cannot_accept_own_task')) {
          return { data: null, error: "You can't accept your own task." };
        }
        if (msg.includes('task_not_posted')) {
          return { data: null, error: 'This task has already been accepted or is no longer available.' };
        }
        return { data: null, error: 'Failed to accept task. Please try again.' };
      }

      if (!data) {
        return { data: null, error: 'Failed to accept task. Please try again.' };
      }

      return { data: data as Task, error: null };
    } catch (error) {
      return { data: null, error: 'Network error. Please check your connection.' };
    }
  }

  /**
   * Cancel a task (only by creator)
   * Safe pattern: fetch by ID only, validate in code, atomic update
   */
  static async cancelTask(taskId: string, userId: string): Promise<{ data: Task | null; error: string | null }> {
    try {
      // SAFE: Fetch task by ID only - no restrictive filters
      const { data: task, error: fetchError } = await TaskRepo.getTaskByIdSafe(taskId);

      if (fetchError) {
        return { data: null, error: fetchError };
      }

      if (!task) {
        return { data: null, error: 'Task not found or no longer available' };
      }

      // Validate in application code (not database filters)
      if (task.created_by !== userId) {
        return { data: null, error: 'You can only cancel your own tasks' };
      }
      
      if (task.status !== 'open' && task.status !== 'accepted') {
        return { data: null, error: 'Only open or accepted tasks can be cancelled' };
      }

      // Atomic update with proper filters for race condition protection
      const { data, error } = await supabase
        .from('tasks')
        .update({
          status: 'cancelled' as TaskStatus,
          updated_at: new Date().toISOString(),
        })
        .eq('id', taskId)
        .eq('created_by', userId)
        .in('status', ['open', 'accepted'])
        .select()
        .limit(1);

      if (error) {
        return { data: null, error: error.message };
      }

      const updatedTask = data?.[0] ?? null;
      if (!updatedTask) {
        return { data: null, error: 'Task not found or no longer available for cancellation' };
      }

      return { data: updatedTask, error: null };
    } catch (error) {
      return { data: null, error: 'Network error. Please check your connection.' };
    }
  }

  /**
   * Update task status with history tracking
   */
  static async updateTaskStatus(data: UpdateTaskStatusData): Promise<{ data: any | null; error: string | null }> {
    try {
      const { data: result, error } = await supabase.rpc('update_task_status', {
        p_task_id: data.taskId,
        p_new_status: data.newStatus,
        p_note: data.note || '',
        p_photo_url: data.photoUrl || ''
      });

      if (error) {
        return { data: null, error: error.message };
      }

      if (result?.error) {
        return { data: null, error: result.error };
      }

      return { data: result, error: null };
    } catch (error) {
      return { data: null, error: 'Network error. Please check your connection.' };
    }
  }

  /**
   * Get task status history
   */
  static async getTaskStatusHistory(taskId: string): Promise<{ data: TaskStatusHistory[] | null; error: string | null }> {
    try {
      const { data: result, error } = await supabase.rpc('get_task_status_history', {
        p_task_id: taskId
      });

      if (error) {
        return { data: null, error: error.message };
      }

      if (result?.error) {
        return { data: null, error: result.error };
      }

      return { data: result?.data || [], error: null };
    } catch (error) {
      return { data: null, error: 'Network error. Please check your connection.' };
    }
  }

  // Utility methods for formatting (moved from TaskService)
  static formatReward(cents: number): string {
    return `$${(cents / 100).toFixed(0)}`;
  }

  static formatEstimatedTime(minutes: number): string {
    if (minutes < 60) {
      return `${minutes} min`;
    }
    const hours = Math.floor(minutes / 60);
    const remainingMinutes = minutes % 60;
    if (remainingMinutes === 0) {
      return `${hours}h`;
    }
    return `${hours}h ${remainingMinutes}m`;
  }

  static formatCategory(category: string): string {
    switch (category) {
      case 'food':
        return 'Food Pickup';
      case 'grocery':
        return 'Grocery Run';
      case 'coffee':
        return 'Coffee Run';
      default:
        return category;
    }
  }

  static formatUrgency(urgency: string): string {
    return urgency.charAt(0).toUpperCase() + urgency.slice(1);
  }

  static getUrgencyColor(urgency: string): string {
    switch (urgency) {
      case 'low':
        return '#10B981'; // Green
      case 'medium':
        return '#F59E0B'; // Yellow
      case 'high':
        return '#EF4444'; // Red
      default:
        return '#6B7280'; // Gray
    }
  }

  static formatCurrentStatus(status: TaskCurrentStatus): string {
    switch (status) {
      case 'accepted':
        return 'Accepted';
      case 'picked_up':
        return 'Picked Up';
      case 'on_the_way':
        return 'On the Way';
      case 'delivered':
        return 'Delivered';
      case 'completed':
        return 'Completed';
      default:
        return status;
    }
  }

  static getCurrentStatusColor(status: TaskCurrentStatus): string {
    switch (status) {
      case 'accepted':
        return '#3B82F6'; // Blue
      case 'picked_up':
        return '#F59E0B'; // Orange
      case 'on_the_way':
        return '#8B5CF6'; // Purple
      case 'delivered':
        return '#10B981'; // Green
      case 'completed':
        return '#059669'; // Dark green
      default:
        return '#6B7280'; // Gray
    }
  }

  static getNextStatus(currentStatus: TaskCurrentStatus): TaskCurrentStatus | null {
    const statusFlow: TaskCurrentStatus[] = ['accepted', 'picked_up', 'on_the_way', 'delivered', 'completed'];
    const currentIndex = statusFlow.indexOf(currentStatus);
    
    if (currentIndex === -1 || currentIndex === statusFlow.length - 1) {
      return null; // Invalid status or already at final status
    }
    
    return statusFlow[currentIndex + 1];
  }
}