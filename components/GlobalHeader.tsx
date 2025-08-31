import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Image, Platform, TextInput, Modal, ScrollView, Dimensions } from 'react-native';
import { useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Search, Bell, X, CircleHelp as HelpCircle, Flag, MessageSquare, Settings, User, FileText } from 'lucide-react-native';
import * as Haptics from 'expo-haptics';
import Animated, { useSharedValue, useAnimatedStyle, withTiming, withSpring } from 'react-native-reanimated';
import { Colors } from '@/theme/colors';
import { useAuth } from '@/contexts/AuthContext';
import ProfileSidebar from './ProfileSidebar';

const { width } = Dimensions.get('window');

const SEARCH_ITEMS = [
  { id: 'help', title: 'Help & Support', subtitle: 'Get assistance', icon: <HelpCircle size={20} color={Colors.primary} strokeWidth={2} />, route: '/profile/help' },
  { id: 'report', title: 'Report Issue', subtitle: 'Report a problem', icon: <Flag size={20} color={Colors.semantic.errorAlert} strokeWidth={2} />, route: '/profile/help' },
  { id: 'feedback', title: 'Send Feedback', subtitle: 'Share your thoughts', icon: <MessageSquare size={20} color={Colors.primary} strokeWidth={2} />, route: '/profile/help' },
  { id: 'settings', title: 'Settings', subtitle: 'App preferences', icon: <Settings size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />, route: '/profile/settings' },
  { id: 'profile', title: 'Profile', subtitle: 'Your account', icon: <User size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />, route: '/profile' },
  { id: 'my-tasks', title: 'My Tasks', subtitle: 'Tasks you posted', icon: <FileText size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />, route: '/profile/my-tasks' },
  { id: 'task-history', title: 'Task History', subtitle: 'Completed tasks', icon: <FileText size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />, route: '/profile/task-history' },
];

interface GlobalHeaderProps {
  showSearch?: boolean;
  showNotifications?: boolean;
  title?: string;
}

