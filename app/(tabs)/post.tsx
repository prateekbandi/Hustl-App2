import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, TextInput, Platform, KeyboardAvoidingView } from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useBottomTabBarHeight } from '@react-navigation/bottom-tabs';
import { X, MapPin, Clock, Store, Package } from 'lucide-react-native';
import * as Haptics from 'expo-haptics';
import { Colors } from '@/theme/colors';
import { useAuth } from '@/contexts/AuthContext';
import { TaskRepo } from '@/lib/taskRepo';
import { TaskCategory, TaskUrgency } from '@/types/database';
import { getModerationErrorMessage, getModerationStatusLabel } from '@/lib/moderation';
import AuthPrompt from '@components/AuthPrompt';
import GlobalHeader from '@/components/GlobalHeader';
import TaskSuccessSheet from '@components/TaskSuccessSheet';
import Toast from '@components/Toast';
import StickyFormFooter from '@components/StickyFormFooter';

// Extended categories to support all card types
const categories: { value: string; label: string }[] = [
  { value: 'car', label: 'Car Rides' },
  { value: 'food', label: 'Food Pickup' },
  { value: 'workout', label: 'Workout Partner' },
  { value: 'coffee', label: 'Coffee Run' },
  { value: 'study', label: 'Study Partner' },
  { value: 'custom', label: 'Custom Task' },
];

const urgencyOptions: { value: string; label: string; price: number }[] = [
  { value: 'low', label: 'Low', price: 0 },
  { value: 'medium', label: 'Medium', price: 100 }, // $1.00 in cents
  { value: 'high', label: 'High', price: 250 }, // $2.50 in cents
];

const BASE_PRICE_CENTS = 150; // $1.50 base price
const MIN_PRICE_CENTS = 200; // $2.00 minimum
const MAX_PRICE_CENTS = 2500; // $25.00 maximum

// Category defaults for prefilling
const getCategoryDefaults = (categoryId: string) => {
  const defaults = {
    car: {
      title: 'Need a ride',
      description: 'Quick campus ride. Can split gas if needed.',
      store: '',
      estimatedMinutes: '15',
      urgency: 'medium' as const,
    },
    food: {
      title: 'Food pickup',
      description: 'Pick up my order and drop it off.',
      store: 'Chipotle / Chick-fil-A / Other',
      estimatedMinutes: '20',
      urgency: 'medium' as const,
    },
    workout: {
      title: 'Workout partner',
      description: 'Looking for a gym/sports buddy.',
      store: '',
      estimatedMinutes: '45',
      urgency: 'low' as const,
    },
    coffee: {
      title: 'Coffee run',
      description: 'Grab a coffee and drop it off.',
      store: 'Starbucks / Dunkin / Other',
      estimatedMinutes: '15',
      urgency: 'medium' as const,
    },
    study: {
      title: 'Study partner',
      description: 'Study session—subject/topic flexible.',
      store: '',
      estimatedMinutes: '60',
      urgency: 'low' as const,
    },
    custom: {
      title: 'Custom task',
      description: 'Describe what you need help with.',
      store: '',
      estimatedMinutes: '20',
      urgency: 'medium' as const,
    },
  };
  
  return defaults[categoryId as keyof typeof defaults] || defaults.custom;
};

