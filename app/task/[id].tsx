import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Modal, Platform, ActivityIndicator } from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { ArrowLeft, Clock, MapPin, Store, ChevronDown, X } from 'lucide-react-native';
import * as Haptics from 'expo-haptics';
import { Colors } from '@/theme/colors';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/lib/supabase';
import Toast from '@/components/Toast';

type TaskStatus = 'posted' | 'accepted' | 'in_progress' | 'completed' | 'cancelled';

interface Task {
  id: string;
  title: string;
  description: string;
  store: string;
  dropoff_address: string;
  dropoff_instructions: string;
  reward_cents: number;
  estimated_minutes: number;
  status: TaskStatus;
  created_by: string;
  assignee_id: string | null;
  created_at: string;
  updated_at: string;
}

const STATUS_FLOW: { value: TaskStatus; label: string; color: string }[] = [
  { value: 'posted', label: 'Posted', color: Colors.semantic.tabInactive },
  { value: 'accepted', label: 'Accepted', color: Colors.semantic.acceptedBadge },
  { value: 'in_progress', label: 'In Progress', color: Colors.semantic.inProgressBadge },
  { value: 'completed', label: 'Completed', color: Colors.semantic.completedBadge },
  { value: 'cancelled', label: 'Cancelled', color: Colors.semantic.errorAlert },
];

