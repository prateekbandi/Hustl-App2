import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Modal, Platform, ActivityIndicator, Dimensions } from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { ArrowLeft, Clock, MapPin, Store, X, ChevronRight, History, AlertTriangle } from 'lucide-react-native';
import * as Haptics from 'expo-haptics';
import { Colors } from '@/theme/colors';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/lib/supabase';
import { Task, TaskCurrentStatus } from '@/types/database';
import Toast from '@/components/Toast';

const { width } = Dimensions.get('window');

type TaskPhase = 'none' | 'started' | 'picked_up' | 'on_the_way' | 'completed';

interface TaskProgress {
  id: string;
  phase: TaskPhase;
  actor_name: string;
  note: string;
  created_at: string;
}

// Category-specific phase flows
const PHASE_FLOWS: Record<string, { phases: TaskPhase[]; labels: string[] }> = {
  food: {
    phases: ['none', 'started', 'picked_up', 'completed'],
    labels: ['Posted', 'Started', 'Picked Up', 'Completed']
  },
  grocery: {
    phases: ['none', 'started', 'on_the_way', 'completed'],
    labels: ['Posted', 'Started', 'On The Way', 'Completed']
  },
  default: {
    phases: ['none', 'started', 'completed'],
    labels: ['Posted', 'Started', 'Completed']
  }
};

