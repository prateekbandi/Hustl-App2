import React from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Image, Platform, Dimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Car, Coffee, Dumbbell, BookOpen, Pizza, Plus, ShoppingCart, Package, Gamepad2, Music, Camera, Wrench, Heart, Briefcase, GraduationCap, Utensils } from 'lucide-react-native';
import * as Haptics from 'expo-haptics';
import { useState } from 'react';
import Animated, { 
  useSharedValue, 
  useAnimatedStyle, 
  withRepeat, 
  withTiming, 
  withSequence,
  interpolate,
  withDelay,
  withSpring,
  Easing
} from 'react-native-reanimated';
import { ActivityIndicator } from 'react-native';
import { ChevronRight } from 'lucide-react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { Colors } from '@/theme/colors';
import GlobalHeader from '@components/GlobalHeader';

const { width, height } = Dimensions.get('window');

const categories = [
  {
    id: 'food',
    title: 'Food Delivery',
    subtitle: 'Quick pickup & delivery',
    icon: <Utensils size={28} color="#FFFFFF" strokeWidth={2.5} />,
    image: 'https://images.pexels.com/photos/1640777/pexels-photo-1640777.jpeg?auto=compress&cs=tinysrgb&w=400',
    gradient: ['#FF6B6B', '#FF8E53'],
    popular: true,
  },
  {
    id: 'coffee',
    title: 'Coffee Runs',
    subtitle: 'Fresh coffee delivered',
    icon: <Coffee size={28} color="#FFFFFF" strokeWidth={2.5} />,
    image: 'https://images.pexels.com/photos/302899/pexels-photo-302899.jpeg?auto=compress&cs=tinysrgb&w=400',
    gradient: ['#8B4513', '#D2691E'],
    popular: true,
  },
  {
    id: 'grocery',
    title: 'Grocery Shopping',
    subtitle: 'Essential items pickup',
    icon: <ShoppingCart size={28} color="#FFFFFF" strokeWidth={2.5} />,
    image: 'https://images.pexels.com/photos/264636/pexels-photo-264636.jpeg?auto=compress&cs=tinysrgb&w=400',
    gradient: ['#4ECDC4', '#44A08D'],
  },
  {
    id: 'car',
    title: 'Ride Share',
    subtitle: 'Campus transportation',
    icon: <Car size={28} color="#FFFFFF" strokeWidth={2.5} />,
    image: 'https://images.pexels.com/photos/116675/pexels-photo-116675.jpeg?auto=compress&cs=tinysrgb&w=400',
    gradient: ['#667eea', '#764ba2'],
  },
  {
    id: 'workout',
    title: 'Workout Partner',
    subtitle: 'Gym & fitness buddy',
    icon: <Dumbbell size={28} color="#FFFFFF" strokeWidth={2.5} />,
    image: 'https://images.pexels.com/photos/1552242/pexels-photo-1552242.jpeg?auto=compress&cs=tinysrgb&w=400',
    gradient: ['#FF9A9E', '#FECFEF'],
  },
  {
    id: 'study',
    title: 'Study Partner',
    subtitle: 'Academic collaboration',
    icon: <BookOpen size={28} color="#FFFFFF" strokeWidth={2.5} />,
    image: 'https://images.pexels.com/photos/159711/books-bookstore-book-reading-159711.jpeg?auto=compress&cs=tinysrgb&w=400',
    gradient: ['#A8EDEA', '#FED6E3'],
  },
  {
    id: 'package',
    title: 'Package Pickup',
    subtitle: 'Mail & deliveries',
    icon: <Package size={28} color="#FFFFFF" strokeWidth={2.5} />,
    image: 'https://images.pexels.com/photos/4246120/pexels-photo-4246120.jpeg?auto=compress&cs=tinysrgb&w=400',
    gradient: ['#FFA726', '#FB8C00'],
  },
  {
    id: 'tutoring',
    title: 'Tutoring',
    subtitle: 'Academic help',
    icon: <GraduationCap size={28} color="#FFFFFF" strokeWidth={2.5} />,
    image: 'https://images.pexels.com/photos/5212345/pexels-photo-5212345.jpeg?auto=compress&cs=tinysrgb&w=400',
    gradient: ['#667eea', '#764ba2'],
  },
  {
    id: 'gaming',
    title: 'Gaming Partner',
    subtitle: 'Play together',
    icon: <Gamepad2 size={28} color="#FFFFFF" strokeWidth={2.5} />,
    image: 'https://images.pexels.com/photos/442576/pexels-photo-442576.jpeg?auto=compress&cs=tinysrgb&w=400',
    gradient: ['#667eea', '#764ba2'],
  },
  {
    id: 'music',
    title: 'Music Events',
    subtitle: 'Concerts & shows',
    icon: <Music size={28} color="#FFFFFF" strokeWidth={2.5} />,
    image: 'https://images.pexels.com/photos/1105666/pexels-photo-1105666.jpeg?auto=compress&cs=tinysrgb&w=400',
    gradient: ['#667eea', '#764ba2'],
  },
  {
    id: 'photography',
    title: 'Photography',
    subtitle: 'Photo sessions',
    icon: <Camera size={28} color="#FFFFFF" strokeWidth={2.5} />,
    image: 'https://images.pexels.com/photos/90946/pexels-photo-90946.jpeg?auto=compress&cs=tinysrgb&w=400',
    gradient: ['#667eea', '#764ba2'],
  },
  {
    id: 'repair',
    title: 'Tech Repair',
    subtitle: 'Device fixes',
    icon: <Wrench size={28} color="#FFFFFF" strokeWidth={2.5} />,
    image: 'https://images.pexels.com/photos/3184291/pexels-photo-3184291.jpeg?auto=compress&cs=tinysrgb&w=400',
    gradient: ['#667eea', '#764ba2'],
  },
];

