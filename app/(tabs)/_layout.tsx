import React from 'react';
import { Tabs } from 'expo-router';
import { Chrome as Home, List, MessageCircle, Gift, Zap } from 'lucide-react-native';
import { TouchableOpacity, View, StyleSheet, Platform, Text } from 'react-native';
import { useRouter } from 'expo-router';
import * as Haptics from 'expo-haptics';
import { LinearGradient } from 'expo-linear-gradient';
import { Colors } from '@/theme/colors';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

// Post Task Tab Button Component
const PostTaskButton = () => {
  const router = useRouter();

  const handlePress = () => {
    if (Platform.OS !== 'web') {
      try {
        Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      } catch (error) {
        // Haptics not available, continue silently
      }
    }
    router.push('/(tabs)/post');
  };

  return (
    <TouchableOpacity
      style={styles.postTaskButton}
      onPress={handlePress}
      activeOpacity={0.8}
      accessibilityLabel="Post Task"
      accessibilityRole="button"
    >
      <View style={styles.postTaskIconContainer}>
        <LinearGradient
          colors={['#0021A5', '#FA4616']}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 1 }}
          style={styles.postTaskGradient}
        >
          <Zap size={24} color={Colors.white} strokeWidth={2.5} fill={Colors.white} />
        </LinearGradient>
      </View>
    </TouchableOpacity>
  );
};

// Custom tab bar button for Post Task
const PostTaskTabButton = (props: any) => {
  return (
    <View style={styles.postTaskTabContainer}>
      <PostTaskButton />
    </View>
  );
};

export default function TabLayout() {
  const insets = useSafeAreaInsets();

  return (
    <View style={styles.container}>
      <Tabs
        screenOptions={{
          headerShown: false,
          tabBarShowLabel: false,
          tabBarStyle: {
            backgroundColor: '#FFFFFF',
            borderTopColor: Colors.semantic.divider,
            borderTopWidth: 1,
            height: 56 + insets.bottom,
            paddingBottom: insets.bottom,
            paddingTop: 4,
            position: 'absolute',
            bottom: 0,
            left: 0,
            right: 0,
            elevation: 12,
            shadowColor: '#000',
            shadowOffset: { width: 0, height: -4 },
            shadowOpacity: 0.08,
            shadowRadius: 16,
          },
          tabBarActiveTintColor: Colors.semantic.tabActive,
          tabBarInactiveTintColor: Colors.semantic.tabInactive,
        }}
      >
        <Tabs.Screen
          name="home"
          options={{
            tabBarLabel: '',
            tabBarAccessibilityLabel: 'Home',
            tabBarIcon: ({ size, color }) => (
              <Home size={24} color={color} strokeWidth={2} />
            ),
          }}
        />
        <Tabs.Screen
          name="tasks"
          options={{
            tabBarLabel: '',
            tabBarAccessibilityLabel: 'Tasks',
            tabBarIcon: ({ size, color, focused }) => (
              <List 
                size={24} 
                color={color} 
                strokeWidth={focused ? 2.5 : 2}
              />
            ),
          }}
        />
        <Tabs.Screen
          name="post"
          options={{
            tabBarLabel: '',
            tabBarAccessibilityLabel: 'Post Task',
            tabBarButton: PostTaskTabButton,
          }}
        />
        <Tabs.Screen
          name="chats"
          options={{
            tabBarLabel: '',
            tabBarAccessibilityLabel: 'Chats',
            tabBarIcon: ({ size, color }) => (
              <MessageCircle size={24} color={color} strokeWidth={2} />
            ),
          }}
        />
        <Tabs.Screen
          name="referrals"
          options={{
            tabBarLabel: '',
            tabBarAccessibilityLabel: 'Referrals',
            tabBarIcon: ({ size, color }) => (
              <Gift size={24} color={color} strokeWidth={2} />
            ),
          }}
        />
      </Tabs>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  postTaskTabContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingTop: 0,
    paddingBottom: 8,
  },
  postTaskButton: {
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
  },
  postTaskIconContainer: {
    width: 52,
    height: 52,
    borderRadius: 26,
    overflow: 'hidden',
    shadowColor: '#0021A5',
    shadowOffset: { width: 0, height: 6 },
    shadowOpacity: 0.25,
    shadowRadius: 12,
    elevation: 8,
  },
  postTaskGradient: {
    width: '100%',
    height: '100%',
    justifyContent: 'center',
    alignItems: 'center',
  },
});