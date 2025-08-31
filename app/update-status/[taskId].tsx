import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, ActivityIndicator, Platform } from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { ArrowLeft, Clock, MapPin, Store, MessageCircle, List } from 'lucide-react-native';
import * as Haptics from 'expo-haptics';
import { Colors } from '@/theme/colors';
import { useAuth } from '@/contexts/AuthContext';
import { TaskRepo } from '@/lib/taskRepo';
import { ChatService } from '@/lib/chat';
import { Task, TaskCurrentStatus } from '@/types/database';
import Toast from '@/components/Toast';

type TaskPhase = 'none' | 'started' | 'picked_up' | 'on_the_way' | 'delivered' | 'completed';

interface PhaseButton {
  phase: TaskPhase;
  label: string;
  color: string;
  enabled: boolean;
}

// Category-specific phase flows
const PHASE_FLOWS: Record<string, { phases: TaskPhase[]; labels: string[] }> = {
  food_delivery: {
    phases: ['none', 'started', 'on_the_way', 'delivered', 'completed'],
    labels: ['Posted', 'Started', 'On The Way', 'Delivered', 'Completed']
  },
  food: {
    phases: ['none', 'started', 'picked_up', 'completed'],
    labels: ['Posted', 'Started', 'Picked Up', 'Completed']
  },
  default: {
    phases: ['none', 'started', 'completed'],
    labels: ['Posted', 'Started', 'Completed']
  }
};

