import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Modal, ScrollView, Dimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { X } from 'lucide-react-native';
import { Colors } from '@/theme/colors';

const { height } = Dimensions.get('window');

interface TermsOfServiceModalProps {
  visible: boolean;
  onClose: () => void;
}

export default function TermsOfServiceModal({ visible, onClose }: TermsOfServiceModalProps) {
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
            <Text style={styles.headerTitle}>Terms of Service</Text>
            <TouchableOpacity style={styles.closeButton} onPress={onClose}>
              <X size={24} color={Colors.semantic.tabInactive} strokeWidth={2} />
            </TouchableOpacity>
          </View>

          <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
            <Text style={styles.title}>Hustl Terms of Service</Text>
            <Text style={styles.effectiveDate}>Effective Date: {getCurrentDate()}</Text>
            
            <Text style={styles.paragraph}>
              Welcome to Hustl, a student-led marketplace at the University of Florida ("UF"). By using Hustl, you agree to the following Terms of Service. Please read carefully.
            </Text>

            <Text style={styles.sectionTitle}>1. About Hustl</Text>
            <Text style={styles.paragraph}>
              Hustl is a peer-to-peer platform that allows students to post and complete tasks, such as rides, food delivery, errands, or other services. Hustl does not employ, supervise, or guarantee the conduct of users. Hustl is not a transportation provider, delivery company, or academic service provider.
            </Text>

            <Text style={styles.sectionTitle}>2. Eligibility</Text>
            <Text style={styles.paragraph}>
              You must be a current UF student, at least 17 years old, and legally permitted to use this service.
            </Text>

            <Text style={styles.sectionTitle}>3. User Responsibilities</Text>
            <Text style={styles.paragraph}>By using Hustl, you agree that:</Text>
            <Text style={styles.bulletPoint}>• You are solely responsible for your own actions, postings, and communications.</Text>
            <Text style={styles.bulletPoint}>• You will comply with all applicable laws, UF regulations, and these Terms.</Text>
            <Text style={styles.bulletPoint}>• You assume all risks associated with interacting with other users.</Text>

            <Text style={styles.sectionTitle}>4. Prohibited Conduct</Text>
            <Text style={styles.paragraph}>
              You may not use Hustl for any harmful, illegal, or unsafe activity, including but not limited to:
            </Text>
            
            <Text style={styles.subsectionTitle}>Violence & Misconduct</Text>
            <Text style={styles.bulletPoint}>• Assault, battery, stalking, harassment, bullying, threats, or intimidation.</Text>
            <Text style={styles.bulletPoint}>• Sexual misconduct of any kind (harassment, exploitation, assault, or unwanted advances).</Text>
            <Text style={styles.bulletPoint}>• Kidnapping, human trafficking, or exploitation.</Text>

            <Text style={styles.subsectionTitle}>Illegal Goods & Services</Text>
            <Text style={styles.bulletPoint}>• Sale or distribution of drugs, controlled substances, or drug paraphernalia.</Text>
            <Text style={styles.bulletPoint}>• Alcohol sales to underage individuals.</Text>
            <Text style={styles.bulletPoint}>• Sale or possession of weapons, explosives, or hazardous materials.</Text>
            <Text style={styles.bulletPoint}>• Distribution of stolen property, counterfeit goods, or pirated digital content.</Text>

            <Text style={styles.subsectionTitle}>Financial & Fraudulent Activities</Text>
            <Text style={styles.bulletPoint}>• Scams, pyramid schemes, money laundering, or financial fraud.</Text>
            <Text style={styles.bulletPoint}>• Identity theft, impersonation, or misrepresentation.</Text>
            <Text style={styles.bulletPoint}>• Misuse of payment methods or chargeback fraud.</Text>

            <Text style={styles.subsectionTitle}>Academic Misconduct</Text>
            <Text style={styles.bulletPoint}>• Selling or distributing exams, essays, or assignments.</Text>
            <Text style={styles.bulletPoint}>• Offering services that violate UF's Honor Code (cheating, plagiarism).</Text>

            <Text style={styles.subsectionTitle}>Dangerous Conduct</Text>
            <Text style={styles.bulletPoint}>• Reckless driving, unsafe transportation, or endangerment of passengers.</Text>
            <Text style={styles.bulletPoint}>• Delivery of unsafe or spoiled food items.</Text>
            <Text style={styles.bulletPoint}>• Encouraging self-harm or suicide.</Text>

            <Text style={styles.subsectionTitle}>Other Prohibited Uses</Text>
            <Text style={styles.bulletPoint}>• Dissemination of hate speech, discriminatory remarks, or extremist content.</Text>
            <Text style={styles.bulletPoint}>• Spamming, hacking, or attempting to interfere with Hustl's systems.</Text>
            <Text style={styles.bulletPoint}>• Any act that violates UF policy, Florida law, or federal law.</Text>

            <Text style={styles.highlight}>
              ⚠️ This list is not exhaustive. Any behavior Hustl deems harmful, unsafe, or unlawful is prohibited.
            </Text>

            <Text style={styles.sectionTitle}>5. No Liability</Text>
            <Text style={styles.paragraph}>
              Hustl does not control, supervise, or guarantee the actions of users and is not responsible or liable for:
            </Text>
            <Text style={styles.bulletPoint}>• Personal injury, death, accidents, or medical emergencies.</Text>
            <Text style={styles.bulletPoint}>• Sexual harassment, assault, stalking, or any unwanted contact.</Text>
            <Text style={styles.bulletPoint}>• Theft, loss, or destruction of property.</Text>
            <Text style={styles.bulletPoint}>• Sale, purchase, or distribution of illegal substances, alcohol, weapons, or dangerous items.</Text>
            <Text style={styles.bulletPoint}>• Fraud, scams, misrepresentation, or identity theft.</Text>
            <Text style={styles.bulletPoint}>• Academic dishonesty, cheating, or disciplinary action by UF.</Text>
            <Text style={styles.bulletPoint}>• Vehicle accidents, reckless driving, or transportation-related incidents.</Text>
            <Text style={styles.bulletPoint}>• Food poisoning, allergic reactions, or unsafe delivery of goods.</Text>
            <Text style={styles.bulletPoint}>• Kidnapping, trafficking, coercion, or unlawful detention.</Text>
            <Text style={styles.bulletPoint}>• Technology misuse, hacking, data theft, or cybercrime.</Text>
            <Text style={styles.bulletPoint}>• Emotional distress, bullying, discrimination, or hate speech.</Text>
            <Text style={styles.bulletPoint}>• Any dispute, conflict, or disagreement between users.</Text>

            <Text style={styles.paragraph}>
              By using Hustl, you agree that all risks are yours alone, and you release Hustl, its founders, student organizers, and affiliates from any liability, claim, damage, loss, or expense arising out of your use of the platform.
            </Text>

            <Text style={styles.sectionTitle}>6. Assumption of Risk</Text>
            <Text style={styles.paragraph}>You understand and agree that:</Text>
            <Text style={styles.bulletPoint}>• Using Hustl involves risks of personal injury, property damage, financial loss, or other harm.</Text>
            <Text style={styles.bulletPoint}>• Hustl does not screen users beyond basic eligibility.</Text>
            <Text style={styles.bulletPoint}>• You assume full responsibility for all risks and outcomes.</Text>

            <Text style={styles.sectionTitle}>7. Food & Errand Transactions</Text>
            <Text style={styles.paragraph}>
              Hustl is designed for quick, casual exchanges between students. Food-related and errand tasks are not professional delivery services.
            </Text>
            
            <Text style={styles.subsectionTitle}>Payment Responsibilities</Text>
            <Text style={styles.bulletPoint}>• Requesters must either prepay the cost of food or reimburse the runner upon delivery, depending on the agreed arrangement.</Text>
            <Text style={styles.bulletPoint}>• Hustl may require funds to be held in escrow to prevent disputes.</Text>

            <Text style={styles.subsectionTitle}>Cancellations</Text>
            <Text style={styles.bulletPoint}>• Once food has been purchased, requesters may not cancel or refuse payment.</Text>
            <Text style={styles.bulletPoint}>• If a requester cancels after purchase, they remain responsible for reimbursing the runner for all costs incurred.</Text>

            <Text style={styles.subsectionTitle}>Runner Protection</Text>
            <Text style={styles.bulletPoint}>• Runners may upload proof of purchase (receipt and photo of items). Once proof is uploaded, requesters are financially obligated.</Text>
            <Text style={styles.bulletPoint}>• If a requester refuses to pay, Hustl reserves the right to suspend their account.</Text>

            <Text style={styles.subsectionTitle}>Requester Protection</Text>
            <Text style={styles.bulletPoint}>• Runners must provide proof of purchase when requested.</Text>
            <Text style={styles.bulletPoint}>• If a runner steals or withholds food, Hustl is not liable but may ban the runner to protect the community.</Text>

            <Text style={styles.subsectionTitle}>No Delivery Fees</Text>
            <Text style={styles.paragraph}>
              Hustl does not charge service or delivery fees. Payments are strictly for the cost of goods and any agreed-upon compensation between students.
            </Text>

            <Text style={styles.highlight}>
              ⚠️ Hustl is not responsible for stolen or spoiled food, food allergies, delivery timing, or any disputes between users. All transactions are peer-to-peer and conducted at users' own risk.
            </Text>

            <Text style={styles.sectionTitle}>8. Payment & Transactions</Text>
            <Text style={styles.paragraph}>
              Hustl is not responsible for payment disputes, scams, or failed transactions. All financial arrangements are strictly between users.
            </Text>

            <Text style={styles.sectionTitle}>9. Reporting & Enforcement</Text>
            <Text style={styles.paragraph}>
              Users are encouraged to report misconduct or violations. Hustl may suspend or remove accounts at its discretion, but Hustl is not obligated to resolve disputes.
            </Text>

            <Text style={styles.sectionTitle}>10. No Warranties</Text>
            <Text style={styles.paragraph}>
              Hustl is provided "as is." Hustl disclaims all warranties, express or implied, including safety, reliability, or fitness for a particular purpose.
            </Text>

            <Text style={styles.sectionTitle}>11. Indemnification</Text>
            <Text style={styles.paragraph}>
              You agree to indemnify and hold harmless Hustl, its founders, student organizers, and affiliates from any claims, damages, or expenses arising from your use of the platform or violation of these Terms.
            </Text>

            <Text style={styles.sectionTitle}>12. Dispute Resolution</Text>
            <Text style={styles.paragraph}>
              Any disputes must first be attempted to be resolved informally with Hustl. If unresolved, disputes will be governed under the laws of the State of Florida.
            </Text>

            <Text style={styles.sectionTitle}>13. Changes to Terms</Text>
            <Text style={styles.paragraph}>
              Hustl may update these Terms at any time. Continued use of the platform constitutes acceptance of updated Terms.
            </Text>

            <Text style={styles.sectionTitle}>14. Contact</Text>
            <Text style={styles.paragraph}>
              For questions or concerns, contact: hustlapp@outlook.com
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