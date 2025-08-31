import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity } from 'react-native';
import { useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { ArrowLeft, DollarSign, Gift, Star, Calendar, TrendingUp } from 'lucide-react-native';
import { Colors } from '@/theme/colors';

export default function CreditsScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  
  // Mock credits data
  const [availableCredits] = useState(500); // $5.00 in cents
  const [earnedCredits] = useState(1250); // $12.50 total earned
  const [expiringCredits] = useState(200); // $2.00 expiring soon

  const handleBack = () => {
    router.back();
  };

  const handleEarnMore = () => {
    router.push('/(tabs)/referrals');
  };

  const formatCurrency = (cents: number): string => {
    return `$${(cents / 100).toFixed(2)}`;
  };

  return (
    <View style={[styles.container, { paddingTop: insets.top }]}>
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity style={styles.backButton} onPress={handleBack}>
          <ArrowLeft size={24} color={Colors.white} strokeWidth={2} />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>Credits</Text>
        <View style={styles.placeholder} />
      </View>

      <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
        {/* Credits Balance Card */}
        <View style={styles.balanceCard}>
          <View style={styles.balanceHeader}>
            <DollarSign size={32} color={Colors.semantic.successAlert} strokeWidth={2} />
            <Text style={styles.balanceTitle}>Available Credits</Text>
          </View>
          <Text style={styles.balanceAmount}>
            {formatCurrency(availableCredits)}
          </Text>
          
          {expiringCredits > 0 && (
            <View style={styles.expiringContainer}>
              <Calendar size={16} color={Colors.semantic.errorAlert} strokeWidth={2} />
              <Text style={styles.expiringText}>
                {formatCurrency(expiringCredits)} expiring in 30 days
              </Text>
            </View>
          )}
        </View>

        {/* Stats Row */}
        <View style={styles.statsContainer}>
          <View style={styles.statCard}>
            <TrendingUp size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />
            <Text style={styles.statValue}>{formatCurrency(earnedCredits)}</Text>
            <Text style={styles.statLabel}>Total Earned</Text>
          </View>
          
          <View style={styles.statCard}>
            <Gift size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />
            <Text style={styles.statValue}>3</Text>
            <Text style={styles.statLabel}>Referrals</Text>
          </View>
          
          <View style={styles.statCard}>
            <Star size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />
            <Text style={styles.statValue}>4.8</Text>
            <Text style={styles.statLabel}>Rating</Text>
          </View>
        </View>

        {/* Earn More Button */}
        <TouchableOpacity style={styles.earnMoreButton} onPress={handleEarnMore}>
          <Gift size={20} color={Colors.white} strokeWidth={2} />
          <Text style={styles.earnMoreButtonText}>Earn More Credits</Text>
        </TouchableOpacity>

        {/* How to Earn */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>How to Earn Credits</Text>
          
          <View style={styles.earnMethodsList}>
            <View style={styles.earnMethod}>
              <View style={styles.earnMethodIcon}>
                <Gift size={20} color={Colors.primary} strokeWidth={2} />
              </View>
              <View style={styles.earnMethodContent}>
                <Text style={styles.earnMethodTitle}>Refer Friends</Text>
                <Text style={styles.earnMethodDescription}>
                  Get $10 for every friend who completes their first task
                </Text>
              </View>
              <Text style={styles.earnMethodAmount}>$10</Text>
            </View>
            
            <View style={styles.earnMethod}>
              <View style={styles.earnMethodIcon}>
                <Star size={20} color={Colors.primary} strokeWidth={2} />
              </View>
              <View style={styles.earnMethodContent}>
                <Text style={styles.earnMethodTitle}>Complete Tasks</Text>
                <Text style={styles.earnMethodDescription}>
                  Earn credits for helping other students
                </Text>
              </View>
              <Text style={styles.earnMethodAmount}>Varies</Text>
            </View>
          </View>
        </View>

        {/* Recent Credits Activity */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Recent Activity</Text>
          
          <View style={styles.activityList}>
            <View style={styles.activityItem}>
              <View style={styles.activityIcon}>
                <Gift size={16} color={Colors.semantic.successAlert} strokeWidth={2} />
              </View>
              <View style={styles.activityContent}>
                <Text style={styles.activityTitle}>Referral Bonus</Text>
                <Text style={styles.activityDate}>2 days ago</Text>
              </View>
              <Text style={styles.activityAmount}>+{formatCurrency(1000)}</Text>
            </View>
            
            <View style={styles.activityItem}>
              <View style={styles.activityIcon}>
                <Star size={16} color={Colors.semantic.successAlert} strokeWidth={2} />
              </View>
              <View style={styles.activityContent}>
                <Text style={styles.activityTitle}>Task Completion</Text>
                <Text style={styles.activityDate}>1 week ago</Text>
              </View>
              <Text style={styles.activityAmount}>+{formatCurrency(250)}</Text>
            </View>
          </View>
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
    paddingTop: 20,
  },
  balanceCard: {
    backgroundColor: Colors.semantic.card,
    borderRadius: 24,
    padding: 24,
    marginBottom: 24,
    alignItems: 'center',
    gap: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.08,
    shadowRadius: 20,
    elevation: 8,
    borderWidth: 1,
    borderColor: 'rgba(229, 231, 235, 0.5)',
  },
  balanceHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  balanceTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: Colors.semantic.bodyText,
  },
  balanceAmount: {
    fontSize: 36,
    fontWeight: '700',
    color: Colors.semantic.successAlert,
  },
  expiringContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: Colors.semantic.errorAlert + '20',
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 6,
  },
  expiringText: {
    fontSize: 14,
    fontWeight: '600',
    color: Colors.semantic.errorAlert,
  },
  statsContainer: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 24,
  },
  statCard: {
    flex: 1,
    backgroundColor: Colors.semantic.card,
    borderRadius: 16,
    padding: 16,
    alignItems: 'center',
    gap: 8,
    borderWidth: 1,
    borderColor: 'rgba(229, 231, 235, 0.5)',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.04,
    shadowRadius: 12,
    elevation: 2,
  },
  statValue: {
    fontSize: 18,
    fontWeight: '700',
    color: Colors.semantic.bodyText,
  },
  statLabel: {
    fontSize: 12,
    color: Colors.semantic.tabInactive,
    textAlign: 'center',
  },
  earnMoreButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.primary,
    borderRadius: 16,
    paddingVertical: 16,
    marginBottom: 32,
    gap: 8,
    shadowColor: Colors.primary,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.2,
    shadowRadius: 8,
    elevation: 6,
  },
  earnMoreButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.white,
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
  earnMethodsList: {
    gap: 12,
  },
  earnMethod: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.semantic.card,
    borderRadius: 16,
    padding: 16,
    borderWidth: 1,
    borderColor: Colors.semantic.cardBorder,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.05,
    shadowRadius: 8,
    elevation: 2,
  },
  earnMethodIcon: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: Colors.muted,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  earnMethodContent: {
    flex: 1,
  },
  earnMethodTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.semantic.bodyText,
    marginBottom: 2,
  },
  earnMethodDescription: {
    fontSize: 14,
    color: Colors.semantic.tabInactive,
    lineHeight: 20,
  },
  earnMethodAmount: {
    fontSize: 16,
    fontWeight: '700',
    color: Colors.semantic.successAlert,
  },
  activityList: {
    gap: 12,
  },
  activityItem: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.semantic.card,
    borderRadius: 16,
    padding: 16,
    borderWidth: 1,
    borderColor: Colors.semantic.cardBorder,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.05,
    shadowRadius: 8,
    elevation: 2,
  },
  activityIcon: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: Colors.muted,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  activityContent: {
    flex: 1,
  },
  activityTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: Colors.semantic.bodyText,
    marginBottom: 2,
  },
  activityDate: {
    fontSize: 12,
    color: Colors.semantic.tabInactive,
  },
  activityAmount: {
    fontSize: 14,
    fontWeight: '700',
    color: Colors.semantic.successAlert,
  },
});