// Floating Particles Component for subtle depth
const FloatingParticles = () => {
  const particles = Array.from({ length: 12 }, (_, i) => {
    const translateY = useSharedValue(height + 50);
    const translateX = useSharedValue(Math.random() * width);
    const opacity = useSharedValue(0);
    const scale = useSharedValue(0.2 + Math.random() * 0.3);
    const rotation = useSharedValue(0);

    React.useEffect(() => {
      const startAnimation = () => {
        const delay = i * 800 + Math.random() * 2000;
        const duration = 15000 + Math.random() * 8000;
        
        translateY.value = withDelay(
          delay,
          withRepeat(
            withTiming(-150, { duration, easing: Easing.linear }),
            -1,
            false
          )
        );
        
        opacity.value = withDelay(
          delay,
          withRepeat(
            withSequence(
              withTiming(0.06 + Math.random() * 0.08, { duration: duration * 0.1 }),
              withTiming(0.06 + Math.random() * 0.08, { duration: duration * 0.8 }),
              withTiming(0, { duration: duration * 0.1 })
            ),
            -1,
            false
          )
        );

        rotation.value = withDelay(
          delay,
          withRepeat(
            withTiming(360, { duration: duration * 0.8, easing: Easing.linear }),
            -1,
            false
          )
        );
      };

      startAnimation();
    }, []);

    const animatedStyle = useAnimatedStyle(() => ({
      transform: [
        { translateX: translateX.value },
        { translateY: translateY.value },
        { scale: scale.value },
        { rotate: `${rotation.value}deg` }
      ],
      opacity: opacity.value,
    }));

    const particleColor = i % 3 === 0 ? '#0021A5' : i % 3 === 1 ? '#FA4616' : '#FFD700';

    return (
      <Animated.View
        key={i}
        style={[
          styles.particle,
          {
            width: 8 + Math.random() * 16,
            height: 8 + Math.random() * 16,
            backgroundColor: particleColor,
          },
          animatedStyle
        ]}
      />
    );
  });

  return (
    <View style={styles.particlesContainer}>
      {particles}
    </View>
  );
};

