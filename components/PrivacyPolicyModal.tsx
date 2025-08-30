import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Modal, ScrollView, Dimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { X } from 'lucide-react-native';
import { Colors } from '@/theme/colors';

const { height } = Dimensions.get('window');

interface PrivacyPolicyModalProps {
  visible: boolean;
  onClose: () => void;
}

export default function PrivacyPolicyModal({ visible, onClose }: PrivacyPolicyModalProps) {
  const insets = useSafeAreaInsets();

  const getCurrentDate = (): string => {
    return new Date().toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric'
    });
  };

  return (
    <Modal
      visible={visible}
      transparent
      animationType="slide"
      onRequestClose={onClose}
    >
      <View style={styles.overlay}>
        <View style={[styles.modal, { paddingTop: insets.top + 20, paddingBottom: insets.bottom + 20 }]}>
          <View style={styles.header}>
            <Text style={styles.headerTitle}>Privacy Policy</Text>
            <TouchableOpacity style={styles.closeButton} onPress={onClose}>
              <X size={24} color={Colors.semantic.tabInactive} strokeWidth={2} />
            </TouchableOpacity>
          </View>

          <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
            <Text style={styles.title}>Hustl Privacy Policy</Text>
            <Text style={styles.effectiveDate}>Effective Date: {getCurrentDate()}</Text>
            
            <Text style={styles.paragraph}>
              At Hustl ("we," "our," or "us"), your privacy matters. As a student-led marketplace at the University of Florida ("UF"), we are committed to protecting the personal information of students using our platform. This Privacy Policy explains what information we collect, how we use it, and your rights regarding your data. By using Hustl, you agree to these practices.
            </Text>

            <Text style={styles.sectionTitle}>1. Information We Collect</Text>
            
            <Text style={styles.subsectionTitle}>Account Information</Text>
            <Text style={styles.paragraph}>When creating your account, we may collect:</Text>
            <Text style={styles.bulletPoint}>• Name, UF email, student ID, and phone number</Text>
            <Text style={styles.bulletPoint}>• Profile picture and optional profile details</Text>

            <Text style={styles.subsectionTitle}>Task & Transaction Data</Text>
            <Text style={styles.bulletPoint}>• Task postings, requests, or completions</Text>
            <Text style={styles.bulletPoint}>• Payment amounts, reimbursements, and proof of purchase</Text>
            <Text style={styles.bulletPoint}>• Messages and communication with other users</Text>

            <Text style={styles.subsectionTitle}>Device & Usage Data</Text>
            <Text style={styles.bulletPoint}>• IP address, device type, browser information</Text>
            <Text style={styles.bulletPoint}>• Platform activity (tasks viewed, clicks, session duration)</Text>

            <Text style={styles.sectionTitle}>2. How We Use Your Information</Text>
            <Text style={styles.paragraph}>We use your information to:</Text>
            <Text style={styles.bulletPoint}>• Provide, operate, and improve Hustl services</Text>
            <Text style={styles.bulletPoint}>• Facilitate peer-to-peer transactions (payments, reimbursements)</Text>
            <Text style={styles.bulletPoint}>• Verify student eligibility and prevent fraud or abuse</Text>
            <Text style={styles.bulletPoint}>• Communicate platform updates, security alerts, and notifications</Text>
            <Text style={styles.bulletPoint}>• Analyze trends to improve user experience</Text>
            <Text style={styles.bulletPoint}>• Enforce our Terms of Service and maintain a safe community</Text>

            <Text style={styles.sectionTitle}>3. Sharing Your Information</Text>
            
            <Text style={styles.subsectionTitle}>With Other Users</Text>
            <Text style={styles.paragraph}>
              Task-related information (name, profile, task details) is shared with other students to complete transactions.
            </Text>

            <Text style={styles.subsectionTitle}>With Service Providers</Text>
            <Text style={styles.paragraph}>
              We may share information with trusted third-party services, such as payment processors, cloud storage, or analytics providers.
            </Text>

            <Text style={styles.subsectionTitle}>Legal Compliance</Text>
            <Text style={styles.paragraph}>
              We may disclose your information if required by law, to prevent fraud, or to enforce our Terms of Service.
            </Text>

            <Text style={styles.highlight}>
              ❌ We do NOT sell your personal information to advertisers or third parties.
            </Text>

            <Text style={styles.sectionTitle}>4. Data Security</Text>
            <Text style={styles.paragraph}>
              We implement reasonable safeguards to protect your information. However, no method of transmission over the internet is completely secure. By using Hustl, you accept the inherent risks and agree to notify us of any suspected breaches.
            </Text>

            <Text style={styles.sectionTitle}>5. Data Retention</Text>
            <Text style={styles.bulletPoint}>• We retain your information while your account is active or as needed to provide services.</Text>
            <Text style={styles.bulletPoint}>• Some data may be retained for legal or compliance reasons even after account deletion.</Text>

            <Text style={styles.sectionTitle}>6. Your Rights & Choices</Text>
            
            <Text style={styles.subsectionTitle}>Access & Correction</Text>
            <Text style={styles.paragraph}>Review and update your account information anytime.</Text>

            <Text style={styles.subsectionTitle}>Communication Preferences</Text>
            <Text style={styles.paragraph}>Opt out of non-essential notifications or emails.</Text>

            <Text style={styles.subsectionTitle}>Account Deletion</Text>
            <Text style={styles.paragraph}>
              Request deletion of your account. Certain transactional data may remain for dispute resolution or legal obligations.
            </Text>

            <Text style={styles.sectionTitle}>7. Cookies & Tracking</Text>
            <Text style={styles.paragraph}>Hustl may use cookies and similar technologies to:</Text>
            <Text style={styles.bulletPoint}>• Enhance your experience</Text>
            <Text style={styles.bulletPoint}>• Remember your preferences</Text>
            <Text style={styles.bulletPoint}>• Analyze platform usage</Text>
            <Text style={styles.paragraph}>
              You can manage cookies through your browser settings.
            </Text>

            <Text style={styles.sectionTitle}>8. Children's Privacy</Text>
            <Text style={styles.paragraph}>
              Hustl is intended for students at UF (17+ years old). We do not knowingly collect information from anyone under 17.
            </Text>

            <Text style={styles.sectionTitle}>9. Changes to This Policy</Text>
            <Text style={styles.paragraph}>
              We may update this Privacy Policy from time to time. Changes will be posted with a revised "Effective Date." Continued use of Hustl constitutes acceptance of the updated policy.
            </Text>

            <Text style={styles.sectionTitle}>10. Contact Us</Text>
            <Text style={styles.paragraph}>
              Questions or concerns? Reach out to us at: hustlapp@outlook.com
            </Text>
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
  modal: {
    backgroundColor: Colors.semantic.screen,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    maxHeight: height * 0.9,
    minHeight: height * 0.7,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 24,
    paddingBottom: 20,
    borderBottomWidth: 1,
    borderBottomColor: Colors.semantic.divider,
  },
  headerTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: Colors.semantic.headingText,
  },
  closeButton: {
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
    paddingTop: 20,
  },
  title: {
    fontSize: 24,
    fontWeight: '700',
    color: Colors.semantic.headingText,
    marginBottom: 8,
    textAlign: 'center',
  },
  effectiveDate: {
    fontSize: 14,
    color: Colors.semantic.tabInactive,
    marginBottom: 24,
    textAlign: 'center',
    fontStyle: 'italic',
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: Colors.semantic.headingText,
    marginTop: 24,
    marginBottom: 12,
  },
  subsectionTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.semantic.bodyText,
    marginTop: 16,
    marginBottom: 8,
  },
  paragraph: {
    fontSize: 14,
    color: Colors.semantic.bodyText,
    lineHeight: 20,
    marginBottom: 12,
  },
  bulletPoint: {
    fontSize: 14,
    color: Colors.semantic.bodyText,
    lineHeight: 20,
    marginBottom: 6,
    paddingLeft: 8,
  },
  highlight: {
    fontSize: 14,
    color: Colors.semantic.bodyText,
    lineHeight: 20,
    marginBottom: 12,
    backgroundColor: Colors.muted,
    padding: 12,
    borderRadius: 8,
    fontWeight: '600',
  },
});