export default function GlobalHeader({ 
  showSearch = true, 
  showNotifications = true,
  title 
}: GlobalHeaderProps) {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user, isGuest } = useAuth();

  const [showProfileSidebar, setShowProfileSidebar] = React.useState(false);
  const [showSearchModal, setShowSearchModal] = React.useState(false);
  const [searchQuery, setSearchQuery] = React.useState('');
  const [filteredSearchItems, setFilteredSearchItems] = React.useState(SEARCH_ITEMS);

  const triggerHaptics = () => {
    if (Platform.OS !== 'web') {
      try {
        Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      } catch (error) {
        // Haptics not available, continue silently
      }
    }
  };

  const handleProfilePress = () => {
    triggerHaptics();
    
    if (isGuest) {
      router.push('/(onboarding)/auth');
      return;
    }
    
    // Open sidebar for authenticated users
    setShowProfileSidebar(true);
  };

  const handleLogoPress = () => {
    triggerHaptics();
    router.push('/(tabs)/home');
  };

  const handleSearchPress = () => {
    triggerHaptics();
    setShowSearchModal(true);
  };

  const handleSearchQueryChange = (query: string) => {
    setSearchQuery(query);
    
    if (!query.trim()) {
      setFilteredSearchItems(SEARCH_ITEMS);
      return;
    }
    
    const filtered = SEARCH_ITEMS.filter(item =>
      item.title.toLowerCase().includes(query.toLowerCase()) ||
      item.subtitle.toLowerCase().includes(query.toLowerCase())
    );
    setFilteredSearchItems(filtered);
  };

  const handleSearchItemPress = (route: string) => {
    triggerHaptics();
    setShowSearchModal(false);
    setSearchQuery('');
    setFilteredSearchItems(SEARCH_ITEMS);
    router.push(route as any);
  };

  const closeSearchModal = () => {
    setShowSearchModal(false);
    setSearchQuery('');
    setFilteredSearchItems(SEARCH_ITEMS);
  };

  const handleNotificationsPress = () => {
    console.log('Notifications pressed');
  };

  const getInitials = (name: string): string => {
    return name
      .split(' ')
      .map(word => word.charAt(0))
      .join('')
      .toUpperCase()
      .slice(0, 2);
  };

  const SearchModal = () => (
    <Modal
      visible={showSearchModal}
      transparent
      animationType="fade"
      onRequestClose={closeSearchModal}
    >
      <View style={styles.searchOverlay}>
        <View style={[styles.searchModal, { paddingTop: insets.top + 20 }]}>
          <View style={styles.searchHeader}>
            <View style={styles.searchInputContainer}>
              <Search size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />
              <TextInput
                style={styles.searchInput}
                value={searchQuery}
                onChangeText={handleSearchQueryChange}
                placeholder="Search for help, settings, or features..."
                placeholderTextColor={Colors.semantic.tabInactive}
                autoFocus
              />
            </View>
            <TouchableOpacity style={styles.searchCloseButton} onPress={closeSearchModal}>
              <X size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />
            </TouchableOpacity>
          </View>
          
          <ScrollView style={styles.searchResults} showsVerticalScrollIndicator={false}>
            {filteredSearchItems.length > 0 ? (
              filteredSearchItems.map((item) => (
                <TouchableOpacity
                  key={item.id}
                  style={styles.searchResultItem}
                  onPress={() => handleSearchItemPress(item.route)}
                >
                  <View style={styles.searchResultIcon}>
                    {item.icon}
                  </View>
                  <View style={styles.searchResultContent}>
                    <Text style={styles.searchResultTitle}>{item.title}</Text>
                    <Text style={styles.searchResultSubtitle}>{item.subtitle}</Text>
                  </View>
                </TouchableOpacity>
              ))
            ) : (
              <View style={styles.noResults}>
                <Text style={styles.noResultsText}>No results found</Text>
                <Text style={styles.noResultsSubtext}>Try searching for "help", "settings", or "profile"</Text>
              </View>
            )}
          </ScrollView>
        </View>
      </View>
    </Modal>
  );

  if (isGuest) {
    return (
      <>
        <View style={[styles.container, { paddingTop: insets.top }]}>
          <View style={styles.content}>
            <TouchableOpacity
              style={styles.guestProfileChip}
              onPress={handleProfilePress}
              accessibilityLabel="Sign in"
              accessibilityRole="button"
            >
              <View style={styles.guestAvatar}>
                <Text style={styles.guestAvatarText}>?</Text>
              </View>
            </TouchableOpacity>
            
            <TouchableOpacity 
              style={styles.logoContainer} 
              onPress={handleLogoPress}
              activeOpacity={0.7}
              accessibilityLabel="Go to Home"
              accessibilityRole="button"
            >
              <Image
                source={require('../src/assets/images/image.png')}
                style={styles.headerLogo}
                resizeMode="contain"
              />
              <Text style={styles.headerBrandText}>Hustl</Text>
            </TouchableOpacity>
            
            <View style={styles.rightSection}>
              {showSearch && (
                <TouchableOpacity style={styles.iconButton} onPress={handleSearchPress}>
                  <Search size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />
                </TouchableOpacity>
              )}
            </View>
          </View>
        </View>
        
        {renderHeaderDropdown()}
        
        {/* Profile Sidebar */}
        <ProfileSidebar
          visible={showProfileSidebar}
          onClose={() => setShowProfileSidebar(false)}
        />
        
        <SearchModal />
      </>
    );
  }

  return (
    <>
      <View style={[styles.container, { paddingTop: insets.top }]}>
        <View style={styles.content}>
          <View style={styles.leftSection}>
            <TouchableOpacity
              style={styles.profileChip}
              onPress={handleProfilePress}
              onLongPress={handleProfileLongPress}
              accessibilityLabel="Profile"
              accessibilityRole="button"
            >
              <View style={styles.avatar}>
                <Text style={styles.avatarText}>
                  {user ? getInitials(user.displayName) : 'U'}
                </Text>
              </View>
            </TouchableOpacity>
            
            <TouchableOpacity 
              style={styles.logoContainer} 
              onPress={handleLogoPress}
              activeOpacity={0.7}
              accessibilityLabel="Go to Home"
              accessibilityRole="button"
            >
              <Image
                source={require('../src/assets/images/image.png')}
                style={styles.headerLogo}
                resizeMode="contain"
              />
              <Text style={styles.headerBrandText}>Hustl</Text>
            <TouchableOpacity 
              style={styles.logoContainer} 
              onPress={handleLogoPress}
              activeOpacity={0.7}
              accessibilityLabel="Go to Home"
              accessibilityRole="button"
            >
              <Image
                source={require('../src/assets/images/image.png')}
                style={styles.headerLogo}
                resizeMode="contain"
              />
              <Text style={styles.headerBrandText}>Hustl</Text>
            </TouchableOpacity>
          </View>

          {title && (
            <Text style={styles.title}>{title}</Text>
          )}

          <View style={styles.rightSection}>
            {showSearch && (
              <TouchableOpacity style={styles.iconButton} onPress={handleSearchPress}>
                <Search size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />
              </TouchableOpacity>
            )}
            
            {showNotifications && (
              <TouchableOpacity style={styles.iconButton} onPress={handleNotificationsPress}>
                <Bell size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />
              </TouchableOpacity>
            )}
          </View>
        </View>
      {/* Profile Sidebar */}
      <ProfileSidebar
        visible={showProfileSidebar}
        onClose={() => setShowProfileSidebar(false)}
      />
      
      <SearchModal />
    </>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: '#FFFFFF',
    borderBottomWidth: 0,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.06,
    shadowRadius: 12,
    elevation: 4,
  },
  content: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 16,
    minHeight: 56,
  },
  leftSection: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  profileChip: {
    borderRadius: 22,
    borderWidth: 2,
    borderColor: 'rgba(0, 33, 165, 0.2)',
    padding: 2,
    shadowColor: '#0021A5',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  guestProfileChip: {
    borderRadius: 22,
    borderWidth: 2,
    borderColor: 'rgba(156, 163, 175, 0.3)',
    padding: 2,
  },
  avatar: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: Colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  guestAvatar: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: Colors.semantic.tabInactive,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    fontSize: 14,
    fontWeight: '700',
    color: '#FFFFFF',
  },
  guestAvatarText: {
    fontSize: 14,
    fontWeight: '700',
    color: '#F1F5F9',
  },
  logoContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  headerLogo: {
    width: 28,
    height: 28,
  },
  headerBrandText: {
    fontSize: 16,
    fontWeight: '700',
    color: Colors.semantic.headingText,
    letterSpacing: 0.3,
  },
  title: {
    fontSize: 18,
    fontWeight: '600',
    color: Colors.semantic.headingText,
    textAlign: 'center',
    flex: 1,
  },
  rightSection: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  iconButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: 'rgba(245, 245, 245, 0.8)',
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: 'rgba(229, 231, 235, 0.5)',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.04,
    shadowRadius: 6,
    elevation: 2,
  },
  searchOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
  },
  searchModal: {
    flex: 1,
    backgroundColor: Colors.white,
    paddingHorizontal: 20,
  },
  searchHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    marginBottom: 20,
  },
  searchInputContainer: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(245, 245, 245, 0.8)',
    borderRadius: 16,
    paddingHorizontal: 16,
    paddingVertical: 12,
    gap: 12,
    borderWidth: 1,
    borderColor: 'rgba(229, 231, 235, 0.5)',
  },
  searchInput: {
    flex: 1,
    fontSize: 16,
    color: Colors.semantic.inputText,
  },
  searchCloseButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(245, 245, 245, 0.8)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  searchResults: {
    flex: 1,
  },
  searchResultItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 16,
    borderRadius: 12,
    marginBottom: 8,
    backgroundColor: 'rgba(255, 255, 255, 0.8)',
    borderWidth: 1,
    borderColor: 'rgba(229, 231, 235, 0.3)',
    gap: 16,
  },
  searchResultIcon: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: 'rgba(245, 245, 245, 0.8)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  searchResultContent: {
    flex: 1,
  },
  searchResultTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.semantic.bodyText,
    marginBottom: 2,
  },
  searchResultSubtitle: {
    fontSize: 14,
    color: Colors.semantic.tabInactive,
  },
  noResults: {
    alignItems: 'center',
    paddingVertical: 60,
    gap: 12,
  },
  noResultsText: {
    fontSize: 18,
    fontWeight: '600',
    color: Colors.semantic.headingText,
  },
  noResultsSubtext: {
    fontSize: 14,
    color: Colors.semantic.tabInactive,
    textAlign: 'center',
  },
});