// Enhanced Referral Banner with Premium Design
const AnimatedReferralsBanner = () => {
  const router = useRouter();
  const glowAnimation = useSharedValue(0);
  const pulseAnimation = useSharedValue(1);
  const shimmerAnimation = useSharedValue(-1);
  const haloAnimation = useSharedValue(0);

  React.useEffect(() => {
    // Glow animation
    glowAnimation.value = withRepeat(
      withSequence(
        withTiming(1, { duration: 3500 }),
        withTiming(0, { duration: 3500 })
      ),
      -1,
      true
    );

    // Pulse animation for button
    pulseAnimation.value = withRepeat(
      withSequence(
        withTiming(1.03, { duration: 2000 }),
        withTiming(1, { duration: 2000 })
      ),
      -1,
      true
    );

    // Shimmer animation
    shimmerAnimation.value = withRepeat(
      withTiming(1, { duration: 4000, easing: Easing.linear }),
      -1,
      false
    );

    // Halo animation
    haloAnimation.value = withRepeat(
      withSequence(
        withTiming(1, { duration: 4000 }),
        withTiming(0, { duration: 4000 })
      ),
      -1,
      true
    );
  }, []);

  const animatedGlowStyle = useAnimatedStyle(() => {
    const shadowOpacity = interpolate(glowAnimation.value, [0, 1], [0.15, 0.35]);
    return {
      shadowOpacity,
    };
  });

  const animatedPulseStyle = useAnimatedStyle(() => ({
    transform: [{ scale: pulseAnimation.value }],
  }));

  const animatedShimmerStyle = useAnimatedStyle(() => {
    const translateX = interpolate(shimmerAnimation.value, [0, 1], [-150, 400]);
    return {
      transform: [{ translateX }],
    };
  });

  const animatedHaloStyle = useAnimatedStyle(() => {
    const opacity = interpolate(haloAnimation.value, [0, 1], [0.1, 0.3]);
    const scale = interpolate(haloAnimation.value, [0, 1], [1, 1.1]);
    return {
      opacity,
      transform: [{ scale }],
    };
  });

  const handleInvitePress = () => {
    if (Platform.OS !== 'web') {
      try {
        Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
      } catch (error) {
        // Haptics not available, continue silently
      }
    }
    router.push('/(tabs)/referrals');
  };

  const handleBannerPress = () => {
    if (Platform.OS !== 'web') {
      try {
        Haptics.selectionAsync();
      } catch (error) {
        // Haptics not available, continue silently
      }
    }
    router.push('/(tabs)/referrals');
  };

  return (
    <View style={styles.referralContainer}>
      <Animated.View style={[styles.referralHalo, animatedHaloStyle]} />
      <Animated.View style={[styles.referralCard, animatedGlowStyle]}>
        <TouchableOpacity onPress={handleBannerPress} activeOpacity={0.95}>
          <LinearGradient
            colors={['#0047FF', '#0021A5', '#FA4616']}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 1 }}
            locations={[0, 0.6, 1]}
            style={styles.referralGradient}
          >
            <View style={styles.referralContent}>
              <View style={styles.referralTextContainer}>
                <Text style={styles.referralTitle}>Get $10 for every referral!</Text>
                <Text style={styles.referralSubtitle}>
                  Invite friends and earn credits when they complete their first task.
                </Text>
              </View>
              
              <Animated.View style={animatedPulseStyle}>
                <TouchableOpacity 
                  style={styles.inviteButton} 
                  onPress={handleInvitePress}
                  activeOpacity={0.8}
                >
                  <Animated.View style={[styles.shimmerOverlay, animatedShimmerStyle]} />
                  <Text style={styles.inviteButtonText}>Invite</Text>
                </TouchableOpacity>
              </Animated.View>
            </View>
          </LinearGradient>
        </TouchableOpacity>
      </Animated.View>
    </View>
  );
};

