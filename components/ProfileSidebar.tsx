import React, { useEffect } from 'react';
import { 
  View, 
  Text, 
  StyleSheet, 
  TouchableOpacity, 
  Modal, 
  ScrollView, 
  Image,
  Dimensions,
  Platform
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { X, User, Star, FileText, History, MessageSquare, Gift, Settings, CircleHelp as HelpCircle, MessageCircle, LogOut, ChevronRight, Shield, CreditCard, Wallet, DollarSign } from 'lucide-react-native';
import * as Haptics from 'expo-haptics';
import Animated, { 
  useSharedValue, 
  useAnimatedStyle, 
  withTiming, 
  withSpring,
  runOnJS
} from 'react-native-reanimated';
import { LinearGradient } from 'expo-linear-gradient';
import { Colors } from '@/theme/colors';
import { useAuth } from '@/contexts/AuthContext';

const { width } = Dimensions.get('window');

interface ProfileSidebarProps {
  visible: boolean;
  onClose: () => void;
}

interface MenuItem {
  icon: React.ReactNode;
  title: string;
  route: string;
  color?: string;
}

const AnimatedTouchableOpacity = Animated.createAnimatedComponent(TouchableOpacity);

export default function ProfileSidebar({ visible, onClose }: ProfileSidebarProps) {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user, logout, isGuest } = useAuth();
  
  // Animation values
  const overlayOpacity = useSharedValue(0);
  const sidebarTranslateX = useSharedValue(-width);

  // Menu items with user context
  const getMenuItems = (): MenuItem[] => [
    { 
      icon: <User size={20} color={Colors.semantic.bodyText} strokeWidth={2} />, 
      title: 'Profile Information',
      route: '/profile/edit'
    },
    { 
      icon: <Wallet size={20} color={Colors.semantic.bodyText} strokeWidth={2} />, 
      title: 'Wallet',
      route: '/wallet'
    },
    { 
      icon: <DollarSign size={20} color={Colors.semantic.bodyText} strokeWidth={2} />, 
      title: 'Credits',
      route: '/credits'
    },
    { 
      icon: <Star size={20} color={Colors.semantic.bodyText} strokeWidth={2} />, 
      title: 'Reviews',
      route: `/profile/reviews?userId=${user?.id || ''}`
    },
    { 
      icon: <FileText size={20} color={Colors.semantic.bodyText} strokeWidth={2} />, 
      title: 'My Tasks',
      route: '/profile/my-tasks'
    },
    { 
      icon: <History size={20} color={Colors.semantic.bodyText} strokeWidth={2} />, 
      title: 'Task History',
      route: '/profile/task-history'
    },
    { 
      icon: <MessageSquare size={20} color={Colors.semantic.bodyText} strokeWidth={2} />, 
      title: 'Messages',
      route: '/(tabs)/chats'
    },
    { 
      icon: <Gift size={20} color={Colors.semantic.bodyText} strokeWidth={2} />, 
      title: 'Rewards & Referrals',
      route: '/(tabs)/referrals'
    },
    { 
      icon: <Settings size={20} color={Colors.semantic.bodyText} strokeWidth={2} />, 
      title: 'Settings',
      route: '/profile/settings'
    },
    { 
      icon: <HelpCircle size={20} color={Colors.semantic.bodyText} strokeWidth={2} />, 
      title: 'Help & Support',
      route: '/profile/help'
    },
    { 
      icon: <MessageCircle size={20} color={Colors.semantic.bodyText} strokeWidth={2} />, 
      title: 'Send Feedback',
      route: '/profile/help' // For now, redirect to help
    },
  ];

  const overlayAnimatedStyle = useAnimatedStyle(() => ({
    opacity: overlayOpacity.value,
  }));

  const sidebarAnimatedStyle = useAnimatedStyle(() => ({
    transform: [{ translateX: sidebarTranslateX.value }],
  }));

  useEffect(() => {
    if (visible) {
      // Show animations
      overlayOpacity.value = withTiming(1, { duration: 300 });
      sidebarTranslateX.value = withSpring(0, { damping: 20, stiffness: 300 });
    } else {
      // Hide animations
      overlayOpacity.value = withTiming(0, { duration: 200 });
      sidebarTranslateX.value = withTiming(-width, { duration: 250 });
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

  const handleMenuPress = (route: string) => {
    triggerHaptics();
    onClose();
    
    // Small delay to let sidebar close animation start
    setTimeout(() => {
      router.push(route as any);
    }, 100);
  };

  const handleLogout = async () => {
    triggerHaptics();
    onClose();
    
    try {
      await logout();
      router.replace('/(onboarding)/welcome');
    } catch (error) {
      console.error('Logout error:', error);
    }
  };

  const handleOverlayPress = () => {
    onClose();
  };

  const getInitials = (name: string): string => {
    return name
      .split(' ')
      .map(word => word.charAt(0))
      .join('')
      .toUpperCase()
      .slice(0, 2);
  };

  const renderMenuItem = (item: MenuItem, index: number) => (
    <TouchableOpacity
      key={index}
      style={styles.menuItem}
      onPress={() => handleMenuPress(item.route)}
      activeOpacity={0.7}
      accessibilityLabel={item.title}
      accessibilityRole="button"
    >
      <View style={styles.menuItemLeft}>
        <View style={styles.menuItemIcon}>
          {item.icon}
        </View>
        <Text style={[styles.menuItemText, item.color && { color: item.color }]}>
          {item.title}
        </Text>
      </View>
      <ChevronRight size={16} color={Colors.semantic.tabInactive} strokeWidth={2} />
    </TouchableOpacity>
  );

  if (!visible) return null;

  return (
    <Modal
      visible={visible}
      transparent
      animationType="none"
      onRequestClose={onClose}
      statusBarTranslucent
    >
      <View style={styles.container}>
        {/* Overlay */}
        <AnimatedTouchableOpacity
          style={[styles.overlay, overlayAnimatedStyle]}
          onPress={handleOverlayPress}
          activeOpacity={1}
        />

        {/* Sidebar */}
        <Animated.View style={[styles.sidebar, sidebarAnimatedStyle, { paddingTop: insets.top }]}>
          {/* Header */}
          <View style={styles.header}>
            <TouchableOpacity style={styles.closeButton} onPress={onClose}>
              <X size={20} color={Colors.white} strokeWidth={2} />
            </TouchableOpacity>
          </View>

          <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
            {/* Profile Section */}
            <View style={styles.profileSection}>
              <LinearGradient
                colors={['#0021A5', '#FA4616']}
                start={{ x: 0, y: 0 }}
                end={{ x: 1, y: 1 }}
                style={styles.profileGradient}
              >
                <View style={styles.profileContent}>
                  <View style={styles.avatarContainer}>
                    <View style={styles.avatar}>
                      <Text style={styles.avatarText}>
                        {user ? getInitials(user.displayName) : (isGuest ? '?' : 'U')}
                      </Text>
                    </View>
                  </View>
                  
                  <Text style={styles.displayName}>
                    {user ? user.displayName : (isGuest ? 'Guest User' : 'User')}
                  </Text>
                  
                  <Text style={styles.userInfo}>
                    {user ? `${user.university || 'University of Florida'} • Student` : 'Browse as Guest'}
                  </Text>
                </View>
              </LinearGradient>
            </View>

            {/* Account Status Card */}
            <View style={styles.statusCard}>
              <View style={styles.statusHeader}>
                <View style={styles.statusIcon}>
                  {isGuest ? (
                    <User size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />
                  ) : (
                    <Shield size={20} color={Colors.semantic.successAlert} strokeWidth={2} />
                  )}
                </View>
                <View style={styles.statusInfo}>
                  <Text style={styles.statusTitle}>
                    {isGuest ? 'Guest Mode' : 'Verified Student'}
                  </Text>
                  <Text style={styles.statusSubtitle}>
                    {isGuest ? 'Limited access to features' : 'Full access to all features'}
                  </Text>
                </View>
              </View>
            </View>

            {/* Menu Items */}
            <View style={styles.menuSection}>
              {getMenuItems().slice(0, 3).map(renderMenuItem)}
            </View>

            <View style={styles.menuSection}>
              {getMenuItems().slice(3, 7).map((item, index) => renderMenuItem(item, index + 3))}
            </View>

            <View style={styles.menuSection}>
              {getMenuItems().slice(7).map((item, index) => renderMenuItem(item, index + 7))}
            </View>

            {/* Logout */}
            {!isGuest && (
              <View style={styles.logoutSection}>
                <TouchableOpacity
                  style={styles.logoutItem}
                  onPress={handleLogout}
                  activeOpacity={0.7}
                  accessibilityLabel="Log out"
                  accessibilityRole="button"
                >
                  <View style={styles.menuItemLeft}>
                    <View style={styles.menuItemIcon}>
                      <LogOut size={20} color={Colors.semantic.errorAlert} strokeWidth={2} />
                    </View>
                    <Text style={[styles.menuItemText, { color: Colors.semantic.errorAlert }]}>
                      Log Out
                    </Text>
                  </View>
                  <ChevronRight size={16} color={Colors.semantic.tabInactive} strokeWidth={2} />
                </TouchableOpacity>
              </View>
            )}

            {/* Footer */}
            <View style={[styles.footer, { paddingBottom: insets.bottom + 20 }]}>
              <Text style={styles.versionText}>Version 1.0 build 2025.1</Text>
              
              <TouchableOpacity onPress={() => console.log('Terms & Privacy pressed')}>
                <Text style={styles.legalText}>Terms of Service & Privacy Policy</Text>
              </TouchableOpacity>
              
              <Text style={styles.copyrightText}>
                © 2025 HUSTLU LLC. All Rights Reserved.
              </Text>
            </View>
          </ScrollView>
        </Animated.View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  overlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
  },
  sidebar: {
    position: 'absolute',
    top: 0,
    left: 0,
    bottom: 0,
    width: width * 0.85,
    maxWidth: 320,
    backgroundColor: Colors.semantic.screen,
    shadowColor: '#000',
    shadowOffset: { width: 4, height: 0 },
    shadowOpacity: 0.15,
    shadowRadius: 20,
    elevation: 20,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: 'transparent',
    position: 'absolute',
    top: 0,
    right: 0,
    zIndex: 10,
  },
  closeButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
    justifyContent: 'center',
    alignItems: 'center',
    backdropFilter: 'blur(10px)',
  },
  content: {
    flex: 1,
  },
  profileSection: {
    marginBottom: 20,
  },
  profileGradient: {
    paddingHorizontal: 24,
    paddingVertical: 32,
    paddingTop: 64,
  },
  profileContent: {
    alignItems: 'center',
  },
  avatarContainer: {
    marginBottom: 16,
  },
  avatar: {
    width: 88,
    height: 88,
    borderRadius: 44,
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 3,
    borderColor: 'rgba(255, 255, 255, 0.3)',
    shadowColor: 'rgba(0, 0, 0, 0.3)',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 1,
    shadowRadius: 8,
  },
  avatarText: {
    fontSize: 28,
    fontWeight: '700',
    color: Colors.white,
  },
  displayName: {
    fontSize: 24,
    fontWeight: '700',
    color: Colors.white,
    marginBottom: 4,
    textAlign: 'center',
    textShadowColor: 'rgba(0, 0, 0, 0.3)',
    textShadowOffset: { width: 0, height: 1 },
    textShadowRadius: 2,
  },
  userInfo: {
    fontSize: 14,
    color: 'rgba(255, 255, 255, 0.9)',
    textAlign: 'center',
    textShadowColor: 'rgba(0, 0, 0, 0.2)',
    textShadowOffset: { width: 0, height: 1 },
    textShadowRadius: 2,
  },
  statusCard: {
    backgroundColor: Colors.semantic.card,
    marginHorizontal: 16,
    marginBottom: 24,
    borderRadius: 20,
    padding: 16,
    borderWidth: 1,
    borderColor: 'rgba(229, 231, 235, 0.5)',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 6 },
    shadowOpacity: 0.06,
    shadowRadius: 16,
    elevation: 4,
  },
  statusHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 12,
  },
  statusIcon: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: 'rgba(245, 245, 245, 0.8)',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
    borderWidth: 1,
    borderColor: 'rgba(229, 231, 235, 0.5)',
  },
  statusInfo: {
    flex: 1,
  },
  statusTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.semantic.bodyText,
    marginBottom: 2,
  },
  statusSubtitle: {
    fontSize: 12,
    color: Colors.semantic.tabInactive,
  },
  creditsContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(0, 33, 165, 0.08)',
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 8,
    gap: 8,
    borderWidth: 1,
    borderColor: 'rgba(0, 33, 165, 0.15)',
  },
  creditsText: {
    fontSize: 14,
    fontWeight: '600',
    color: Colors.primary,
  },
  menuSection: {
    paddingHorizontal: 8,
    marginBottom: 24,
  },
  menuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 18,
    borderRadius: 16,
    marginBottom: 4,
    backgroundColor: 'rgba(255, 255, 255, 0.6)',
    borderWidth: 1,
    borderColor: 'rgba(229, 231, 235, 0.3)',
  },
  menuItemLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
  },
  menuItemIcon: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: 'rgba(245, 245, 245, 0.8)',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 16,
    borderWidth: 1,
    borderColor: 'rgba(229, 231, 235, 0.5)',
  },
  menuItemText: {
    fontSize: 16,
    fontWeight: '500',
    color: Colors.semantic.bodyText,
    flex: 1,
  },
  logoutSection: {
    paddingHorizontal: 8,
    marginBottom: 32,
    borderTopWidth: 1,
    borderTopColor: 'rgba(229, 231, 235, 0.5)',
    paddingTop: 16,
  },
  logoutItem: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 18,
    borderRadius: 16,
    backgroundColor: 'rgba(255, 255, 255, 0.6)',
    borderWidth: 1,
    borderColor: 'rgba(229, 231, 235, 0.3)',
  },
  footer: {
    paddingHorizontal: 24,
    alignItems: 'center',
    gap: 12,
  },
  versionText: {
    fontSize: 12,
    color: Colors.semantic.tabInactive,
    fontWeight: '500',
  },
  legalText: {
    fontSize: 12,
    color: Colors.primary,
    fontWeight: '500',
    textDecorationLine: 'underline',
  },
  copyrightText: {
    fontSize: 11,
    color: Colors.semantic.tabInactive,
    textAlign: 'center',
    lineHeight: 16,
  },
});