export default function TaskDetailScreen() {
  const router = useRouter();
  const params = useLocalSearchParams();
  const insets = useSafeAreaInsets();
  const { user } = useAuth();
  
  const taskId = params.id as string;
  
  const [task, setTask] = useState<Task | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isUpdating, setIsUpdating] = useState(false);
  const [showStatusSheet, setShowStatusSheet] = useState(false);
  const [toast, setToast] = useState<{ visible: boolean; message: string; type: 'success' | 'error' }>({
    visible: false,
    message: '',
    type: 'success'
  });

  useEffect(() => {
    loadTask();
    setupRealtimeSubscription();
    
    return () => {
      // Cleanup subscription
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
    const channel = supabase
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
      .subscribe();

    return () => {
      channel.unsubscribe();
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

  const getValidNextStatuses = (currentStatus: TaskStatus): TaskStatus[] => {
    const validTransitions: Record<TaskStatus, TaskStatus[]> = {
      posted: ['accepted', 'cancelled'],
      accepted: ['in_progress', 'cancelled'],
      in_progress: ['completed', 'cancelled'],
      completed: [],
      cancelled: []
    };

    return validTransitions[currentStatus] || [];
  };

  const canUpdateStatus = (): boolean => {
    if (!task || !user) return false;
    return task.created_by === user.id || task.assignee_id === user.id;
  };

  const handleStatusUpdate = async (newStatus: TaskStatus) => {
    if (!task || isUpdating) return;
    
    triggerHaptics();
    setIsUpdating(true);
    setShowStatusSheet(false);
    
    // Optimistic update
    const previousTask = { ...task };
    setTask({ ...task, status: newStatus, updated_at: new Date().toISOString() });

    try {
      const { data, error } = await supabase.rpc('update_task_status', {
        task_id: taskId,
        new_status: newStatus
      });

      if (error) {
        // Revert optimistic update
        setTask(previousTask);
        setToast({
          visible: true,
          message: 'Couldn\'t update status',
          type: 'error'
        });
        return;
      }

      setToast({
        visible: true,
        message: 'Status updated',
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

  const getStatusInfo = (status: TaskStatus) => {
    return STATUS_FLOW.find(s => s.value === status) || STATUS_FLOW[0];
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

  const statusInfo = getStatusInfo(task.status);
  const validNextStatuses = getValidNextStatuses(task.status);
  const showUpdateButton = canUpdateStatus() && validNextStatuses.length > 0;

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

            {/* Current Status */}
            <View style={styles.statusContainer}>
              <View style={[styles.statusPill, { backgroundColor: statusInfo.color + '20' }]}>
                <View style={[styles.statusDot, { backgroundColor: statusInfo.color }]} />
                <Text style={[styles.statusText, { color: statusInfo.color }]}>
                  {statusInfo.label}
                </Text>
              </View>
              <Text style={styles.lastUpdated}>
                Updated {new Date(task.updated_at).toLocaleTimeString([], { 
                  hour: '2-digit', 
                  minute: '2-digit' 
                })}
              </Text>
            </View>

            {/* Update Status Button */}
            {showUpdateButton && (
              <TouchableOpacity
                style={[styles.updateButton, isUpdating && styles.updateButtonDisabled]}
                onPress={() => setShowStatusSheet(true)}
                disabled={isUpdating}
              >
                {isUpdating ? (
                  <ActivityIndicator size="small" color={Colors.white} />
                ) : (
                  <>
                    <Text style={styles.updateButtonText}>Update Status</Text>
                    <ChevronDown size={16} color={Colors.white} strokeWidth={2} />
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

      {/* Status Update Sheet */}
      <Modal
        visible={showStatusSheet}
        transparent
        animationType="slide"
        onRequestClose={() => setShowStatusSheet(false)}
      >
        <View style={styles.sheetOverlay}>
          <View style={[styles.statusSheet, { paddingBottom: insets.bottom + 24 }]}>
            <View style={styles.sheetHeader}>
              <View style={styles.dragHandle} />
              <TouchableOpacity 
                style={styles.sheetCloseButton} 
                onPress={() => setShowStatusSheet(false)}
              >
                <X size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />
              </TouchableOpacity>
            </View>

            <View style={styles.sheetContent}>
              <Text style={styles.sheetTitle}>Update Status</Text>
              
              <View style={styles.statusOptions}>
                {validNextStatuses.map((status) => {
                  const statusInfo = getStatusInfo(status);
                  return (
                    <TouchableOpacity
                      key={status}
                      style={[
                        styles.statusOption,
                        status === 'cancelled' && styles.cancelledOption
                      ]}
                      onPress={() => handleStatusUpdate(status)}
                    >
                      <View style={[styles.statusOptionDot, { backgroundColor: statusInfo.color }]} />
                      <Text style={[
                        styles.statusOptionText,
                        status === 'cancelled' && styles.cancelledOptionText
                      ]}>
                        {statusInfo.label}
                      </Text>
                    </TouchableOpacity>
                  );
                })}
              </View>
            </View>
          </View>
        </View>
      </Modal>

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
    marginBottom: 20,
    gap: 8,
  },
  statusPill: {
    flexDirection: 'row',
    alignItems: 'center',
    alignSelf: 'flex-start',
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
  },
  lastUpdated: {
    fontSize: 12,
    color: Colors.semantic.tabInactive,
    fontStyle: 'italic',
  },
  updateButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.semantic.primaryButton,
    borderRadius: 12,
    paddingVertical: 12,
    paddingHorizontal: 16,
    marginBottom: 20,
    gap: 8,
  },
  updateButtonDisabled: {
    backgroundColor: Colors.semantic.tabInactive,
  },
  updateButtonText: {
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
  sheetOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'flex-end',
  },
  statusSheet: {
    backgroundColor: Colors.semantic.screen,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    paddingTop: 12,
  },
  sheetHeader: {
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
  sheetCloseButton: {
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
  sheetContent: {
    paddingHorizontal: 24,
  },
  sheetTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: Colors.semantic.headingText,
    textAlign: 'center',
    marginBottom: 24,
  },
  statusOptions: {
    gap: 12,
    marginBottom: 24,
  },
  statusOption: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.semantic.card,
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 16,
    borderWidth: 1,
    borderColor: Colors.semantic.cardBorder,
    gap: 12,
  },
  cancelledOption: {
    borderColor: Colors.semantic.errorAlert + '40',
    backgroundColor: Colors.semantic.errorAlert + '10',
  },
  statusOptionDot: {
    width: 12,
    height: 12,
    borderRadius: 6,
  },
  statusOptionText: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.semantic.bodyText,
  },
  cancelledOptionText: {
    color: Colors.semantic.errorAlert,
  },
});