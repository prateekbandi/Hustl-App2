import React, { useEffect, useRef, useState, useMemo } from 'react';
import { View, Text, StyleSheet, Alert, ActivityIndicator, TouchableOpacity, ScrollView, Platform, Dimensions } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import ConfettiCannon from 'react-native-confetti-cannon';
import * as Haptics from 'expo-haptics';
import { ArrowLeft, MessageCircle, Play, CheckCircle, X, Zap, Clock, MapPin, Store } from 'lucide-react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { Colors } from '@/theme/colors';
import { getTask, updateTaskStatus } from '@/src/services/tasks';
import { useAuth } from '@/contexts/AuthContext';
import type { Task, TaskStatus } from '@/src/types/task';

const { width, height } = Dimensions.get('window');

export default function HustledScreen() {
  const router = useRouter();
  const { taskId } = useLocalSearchParams<{ taskId: string }>();
  const insets = useSafeAreaInsets();
  const { user } = useAuth();
  
  const [task, setTask] = useState<Task | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState<TaskStatus | null>(null);
  const confettiRef = useRef<any>(null);

  useEffect(() => {
    let mounted = true;
    (async () => {
      try {
        if (!taskId) throw new Error('No task ID provided');
        const t = await getTask(taskId);
        if (mounted) setTask(t);
      } catch (e: any) {
        Alert.alert('Error', e.message ?? 'Unable to load task.');
        if (mounted) router.back();
      } finally {
        if (mounted) setLoading(false);
      }
    })();
    return () => { mounted = false; };
  }, [taskId]);

  useEffect(() => {
    if (!loading && task) {
      // Fire confetti after layout is ready
      const timer = setTimeout(() => {
        confettiRef.current?.start?.();
        
        // Haptics feedback
        if (Platform.OS !== 'web') {
          try {
            Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
          } catch (error) {
            // Haptics not available, continue silently
          }
        }
      }, 300);
      
      return () => clearTimeout(timer);
    }
  }, [loading, task]);

  const allowedUpgrades: TaskStatus[] = useMemo(() => {
    if (!task) return [];
    switch (task.task_current_status) {
      case 'accepted':
        return ['in_progress', 'completed'];
      case 'in_progress':
        return ['completed'];
      default:
        return [];
    }
  }, [task]);

  const canCancel = task && user && task.created_by === user.id && 
    (task.task_current_status === 'accepted' || task.task_current_status === 'in_progress');

  const onChangeStatus = async (next: TaskStatus) => {
    if (!task) return;
    
    setSaving(next);
    const prev = task.task_current_status;
    
    try {
      // Optimistic update
      setTask({ ...task, task_current_status: next });
      
      await updateTaskStatus(task.id, next);
      
      // Success haptics
      if (Platform.OS !== 'web') {
        try {
          Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
        } catch (error) {
          // Haptics not available, continue silently
        }
      }
    } catch (e: any) {
      // Rollback on error
      setTask({ ...task, task_current_status: prev });
      Alert.alert('Update failed', e.message ?? 'Please try again.');
    } finally {
      setSaving(null);
    }
  };

  const handleBack = () => {
    router.back();
  };

  const handleViewChat = () => {
    // Navigate to chat for this task
    router.push('/(tabs)/chats');
  };

  const handleBackToTasks = () => {
    router.replace('/(tabs)/tasks');
  };

  const formatReward = (cents?: number): string => {
    if (!cents) return '$0';
    return `$${(cents / 100).toFixed(0)}`;
  };

  const formatEstimatedTime = (minutes?: number): string => {
    if (!minutes) return 'Unknown';
    if (minutes < 60) return `${minutes} min`;
    const hours = Math.floor(minutes / 60);
    const remainingMinutes = minutes % 60;
    if (remainingMinutes === 0) return `${hours}h`;
    return `${hours}h ${remainingMinutes}m`;
  };

  const getStatusColor = (status: TaskStatus): string => {
    switch (status) {
      case 'posted':
        return '#6B7280';
      case 'accepted':
        return '#3B82F6';
      case 'in_progress':
        return '#F59E0B';
      case 'completed':
        return '#10B981';
      case 'cancelled':
        return '#EF4444';
      default:
        return '#6B7280';
    }
  };

  const getStatusLabel = (status: TaskStatus): string => {
    switch (status) {
      case 'posted':
        return 'Posted';
      case 'accepted':
        return 'Accepted';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  };

  if (loading || !task) {
    return (
      <View style={[styles.container, { paddingTop: insets.top }]}>
        <View style={styles.header}>
          <TouchableOpacity style={styles.backButton} onPress={handleBack}>
            <ArrowLeft size={24} color={Colors.white} strokeWidth={2} />
          </TouchableOpacity>
          <Text style={styles.headerTitle}>Task Accepted</Text>
          <View style={styles.placeholder} />
        </View>
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={Colors.primary} />
          <Text style={styles.loadingText}>Loading task details...</Text>
        </View>
      </View>
    );
  }

  return (
    <View style={[styles.container, { paddingTop: insets.top }]}>
      {/* Confetti */}
      <ConfettiCannon
        autoStart={false}
        ref={confettiRef}
        count={180}
        fallSpeed={2500}
        fadeOut
        origin={{ x: width / 2, y: 0 }}
        colors={[Colors.primary, Colors.secondary, '#FFD700', '#FF69B4', '#00CED1']}
      />

      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity style={styles.backButton} onPress={handleBack}>
          <ArrowLeft size={24} color={Colors.white} strokeWidth={2} />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>Task Accepted</Text>
        <View style={styles.placeholder} />
      </View>

      <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
        {/* Celebration Section */}
        <View style={styles.celebrationSection}>
          <View style={styles.heroIcon}>
            <LinearGradient
              colors={[Colors.primary, Colors.secondary]}
              style={styles.heroIconGradient}
            >
              <Zap size={40} color={Colors.white} strokeWidth={2.5} fill={Colors.white} />
            </LinearGradient>
          </View>
          
          <Text style={styles.celebrationTitle}>You just Hustled it!</Text>
          <Text style={styles.celebrationSubtitle}>
            Task accepted successfully. Keep the momentum going 🚀
          </Text>
        </View>

        {/* Task Details Card */}
        <View style={styles.taskCard}>
          <View style={styles.taskHeader}>
            <Text style={styles.taskTitle}>{task.title}</Text>
            <Text style={styles.taskReward}>
              {formatReward(task.reward_cents)}
            </Text>
          </View>
          
          {task.description && (
            <Text style={styles.taskDescription} numberOfLines={3}>
              {task.description}
            </Text>
          )}

          {/* Current Status */}
          <View style={styles.statusContainer}>
            <View style={[
              styles.statusBadge,
              { backgroundColor: getStatusColor(task.task_current_status) + '20' }
            ]}>
              <View style={[
                styles.statusDot,
                { backgroundColor: getStatusColor(task.task_current_status) }
              ]} />
              <Text style={[
                styles.statusText,
                { color: getStatusColor(task.task_current_status) }
              ]}>
                {getStatusLabel(task.task_current_status)}
              </Text>
            </View>
          </View>

          {/* Task Details */}
          <View style={styles.taskDetails}>
            {task.store && (
              <View style={styles.detailRow}>
                <Store size={16} color={Colors.semantic.tabInactive} strokeWidth={2} />
                <Text style={styles.detailText}>{task.store}</Text>
              </View>
            )}
            
            {task.dropoff_address && (
              <View style={styles.detailRow}>
                <MapPin size={16} color={Colors.semantic.tabInactive} strokeWidth={2} />
                <Text style={styles.detailText}>{task.dropoff_address}</Text>
              </View>
            )}
            
            {task.estimated_minutes && (
              <View style={styles.detailRow}>
                <Clock size={16} color={Colors.semantic.tabInactive} strokeWidth={2} />
                <Text style={styles.detailText}>
                  {formatEstimatedTime(task.estimated_minutes)}
                </Text>
              </View>
            )}
          </View>
        </View>

        {/* Status Upgrade Actions */}
        {allowedUpgrades.length > 0 && (
          <View style={styles.upgradeSection}>
            <Text style={styles.sectionTitle}>Update Status</Text>
            <View style={styles.upgradeButtons}>
              {allowedUpgrades.includes('in_progress') && (
                <TouchableOpacity
                  style={[
                    styles.upgradeButton,
                    saving === 'in_progress' && styles.upgradeButtonDisabled
                  ]}
                  onPress={() => onChangeStatus('in_progress')}
                  disabled={!!saving}
                >
                  <LinearGradient
                    colors={saving === 'in_progress' ? ['#9CA3AF', '#9CA3AF'] : ['#F59E0B', '#D97706']}
                    style={styles.upgradeButtonGradient}
                  >
                    {saving === 'in_progress' ? (
                      <ActivityIndicator size="small" color={Colors.white} />
                    ) : (
                      <>
                        <Play size={18} color={Colors.white} strokeWidth={2} />
                        <Text style={styles.upgradeButtonText}>Start Task</Text>
                      </>
                    )}
                  </LinearGradient>
                </TouchableOpacity>
              )}

              {allowedUpgrades.includes('completed') && (
                <TouchableOpacity
                  style={[
                    styles.upgradeButton,
                    saving === 'completed' && styles.upgradeButtonDisabled
                  ]}
                  onPress={() => onChangeStatus('completed')}
                  disabled={!!saving}
                >
                  <LinearGradient
                    colors={saving === 'completed' ? ['#9CA3AF', '#9CA3AF'] : ['#10B981', '#059669']}
                    style={styles.upgradeButtonGradient}
                  >
                    {saving === 'completed' ? (
                      <ActivityIndicator size="small" color={Colors.white} />
                    ) : (
                      <>
                        <CheckCircle size={18} color={Colors.white} strokeWidth={2} />
                        <Text style={styles.upgradeButtonText}>Mark as Completed</Text>
                      </>
                    )}
                  </LinearGradient>
                </TouchableOpacity>
              )}

              {canCancel && (
                <TouchableOpacity
                  style={[
                    styles.cancelButton,
                    saving === 'cancelled' && styles.upgradeButtonDisabled
                  ]}
                  onPress={() => onChangeStatus('cancelled')}
                  disabled={!!saving}
                >
                  {saving === 'cancelled' ? (
                    <ActivityIndicator size="small" color={Colors.semantic.errorAlert} />
                  ) : (
                    <>
                      <X size={18} color={Colors.semantic.errorAlert} strokeWidth={2} />
                      <Text style={styles.cancelButtonText}>Cancel Task</Text>
                    </>
                  )}
                </TouchableOpacity>
              )}
            </View>
          </View>
        )}

        {/* Navigation Actions */}
        <View style={styles.navigationSection}>
          <TouchableOpacity style={styles.secondaryButton} onPress={handleViewChat}>
            <MessageCircle size={20} color={Colors.primary} strokeWidth={2} />
            <Text style={styles.secondaryButtonText}>View Chat</Text>
          </TouchableOpacity>
          
          <TouchableOpacity style={styles.secondaryButton} onPress={handleBackToTasks}>
            <Text style={styles.secondaryButtonText}>Back to Tasks</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </View>
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
    backgroundColor: Colors.primary,
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
    paddingHorizontal: 24,
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
  celebrationSection: {
    alignItems: 'center',
    paddingVertical: 40,
    gap: 16,
  },
  heroIcon: {
    width: 100,
    height: 100,
    borderRadius: 50,
    overflow: 'hidden',
    shadowColor: Colors.primary,
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.3,
    shadowRadius: 16,
    elevation: 12,
  },
  heroIconGradient: {
    width: '100%',
    height: '100%',
    justifyContent: 'center',
    alignItems: 'center',
  },
  celebrationTitle: {
    fontSize: 32,
    fontWeight: '700',
    color: Colors.semantic.headingText,
    textAlign: 'center',
  },
  celebrationSubtitle: {
    fontSize: 16,
    color: Colors.semantic.tabInactive,
    textAlign: 'center',
    lineHeight: 24,
    paddingHorizontal: 20,
  },
  taskCard: {
    backgroundColor: Colors.semantic.card,
    borderRadius: 20,
    padding: 24,
    marginBottom: 32,
    borderWidth: 1,
    borderColor: Colors.semantic.cardBorder,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.08,
    shadowRadius: 16,
    elevation: 6,
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
    color: Colors.secondary,
  },
  taskDescription: {
    fontSize: 16,
    color: Colors.semantic.bodyText,
    lineHeight: 24,
    marginBottom: 20,
  },
  statusContainer: {
    marginBottom: 20,
  },
  statusBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    alignSelf: 'flex-start',
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 10,
    gap: 10,
  },
  statusDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
  },
  statusText: {
    fontSize: 16,
    fontWeight: '600',
  },
  taskDetails: {
    gap: 12,
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
  upgradeSection: {
    marginBottom: 32,
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: Colors.semantic.headingText,
    marginBottom: 16,
  },
  upgradeButtons: {
    gap: 12,
  },
  upgradeButton: {
    borderRadius: 16,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 12,
    elevation: 6,
  },
  upgradeButtonDisabled: {
    shadowOpacity: 0,
    elevation: 0,
  },
  upgradeButtonGradient: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 16,
    paddingHorizontal: 24,
    gap: 12,
    minHeight: 56,
  },
  upgradeButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.white,
  },
  cancelButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'transparent',
    borderWidth: 2,
    borderColor: Colors.semantic.errorAlert,
    borderRadius: 16,
    paddingVertical: 16,
    paddingHorizontal: 24,
    gap: 12,
    minHeight: 56,
  },
  cancelButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.semantic.errorAlert,
  },
  navigationSection: {
    gap: 16,
    paddingBottom: 40,
  },
  secondaryButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'transparent',
    borderWidth: 1,
    borderColor: Colors.primary,
    borderRadius: 16,
    paddingVertical: 16,
    paddingHorizontal: 24,
    gap: 12,
    minHeight: 56,
  },
  secondaryButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.primary,
  },
});