import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { AlertTriangle, Clock, X } from 'lucide-react-native';
import { Colors } from '@/theme/colors';
import { ModerationStatus, getModerationStatusColor, getModerationErrorMessage } from '@/lib/moderation';

interface ModerationBannerProps {
  status: ModerationStatus;
  reason?: string;
  onEdit?: () => void;
  onDismiss?: () => void;
}

export default function ModerationBanner({ 
  status, 
  reason, 
  onEdit, 
  onDismiss 
}: ModerationBannerProps) {
  if (status === 'approved') return null;

  const getIcon = () => {
    switch (status) {
      case 'blocked':
        return <X size={16} color={Colors.white} strokeWidth={2} />;
      case 'needs_review':
        return <Clock size={16} color={Colors.white} strokeWidth={2} />;
      default:
        return <AlertTriangle size={16} color={Colors.white} strokeWidth={2} />;
    }
  };

  const getMessage = () => {
    switch (status) {
      case 'blocked':
        return getModerationErrorMessage(reason);
      case 'needs_review':
        return 'Your task is under review. Only you can see it for now.';
      default:
        return 'Task status unknown';
    }
  };

  const backgroundColor = getModerationStatusColor(status);

  return (
    <View style={[styles.container, { backgroundColor }]}>
      <View style={styles.content}>
        <View style={styles.iconContainer}>
          {getIcon()}
        </View>
        
        <View style={styles.textContainer}>
          <Text style={styles.message}>{getMessage()}</Text>
        </View>
        
        <View style={styles.actions}>
          {status === 'blocked' && onEdit && (
            <TouchableOpacity style={styles.editButton} onPress={onEdit}>
              <Text style={styles.editButtonText}>Edit</Text>
            </TouchableOpacity>
          )}
          
          {onDismiss && (
            <TouchableOpacity style={styles.dismissButton} onPress={onDismiss}>
              <X size={16} color={Colors.white} strokeWidth={2} />
            </TouchableOpacity>
          )}
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    borderRadius: 12,
    marginHorizontal: 16,
    marginVertical: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  content: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
    gap: 12,
  },
  iconContainer: {
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  textContainer: {
    flex: 1,
  },
  message: {
    fontSize: 14,
    fontWeight: '500',
    color: Colors.white,
    lineHeight: 20,
  },
  actions: {
    flexDirection: 'row',
    gap: 8,
  },
  editButton: {
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 6,
  },
  editButtonText: {
    fontSize: 12,
    fontWeight: '600',
    color: Colors.white,
  },
  dismissButton: {
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
    justifyContent: 'center',
    alignItems: 'center',
  },
});