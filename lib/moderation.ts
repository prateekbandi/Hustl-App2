import { supabase } from '@/lib/supabase';

export type ModerationStatus = 'approved' | 'needs_review' | 'blocked';

export interface ModerationResult {
  status: ModerationStatus;
  reason?: string;
  task_id?: string;
  error?: string;
}

export interface TaskModerationData {
  title: string;
  description?: string;
  dropoff_instructions?: string;
  store?: string;
  dropoff_address?: string;
  category?: string;
  urgency?: string;
  estimated_minutes?: number;
  reward_cents?: number;
  task_id?: string;
}

/**
 * Moderate and save a task using the server-side moderation function
 */
export async function moderateAndSaveTask(data: TaskModerationData): Promise<ModerationResult> {
  try {
    const { data: result, error } = await supabase.rpc('moderate_task_and_save', {
      p_title: data.title,
      p_description: data.description || '',
      p_dropoff_instructions: data.dropoff_instructions || '',
      p_store: data.store || '',
      p_dropoff_address: data.dropoff_address || '',
      p_category: data.category || 'food',
      p_urgency: data.urgency || 'medium',
      p_estimated_minutes: data.estimated_minutes || 30,
      p_reward_cents: data.reward_cents || 200,
      p_task_id: data.task_id || null
    });

    if (error) {
      return { status: 'blocked', error: error.message };
    }

    if (result?.error) {
      return { status: 'blocked', error: result.error };
    }

    return {
      status: result.status as ModerationStatus,
      reason: result.reason,
      task_id: result.task_id
    };
  } catch (error) {
    return { 
      status: 'blocked', 
      error: 'Network error. Please check your connection.' 
    };
  }
}

/**
 * Get user-friendly moderation status labels
 */
export function getModerationStatusLabel(status: ModerationStatus): string {
  switch (status) {
    case 'approved':
      return 'Approved';
    case 'needs_review':
      return 'Under Review';
    case 'blocked':
      return 'Blocked';
    default:
      return 'Unknown';
  }
}

/**
 * Get moderation status colors
 */
export function getModerationStatusColor(status: ModerationStatus): string {
  switch (status) {
    case 'approved':
      return '#10B981'; // Green
    case 'needs_review':
      return '#F59E0B'; // Yellow
    case 'blocked':
      return '#EF4444'; // Red
    default:
      return '#6B7280'; // Gray
  }
}

/**
 * Get user-friendly error messages for blocked content
 */
export function getModerationErrorMessage(reason?: string): string {
  if (!reason) return 'Content violates community guidelines. Please review and edit your task.';
  
  if (reason.includes('sexual')) {
    return 'Sexual content is not allowed. Please remove inappropriate language and try again.';
  }
  
  if (reason.includes('violence') || reason.includes('harm')) {
    return 'Content suggesting violence or harm is not allowed. Please edit your task.';
  }
  
  if (reason.includes('illegal') || reason.includes('unsafe')) {
    return 'Illegal or unsafe activities are not allowed. Please review our community guidelines.';
  }
  
  return 'Content violates community guidelines. Please review and edit your task.';
}

/**
 * Check if user can edit a task based on moderation status
 */
export function canEditTask(status: ModerationStatus): boolean {
  return status === 'blocked' || status === 'needs_review';
}

/**
 * Check if task should be visible in public listings
 */
export function isTaskPubliclyVisible(status: ModerationStatus): boolean {
  return status === 'approved';
}