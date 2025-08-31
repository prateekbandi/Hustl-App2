import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity } from 'react-native';
import { useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { ArrowLeft, CreditCard, DollarSign, Plus, History, TrendingUp } from 'lucide-react-native';
import { Colors } from '@/theme/colors';

export default function WalletScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  
  // Mock wallet data
  const [balance] = useState(1250); // $12.50 in cents
  const [pendingEarnings] = useState(500); // $5.00 in cents

  const handleBack = () => {
    router.back();
  };

  const handleAddFunds = () => {
    console.log('Add funds pressed');
  };

  const handleViewHistory = () => {
    console.log('View history pressed');
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
        <Text style={styles.headerTitle}>Wallet</Text>
        <View style={styles.placeholder} />
      </View>

      <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
        {/* Balance Card */}
        <View style={styles.balanceCard}>
          <View style={styles.balanceHeader}>
            <CreditCard size={32} color={Colors.primary} strokeWidth={2} />
            <Text style={styles.balanceTitle}>Available Balance</Text>
          </View>
          <Text style={styles.balanceAmount}>
            {formatCurrency(balance)}
          </Text>
          
          {pendingEarnings > 0 && (
            <View style={styles.pendingContainer}>
              <TrendingUp size={16} color={Colors.semantic.successAlert} strokeWidth={2} />
              <Text style={styles.pendingText}>
                {formatCurrency(pendingEarnings)} pending
              </Text>
            </View>
          )}
        </View>

        {/* Quick Actions */}
        <View style={styles.actionsContainer}>
          <TouchableOpacity style={styles.actionButton} onPress={handleAddFunds}>
            <Plus size={20} color={Colors.primary} strokeWidth={2} />
            <Text style={styles.actionButtonText}>Add Funds</Text>
          </TouchableOpacity>
          
          <TouchableOpacity style={styles.actionButton} onPress={handleViewHistory}>
            <History size={20} color={Colors.primary} strokeWidth={2} />
            <Text style={styles.actionButtonText}>Transaction History</Text>
          </TouchableOpacity>
        </View>

        {/* Recent Transactions */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Recent Transactions</Text>
          
          <View style={styles.transactionsList}>
            <View style={styles.transactionItem}>
              <View style={styles.transactionIcon}>
                <DollarSign size={16} color={Colors.semantic.successAlert} strokeWidth={2} />
              </View>
              <View style={styles.transactionContent}>
                <Text style={styles.transactionTitle}>Task Completed</Text>
                <Text style={styles.transactionDate}>2 hours ago</Text>
              </View>
              <Text style={styles.transactionAmount}>+$3.50</Text>
            </View>
            
            <View style={styles.transactionItem}>
              <View style={styles.transactionIcon}>
                <DollarSign size={16} color={Colors.semantic.errorAlert} strokeWidth={2} />
              </View>
              <View style={styles.transactionContent}>
                <Text style={styles.transactionTitle}>Food Order</Text>
                <Text style={styles.transactionDate}>Yesterday</Text>
              </View>
              <Text style={styles.transactionAmount}>-$8.75</Text>
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
    color: Colors.primary,
  },
  pendingContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: Colors.semantic.successAlert + '20',
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 6,
  },
  pendingText: {
    fontSize: 14,
    fontWeight: '600',
    color: Colors.semantic.successAlert,
  },
  actionsContainer: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 32,
  },
  actionButton: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'transparent',
    borderWidth: 1,
    borderColor: Colors.primary,
    borderRadius: 16,
    paddingVertical: 16,
    gap: 8,
  },
  actionButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.primary,
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
  transactionsList: {
    gap: 12,
  },
  transactionItem: {
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
  transactionIcon: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: Colors.muted,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  transactionContent: {
    flex: 1,
  },
  transactionTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.semantic.bodyText,
    marginBottom: 2,
  },
  transactionDate: {
    fontSize: 14,
    color: Colors.semantic.tabInactive,
  },
  transactionAmount: {
    fontSize: 16,
    fontWeight: '700',
    color: Colors.semantic.bodyText,
  },
});