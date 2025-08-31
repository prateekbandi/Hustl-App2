import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Modal, TextInput, ScrollView, Platform } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { X, Star } from 'lucide-react-native';
import * as Haptics from 'expo-haptics';
import { Colors } from '@/theme/colors';
import { supabase } from '@/lib/supabase';
import { Task } from '@/types/database';

interface ReviewSheetProps {
  visible: boolean;
  onClose: () => void;
  task: Task | null;
  onReviewSubmitted?: () => void;
}

const QUICK_TAGS = [
  'On time',
  'Friendly',
  'Great communication',
  'Professional',
  'Careful handling',
  'Quick delivery'
];

export default function ReviewSheet({ visible, onClose, task, onReviewSubmitted }: ReviewSheetProps) {
  const insets = useSafeAreaInsets();
  const [stars, setStars] = useState(5);
  const [comment, setComment] = useState('');
  const [selectedTags, setSelectedTags] = useState<string[]>([]);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState('');

  // Reset form when sheet opens
  useEffect(() => {
    if (visible) {
      setStars(5);
      setComment('');
      setSelectedTags([]);
      setError('');
    }
  }, [visible]);

  const triggerHaptics = () => {
    if (Platform.OS !== 'web') {
      try {
        Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      } catch (error) {
        // Haptics not available, continue silently
      }
    }
  };

  const handleStarPress = (rating: number) => {
    triggerHaptics();
    setStars(rating);
  };

  const handleTagToggle = (tag: string) => {
    triggerHaptics();
    setSelectedTags(prev => 
      prev.includes(tag) 
        ? prev.filter(t => t !== tag)
        : [...prev, tag]
    );
  };

  const handleSubmit = async () => {
    if (!task || isSubmitting) return;

    setError('');
    setIsSubmitting(true);

    try {
      const { data, error: submitError } = await supabase.rpc('submit_task_review', {
        p_task_id: task.id,
        p_rating: stars,
        p_comment: comment.trim()
      });

      if (submitError || !data?.[0]?.success) {
        setError(data?.[0]?.error_message || submitError?.message || 'Failed to submit review');
        return;
      }

      // Success
      onReviewSubmitted?.();
    } catch (error) {
      setError('Failed to submit review. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  };

  const isFormValid = stars >= 1 && stars <= 5;

  if (!task) return null;

  return (
    <Modal
      visible={visible}
      transparent
      animationType="slide"
      onRequestClose={onClose}
    >
      <View style={styles.overlay}>
        <View style={[styles.sheet, { paddingBottom: insets.bottom + 24 }]}>
          <View style={styles.header}>
            <View style={styles.dragHandle} />
            <TouchableOpacity style={styles.closeButton} onPress={onClose}>
              <X size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />
            </TouchableOpacity>
          </View>

          <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
            <View style={styles.titleSection}>
              <Text style={styles.title}>Leave a Review</Text>
              <Text style={styles.subtitle}>
                How was your experience with this task?
              </Text>
              <Text style={styles.taskTitle}>"{task.title}"</Text>
            </View>

            {/* Error Message */}
            {error ? (
              <View style={styles.errorContainer}>
                <Text style={styles.errorText}>{error}</Text>
              </View>
            ) : null}

            {/* Star Rating */}
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Rating *</Text>
              <View style={styles.starsContainer}>
                {[1, 2, 3, 4, 5].map((rating) => (
                  <TouchableOpacity
                    key={rating}
                    style={styles.starButton}
                    onPress={() => handleStarPress(rating)}
                    disabled={isSubmitting}
                    accessibilityLabel={`${rating} star${rating !== 1 ? 's' : ''}`}
                    accessibilityRole="button"
                  >
                    <Star
                      size={32}
                      color={rating <= stars ? '#FFD700' : Colors.semantic.tabInactive}
                      fill={rating <= stars ? '#FFD700' : 'none'}
                      strokeWidth={1.5}
                    />
                  </TouchableOpacity>
                ))}
              </View>
              <Text style={styles.ratingLabel}>
                {stars === 1 ? '1 star' : `${stars} stars`}
              </Text>
            </View>

            {/* Quick Tags */}
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Quick Tags</Text>
              <View style={styles.tagsContainer}>
                {QUICK_TAGS.map((tag) => (
                  <TouchableOpacity
                    key={tag}
                    style={[
                      styles.tagButton,
                      selectedTags.includes(tag) && styles.tagButtonSelected
                    ]}
                    onPress={() => handleTagToggle(tag)}
                    disabled={isSubmitting}
                    accessibilityLabel={`${tag} tag`}
                    accessibilityRole="button"
                    accessibilityState={{ selected: selectedTags.includes(tag) }}
                  >
                    <Text style={[
                      styles.tagText,
                      selectedTags.includes(tag) && styles.tagTextSelected
                    ]}>
                      {tag}
                    </Text>
                  </TouchableOpacity>
                ))}
              </View>
            </View>

            {/* Comment */}
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Comment (Optional)</Text>
              <TextInput
                style={styles.commentInput}
                value={comment}
                onChangeText={setComment}
                placeholder="Share more details about your experience..."
                placeholderTextColor={Colors.semantic.tabInactive}
                multiline
                numberOfLines={4}
                maxLength={200}
                textAlignVertical="top"
                editable={!isSubmitting}
              />
              <Text style={styles.characterCount}>
                {comment.length}/200 characters
              </Text>
            </View>

            {/* Submit Button */}
            <TouchableOpacity
              style={[
                styles.submitButton,
                (!isFormValid || isSubmitting) && styles.submitButtonDisabled
              ]}
              onPress={handleSubmit}
              disabled={!isFormValid || isSubmitting}
              accessibilityLabel="Submit review"
              accessibilityRole="button"
            >
              <Text style={[
                styles.submitButtonText,
                (!isFormValid || isSubmitting) && styles.submitButtonTextDisabled
              ]}>
                {isSubmitting ? 'Submitting...' : 'Submit Review'}
              </Text>
            </TouchableOpacity>
          </ScrollView>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'flex-end',
  },
  sheet: {
    backgroundColor: Colors.semantic.screen,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    maxHeight: '85%',
  },
  header: {
    alignItems: 'center',
    paddingTop: 12,
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
  closeButton: {
    position: 'absolute',
    top: 12,
    right: 16,
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: Colors.muted,
    justifyContent: 'center',
    alignItems: 'center',
  },
  content: {
    flex: 1,
    paddingHorizontal: 24,
  },
  titleSection: {
    alignItems: 'center',
    marginBottom: 32,
    gap: 8,
  },
  title: {
    fontSize: 24,
    fontWeight: '700',
    color: Colors.semantic.headingText,
  },
  subtitle: {
    fontSize: 16,
    color: Colors.semantic.tabInactive,
    textAlign: 'center',
  },
  taskTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: Colors.primary,
    textAlign: 'center',
    fontStyle: 'italic',
  },
  errorContainer: {
    backgroundColor: '#FEF2F2',
    borderWidth: 1,
    borderColor: '#FECACA',
    borderRadius: 12,
    padding: 16,
    marginBottom: 24,
  },
  errorText: {
    fontSize: 14,
    color: Colors.semantic.errorAlert,
    textAlign: 'center',
  },
  section: {
    marginBottom: 32,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: Colors.semantic.headingText,
    marginBottom: 16,
  },
  starsContainer: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 8,
    marginBottom: 12,
  },
  starButton: {
    padding: 4,
  },
  ratingLabel: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.semantic.bodyText,
    textAlign: 'center',
  },
  tagsContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  tagButton: {
    backgroundColor: Colors.muted,
    borderRadius: 20,
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderWidth: 1,
    borderColor: Colors.semantic.inputBorder,
  },
  tagButtonSelected: {
    backgroundColor: Colors.primary,
    borderColor: Colors.primary,
  },
  tagText: {
    fontSize: 14,
    fontWeight: '500',
    color: Colors.semantic.bodyText,
  },
  tagTextSelected: {
    color: Colors.white,
  },
  commentInput: {
    borderWidth: 1,
    borderColor: Colors.semantic.inputBorder,
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 16,
    fontSize: 16,
    color: Colors.semantic.inputText,
    backgroundColor: Colors.semantic.inputBackground,
    height: 100,
    marginBottom: 8,
  },
  characterCount: {
    fontSize: 12,
    color: Colors.semantic.tabInactive,
    textAlign: 'right',
  },
  submitButton: {
    backgroundColor: Colors.semantic.primaryButton,
    borderRadius: 12,
    paddingVertical: 16,
    alignItems: 'center',
    marginBottom: 24,
  },
  submitButtonDisabled: {
    backgroundColor: Colors.muted,
  },
  submitButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.white,
  },
  submitButtonTextDisabled: {
    color: Colors.semantic.tabInactive,
  },
});