// Enhanced Category Card with Professional Design
const CategoryCard = ({ 
  category, 
  index, 
  onSelectTask,
  isSelecting 
}: { 
  category: any; 
  index: number; 
  onSelectTask: () => void;
  isSelecting: boolean;
}) => {
  const scaleAnimation = useSharedValue(0.85);
  const opacityAnimation = useSharedValue(0);
  const translateY = useSharedValue(40);
  const shadowAnimation = useSharedValue(0);
  const haloAnimation = useSharedValue(0);

  // Staggered entrance animation
  React.useEffect(() => {
    const delay = index * 120;
    
    opacityAnimation.value = withDelay(delay, withTiming(1, { duration: 800 }));
    scaleAnimation.value = withDelay(delay, withSpring(1, { damping: 18, stiffness: 280 }));
    translateY.value = withDelay(delay, withSpring(0, { damping: 18, stiffness: 280 }));
    shadowAnimation.value = withDelay(delay, withTiming(1, { duration: 800 }));
    
    // Subtle halo for popular items
    if (category.popular) {
      haloAnimation.value = withDelay(
        delay + 500,
        withRepeat(
          withSequence(
            withTiming(1, { duration: 2500 }),
            withTiming(0, { duration: 2500 })
          ),
          -1,
          true
        )
      );
    }
  }, [index]);

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [
      { scale: scaleAnimation.value },
      { translateY: translateY.value }
    ],
    opacity: opacityAnimation.value,
  }));

  const animatedShadowStyle = useAnimatedStyle(() => {
    const shadowOpacity = interpolate(shadowAnimation.value, [0, 1], [0, 0.12]);
    return {
      shadowOpacity,
    };
  });

  const animatedHaloStyle = useAnimatedStyle(() => {
    const opacity = interpolate(haloAnimation.value, [0, 1], [0, 0.15]);
    const scale = interpolate(haloAnimation.value, [0, 1], [1, 1.05]);
    return {
      opacity,
      transform: [{ scale }],
    };
  });

  return (
    <View style={styles.categoryCardContainer}>
      {category.popular && (
        <Animated.View style={[styles.categoryHalo, animatedHaloStyle]} />
      )}
      <Animated.View style={[styles.categoryCard, animatedStyle, animatedShadowStyle]}>
        {/* Popular Badge */}
        {category.popular && (
          <View style={styles.popularBadge}>
            <Text style={styles.popularText}>Popular</Text>
          </View>
        )}

        {/* Image Section with Gradient Overlay */}
        <View style={styles.imageContainer}>
          <Image
            source={{ uri: category.image }}
            style={styles.categoryImage}
            resizeMode="cover"
          />
          <LinearGradient
            colors={['rgba(0,0,0,0.1)', 'rgba(0,0,0,0.6)']}
            style={styles.categoryOverlay}
          />
          
          {/* Icon with Gradient Background */}
          <View style={styles.iconContainer}>
            <LinearGradient
              colors={category.gradient}
              style={styles.iconGradient}
            >
              {category.icon}
            </LinearGradient>
          </View>
        </View>
        
        {/* Content Section */}
        <View style={styles.categoryContent}>
          <Text style={styles.categoryTitle} numberOfLines={1}>
            {category.title}
          </Text>
          <Text style={styles.categorySubtitle} numberOfLines={1}>
            {category.subtitle}
          </Text>
        </View>
        
        {/* Footer with Enhanced Select Button */}
        <View style={styles.categoryFooter}>
          <TouchableOpacity
            style={[
              styles.selectTaskButton,
              isSelecting && styles.selectTaskButtonDisabled
            ]}
            onPress={onSelectTask}
            disabled={isSelecting}
            activeOpacity={0.8}
            accessibilityLabel={`Select ${category.title} task`}
            accessibilityRole="button"
          >
            <LinearGradient
              colors={isSelecting ? ['#9CA3AF', '#9CA3AF'] : ['#0047FF', '#0021A5']}
              start={{ x: 0, y: 0.5 }}
              end={{ x: 1, y: 0.5 }}
              style={styles.selectTaskGradient}
            >
              {isSelecting ? (
                <ActivityIndicator size="small" color={Colors.white} />
              ) : (
                <>
                  <Text style={styles.selectTaskText}>Select</Text>
                  <ChevronRight size={16} color={Colors.white} strokeWidth={2.5} />
                </>
              )}
            </LinearGradient>
          </TouchableOpacity>
        </View>
      </Animated.View>
    </View>
  );
};

// Animated Background Component
const AnimatedBackground = () => {
  const gradientAnimation = useSharedValue(0);
  const waveAnimation = useSharedValue(0);

  React.useEffect(() => {
    gradientAnimation.value = withRepeat(
      withTiming(1, { duration: 8000, easing: Easing.inOut(Easing.sin) }),
      -1,
      true
    );

    waveAnimation.value = withRepeat(
      withTiming(1, { duration: 12000, easing: Easing.linear }),
      -1,
      false
    );
  }, []);

  const animatedGradientStyle = useAnimatedStyle(() => {
    const opacity = interpolate(gradientAnimation.value, [0, 1], [0.02, 0.06]);
    return { opacity };
  });

  const animatedWaveStyle = useAnimatedStyle(() => {
    const translateX = interpolate(waveAnimation.value, [0, 1], [0, width]);
    return {
      transform: [{ translateX }],
    };
  });

  return (
    <View style={styles.backgroundContainer}>
      <Animated.View style={[styles.gradientBackground, animatedGradientStyle]}>
        <LinearGradient
          colors={['#0021A5', '#FA4616', '#FFD700']}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 1 }}
          style={StyleSheet.absoluteFill}
        />
      </Animated.View>
      
      <Animated.View style={[styles.wavePattern, animatedWaveStyle]} />
    </View>
  );
};