export default function TaskDetailScreen() {
  const router = useRouter();
  const params = useLocalSearchParams();
  const insets = useSafeAreaInsets();
  const { user } = useAuth();
  
  const taskId = params.id as string;
  
  const [task, setTask] = useState<Task | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isUpdating, setIsUpdating] = useState(false);
  const [showStatusModal, setShowStatusModal] = useState(false);
  const [progressHistory, setProgressHistory] = useState<TaskProgress[]>([]);
  const [toast, setToast] = useState<{ visible: boolean; message: string; type: 'success' | 'error' }>({
    visible: false,
    message: '',
    type: 'success'
  });

  useEffect(() => {
    loadTask();
    setupRealtimeSubscription();
    
    return () => {
      supabase.removeAllChannels();
    };
  }, [taskId]);

  const loadTask = async () => {
    if (!taskId) return;
    
    try {
      const { data, error } = await supabase
        .from('tasks')
        .select('*')
        .eq('id', taskId)
        .limit(1);

      if (error) {
        setToast({
          visible: true,
          message: 'Failed to load task',
          type: 'error'
        });
        return;
      }

      const taskData = data?.[0] ?? null;
      setTask(taskData);
      
      if (taskData) {
        loadProgressHistory();
      }
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

  const loadProgressHistory = async () => {
    try {
      const { data, error } = await supabase.rpc('get_task_progress_history', {
        p_task_id: taskId
      });

      if (data && !error) {
        setProgressHistory(data);
      }
    } catch (error) {
      console.warn('Failed to load progress history:', error);
    }
  };

  const setupRealtimeSubscription = () => {
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
        (payload) => {
          setTask(payload.new as Task);
        }
      )
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'task_progress',
          filter: `task_id=eq.${taskId}`
        },
        () => {
          loadProgressHistory();
        }
      )
      .subscribe();

    return () => {
      taskChannel.unsubscribe();
    };
  };

  const triggerHaptics = () => {
    if (Platform.OS !== 'web') {
      try {
        Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      } catch (error) {
        // Haptics not available, continue silently
      }
    }
  };

  const getPhaseFlow = (category: string) => {
    return PHASE_FLOWS[category] || PHASE_FLOWS.default;
  };

  const getNextPhase = (currentPhase: TaskPhase, category: string): TaskPhase | null => {
    const flow = getPhaseFlow(category);
    const currentIndex = flow.phases.indexOf(currentPhase);
    
    if (currentIndex === -1 || currentIndex >= flow.phases.length - 1) {
      return null;
    }
    
    return flow.phases[currentIndex + 1];
  };

  const canSkipToComplete = (currentPhase: TaskPhase, category: string): boolean => {
    const flow = getPhaseFlow(category);
    return currentPhase === 'none' && flow.phases.length === 3; // Only 3 phases means no middle step
  };

  const canUpdateStatus = (): boolean => {
    if (!task || !user) return false;
    if (task.status === 'completed' || task.status === 'cancelled') return false;
    return task.created_by === user.id || task.assignee_id === user.id;
  };

  const handlePhaseUpdate = async (newPhase: TaskPhase) => {
    if (!task || isUpdating) return;
    
    triggerHaptics();
    setIsUpdating(true);
    setShowStatusModal(false);
    
    // Optimistic update
    const previousTask = { ...task };
    const updatedTask = { 
      ...task, 
      phase: newPhase,
      status: newPhase === 'completed' ? 'completed' : 'in_progress',
      updated_at: new Date().toISOString() 
    };
    setTask(updatedTask);

    try {
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

  const handleStartAndComplete = async () => {
    await handlePhaseUpdate('completed');
  };

  const handleCancelTask = async () => {
    if (!task || isUpdating) return;
    
    triggerHaptics();
    setIsUpdating(true);
    setShowStatusModal(false);
    
    // Optimistic update
    const previousTask = { ...task };
    setTask({ ...task, status: 'cancelled', updated_at: new Date().toISOString() });

    try {
      const { data, error } = await supabase
        .from('tasks')
        .update({ status: 'cancelled', updated_at: new Date().toISOString() })
        .eq('id', taskId)
        .select()
        .limit(1);

      if (error) {
        setTask(previousTask);
        setToast({
          visible: true,
          message: 'Couldn\'t cancel task',
          type: 'error'
        });
        return;
      }

      setToast({
        visible: true,
        message: 'Task cancelled',
        type: 'success'
      });
    } catch (error) {
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

  const renderProgressStepper = () => {
    if (!task) return null;
    
    const flow = getPhaseFlow(task.category);
    const currentIndex = flow.phases.indexOf(task.phase || 'none');
    
    return (
      <View style={styles.stepperContainer}>
        <View style={styles.stepper}>
          {flow.phases.map((phase, index) => {
            const isActive = index <= currentIndex;
            const isCurrent = index === currentIndex;
            
            return (
              <React.Fragment key={phase}>
                <View style={[
                  styles.stepDot,
                  isActive && styles.stepDotActive,
                  isCurrent && styles.stepDotCurrent
                ]}>
                  {isActive && (
                    <View style={styles.stepDotInner} />
                  )}
                </View>
                
                {index < flow.phases.length - 1 && (
                  <View style={[
                    styles.stepLine,
                    isActive && styles.stepLineActive
                  ]} />
                )}
              </React.Fragment>
            );
          })}
        </View>
        
        <View style={styles.stepLabels}>
          {flow.labels.map((label, index) => {
            const isActive = index <= currentIndex;
            const isCurrent = index === currentIndex;
            
            return (
              <Text
                key={index}
                style={[
                  styles.stepLabel,
                  isActive && styles.stepLabelActive,
                  isCurrent && styles.stepLabelCurrent
                ]}
              >
                {label}
              </Text>
            );
          })}
        </View>
        
        <Text style={styles.lastUpdated}>
          Last updated {formatRelativeTime(task.updated_at)}
        </Text>
      </View>
    );
  };

  const renderStatusModal = () => {
    if (!task) return null;
    
    const nextPhase = getNextPhase(task.phase || 'none', task.category);
    const canSkip = canSkipToComplete(task.phase || 'none', task.category);
    const flow = getPhaseFlow(task.category);
    const nextPhaseIndex = nextPhase ? flow.phases.indexOf(nextPhase) : -1;
    const nextPhaseLabel = nextPhaseIndex >= 0 ? flow.labels[nextPhaseIndex] : '';
    
    return (
      <Modal
        visible={showStatusModal}
        transparent
        animationType="slide"
        onRequestClose={() => setShowStatusModal(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={[styles.statusModal, { paddingBottom: insets.bottom + 24 }]}>
            <View style={styles.modalHeader}>
              <View style={styles.dragHandle} />
              <TouchableOpacity 
                style={styles.modalCloseButton} 
                onPress={() => setShowStatusModal(false)}
              >
                <X size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />
              </TouchableOpacity>
            </View>

            <View style={styles.modalContent}>
              <Text style={styles.modalTitle}>Update Status</Text>
              
              {renderProgressStepper()}

              <View style={styles.actionButtons}>
                {nextPhase && (
                  <TouchableOpacity
                    style={styles.primaryActionButton}
                    onPress={() => handlePhaseUpdate(nextPhase)}
                    disabled={isUpdating}
                  >
                    {isUpdating ? (
                      <ActivityIndicator size="small" color={Colors.white} />
                    ) : (
                      <Text style={styles.primaryActionText}>
                        Mark as {nextPhaseLabel}
                      </Text>
                    )}
                  </TouchableOpacity>
                )}
                
                {canSkip && (
                  <TouchableOpacity
                    style={styles.secondaryActionButton}
                    onPress={handleStartAndComplete}
                    disabled={isUpdating}
                  >
                    <Text style={styles.secondaryActionText}>
                      Start & Complete
                    </Text>
                  </TouchableOpacity>
                )}
              </View>

              <View style={styles.secondaryActions}>
                {task.status !== 'cancelled' && task.status !== 'completed' && (
                  <TouchableOpacity
                    style={styles.cancelButton}
                    onPress={handleCancelTask}
                    disabled={isUpdating}
                  >
                    <AlertTriangle size={16} color={Colors.semantic.errorAlert} strokeWidth={2} />
                    <Text style={styles.cancelButtonText}>Cancel Task</Text>
                  </TouchableOpacity>
                )}
                
                <TouchableOpacity
                  style={styles.historyButton}
                  onPress={() => console.log('View history')}
                >
                  <History size={16} color={Colors.semantic.tabInactive} strokeWidth={2} />
                  <Text style={styles.historyButtonText}>View History</Text>
                </TouchableOpacity>
              </View>
            </View>
          </View>
        </View>
      </Modal>
    );
  };

  if (isLoading) {
    return (
      <View style={[styles.container, { paddingTop: insets.top }]}>
        <View style={styles.header}>
          <TouchableOpacity style={styles.backButton} onPress={handleBack}>
            <ArrowLeft size={24} color={Colors.white} strokeWidth={2} />
          </TouchableOpacity>
          <Text style={styles.headerTitle}>Task Details</Text>
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
          <Text style={styles.headerTitle}>Task Details</Text>
          <View style={styles.placeholder} />
        </View>
        <View style={styles.errorContainer}>
          <Text style={styles.errorText}>Task not found</Text>
        </View>
      </View>
    );
  }

  const flow = getPhaseFlow(task.category);
  const currentPhaseIndex = flow.phases.indexOf(task.phase || 'none');
  const currentPhaseLabel = flow.labels[currentPhaseIndex] || 'Unknown';
  const showUpdateButton = canUpdateStatus();

  return (
    <>
      <View style={[styles.container, { paddingTop: insets.top }]}>
        <View style={styles.header}>
          <TouchableOpacity style={styles.backButton} onPress={handleBack}>
            <ArrowLeft size={24} color={Colors.white} strokeWidth={2} />
          </TouchableOpacity>
          <Text style={styles.headerTitle}>Task Details</Text>
          <View style={styles.placeholder} />
        </View>

        <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
          <View style={styles.taskCard}>
            <View style={styles.taskHeader}>
              <Text style={styles.taskTitle}>{task.title}</Text>
              <Text style={styles.taskReward}>{formatReward(task.reward_cents)}</Text>
            </View>

            {/* Current Status Pill */}
            <View style={styles.statusContainer}>
              <View style={styles.statusPill}>
                <View style={[styles.statusDot, { backgroundColor: Colors.semantic.acceptedBadge }]} />
                <Text style={styles.statusText}>{currentPhaseLabel}</Text>
              </View>
              <Text style={styles.lastUpdated}>
                Updated {formatRelativeTime(task.updated_at)}
              </Text>
            </View>

            {/* Update Status Button */}
            {showUpdateButton && (
              <TouchableOpacity
                style={[styles.updateStatusButton, isUpdating && styles.updateStatusButtonDisabled]}
                onPress={() => setShowStatusModal(true)}
                disabled={isUpdating}
              >
                {isUpdating ? (
                  <ActivityIndicator size="small" color={Colors.white} />
                ) : (
                  <>
                    <Text style={styles.updateStatusText}>Update Status</Text>
                    <ChevronRight size={16} color={Colors.white} strokeWidth={2} />
                  </>
                )}
              </TouchableOpacity>
            )}

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
        </ScrollView>
      </View>

      {renderStatusModal()}

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
  updateStatusButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.semantic.primaryButton,
    borderRadius: 12,
    paddingVertical: 12,
    paddingHorizontal: 16,
    marginBottom: 20,
    gap: 8,
    shadowColor: Colors.primary,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 4,
    elevation: 3,
  },
  updateStatusButtonDisabled: {
    backgroundColor: Colors.semantic.tabInactive,
    shadowOpacity: 0,
    elevation: 0,
  },
  updateStatusText: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.white,
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
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'flex-end',
  },
  statusModal: {
    backgroundColor: Colors.semantic.screen,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    paddingTop: 12,
    maxHeight: '70%',
  },
  modalHeader: {
    alignItems: 'center',
    paddingHorizontal: 24,
    paddingBottom: 20,
    position: 'relative',
  },
  dragHandle: {
    width: 36,
    height: 4,
    backgroundColor: Colors.semantic.tabInactive + '40',
    borderRadius: 2,
    marginBottom: 16,
  },
  modalCloseButton: {
    position: 'absolute',
    top: 12,
    right: 16,
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: Colors.semantic.inputBackground,
    justifyContent: 'center',
    alignItems: 'center',
  },
  modalContent: {
    paddingHorizontal: 24,
  },
  modalTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: Colors.semantic.headingText,
    textAlign: 'center',
    marginBottom: 24,
  },
  stepperContainer: {
    marginBottom: 32,
    gap: 16,
  },
  stepper: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
  },
  stepDot: {
    width: 12,
    height: 12,
    borderRadius: 6,
    backgroundColor: Colors.semantic.inputBackground,
    borderWidth: 2,
    borderColor: Colors.semantic.tabInactive,
    justifyContent: 'center',
    alignItems: 'center',
  },
  stepDotActive: {
    borderColor: Colors.semantic.acceptedBadge,
    backgroundColor: Colors.semantic.acceptedBadge + '20',
  },
  stepDotCurrent: {
    borderColor: Colors.primary,
    backgroundColor: Colors.primary + '20',
  },
  stepDotInner: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: Colors.primary,
  },
  stepLine: {
    width: 32,
    height: 2,
    backgroundColor: Colors.semantic.tabInactive,
    marginHorizontal: 8,
  },
  stepLineActive: {
    backgroundColor: Colors.semantic.acceptedBadge,
  },
  stepLabels: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingHorizontal: 6,
  },
  stepLabel: {
    fontSize: 12,
    color: Colors.semantic.tabInactive,
    fontWeight: '500',
    textAlign: 'center',
    flex: 1,
  },
  stepLabelActive: {
    color: Colors.semantic.acceptedBadge,
    fontWeight: '600',
  },
  stepLabelCurrent: {
    color: Colors.primary,
    fontWeight: '700',
  },
  actionButtons: {
    gap: 12,
    marginBottom: 24,
  },
  primaryActionButton: {
    backgroundColor: Colors.semantic.primaryButton,
    borderRadius: 12,
    paddingVertical: 16,
    alignItems: 'center',
    minHeight: 48,
    shadowColor: Colors.primary,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 4,
    elevation: 3,
  },
  primaryActionText: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.white,
  },
  secondaryActionButton: {
    backgroundColor: 'transparent',
    borderWidth: 1,
    borderColor: Colors.primary,
    borderRadius: 12,
    paddingVertical: 16,
    alignItems: 'center',
    minHeight: 48,
  },
  secondaryActionText: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.primary,
  },
  secondaryActions: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    gap: 16,
  },
  cancelButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingVertical: 8,
    paddingHorizontal: 12,
  },
  cancelButtonText: {
    fontSize: 14,
    color: Colors.semantic.errorAlert,
    fontWeight: '500',
  },
  historyButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingVertical: 8,
    paddingHorizontal: 12,
  },
  historyButtonText: {
    fontSize: 14,
    color: Colors.semantic.tabInactive,
    fontWeight: '500',
  },
});