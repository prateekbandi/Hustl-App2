import { supabase } from './supabase';
import type { Task, CreateTaskData, TaskStatus, TaskCategory, TaskUrgency } from '@/types/database';

export class TaskRepo {
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

  static async acceptTask(taskId: string, userId: string): Promise<{ data: Task | null; error: string | null }> {
    try {
      // Use atomic RPC function - parameter name must match exactly
      const { data, error } = await supabase.rpc('accept_task', { 
        task_id: taskId
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
        return '#10B981';
      case 'medium':
        return '#F59E0B';
      case 'high':
        return '#EF4444';
      default:
        return '#6B7280';
    }
  }
}

export const ColorUtils = {
  withOpacity: (color: string, opacity: number): string => {
    const hex = color.replace('#', '');
    const alpha = Math.round(opacity * 255).toString(16).padStart(2, '0');
    return `#${hex}${alpha}`;
  },

  getTextColor: (backgroundColor: string): string => {
    const darkBackgrounds = [
      Colors.primary,
      Colors.primaryDark,
      Colors.secondary,
      Colors.secondaryDark,
      Colors.text,
      Colors.textHover,
      Colors.acceptedDark,
      Colors.inProgressDark,
      Colors.successDark,
      Colors.purpleDark,
    ];
    
    return darkBackgrounds.includes(backgroundColor) ? Colors.white : Colors.text;
  },

  getPressedColor: (baseColor: string): string => {
    const pressedMap: Record<string, string> = {
      [Colors.primary]: Colors.primaryDark,
      [Colors.secondary]: Colors.secondaryDark,
      [Colors.accepted]: Colors.acceptedDark,
      [Colors.inProgress]: Colors.inProgressDark,
      [Colors.success]: Colors.successDark,
      [Colors.purple]: Colors.purpleDark,
    };
    
    return pressedMap[baseColor] || baseColor;
  },
};

export default Colors;