export default function PostScreen() {
  const router = useRouter();
  const params = useLocalSearchParams();
  const insets = useSafeAreaInsets();
  const tabBarHeight = useBottomTabBarHeight();
  const { user, isGuest } = useAuth();
  
  // Form state
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [category, setCategory] = useState<string>('');
  const [store, setStore] = useState('');
  const [dropoffAddress, setDropoffAddress] = useState('');
  const [dropoffInstructions, setDropoffInstructions] = useState('');
  const [urgency, setUrgency] = useState<string>('medium');
  const [estimatedMinutes, setEstimatedMinutes] = useState('');
  const [prefilledCategory, setPrefilledCategory] = useState<string | null>(null);
  
  // Computed pricing
  const [computedPriceCents, setComputedPriceCents] = useState(BASE_PRICE_CENTS + 100); // Base + medium urgency
  
  // Field validation errors
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  
  // UI state
  const [isLoading, setIsLoading] = useState(false);
  const [submitError, setSubmitError] = useState('');
  const [moderationError, setModerationError] = useState('');
  const [showAuthPrompt, setShowAuthPrompt] = useState(false);
  const [showSuccessSheet, setShowSuccessSheet] = useState(false);
  const [lastCreatedTaskId, setLastCreatedTaskId] = useState<string | null>(null);

  // Toast state
  const [toast, setToast] = useState<{ visible: boolean; message: string; type: 'success' | 'error' }>({
    visible: false,
    message: '',
    type: 'success'
  });

  // Handle category prefilling from navigation params
  useEffect(() => {
    const categoryParam = params.category as string;
    if (categoryParam && categoryParam !== prefilledCategory) {
      const defaults = getCategoryDefaults(categoryParam);
      
      // Prefill form with category defaults
      setTitle(defaults.title);
      setDescription(defaults.description);
      setCategory(categoryParam);
      setStore(defaults.store);
      setEstimatedMinutes(defaults.estimatedMinutes);
      setUrgency(defaults.urgency);
      setPrefilledCategory(categoryParam);
      
      // Clear other fields
      setDropoffAddress('');
      setDropoffInstructions('');
      setFieldErrors({});
      setSubmitError('');
      
      // Show toast
      const categoryLabel = categories.find(cat => cat.value === categoryParam)?.label || 'Category';
      setToast({
        visible: true,
        message: `Prefilled from ${categoryLabel}`,
        type: 'success'
      });
    }
  }, [params.category, prefilledCategory]);

  // Calculate price whenever urgency changes
  useEffect(() => {
    const urgencyPrice = urgencyOptions.find(opt => opt.value === urgency)?.price || 100;
    let total = BASE_PRICE_CENTS + urgencyPrice;
    
    // Round up to nearest $0.25 (25 cents)
    total = Math.ceil(total / 25) * 25;
    
    // Clamp between min and max
    total = Math.max(MIN_PRICE_CENTS, Math.min(MAX_PRICE_CENTS, total));
    
    setComputedPriceCents(total);
  }, [urgency]);

  const handleClose = () => {
    router.back();
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

  const validateField = (field: string, value: string): string => {
    switch (field) {
      case 'title':
        return !value.trim() ? 'Task title is required' : '';
      case 'category':
        return !value ? 'Please select a category' : '';
      case 'store':
        return !value.trim() ? 'Store name is required' : '';
      case 'dropoffAddress':
        return !value.trim() ? 'Drop-off address is required' : '';
      case 'estimatedMinutes':
        const minutes = Number(value);
        if (!value.trim()) return 'Estimated time is required';
        if (isNaN(minutes)) return 'Please enter a valid number';
        if (minutes < 5) return 'Minimum 5 minutes';
        if (minutes > 180) return 'Maximum 180 minutes';
        return '';
      case 'urgency':
        return !value ? 'Please select urgency level' : '';
      default:
        return '';
    }
  };

  const updateFieldError = (field: string, value: string) => {
    const error = validateField(field, value);
    setFieldErrors(prev => ({
      ...prev,
      [field]: error
    }));
  };

  const isFormValid = (): boolean => {
    const requiredFields = {
      title,
      category: category as string,
      store,
      dropoffAddress,
      estimatedMinutes,
      urgency: urgency as string,
    };

    // Check if all required fields have values
    const hasAllValues = Object.values(requiredFields).every(value => value.trim());
    
    // Check if any field has validation errors
    const hasErrors = Object.values(fieldErrors).some(error => error);
    
    return hasAllValues && !hasErrors && !isLoading;
  };

  const handleSubmit = async () => {
    triggerHaptics();

    // Check authentication
    if (isGuest || !user) {
      setShowAuthPrompt(true);
      return;
    }

    // Clear previous errors
    setSubmitError('');
    setModerationError('');

    // Final validation of all fields
    const errors: Record<string, string> = {};
    errors.title = validateField('title', title);
    errors.category = validateField('category', category as string);
    errors.store = validateField('store', store);
    errors.dropoffAddress = validateField('dropoffAddress', dropoffAddress);
    errors.estimatedMinutes = validateField('estimatedMinutes', estimatedMinutes);
    errors.urgency = validateField('urgency', urgency as string);

    // Remove empty errors
    Object.keys(errors).forEach(key => {
      if (!errors[key]) delete errors[key];
    });

    setFieldErrors(errors);

    if (Object.keys(errors).length > 0) {
      return;
    }

    // Prevent double submits
    if (isLoading) return;

    setIsLoading(true);

    try {
      const taskData = {
        title: title.trim(),
        description: description.trim(),
        dropoff_instructions: dropoffInstructions.trim(),
        category: mapCategoryToDatabase(category),
        store: store.trim(),
        dropoff_address: dropoffAddress.trim(),
        urgency: urgency as TaskUrgency,
        estimated_minutes: Number(estimatedMinutes),
        reward_cents: computedPriceCents,
      };

      const { data, error: createError, moderationStatus, moderationReason } = await TaskRepo.createTask(taskData, user.id);

      if (createError || moderationStatus === 'blocked') {
        if (moderationStatus === 'blocked') {
          setModerationError(getModerationErrorMessage(moderationReason));
        } else {
          setSubmitError(createError || "Couldn't post your task. Try again.");
        }
        return;
      }

      if (!data || !data.id) {
        setSubmitError("Couldn't post your task. Try again.");
        return;
      }

      // Handle moderation status
      if (moderationStatus === 'needs_review') {
        setToast({
          visible: true,
          message: 'Task submitted for review. Only you can see it for now.',
          type: 'success'
        });
      }

      // Success - store the created task ID and show success screen
      setLastCreatedTaskId(data.id);
      
      // Add to tasks list if available
      if ((global as any).addNewTaskToTasksList) {
        (global as any).addNewTaskToTasksList(data);
      }
      
      setShowSuccessSheet(true);
      
      // Clear form for next use
      clearForm();
    } catch (error) {
      setSubmitError("Couldn't post your task. Try again.");
    } finally {
      setIsLoading(false);
    }
  };

  const clearForm = () => {
    setTitle('');
    setDescription('');
    setCategory('');
    setStore('');
    setDropoffAddress('');
    setDropoffInstructions('');
    setUrgency('medium');
    setEstimatedMinutes('');
    setFieldErrors({});
    setSubmitError('');
  };

  // Map UI categories to database categories
  const mapCategoryToDatabase = (uiCategory: string): TaskCategory => {
    const mapping: Record<string, TaskCategory> = {
      car: 'food', // Map to existing category for now
      food: 'food',
      workout: 'food', // Map to existing category for now
      coffee: 'coffee',
      study: 'food', // Map to existing category for now
      custom: 'food', // Map to existing category for now
    };
    return mapping[uiCategory] || 'food';
  };

  // Hide toast
  const hideToast = () => {
    setToast(prev => ({ ...prev, visible: false }));
  };

  const formatPrice = (cents: number): string => {
    return `$${(cents / 100).toFixed(2)}`;
  };

  const CategorySelector = () => (
    <View style={styles.inputGroup}>
      <Text style={styles.label}>Category *</Text>
      <View style={styles.segmentedControl}>
        {categories.map((cat) => (
          <TouchableOpacity
            key={cat.value}
            style={[
              styles.segment,
              category === cat.value && styles.activeSegment
            ]}
            onPress={() => {
              triggerHaptics();
              setCategory(cat.value);
              updateFieldError('category', cat.value);
            }}
            disabled={isLoading}
          >
            <Text style={[
              styles.segmentText,
              category === cat.value && styles.activeSegmentText
            ]}>
              {cat.label}
            </Text>
          </TouchableOpacity>
        ))}
      </View>
      {fieldErrors.category && (
        <Text style={styles.fieldError}>{fieldErrors.category}</Text>
      )}
    </View>
  );

  const UrgencySelector = () => (
    <View style={styles.inputGroup}>
      <Text style={styles.label}>Urgency *</Text>
      <View style={styles.segmentedControl}>
        {urgencyOptions.map((option) => (
          <TouchableOpacity
            key={option.value}
            style={[
              styles.segment,
              urgency === option.value && styles.activeSegment
            ]}
            onPress={() => {
              triggerHaptics();
              setUrgency(option.value);
              updateFieldError('urgency', option.value);
            }}
            disabled={isLoading}
          >
            <Text style={[
              styles.segmentText,
              urgency === option.value && styles.activeSegmentText
            ]}>
              {option.label}
            </Text>
          </TouchableOpacity>
        ))}
      </View>
      {fieldErrors.urgency && (
        <Text style={styles.fieldError}>{fieldErrors.urgency}</Text>
      )}
    </View>
  );

  const PricingBreakdown = () => {
    const urgencyPrice = urgencyOptions.find(opt => opt.value === urgency)?.price || 100;
    
    return (
      <View style={styles.inputGroup}>
        <Text style={styles.label}>Computed Total</Text>
        <View style={styles.pricingCard}>
          <View style={styles.pricingRow}>
            <Text style={styles.pricingLabel}>Base</Text>
            <Text style={styles.pricingValue}>{formatPrice(BASE_PRICE_CENTS)}</Text>
          </View>
          <View style={styles.pricingRow}>
            <Text style={styles.pricingLabel}>Urgency ({urgency})</Text>
            <Text style={styles.pricingValue}>+{formatPrice(urgencyPrice)}</Text>
          </View>
          <View style={[styles.pricingRow, styles.pricingTotal]}>
            <Text style={styles.pricingTotalLabel}>Total</Text>
            <Text style={styles.pricingTotalValue}>{formatPrice(computedPriceCents)}</Text>
          </View>
        </View>
      </View>
    );
  };

  return (
    <>
      <KeyboardAvoidingView 
        style={styles.container}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        keyboardVerticalOffset={tabBarHeight + insets.top}
      >
        <GlobalHeader 
          title={prefilledCategory ? `Create ${categories.find(c => c.value === prefilledCategory)?.label || 'Task'}` : "Create Task"} 
          showSearch={false} 
          showNotifications={false} 
        />

        <ScrollView 
          style={styles.content} 
          showsVerticalScrollIndicator={false}
          contentContainerStyle={[
            styles.scrollContent,
            { paddingBottom: 120 + tabBarHeight + insets.bottom }
          ]}
        >
          <View style={styles.form}>
            {/* Prefilled Category Chip */}
            {prefilledCategory && (
              <View style={styles.prefilledChip}>
                <Text style={styles.prefilledChipText}>
                  Prefilled from {categories.find(c => c.value === prefilledCategory)?.label}
                </Text>
              </View>
            )}

            {/* Submit Error */}
            {submitError ? (
              <View style={styles.submitErrorContainer}>
                <Text style={styles.submitErrorText}>{submitError}</Text>
              </View>
            ) : null}

            {/* Moderation Error */}
            {moderationError ? (
              <View style={styles.moderationErrorContainer}>
                <Text style={styles.moderationErrorText}>{moderationError}</Text>
                <TouchableOpacity 
                  style={styles.editResubmitButton}
                  onPress={() => setModerationError('')}
                >
                  <Text style={styles.editResubmitButtonText}>Edit & Resubmit</Text>
                </TouchableOpacity>
              </View>
            ) : null}

            {/* Task Details Section */}
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Task Details</Text>
              
              <View style={styles.inputGroup}>
                <Text style={styles.label}>Task Title *</Text>
                <TextInput
                  style={[styles.input, fieldErrors.title && styles.inputError]}
                  value={title}
                  onChangeText={(value) => {
                    setTitle(value);
                    updateFieldError('title', value);
                  }}
                  placeholder="What do you need help with?"
                  placeholderTextColor={Colors.muted.foreground}
                  editable={!isLoading}
                  accessibilityLabel="Task title"
                />
                {fieldErrors.title && (
                  <Text style={styles.fieldError}>{fieldErrors.title}</Text>
                )}
              </View>

              <View style={styles.inputGroup}>
                <Text style={styles.label}>Description</Text>
                <TextInput
                  style={[styles.input, styles.textArea]}
                  value={description}
                  onChangeText={setDescription}
                  placeholder="Provide more details about the task..."
                  placeholderTextColor={Colors.muted.foreground}
                  multiline
                  numberOfLines={3}
                  textAlignVertical="top"
                  editable={!isLoading}
                  accessibilityLabel="Task description"
                />
              </View>

              <CategorySelector />

              <View style={styles.inputGroup}>
                <Text style={styles.label}>Store *</Text>
                <View style={[styles.inputWithIcon, fieldErrors.store && styles.inputError]}>
                  <Store size={20} color={Colors.muted.foreground} strokeWidth={2} />
                  <TextInput
                    style={styles.inputText}
                    value={store}
                    onChangeText={(value) => {
                      setStore(value);
                      updateFieldError('store', value);
                    }}
                    placeholder="e.g., Publix, Starbucks, Target"
                    placeholderTextColor={Colors.muted.foreground}
                    editable={!isLoading}
                    accessibilityLabel="Store name"
                  />
                </View>
                {fieldErrors.store && (
                  <Text style={styles.fieldError}>{fieldErrors.store}</Text>
                )}
              </View>
            </View>

            {/* Drop-off Section */}
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Drop-off</Text>
              
              <View style={styles.inputGroup}>
                <Text style={styles.label}>Drop-off Address *</Text>
                <View style={[styles.inputWithIcon, fieldErrors.dropoffAddress && styles.inputError]}>
                  <MapPin size={20} color={Colors.muted.foreground} strokeWidth={2} />
                  <TextInput
                    style={styles.inputText}
                    value={dropoffAddress}
                    onChangeText={(value) => {
                      setDropoffAddress(value);
                      updateFieldError('dropoffAddress', value);
                    }}
                    placeholder="Where should this be delivered?"
                    placeholderTextColor={Colors.muted.foreground}
                    editable={!isLoading}
                    accessibilityLabel="Drop-off address"
                  />
                </View>
                {fieldErrors.dropoffAddress && (
                  <Text style={styles.fieldError}>{fieldErrors.dropoffAddress}</Text>
                )}
              </View>

              <View style={styles.inputGroup}>
                <Text style={styles.label}>Drop-off Instructions</Text>
                <View style={styles.inputWithIcon}>
                  <Package size={20} color={Colors.muted.foreground} strokeWidth={2} />
                  <TextInput
                    style={styles.inputText}
                    value={dropoffInstructions}
                    onChangeText={setDropoffInstructions}
                    placeholder="Any special delivery instructions?"
                    placeholderTextColor={Colors.muted.foreground}
                    editable={!isLoading}
                    accessibilityLabel="Drop-off instructions"
                  />
                </View>
              </View>
            </View>

            {/* Timing & Urgency Section */}
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Timing & Urgency</Text>
              
              <View style={styles.inputGroup}>
                <Text style={styles.label}>Estimated Time *</Text>
                <View style={[styles.inputWithIcon, fieldErrors.estimatedMinutes && styles.inputError]}>
                  <Clock size={20} color={Colors.muted.foreground} strokeWidth={2} />
                  <TextInput
                    style={styles.inputText}
                    value={estimatedMinutes}
                    onChangeText={(value) => {
                      setEstimatedMinutes(value);
                      updateFieldError('estimatedMinutes', value);
                    }}
                    placeholder="30"
                    placeholderTextColor={Colors.muted.foreground}
                    keyboardType="number-pad"
                    editable={!isLoading}
                    accessibilityLabel="Estimated time in minutes"
                  />
                </View>
                <Text style={styles.helperText}>in minutes</Text>
                {fieldErrors.estimatedMinutes && (
                  <Text style={styles.fieldError}>{fieldErrors.estimatedMinutes}</Text>
                )}
              </View>

              <UrgencySelector />
            </View>

            {/* Pricing Section */}
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Pricing</Text>
              <PricingBreakdown />
            </View>
          </View>
        </ScrollView>

        {/* Sticky Footer */}
        <StickyFormFooter
          onSubmit={handleSubmit}
          isSubmitting={isLoading}
          isValid={isFormValid()}
          buttonText="Post Task"
        />
      </KeyboardAvoidingView>

      {/* Auth Prompt Modal */}
      <AuthPrompt
        visible={showAuthPrompt}
        onClose={() => setShowAuthPrompt(false)}
        title="Sign in to post tasks"
        message="Create an account or sign in to post tasks and connect with other students."
      />

      {/* Success Sheet */}
      <TaskSuccessSheet
        visible={showSuccessSheet}
        onClose={() => setShowSuccessSheet(false)}
        taskId={lastCreatedTaskId}
      />

      {/* Toast */}
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
  content: {
    flex: 1,
  },
  scrollContent: {
    flexGrow: 1,
  },
  form: {
    padding: 24,
    gap: 32,
  },
  section: {
    gap: 20,
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: Colors.semantic.headingText,
    marginBottom: 4,
  },
  inputGroup: {
    gap: 8,
  },
  label: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.semantic.bodyText,
  },
  input: {
    borderWidth: 1,
    borderColor: 'rgba(229, 231, 235, 0.6)',
    borderRadius: 16,
    paddingHorizontal: 16,
    paddingVertical: 16,
    fontSize: 16,
    color: Colors.semantic.inputText,
    backgroundColor: 'rgba(255, 255, 255, 0.8)',
    minHeight: 44,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.03,
    shadowRadius: 6,
    elevation: 1,
  },
  inputError: {
    borderColor: Colors.semantic.errorAlert,
  },
  textArea: {
    height: 80,
    paddingTop: 16,
  },
  inputWithIcon: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: 'rgba(229, 231, 235, 0.6)',
    borderRadius: 16,
    paddingHorizontal: 16,
    paddingVertical: 16,
    gap: 12,
    minHeight: 44,
    backgroundColor: 'rgba(255, 255, 255, 0.8)',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.03,
    shadowRadius: 6,
    elevation: 1,
  },
  inputText: {
    flex: 1,
    fontSize: 16,
    color: Colors.semantic.inputText,
  },
  helperText: {
    fontSize: 14,
    color: Colors.semantic.tabInactive,
    marginTop: 4,
  },
  fieldError: {
    fontSize: 14,
    color: Colors.semantic.errorAlert,
    marginTop: 4,
  },
  segmentedControl: {
    flexDirection: 'row',
    backgroundColor: 'rgba(245, 245, 245, 0.8)',
    borderRadius: 16,
    padding: 4,
    borderWidth: 1,
    borderColor: 'rgba(229, 231, 235, 0.5)',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.03,
    shadowRadius: 6,
    elevation: 1,
  },
  segment: {
    flex: 1,
    paddingVertical: 12,
    alignItems: 'center',
    borderRadius: 12,
    minHeight: 44,
    justifyContent: 'center',
  },
  activeSegment: {
    backgroundColor: Colors.white,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 3 },
    shadowOpacity: 0.08,
    shadowRadius: 6,
    elevation: 3,
    borderWidth: 1,
    borderColor: 'rgba(0, 33, 165, 0.1)',
  },
  segmentText: {
    fontSize: 14,
    fontWeight: '500',
    color: Colors.semantic.tabInactive,
  },
  activeSegmentText: {
    color: Colors.primary,
    fontWeight: '600',
  },
  pricingCard: {
    backgroundColor: 'rgba(245, 245, 245, 0.8)',
    borderRadius: 16,
    padding: 16,
    gap: 8,
    borderWidth: 1,
    borderColor: 'rgba(229, 231, 235, 0.5)',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.04,
    shadowRadius: 12,
    elevation: 2,
  },
  pricingRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  pricingLabel: {
    fontSize: 14,
    color: Colors.semantic.tabInactive,
  },
  pricingValue: {
    fontSize: 14,
    color: Colors.semantic.bodyText,
    fontWeight: '500',
  },
  pricingTotal: {
    borderTopWidth: 1,
    borderTopColor: Colors.semantic.divider,
    paddingTop: 8,
    marginTop: 4,
  },
  pricingTotalLabel: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.semantic.bodyText,
  },
  pricingTotalValue: {
    fontSize: 18,
    fontWeight: '700',
    color: Colors.primary,
  },
  submitErrorContainer: {
    backgroundColor: '#FEF2F2',
    borderWidth: 1,
    borderColor: '#FECACA',
    borderRadius: 12,
    padding: 16,
  },
  submitErrorText: {
    fontSize: 14,
    color: Colors.semantic.errorAlert,
    textAlign: 'center',
    lineHeight: 20,
  },
  moderationErrorContainer: {
    backgroundColor: '#FEF2F2',
    borderWidth: 1,
    borderColor: '#FECACA',
    borderRadius: 12,
    padding: 16,
    gap: 12,
  },
  moderationErrorText: {
    fontSize: 14,
    color: Colors.semantic.errorAlert,
    textAlign: 'center',
    lineHeight: 20,
  },
  editResubmitButton: {
    backgroundColor: Colors.semantic.errorAlert,
    borderRadius: 8,
    paddingVertical: 8,
    paddingHorizontal: 16,
    alignSelf: 'center',
  },
  editResubmitButtonText: {
    fontSize: 14,
    fontWeight: '600',
    color: Colors.white,
  },
  prefilledChip: {
    backgroundColor: Colors.primary + '15', // 15% opacity
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 8,
    alignSelf: 'center',
    marginBottom: 16,
  },
  prefilledChipText: {
    fontSize: 12,
    fontWeight: '600',
    color: Colors.primary,
  },
});