export default function UpdateStatusScreen() {
  const router = useRouter();
  const params = useLocalSearchParams();
  const insets = useSafeAreaInsets();
  const { user } = useAuth();
  
  const taskId = params.taskId as string;
  
  const [task, setTask] = useState<Task | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isUpdating, setIsUpdating] = useState(false);
  const [toast, setToast] = useState<{ visible: boolean; message: string; type: 'success' | 'error' }>({
    visible: false,
    message: '',
    type: 'success'
  });

  useEffect(() => {
    loadTask();
    setupRealtimeSubscription();
    
    return () => {
      // Cleanup subscriptions
      const channels = (global as any).supabaseChannels || [];
      channels.forEach((channel: any) => channel.unsubscribe());
    };
  }, [taskId]);

  const loadTask = async () => {
    if (!taskId) return;
    
    try {
      const { data, error } = await TaskRepo.getTaskByIdSafe(taskId);

      if (error) {
        setToast({
          visible: true,
          message: 'Failed to load task',
          type: 'error'
        });
        return;
      }

      setTask(data);
    } catch (error) {
      setToast({
        visible: true,
        message: 'Network error',
        type: 'error'
      });
    } finally {
      setIsLoading(false);
    }
  };

  const setupRealtimeSubscription = () => {
    const { supabase } = require('@/lib/supabase');
    
    const taskChannel = supabase
      .channel(`task_${taskId}`)
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'tasks',
          filter: `id=eq.${taskId}`
        },
        (payload: any) => {
          setTask(payload.new as Task);
        }
      )
      .subscribe();

    // Store for cleanup
    if (!(global as any).supabaseChannels) {
      (global as any).supabaseChannels = [];
    }
    (global as any).supabaseChannels.push(taskChannel);
  };

  const triggerHaptics = () => {
    if (Platform.OS !== 'web') {
      try {
        Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
      } catch (error) {
        // Haptics not available, continue silently
      }
    }
  };

  const getPhaseFlow = (category: string) => {
    // Check if it's food delivery based on category and store name
    if (category === 'food' && task?.store?.toLowerCase().includes('delivery')) {
      return PHASE_FLOWS.food_delivery;
    }
    return PHASE_FLOWS[category] || PHASE_FLOWS.default;
  };

  const getNextPhaseButtons = (): PhaseButton[] => {
    if (!task) return [];
    
    const flow = getPhaseFlow(task.category);
    const currentIndex = flow.phases.indexOf(task.phase || 'none');
    
    if (currentIndex === -1 || currentIndex >= flow.phases.length - 1) {
      return []; // Invalid phase or already at final phase
    }
    
    const buttons: PhaseButton[] = [];
    const nextPhase = flow.phases[currentIndex + 1];
    const nextLabel = flow.labels[currentIndex + 1];
    
    // Always show the next step
    buttons.push({
      phase: nextPhase,
      label: nextLabel,
      color: getPhaseColor(nextPhase),
      enabled: true
    });
    
    // For categories without middle steps, also show "Start & Complete"
    if (currentIndex === 0 && flow.phases.length === 3) {
      buttons.push({
        phase: 'completed',
        label: 'Start & Complete',
        color: Colors.semantic.completedBadge,
        enabled: true
      });
    }
    
    return buttons;
  };

  const getPhaseColor = (phase: TaskPhase): string => {
    switch (phase) {
      case 'started':
        return '#F59E0B'; // Orange
      case 'picked_up':
      case 'on_the_way':
        return '#8B5CF6'; // Purple
      case 'delivered':
      case 'completed':
        return Colors.semantic.completedBadge; // Green
      default:
        return Colors.primary;
    }
  };

  const canUpdateStatus = (): boolean => {
    if (!task || !user) return false;
    if (task.status === 'completed' || task.status === 'cancelled') return false;
    return task.created_by === user.id || task.assignee_id === user.id;
  };

  const getPageTitle = (): string => {
    if (!task) return 'Update Status';
    
    switch (task.status) {
      case 'accepted':
        return 'Task Accepted';
      case 'in_progress':
        return 'Task In Progress';
      case 'completed':
        return 'Task Completed';
      case 'cancelled':
        return 'Task Cancelled';
      default:
        return 'Update Status';
    }
  };

  const handlePhaseUpdate = async (newPhase: TaskPhase) => {
    if (!task || isUpdating) return;
    
    triggerHaptics();
    setIsUpdating(true);
    
    // Optimistic update
    const previousTask = { ...task };
    const updatedTask = { 
      ...task, 
      phase: newPhase,
      status: newPhase === 'completed' ? 'completed' : 'accepted',
      updated_at: new Date().toISOString() 
    };
    setTask(updatedTask);

    try {
      const { supabase } = require('@/lib/supabase');
      const { data, error } = await supabase.rpc('update_task_phase', {
        p_task_id: taskId,
        p_new_phase: newPhase
      });

      if (error) {
        // Revert optimistic update
        setTask(previousTask);
        
        let errorMessage = 'Couldn\'t update status';
        if (error.message.includes('invalid_phase_transition')) {
          errorMessage = 'Invalid status transition';
        } else if (error.message.includes('not_authorized')) {
          errorMessage = 'Not authorized to update this task';
        }
        
        setToast({
          visible: true,
          message: errorMessage,
          type: 'error'
        });
        return;
      }

      const flow = getPhaseFlow(task.category);
      const phaseIndex = flow.phases.indexOf(newPhase);
      const phaseLabel = flow.labels[phaseIndex] || 'Updated';
      
      setToast({
        visible: true,
        message: `Updated to ${phaseLabel}`,
        type: 'success'
      });
    } catch (error) {
      // Revert optimistic update
      setTask(previousTask);
      setToast({
        visible: true,
        message: 'Network error',
        type: 'error'
      });
    } finally {
      setIsUpdating(false);
    }
  };

  const handleViewChat = async () => {
    if (!task) return;
    
    triggerHaptics();
    
    try {
      const { data: room, error } = await ChatService.ensureRoomForTask(task.id);
      
      if (error || !room) {
        setToast({
          visible: true,
          message: 'Chat not available for this task',
          type: 'error'
        });
        return;
      }

      router.push(`/chat/${room.id}`);
    } catch (error) {
      setToast({
        visible: true,
        message: 'Failed to open chat',
        type: 'error'
      });
    }
  };

  const handleBackToTasks = () => {
    router.push('/(tabs)/tasks');
  };

  const handleBack = () => {
    router.back();
  };

  const hideToast = () => {
    setToast(prev => ({ ...prev, visible: false }));
  };

  const formatReward = (cents: number): string => {
    return `$${(cents / 100).toFixed(0)}`;
  };

  const formatEstimatedTime = (minutes: number): string => {
    if (minutes < 60) return `${minutes} min`;
    const hours = Math.floor(minutes / 60);
    const remainingMinutes = minutes % 60;
    if (remainingMinutes === 0) return `${hours}h`;
    return `${hours}h ${remainingMinutes}m`;
  };

  const formatRelativeTime = (timestamp: string): string => {
    const date = new Date(timestamp);
    const now = new Date();
    const diffInMinutes = (now.getTime() - date.getTime()) / (1000 * 60);
    
    if (diffInMinutes < 1) return 'Just now';
    if (diffInMinutes < 60) return `${Math.floor(diffInMinutes)}m ago`;
    if (diffInMinutes < 1440) return `${Math.floor(diffInMinutes / 60)}h ago`;
    return `${Math.floor(diffInMinutes / 1440)}d ago`;
  };

  const getCurrentPhaseLabel = (): string => {
    if (!task) return 'Unknown';
    
    const flow = getPhaseFlow(task.category);
    const currentIndex = flow.phases.indexOf(task.phase || 'none');
    return flow.labels[currentIndex] || 'Unknown';
  };

  if (isLoading) {
    return (
      <View style={[styles.container, { paddingTop: insets.top }]}>
        <View style={styles.header}>
          <TouchableOpacity style={styles.backButton} onPress={handleBack}>
            <ArrowLeft size={24} color={Colors.white} strokeWidth={2} />
          </TouchableOpacity>
          <Text style={styles.headerTitle}>Update Status</Text>
          <View style={styles.placeholder} />
        </View>
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={Colors.semantic.primaryButton} />
          <Text style={styles.loadingText}>Loading task...</Text>
        </View>
      </View>
    );
  }

  if (!task) {
    return (
      <View style={[styles.container, { paddingTop: insets.top }]}>
        <View style={styles.header}>
          <TouchableOpacity style={styles.backButton} onPress={handleBack}>
            <ArrowLeft size={24} color={Colors.white} strokeWidth={2} />
          </TouchableOpacity>
          <Text style={styles.headerTitle}>Update Status</Text>
          <View style={styles.placeholder} />
        </View>
        <View style={styles.errorContainer}>
          <Text style={styles.errorText}>Task not found</Text>
        </View>
      </View>
    );
  }

  const nextButtons = getNextPhaseButtons();
  const isReadOnly = task.status === 'completed' || task.status === 'cancelled';
  const canUpdate = canUpdateStatus() && !isReadOnly;

  return (
    <>
      <View style={[styles.container, { paddingTop: insets.top }]}>
        <View style={styles.header}>
          <TouchableOpacity style={styles.backButton} onPress={handleBack}>
            <ArrowLeft size={24} color={Colors.white} strokeWidth={2} />
          </TouchableOpacity>
          <Text style={styles.headerTitle}>{getPageTitle()}</Text>
          <View style={styles.placeholder} />
        </View>

        <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
          {/* Task Summary Card */}
          <View style={styles.taskCard}>
            <View style={styles.taskHeader}>
              <Text style={styles.taskTitle}>{task.title}</Text>
              <Text style={styles.taskReward}>{formatReward(task.reward_cents)}</Text>
            </View>

            {/* Current Status Chip */}
            <View style={styles.statusContainer}>
              <View style={styles.statusPill}>
                <View style={[styles.statusDot, { backgroundColor: getPhaseColor(task.phase || 'none') }]} />
                <Text style={styles.statusText}>{getCurrentPhaseLabel()}</Text>
              </View>
              <Text style={styles.lastUpdated}>
                Last updated {formatRelativeTime(task.updated_at)}
              </Text>
            </View>

            {task.description && (
              <Text style={styles.taskDescription}>{task.description}</Text>
            )}

            <View style={styles.taskDetails}>
              <View style={styles.detailRow}>
                <Store size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />
                <Text style={styles.detailText}>{task.store}</Text>
              </View>
              
              <View style={styles.detailRow}>
                <MapPin size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />
                <Text style={styles.detailText}>{task.dropoff_address}</Text>
              </View>
              
              {task.dropoff_instructions && (
                <View style={styles.detailRow}>
                  <Text style={styles.instructionsLabel}>Instructions:</Text>
                  <Text style={styles.instructionsText}>{task.dropoff_instructions}</Text>
                </View>
              )}
              
              <View style={styles.detailRow}>
                <Clock size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />
                <Text style={styles.detailText}>
                  {formatEstimatedTime(task.estimated_minutes)}
                </Text>
              </View>
            </View>
          </View>

          {/* Update Status Section */}
          <View style={styles.updateSection}>
            <Text style={styles.sectionTitle}>Update Status</Text>
            
            {canUpdate && nextButtons.length > 0 ? (
              <View style={styles.actionButtons}>
                {nextButtons.map((button) => (
                  <TouchableOpacity
                    key={button.phase}
                    style={[
                      styles.primaryActionButton,
                      { backgroundColor: button.color },
                      (!button.enabled || isUpdating) && styles.primaryActionButtonDisabled
                    ]}
                    onPress={() => handlePhaseUpdate(button.phase)}
                    disabled={!button.enabled || isUpdating}
                    accessibilityLabel={`Update status to ${button.label}`}
                    accessibilityRole="button"
                  >
                    {isUpdating ? (
                      <ActivityIndicator size="small" color={Colors.white} />
                    ) : (
                      <Text style={styles.primaryActionText}>
                        {button.label}
                      </Text>
                    )}
                  </TouchableOpacity>
                ))}
              </View>
            ) : (
              <View style={styles.readOnlyContainer}>
                <Text style={styles.readOnlyText}>
                  {isReadOnly ? 'Task is complete' : 'No updates available'}
                </Text>
              </View>
            )}
          </View>

          {/* Secondary Actions */}
          <View style={styles.secondarySection}>
            <TouchableOpacity 
              style={styles.secondaryButton} 
              onPress={handleViewChat}
              accessibilityLabel="View chat"
              accessibilityRole="button"
            >
              <MessageCircle size={20} color={Colors.primary} strokeWidth={2} />
              <Text style={styles.secondaryButtonText}>View Chat</Text>
            </TouchableOpacity>
            
            <TouchableOpacity 
              style={styles.secondaryButton} 
              onPress={handleBackToTasks}
              accessibilityLabel="Back to tasks"
              accessibilityRole="button"
            >
              <List size={20} color={Colors.primary} strokeWidth={2} />
              <Text style={styles.secondaryButtonText}>Back to Tasks</Text>
            </TouchableOpacity>
          </View>
        </ScrollView>
      </View>

      <Toast
        visible={toast.visible}
        message={toast.message}
        type={toast.type}
        onHide={hideToast}
      />
    </>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.semantic.screen,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: Colors.semantic.primaryButton,
  },
  backButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: Colors.white + '33',
    justifyContent: 'center',
    alignItems: 'center',
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: Colors.white,
  },
  placeholder: {
    width: 40,
  },
  content: {
    flex: 1,
    paddingHorizontal: 16,
    paddingTop: 16,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    gap: 16,
  },
  loadingText: {
    fontSize: 16,
    color: Colors.semantic.tabInactive,
  },
  errorContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  errorText: {
    fontSize: 18,
    color: Colors.semantic.errorAlert,
  },
  taskCard: {
    backgroundColor: Colors.semantic.card,
    borderRadius: 16,
    padding: 20,
    marginBottom: 24,
    borderWidth: 1,
    borderColor: Colors.semantic.cardBorder,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.05,
    shadowRadius: 8,
    elevation: 2,
  },
  taskHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 16,
  },
  taskTitle: {
    flex: 1,
    fontSize: 20,
    fontWeight: '700',
    color: Colors.semantic.headingText,
    marginRight: 16,
  },
  taskReward: {
    fontSize: 24,
    fontWeight: '700',
    color: Colors.semantic.secondaryButton,
  },
  statusContainer: {
    marginBottom: 16,
    gap: 8,
  },
  statusPill: {
    flexDirection: 'row',
    alignItems: 'center',
    alignSelf: 'flex-start',
    backgroundColor: Colors.semantic.acceptedBadge + '20',
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 8,
    gap: 8,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  statusText: {
    fontSize: 14,
    fontWeight: '600',
    color: Colors.semantic.acceptedBadge,
  },
  lastUpdated: {
    fontSize: 12,
    color: Colors.semantic.tabInactive,
    fontStyle: 'italic',
  },
  taskDescription: {
    fontSize: 16,
    color: Colors.semantic.bodyText,
    lineHeight: 24,
    marginBottom: 20,
  },
  taskDetails: {
    gap: 16,
  },
  detailRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  detailText: {
    flex: 1,
    fontSize: 16,
    color: Colors.semantic.bodyText,
  },
  instructionsLabel: {
    fontSize: 14,
    fontWeight: '600',
    color: Colors.semantic.bodyText,
    minWidth: 80,
  },
  instructionsText: {
    flex: 1,
    fontSize: 14,
    color: Colors.semantic.bodyText,
    fontStyle: 'italic',
  },
  updateSection: {
    marginBottom: 32,
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: Colors.semantic.headingText,
    marginBottom: 16,
  },
  actionButtons: {
    gap: 12,
  },
  primaryActionButton: {
    borderRadius: 12,
    paddingVertical: 16,
    alignItems: 'center',
    minHeight: 48,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 4,
    elevation: 3,
  },
  primaryActionButtonDisabled: {
    backgroundColor: Colors.semantic.tabInactive + ' !important',
    shadowOpacity: 0,
    elevation: 0,
  },
  primaryActionText: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.white,
  },
  readOnlyContainer: {
    backgroundColor: Colors.muted,
    borderRadius: 12,
    paddingVertical: 16,
    alignItems: 'center',
  },
  readOnlyText: {
    fontSize: 16,
    fontWeight: '500',
    color: Colors.semantic.tabInactive,
  },
  secondarySection: {
    gap: 12,
    marginBottom: 40,
  },
  secondaryButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'transparent',
    borderWidth: 1,
    borderColor: Colors.primary,
    borderRadius: 12,
    paddingVertical: 16,
    paddingHorizontal: 24,
    gap: 12,
    minHeight: 48,
  },
  secondaryButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.primary,
  },
});