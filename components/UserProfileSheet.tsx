import React, { useState, useRef } from 'react';
import { 
  View, 
  Text, 
  StyleSheet, 
  TouchableOpacity, 
  Modal, 
  Image, 
  ScrollView, 
  RefreshControl,
  Share,
  Alert,
  Dimensions,
  Platform
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { 
  X, 
  MessageCircle, 
  Flag, 
  Share2, 
  Star, 
  Calendar,
  GraduationCap,
  MapPin,
  User as UserIcon
} from 'lucide-react-native';
import * as Haptics from 'expo-haptics';
import { useRouter } from 'expo-router';
import { Colors } from '@/theme/colors';
import { useAuth } from '@/contexts/AuthContext';
import { useUserProfile } from '@/hooks/useUserProfile';
import { ChatService } from '@/lib/chat';
import StarRating from '@/components/StarRating';
import Toast from '@/components/Toast';

const { height } = Dimensions.get('window');

interface UserProfileSheetProps {
  visible: boolean;
  onClose: () => void;
  userId: string | null;
  currentChatRoomId?: string; // If opened from chat, don't show message button
}

const STAR_FILTERS = [
  { value: null, label: 'All' },
  { value: 5, label: '5★' },
  { value: 4, label: '4★' },
  { value: 3, label: '3★' },
  { value: 2, label: '2★' },
  { value: 1, label: '1★' },
];

export default function UserProfileSheet({ 
  visible, 
  onClose, 
  userId, 
  currentChatRoomId 
}: UserProfileSheetProps) {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const { user: currentUser } = useAuth();
  const scrollViewRef = useRef<ScrollView>(null);
  
  const { 
    data, 
    isLoading, 
    error, 
    refreshProfile, 
    loadMoreReviews, 
    filterReviews,
    isLoadingMore 
  } = useUserProfile(userId);

  const [selectedStarsFilter, setSelectedStarsFilter] = useState<number | null>(null);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [toast, setToast] = useState<{ visible: boolean; message: string; type: 'success' | 'error' }>({
    visible: false,
    message: '',
    type: 'success'
  });

  const triggerHaptics = () => {
    if (Platform.OS !== 'web') {
      try {
        Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      } catch (error) {
        // Haptics not available, continue silently
      }
    }
  };

  const handleRefresh = async () => {
    setIsRefreshing(true);
    await refreshProfile();
    setSelectedStarsFilter(null);
    setIsRefreshing(false);
  };

  const handleStarsFilter = async (starsFilter: number | null) => {
    triggerHaptics();
    setSelectedStarsFilter(starsFilter);
    await filterReviews(starsFilter);
    scrollViewRef.current?.scrollTo({ y: 0, animated: true });
  };

  const handleMessage = async () => {
    if (!userId || !currentUser || currentChatRoomId) return;
    
    triggerHaptics();
    onClose();
    
    try {
      // Find existing chat room or create one
      // For now, we'll navigate to chats tab - in a real app you'd create a DM room
      router.push('/(tabs)/chats');
      
      setToast({
        visible: true,
        message: 'Opening messages...',
        type: 'success'
      });
    } catch (error) {
      setToast({
        visible: true,
        message: 'Failed to open chat',
        type: 'error'
      });
    }
  };

  const handleReport = () => {
    triggerHaptics();
    Alert.alert(
      'Report User',
      'Why are you reporting this user?',
      [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Inappropriate behavior', onPress: () => submitReport('inappropriate') },
        { text: 'Spam or fake profile', onPress: () => submitReport('spam') },
        { text: 'Other', onPress: () => submitReport('other') },
      ]
    );
  };

  const submitReport = (reason: string) => {
    // TODO: Implement report submission
    setToast({
      visible: true,
      message: 'Report submitted. Thank you.',
      type: 'success'
    });
  };

  const handleShare = async () => {
    if (!data.profile) return;
    
    triggerHaptics();
    
    try {
      const profileUrl = `https://hustl.app/profile/${userId}`;
      const message = `Check out ${data.profile.full_name || data.profile.username || 'this user'}'s profile on Hustl: ${profileUrl}`;
      
      await Share.share({
        message,
        url: profileUrl,
        title: `${data.profile.full_name || data.profile.username || 'User'} - Hustl Profile`,
      });
    } catch (error) {
      console.error('Error sharing profile:', error);
    }
  };

  const handleLoadMore = () => {
    if (!isLoadingMore && data.hasMoreReviews) {
      loadMoreReviews();
    }
  };

  const hideToast = () => {
    setToast(prev => ({ ...prev, visible: false }));
  };

  const getInitials = (name: string | null): string => {
    if (!name) return 'U';
    return name
      .split(' ')
      .map(word => word.charAt(0))
      .join('')
      .toUpperCase()
      .slice(0, 2);
  };

  const formatDate = (dateString: string): string => {
    const date = new Date(dateString);
    return date.toLocaleDateString([], { 
      month: 'long', 
      year: 'numeric' 
    });
  };

  const formatReviewDate = (dateString: string): string => {
    const date = new Date(dateString);
    const now = new Date();
    const diffInDays = Math.floor((now.getTime() - date.getTime()) / (1000 * 60 * 60 * 24));
    
    if (diffInDays === 0) return 'Today';
    if (diffInDays === 1) return 'Yesterday';
    if (diffInDays < 7) return `${diffInDays} days ago`;
    if (diffInDays < 30) return `${Math.floor(diffInDays / 7)} weeks ago`;
    
    return date.toLocaleDateString([], { month: 'short', day: 'numeric' });
  };

  const formatOnlineStatus = (lastSeenAt: string): string => {
    const lastSeen = new Date(lastSeenAt);
    const now = new Date();
    const diffInMinutes = (now.getTime() - lastSeen.getTime()) / (1000 * 60);
    
    if (diffInMinutes < 5) return 'Online';
    if (diffInMinutes < 60) return `Last seen ${Math.floor(diffInMinutes)}m ago`;
    if (diffInMinutes < 1440) return `Last seen ${Math.floor(diffInMinutes / 60)}h ago`;
    return `Last seen ${Math.floor(diffInMinutes / 1440)}d ago`;
  };

  const renderSkeleton = () => (
    <View style={styles.skeletonContainer}>
      <View style={styles.skeletonAvatar} />
      <View style={styles.skeletonTextLarge} />
      <View style={styles.skeletonTextSmall} />
    </View>
  );

  const renderReviewItem = (review: any) => (
    <View key={review.id} style={styles.reviewItem}>
      <View style={styles.reviewHeader}>
        <StarRating rating={review.stars} size={16} showNumber={false} />
        <Text style={styles.reviewDate}>{formatReviewDate(review.created_at)}</Text>
      </View>
      
      {review.task && (
        <Text style={styles.reviewTaskTitle}>"{review.task.title}"</Text>
      )}
      
      {review.tags && review.tags.length > 0 && (
        <View style={styles.reviewTags}>
          {review.tags.slice(0, 3).map((tag: string, index: number) => (
            <View key={index} style={styles.reviewTag}>
              <Text style={styles.reviewTagText}>{tag}</Text>
            </View>
          ))}
          {review.tags.length > 3 && (
            <Text style={styles.reviewTagsMore}>+{review.tags.length - 3} more</Text>
          )}
        </View>
      )}
      
      {review.comment && (
        <Text style={styles.reviewComment} numberOfLines={3}>
          "{review.comment}"
        </Text>
      )}
      
      <View style={styles.reviewFooter}>
        <Text style={styles.reviewerName}>
          by {review.rater?.full_name || review.rater?.username || 'Anonymous'}
        </Text>
        {review.edited_at && (
          <Text style={styles.reviewEdited}>Edited</Text>
        )}
      </View>
    </View>
  );

  if (!visible || !userId) return null;

  return (
    <>
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

            <ScrollView
              ref={scrollViewRef}
              style={styles.content}
              showsVerticalScrollIndicator={false}
              refreshControl={
                <RefreshControl
                  refreshing={isRefreshing}
                  onRefresh={handleRefresh}
                  tintColor={Colors.primary}
                  colors={[Colors.primary]}
                />
              }
              onScroll={({ nativeEvent }) => {
                const { layoutMeasurement, contentOffset, contentSize } = nativeEvent;
                const isCloseToBottom = layoutMeasurement.height + contentOffset.y >= contentSize.height - 100;
                
                if (isCloseToBottom) {
                  handleLoadMore();
                }
              }}
              scrollEventThrottle={400}
            >
              {isLoading ? (
                renderSkeleton()
              ) : error ? (
                <View style={styles.errorContainer}>
                  <Text style={styles.errorText}>{error}</Text>
                  <TouchableOpacity style={styles.retryButton} onPress={() => refreshProfile()}>
                    <Text style={styles.retryButtonText}>Retry</Text>
                  </TouchableOpacity>
                </View>
              ) : data.profile ? (
                <>
                  {/* Profile Header */}
                  <View style={styles.profileSection}>
                    <View style={styles.avatarContainer}>
                      {data.profile.avatar_url ? (
                        <Image source={{ uri: data.profile.avatar_url }} style={styles.avatar} />
                      ) : (
                        <View style={styles.avatarPlaceholder}>
                          <Text style={styles.avatarText}>
                            {getInitials(data.profile.full_name || data.profile.username)}
                          </Text>
                        </View>
                      )}
                    </View>
                    
                    {/* Online Status */}
                    <View style={styles.onlineStatusContainer}>
                      <View style={[
                        styles.onlineStatusDot,
                        { backgroundColor: data.profile.last_seen_at && 
                          (new Date().getTime() - new Date(data.profile.last_seen_at).getTime()) < 5 * 60 * 1000
                          ? Colors.semantic.successAlert 
                          : Colors.semantic.tabInactive 
                        }
                      ]} />
                      <Text style={styles.onlineStatusText}>
                        {data.profile.last_seen_at 
                          ? formatOnlineStatus(data.profile.last_seen_at)
                          : 'Offline'
                        }
                      </Text>
                    </View>

                    <Text style={styles.displayName}>
                      {data.profile.full_name || data.profile.username || 'User'}
                    </Text>
                    
                    {data.profile.username && data.profile.full_name && (
                      <Text style={styles.username}>@{data.profile.username}</Text>
                    )}

                    {data.profile.major && (
                      <View style={styles.majorPill}>
                        <Text style={styles.majorText}>{data.profile.major}</Text>
                      </View>
                    )}

                    {/* Rating Summary */}
                    {data.aggregate && data.aggregate.ratings_count > 0 && (
                      <View style={styles.ratingContainer}>
                        <StarRating rating={data.aggregate.average_rating} size={20} />
                        <Text style={styles.ratingCount}>
                          ({data.aggregate.ratings_count} review{data.aggregate.ratings_count !== 1 ? 's' : ''})
                        </Text>
                      </View>
                    )}

                    {/* Stats Cards */}
                    <View style={styles.statsContainer}>
                      <View style={styles.statCard}>
                        <Text style={styles.statValue}>{data.profile.completed_tasks_count || 0}</Text>
                        <Text style={styles.statLabel}>Tasks</Text>
                      </View>
                      
                      <View style={styles.statCard}>
                        <Text style={styles.statValue}>{(data.profile.response_rate || 0).toFixed(0)}%</Text>
                        <Text style={styles.statLabel}>Response</Text>
                      </View>
                      
                      {data.profile.class_year && (
                        <View style={styles.statCard}>
                          <Text style={styles.statValue}>{data.profile.class_year}</Text>
                          <Text style={styles.statLabel}>Year</Text>
                        </View>
                      )}
                    </View>

                    {/* Action Buttons */}
                    <View style={styles.actionButtons}>
                      {!currentChatRoomId && currentUser?.id !== userId && (
                        <TouchableOpacity style={styles.messageButton} onPress={handleMessage}>
                          <MessageCircle size={16} color={Colors.white} strokeWidth={2} />
                          <Text style={styles.messageButtonText}>Message</Text>
                        </TouchableOpacity>
                      )}
                      
                      <TouchableOpacity style={styles.shareButton} onPress={handleShare}>
                        <Share2 size={16} color={Colors.primary} strokeWidth={2} />
                        <Text style={styles.shareButtonText}>Share</Text>
                      </TouchableOpacity>
                      
                      {currentUser?.id !== userId && (
                        <TouchableOpacity style={styles.reportButton} onPress={handleReport}>
                          <Flag size={16} color={Colors.semantic.errorAlert} strokeWidth={2} />
                          <Text style={styles.reportButtonText}>Report</Text>
                        </TouchableOpacity>
                      )}
                    </View>
                  </View>

                  {/* About Section */}
                  <View style={styles.section}>
                    <Text style={styles.sectionTitle}>About</Text>
                    
                    <View style={styles.aboutGrid}>
                      {data.profile.major && (
                        <View style={styles.aboutItem}>
                          <GraduationCap size={16} color={Colors.semantic.tabInactive} strokeWidth={2} />
                          <Text style={styles.aboutText}>{data.profile.major}</Text>
                        </View>
                      )}
                      
                      {data.profile.university && (
                        <View style={styles.aboutItem}>
                          <MapPin size={16} color={Colors.semantic.tabInactive} strokeWidth={2} />
                          <Text style={styles.aboutText}>{data.profile.university}</Text>
                        </View>
                      )}
                      
                      <View style={styles.aboutItem}>
                        <Calendar size={16} color={Colors.semantic.tabInactive} strokeWidth={2} />
                        <Text style={styles.aboutText}>
                          Member since {formatDate(data.profile.created_at)}
                        </Text>
                      </View>
                      
                      {data.profile.is_verified && (
                        <View style={styles.aboutItem}>
                          <View style={styles.verifiedBadge}>
                            <Text style={styles.verifiedText}>✓ Verified Student</Text>
                          </View>
                        </View>
                      )}
                    </View>

                    {data.profile.bio && data.profile.bio.trim() ? (
                      <Text style={styles.bioText} numberOfLines={3}>
                        {data.profile.bio}
                      </Text>
                    ) : (
                      <Text style={styles.noBioText}>No bio available</Text>
                    )}
                  </View>

                  {/* Reviews Section */}
                  <View style={styles.section}>
                    <Text style={styles.sectionTitle}>
                      Reviews {data.totalReviews > 0 && `(${data.totalReviews})`}
                    </Text>

                    {/* Rating Breakdown */}
                    {data.aggregate && data.aggregate.ratings_count > 0 && (
                      <View style={styles.ratingBreakdown}>
                        {Object.entries(data.aggregate.ratings_breakdown)
                          .reverse()
                          .map(([star, count]) => (
                            <View key={star} style={styles.breakdownRow}>
                              <Text style={styles.breakdownStar}>{star}★</Text>
                              <View style={styles.breakdownBar}>
                                <View 
                                  style={[
                                    styles.breakdownFill,
                                    { 
                                      width: data.aggregate!.ratings_count > 0 
                                        ? `${(count / data.aggregate!.ratings_count) * 100}%` 
                                        : '0%' 
                                    }
                                  ]} 
                                />
                              </View>
                              <Text style={styles.breakdownCount}>{count}</Text>
                            </View>
                          ))}
                      </View>
                    )}

                    {/* Filter Tabs */}
                    {data.totalReviews > 0 && (
                      <ScrollView 
                        horizontal 
                        showsHorizontalScrollIndicator={false}
                        contentContainerStyle={styles.filterTabs}
                      >
                        {STAR_FILTERS.map((filter) => (
                          <TouchableOpacity
                            key={filter.label}
                            style={[
                              styles.filterTab,
                              selectedStarsFilter === filter.value && styles.activeFilterTab
                            ]}
                            onPress={() => handleStarsFilter(filter.value)}
                          >
                            <Text style={[
                              styles.filterTabText,
                              selectedStarsFilter === filter.value && styles.activeFilterTabText
                            ]}>
                              {filter.label}
                            </Text>
                          </TouchableOpacity>
                        ))}
                      </ScrollView>
                    )}

                    {/* Reviews List */}
                    {data.reviews.length > 0 ? (
                      <View style={styles.reviewsList}>
                        {data.reviews.map(renderReviewItem)}
                        
                        {isLoadingMore && (
                          <View style={styles.loadingMore}>
                            <Text style={styles.loadingMoreText}>Loading more reviews...</Text>
                          </View>
                        )}
                      </View>
                    ) : (
                      <View style={styles.emptyReviews}>
                        <Star size={32} color={Colors.semantic.tabInactive} strokeWidth={1} />
                        <Text style={styles.emptyReviewsText}>No reviews yet</Text>
                        <Text style={styles.emptyReviewsSubtext}>
                          Reviews will appear here after completing tasks
                        </Text>
                      </View>
                    )}
                  </View>
                </>
              ) : null}
            </ScrollView>
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
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'flex-end',
  },
  sheet: {
    backgroundColor: Colors.semantic.screen,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    maxHeight: height * 0.85,
    minHeight: height * 0.4,
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
  skeletonContainer: {
    alignItems: 'center',
    paddingVertical: 40,
    gap: 16,
  },
  skeletonAvatar: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: Colors.muted,
  },
  skeletonTextLarge: {
    width: 120,
    height: 20,
    borderRadius: 10,
    backgroundColor: Colors.muted,
  },
  skeletonTextSmall: {
    width: 80,
    height: 16,
    borderRadius: 8,
    backgroundColor: Colors.muted,
  },
  errorContainer: {
    alignItems: 'center',
    paddingVertical: 40,
    gap: 16,
  },
  errorText: {
    fontSize: 16,
    color: Colors.semantic.errorAlert,
    textAlign: 'center',
  },
  retryButton: {
    backgroundColor: Colors.primary,
    borderRadius: 8,
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  retryButtonText: {
    fontSize: 14,
    fontWeight: '600',
    color: Colors.white,
  },
  profileSection: {
    alignItems: 'center',
    paddingBottom: 32,
    borderBottomWidth: 1,
    borderBottomColor: Colors.semantic.divider,
    marginBottom: 24,
  },
  avatarContainer: {
    marginBottom: 16,
  },
  avatar: {
    width: 80,
    height: 80,
    borderRadius: 40,
  },
  avatarPlaceholder: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: Colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    fontSize: 24,
    fontWeight: '700',
    color: Colors.white,
  },
  displayName: {
    fontSize: 24,
    fontWeight: '700',
    color: Colors.semantic.headingText,
    textAlign: 'center',
    marginBottom: 4,
  },
  username: {
    fontSize: 16,
    color: Colors.semantic.tabInactive,
    textAlign: 'center',
    marginBottom: 12,
  },
  majorPill: {
    backgroundColor: Colors.primary + '20',
    borderRadius: 16,
    paddingHorizontal: 12,
    paddingVertical: 6,
    marginBottom: 16,
  },
  majorText: {
    fontSize: 14,
    fontWeight: '600',
    color: Colors.primary,
  },
  onlineStatusContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginBottom: 12,
  },
  onlineStatusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  onlineStatusText: {
    fontSize: 12,
    color: Colors.semantic.tabInactive,
    fontWeight: '500',
  },
  statsContainer: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 20,
  },
  statCard: {
    flex: 1,
    backgroundColor: Colors.muted,
    borderRadius: 12,
    padding: 12,
    alignItems: 'center',
    gap: 4,
  },
  statValue: {
    fontSize: 18,
    fontWeight: '700',
    color: Colors.semantic.bodyText,
  },
  statLabel: {
    fontSize: 11,
    color: Colors.semantic.tabInactive,
    fontWeight: '500',
  },
  ratingContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 20,
  },
  ratingCount: {
    fontSize: 14,
    color: Colors.semantic.tabInactive,
    fontWeight: '500',
  },
  actionButtons: {
    flexDirection: 'row',
    gap: 12,
    flexWrap: 'wrap',
    justifyContent: 'center',
  },
  messageButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.primary,
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 10,
    gap: 6,
  },
  messageButtonText: {
    fontSize: 14,
    fontWeight: '600',
    color: Colors.white,
  },
  shareButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'transparent',
    borderWidth: 1,
    borderColor: Colors.primary,
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 10,
    gap: 6,
  },
  shareButtonText: {
    fontSize: 14,
    fontWeight: '600',
    color: Colors.primary,
  },
  reportButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'transparent',
    borderWidth: 1,
    borderColor: Colors.semantic.errorAlert,
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 10,
    gap: 6,
  },
  reportButtonText: {
    fontSize: 14,
    fontWeight: '600',
    color: Colors.semantic.errorAlert,
  },
  section: {
    marginBottom: 32,
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: Colors.semantic.headingText,
    marginBottom: 16,
  },
  aboutGrid: {
    gap: 12,
    marginBottom: 16,
  },
  aboutItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  aboutText: {
    fontSize: 16,
    color: Colors.semantic.bodyText,
    flex: 1,
  },
  verifiedBadge: {
    backgroundColor: Colors.semantic.successAlert + '20',
    borderRadius: 12,
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  verifiedText: {
    fontSize: 12,
    fontWeight: '600',
    color: Colors.semantic.successAlert,
  },
  bioText: {
    fontSize: 16,
    color: Colors.semantic.bodyText,
    lineHeight: 24,
    fontStyle: 'italic',
  },
  noBioText: {
    fontSize: 16,
    color: Colors.semantic.tabInactive,
    fontStyle: 'italic',
  },
  ratingBreakdown: {
    backgroundColor: Colors.muted,
    borderRadius: 12,
    padding: 16,
    marginBottom: 16,
    gap: 8,
  },
  breakdownRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  breakdownStar: {
    fontSize: 12,
    fontWeight: '600',
    color: Colors.semantic.bodyText,
    width: 20,
  },
  breakdownBar: {
    flex: 1,
    height: 6,
    backgroundColor: Colors.semantic.divider,
    borderRadius: 3,
    overflow: 'hidden',
  },
  breakdownFill: {
    height: '100%',
    backgroundColor: '#FA4616',
    borderRadius: 3,
  },
  breakdownCount: {
    fontSize: 12,
    color: Colors.semantic.tabInactive,
    width: 20,
    textAlign: 'right',
  },
  filterTabs: {
    paddingBottom: 16,
    gap: 8,
  },
  filterTab: {
    backgroundColor: Colors.muted,
    borderRadius: 20,
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderWidth: 1,
    borderColor: Colors.semantic.inputBorder,
  },
  activeFilterTab: {
    backgroundColor: Colors.primary,
    borderColor: Colors.primary,
  },
  filterTabText: {
    fontSize: 14,
    fontWeight: '500',
    color: Colors.semantic.bodyText,
  },
  activeFilterTabText: {
    color: Colors.white,
  },
  reviewsList: {
    gap: 16,
  },
  reviewItem: {
    backgroundColor: Colors.semantic.card,
    borderRadius: 12,
    padding: 16,
    borderWidth: 1,
    borderColor: Colors.semantic.cardBorder,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 4,
    elevation: 1,
  },
  reviewHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  reviewDate: {
    fontSize: 12,
    color: Colors.semantic.tabInactive,
  },
  reviewTaskTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: Colors.semantic.bodyText,
    marginBottom: 8,
    fontStyle: 'italic',
  },
  reviewTags: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
    marginBottom: 8,
    alignItems: 'center',
  },
  reviewTag: {
    backgroundColor: Colors.muted,
    borderRadius: 12,
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  reviewTagText: {
    fontSize: 12,
    fontWeight: '500',
    color: Colors.semantic.bodyText,
  },
  reviewTagsMore: {
    fontSize: 12,
    color: Colors.semantic.tabInactive,
    fontStyle: 'italic',
  },
  reviewComment: {
    fontSize: 14,
    color: Colors.semantic.bodyText,
    lineHeight: 20,
    marginBottom: 8,
    fontStyle: 'italic',
  },
  reviewFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  reviewerName: {
    fontSize: 12,
    color: Colors.semantic.tabInactive,
    fontWeight: '500',
  },
  reviewEdited: {
    fontSize: 11,
    color: Colors.semantic.tabInactive,
    fontStyle: 'italic',
  },
  loadingMore: {
    paddingVertical: 20,
    alignItems: 'center',
  },
  loadingMoreText: {
    fontSize: 14,
    color: Colors.semantic.tabInactive,
  },
  emptyReviews: {
    alignItems: 'center',
    paddingVertical: 40,
    gap: 12,
  },
  emptyReviewsText: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.semantic.headingText,
  },
  emptyReviewsSubtext: {
    fontSize: 14,
    color: Colors.semantic.tabInactive,
    textAlign: 'center',
  },
});