export default function HomeScreen() {
  const router = useRouter();
  const [selectingTaskId, setSelectingTaskId] = useState<string | null>(null);

  const handleSelectTask = async (categoryId: string) => {
    if (selectingTaskId) return;
    
    // Log analytics
    console.log('home_select_task_clicked', { taskId: categoryId, category: categoryId });
    
    setSelectingTaskId(categoryId);
    
    // Haptics feedback
    if (Platform.OS !== 'web') {
      try {
        Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
      } catch (error) {
        // Haptics not available, continue silently
      }
    }
    
    // Simulate task selection process
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // Navigate to Post Task with category prefill
    router.push({
      pathname: '/(tabs)/post',
      params: { category: categoryId }
    });
    
    setSelectingTaskId(null);
  };

  return (
    <View style={styles.container}>
      {/* Animated Background */}
      <AnimatedBackground />
      
      {/* Subtle Floating Particles */}
      <FloatingParticles />
      
      <GlobalHeader />

      <ScrollView 
        style={styles.content} 
        showsVerticalScrollIndicator={false}
        bounces={true}
        contentContainerStyle={styles.scrollContent}
      >
        {/* Enhanced Referral Banner */}
        <AnimatedReferralsBanner />

        {/* Task Categories Section */}
        <View style={styles.categoriesSection}>
          <View style={styles.categoriesHeader}>
            <Text style={styles.categoriesTitle}>Task Categories</Text>
            <Text style={styles.categoriesSubtitle}>Choose what you need help with</Text>
          </View>
          
          <View style={styles.categoriesGrid}>
            {categories.map((category, index) => (
              <CategoryCard
                key={category.id}
                category={category}
                index={index}
                onSelectTask={() => handleSelectTask(category.id)}
                isSelecting={selectingTaskId === category.id}
              />
            ))}
          </View>
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#FFFFFF',
    position: 'relative',
  },
  backgroundContainer: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    zIndex: 0,
  },
  gradientBackground: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
  },
  wavePattern: {
    position: 'absolute',
    top: height * 0.3,
    left: -width,
    width: width * 2,
    height: 200,
    backgroundColor: 'rgba(0, 33, 165, 0.03)',
    borderRadius: width,
  },
  particlesContainer: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    pointerEvents: 'none',
    zIndex: 1,
  },
  particle: {
    position: 'absolute',
    borderRadius: 50,
    opacity: 0.1,
  },
  content: {
    flex: 1,
    zIndex: 2,
  },
  scrollContent: {
    paddingBottom: 140, // Extra space for tab bar
  },
  
  // Enhanced Referral Section
  referralContainer: {
    marginHorizontal: 20,
    marginTop: 16,
    marginBottom: 40,
    position: 'relative',
  },
  referralHalo: {
    position: 'absolute',
    top: -8,
    left: -8,
    right: -8,
    bottom: -8,
    borderRadius: 28,
    backgroundColor: '#0047FF',
    zIndex: 0,
  },
  referralCard: {
    borderRadius: 20,
    shadowColor: '#0047FF',
    shadowOffset: { width: 0, height: 16 },
    shadowOpacity: 0.25,
    shadowRadius: 24,
    elevation: 20,
    overflow: 'hidden',
    zIndex: 1,
  },
  referralGradient: {
    borderRadius: 20,
  },
  referralContent: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 28,
    gap: 24,
  },
  referralTextContainer: {
    flex: 1,
    gap: 10,
  },
  referralTitle: {
    fontSize: 22,
    fontWeight: '700',
    color: '#FFFFFF',
    lineHeight: 26,
    textShadowColor: 'rgba(0, 0, 0, 0.4)',
    textShadowOffset: { width: 0, height: 2 },
    textShadowRadius: 4,
  },
  referralSubtitle: {
    fontSize: 15,
    color: '#F1F5F9',
    lineHeight: 22,
    opacity: 0.95,
  },
  inviteButton: {
    backgroundColor: '#FA4616',
    borderRadius: 28,
    paddingHorizontal: 28,
    paddingVertical: 14,
    minHeight: 56,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#FA4616',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.5,
    shadowRadius: 16,
    elevation: 12,
    position: 'relative',
    overflow: 'hidden',
  },
  shimmerOverlay: {
    position: 'absolute',
    top: 0,
    left: -150,
    width: 150,
    height: '100%',
    backgroundColor: 'rgba(255, 255, 255, 0.4)',
    transform: [{ skewX: '-25deg' }],
  },
  inviteButtonText: {
    fontSize: 17,
    fontWeight: '700',
    color: '#FFFFFF',
    textShadowColor: 'rgba(0, 0, 0, 0.3)',
    textShadowOffset: { width: 0, height: 1 },
    textShadowRadius: 2,
    letterSpacing: 0.5,
  },

  // Categories Section
  categoriesSection: {
    paddingHorizontal: 20,
    zIndex: 3,
  },
  categoriesHeader: {
    marginBottom: 32,
    alignItems: 'center',
    gap: 8,
  },
  categoriesTitle: {
    fontSize: 32,
    fontWeight: '700',
    color: '#111827',
    letterSpacing: 0.5,
    textAlign: 'center',
  },
  categoriesSubtitle: {
    fontSize: 17,
    color: '#6B7280',
    textAlign: 'center',
  },
  categoriesGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'space-between',
    gap: 16,
  },
  
  // Enhanced Category Cards
  categoryCardContainer: {
    width: '48%',
    position: 'relative',
  },
  categoryHalo: {
    position: 'absolute',
    top: -4,
    left: -4,
    right: -4,
    bottom: -4,
    borderRadius: 24,
    backgroundColor: '#FFD700',
    zIndex: 0,
  },
  categoryCard: {
    height: 280,
    marginBottom: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 12 },
    shadowOpacity: 0.12,
    shadowRadius: 20,
    elevation: 12,
    borderRadius: 20,
    overflow: 'hidden',
    backgroundColor: Colors.white,
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.8)',
    zIndex: 1,
  },
  popularBadge: {
    position: 'absolute',
    top: 12,
    left: 12,
    backgroundColor: '#FFD700',
    borderRadius: 12,
    paddingHorizontal: 8,
    paddingVertical: 4,
    zIndex: 10,
    shadowColor: '#FFD700',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.3,
    shadowRadius: 4,
    elevation: 4,
  },
  popularText: {
    fontSize: 11,
    fontWeight: '700',
    color: '#FFFFFF',
    textShadowColor: 'rgba(0, 0, 0, 0.3)',
    textShadowOffset: { width: 0, height: 1 },
    textShadowRadius: 2,
  },
  imageContainer: {
    height: 140,
    position: 'relative',
  },
  categoryImage: {
    width: '100%',
    height: '100%',
  },
  categoryOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
  },
  iconContainer: {
    position: 'absolute',
    top: 16,
    right: 16,
    width: 56,
    height: 56,
    borderRadius: 28,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 6,
  },
  iconGradient: {
    width: '100%',
    height: '100%',
    justifyContent: 'center',
    alignItems: 'center',
  },
  categoryContent: {
    flex: 1,
    padding: 16,
    justifyContent: 'center',
    gap: 4,
  },
  categoryTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: '#111827',
    lineHeight: 22,
  },
  categorySubtitle: {
    fontSize: 14,
    color: '#6B7280',
    fontWeight: '500',
  },
  categoryFooter: {
    paddingHorizontal: 16,
    paddingBottom: 16,
  },
  selectTaskButton: {
    height: 44,
    borderRadius: 12,
    overflow: 'hidden',
    shadowColor: '#0047FF',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.2,
    shadowRadius: 8,
    elevation: 6,
  },
  selectTaskButtonDisabled: {
    shadowOpacity: 0,
    elevation: 0,
  },
  selectTaskGradient: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 16,
    gap: 8,
  },
  selectTaskText: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.white,
    letterSpacing: 0.3,
  },
});