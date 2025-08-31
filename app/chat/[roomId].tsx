import React, { useState, useEffect, useRef, useCallback } from 'react';
import { View, Text, StyleSheet, ScrollView, TextInput, TouchableOpacity, KeyboardAvoidingView, Platform, Image, Dimensions } from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { ArrowLeft, Send, MoveHorizontal as MoreHorizontal, Plus, User } from 'lucide-react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { Colors } from '@/theme/colors';
import { useAuth } from '@/contexts/AuthContext';
import { ChatService } from '@/lib/chat';
import { supabase } from '@/lib/supabase';
import type { ChatMessage } from '@/types/chat';
import UserProfileSheet from '@/components/UserProfileSheet';

const { width } = Dimensions.get('window');

interface ChatParticipant {
  id: string;
  full_name: string | null;
  username: string | null;
  avatar_url: string | null;
  major: string | null;
  class_year: string | null;
  university: string | null;
  bio: string | null;
  is_verified: boolean;
  completed_tasks_count: number;
  response_rate: number;
  last_seen_at: string;
  created_at: string;
}

export default function ChatScreen() {
  const router = useRouter();
  const params = useLocalSearchParams();
  const insets = useSafeAreaInsets();
  const { user } = useAuth();
  
  const roomId = params.roomId as string;
  const scrollViewRef = useRef<ScrollView>(null);
  
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [inputText, setInputText] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [isSending, setIsSending] = useState(false);
  const [otherParticipant, setOtherParticipant] = useState<ChatParticipant | null>(null);
  const [otherLastReadAt, setOtherLastReadAt] = useState<Date | null>(null);
  const [showProfile, setShowProfile] = useState(false);
  const unsubscribeRef = useRef<(() => void) | null>(null);
  const readChannelRef = useRef<any>(null);

  // Load message history
  useEffect(() => {
    loadMessages();
    loadOtherParticipant();
  }, [roomId]);

  // Realtime subscription
  useEffect(() => {
    if (!roomId) return;

    // Subscribe to new messages
    unsubscribeRef.current = ChatService.subscribeToRoom(roomId, (message: ChatMessage) => {
      setMessages(prev => [...prev, message]);
      scrollToBottom();
    });

    // Subscribe to read receipts via chat_members updates
    if (otherParticipant) {
      readChannelRef.current = supabase
        .channel(`room_${roomId}_reads`)
        .on('postgres_changes',
            { event: 'UPDATE', schema: 'public', table: 'chat_members', filter: `room_id=eq.${roomId}` },
            (payload) => {
              const row = payload.new as { user_id: string; last_read_at: string };
              if (row.user_id === otherParticipant.id && row.last_read_at) {
                setOtherLastReadAt(new Date(row.last_read_at));
              }
            })
        .subscribe();
    }

    return () => {
      unsubscribeRef.current?.();
      unsubscribeRef.current = null;
      readChannelRef.current?.unsubscribe();
      readChannelRef.current = null;
    };
  }, [roomId, otherParticipant]);

  // Mark room as read when screen is focused
  useEffect(() => {
    if (roomId) {
      ChatService.markRoomRead(roomId);
    }
  }, [roomId]);

  const loadMessages = async () => {
    setIsLoading(true);
    try {
      const { data, error } = await ChatService.getMessages(roomId);
      
      if (data) {
        setMessages(data);
        setTimeout(scrollToBottom, 100);
      } else if (error) {
        console.error('Failed to load messages:', error);
      }
    } catch (error) {
      console.error('Failed to load messages:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const loadOtherParticipant = async () => {
    try {
      if (!user?.id) return;

      // Get other participant's profile using RPC
      const { data: participantData, error } = await supabase.rpc('get_chat_participant_profile', {
        p_room_id: roomId,
        p_current_user_id: user.id
      });

      if (error) {
        console.error('Failed to load participant profile:', error);
        return;
      }

      if (participantData && participantData.length > 0) {
        const participant = participantData[0] as ChatParticipant;
        setOtherParticipant(participant);

        // Load their current last_read_at
        const { data: memberData } = await supabase
          .from('chat_members')
          .select('last_read_at')
          .eq('room_id', roomId)
          .eq('user_id', participant.id)
          .limit(1);

        if (memberData?.[0]?.last_read_at) {
          setOtherLastReadAt(new Date(memberData[0].last_read_at));
        }
      }
    } catch (error) {
      console.error('Failed to load other participant:', error);
    }
  };

  const scrollToBottom = () => {
    scrollViewRef.current?.scrollToEnd({ animated: true });
  };

  const handleSendMessage = async () => {
    if (!inputText.trim() || isSending) return;

    const messageText = inputText.trim();
    setInputText('');
    setIsSending(true);

    try {
      if (!user) {
        setInputText(messageText);
        return;
      }

      const { error } = await ChatService.sendMessage(roomId, user.id, messageText);
      
      if (error) {
        console.error('Failed to send message:', error);
        setInputText(messageText);
      }
    } catch (error) {
      console.error('Failed to send message:', error);
      setInputText(messageText);
    } finally {
      setIsSending(false);
    }
  };

  const handleBack = () => {
    router.back();
  };

  const handleProfilePress = useCallback(() => {
    if (!otherParticipant) return;
    
    // Analytics
    console.log('chat_profile_opened', { otherUserId: otherParticipant.id, roomId });
    
    setShowProfile(true);
  }, [otherParticipant, roomId]);

  const formatDisplayName = (participant: ChatParticipant | null): string => {
    if (!participant) return 'User';
    
    const fullName = participant.full_name;
    const username = participant.username;
    
    if (fullName) {
      const parts = fullName.trim().split(' ');
      if (parts.length >= 2) {
        // "First L." format
        return `${parts[0]} ${parts[parts.length - 1].charAt(0)}.`;
      }
      return parts[0]; // Just first name if only one word
    }
    
    return username || 'User';
  };

  const formatSubtitle = (participant: ChatParticipant | null): string => {
    if (!participant) return '';
    
    // Check if user was recently active (within 5 minutes)
    if (participant.last_seen_at) {
      const lastSeen = new Date(participant.last_seen_at);
      const now = new Date();
      const diffInMinutes = (now.getTime() - lastSeen.getTime()) / (1000 * 60);
      
      if (diffInMinutes < 5) {
        return 'Online';
      } else if (diffInMinutes < 60) {
        return `Last seen ${Math.floor(diffInMinutes)}m ago`;
      } else if (diffInMinutes < 1440) {
        return `Last seen ${Math.floor(diffInMinutes / 60)}h ago`;
      }
    }
    
    // Fallback to university and major
    const parts = [];
    if (participant.university) {
      const shortUni = participant.university.includes('University of Florida') ? 'UF' : participant.university;
      parts.push(shortUni);
    }
    if (participant.major) {
      parts.push(participant.major);
    }
    
    return parts.join(' • ') || '';
  };

  const formatTime = (timestamp: string): string => {
    const date = new Date(timestamp);
    const now = new Date();
    const diffInMinutes = (now.getTime() - date.getTime()) / (1000 * 60);
    const diffInHours = diffInMinutes / 60;
    const isToday = date.toDateString() === now.toDateString();
    const isYesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000).toDateString() === date.toDateString();
    
    if (diffInMinutes < 1) {
      return 'now';
    } else if (isToday) {
      return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    } else if (isYesterday) {
      return 'Yesterday ' + date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    } else {
      return date.toLocaleDateString([], { month: 'short', day: 'numeric' });
    }
  };

  const isMessageSeen = (message: ChatMessage): boolean => {
    if (message.sender_id !== user?.id) return false;
    if (!otherLastReadAt) return false;
    
    const messageTime = new Date(message.created_at);
    return messageTime <= otherLastReadAt;
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

  const renderMessage = (message: ChatMessage) => {
    const isOwnMessage = message.sender_id === user?.id;
    const seen = isMessageSeen(message);
    
    return (
      <View key={message.id} style={[
        styles.messageContainer,
        isOwnMessage ? styles.ownMessageContainer : styles.otherMessageContainer
      ]}>
        <View style={[
          styles.messageBubble,
          isOwnMessage ? styles.ownMessageBubble : styles.otherMessageBubble
        ]}>
          <Text style={[
            styles.messageText,
            isOwnMessage ? styles.ownMessageText : styles.otherMessageText
          ]}>
            {message.text}
          </Text>
        </View>
        <View style={[
          styles.messageFooter,
          isOwnMessage ? styles.ownMessageFooter : styles.otherMessageFooter
        ]}>
          <Text style={styles.messageTime}>
            {formatTime(message.created_at)}
          </Text>
          {isOwnMessage && seen && (
            <Text style={styles.seenText}>Seen</Text>
          )}
        </View>
      </View>
    );
  };

  return (
    <KeyboardAvoidingView 
      style={[styles.container, { paddingTop: insets.top }]}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity style={styles.backButton} onPress={handleBack}>
          <ArrowLeft size={24} color={Colors.semantic.bodyText} strokeWidth={2} />
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.headerCenter} onPress={handleProfilePress}>
          <View style={styles.headerAvatarContainer}>
            {otherParticipant?.avatar_url ? (
              <Image source={{ uri: otherParticipant.avatar_url }} style={styles.headerAvatar} />
            ) : (
              <View style={styles.headerAvatarPlaceholder}>
                <Text style={styles.headerAvatarText}>
                  {getInitials(otherParticipant?.full_name || otherParticipant?.username)}
                </Text>
              </View>
            )}
          </View>
          <View style={styles.headerInfo}>
            <Text style={styles.headerTitle}>
              {formatDisplayName(otherParticipant)}
            </Text>
            {formatSubtitle(otherParticipant) && (
              <Text style={styles.headerSubtitle}>{formatSubtitle(otherParticipant)}</Text>
            )}
          </View>
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.optionsButton}>
          <MoreHorizontal size={20} color={Colors.semantic.bodyText} strokeWidth={2} />
        </TouchableOpacity>
      </View>

      {/* Messages */}
      <ScrollView
        ref={scrollViewRef}
        style={styles.messagesContainer}
        contentContainerStyle={styles.messagesContent}
        showsVerticalScrollIndicator={false}
        onContentSizeChange={scrollToBottom}
      >
        {isLoading ? (
          <View style={styles.loadingContainer}>
            <Text style={styles.loadingText}>Loading messages...</Text>
          </View>
        ) : messages.length === 0 ? (
          <View style={styles.emptyContainer}>
            <View style={styles.emptyIconContainer}>
              <Text style={styles.emptyIcon}>💬</Text>
            </View>
            <Text style={styles.emptyText}>Start the conversation</Text>
            <Text style={styles.emptySubtext}>Send a message to get things started!</Text>
          </View>
        ) : (
          messages.map(renderMessage)
        )}
      </ScrollView>

      {/* Input */}
      <View style={[styles.inputContainer, { paddingBottom: insets.bottom + 16 }]}>
        <View style={styles.inputRow}>
          <TouchableOpacity style={styles.attachButton}>
            <Plus size={20} color={Colors.semantic.tabInactive} strokeWidth={2} />
          </TouchableOpacity>
          
          <TextInput
            style={styles.textInput}
            value={inputText}
            onChangeText={setInputText}
            placeholder="Type a message..."
            placeholderTextColor={Colors.semantic.tabInactive}
            multiline
            maxLength={1000}
          />
        </View>
        
        <TouchableOpacity
          style={[
            styles.sendButton,
            (!inputText.trim() || isSending) && styles.sendButtonDisabled
          ]}
          onPress={handleSendMessage}
          disabled={!inputText.trim() || isSending}
        >
          {(!inputText.trim() || isSending) ? (
            <Send size={18} color={Colors.white} strokeWidth={2} />
          ) : (
            <LinearGradient
              colors={[Colors.primary, Colors.secondary]}
              start={{ x: 0, y: 0 }}
              end={{ x: 1, y: 1 }}
              style={styles.sendButtonGradient}
            >
              <Send size={18} color={Colors.white} strokeWidth={2} />
            </LinearGradient>
          )}
        </TouchableOpacity>
      </View>

      {/* User Profile Sheet */}
      <UserProfileSheet
        visible={showProfile}
        onClose={() => setShowProfile(false)}
        userId={otherParticipant?.id || null}
        currentChatRoomId={roomId}
      />
    </KeyboardAvoidingView>
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
    paddingHorizontal: 20,
    paddingVertical: 16,
    backgroundColor: Colors.white,
    borderBottomWidth: 0.5,
    borderBottomColor: 'rgba(229, 231, 235, 0.6)',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 3,
    elevation: 2,
  },
  backButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(245, 245, 245, 0.8)',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  headerCenter: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
  },
  headerAvatarContainer: {
    marginRight: 12,
  },
  headerAvatar: {
    width: 40,
    height: 40,
    borderRadius: 20,
  },
  headerAvatarPlaceholder: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: Colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  headerAvatarText: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.white,
  },
  headerInfo: {
    flex: 1,
  },
  headerTitle: {
    fontSize: 17,
    fontWeight: '600',
    color: Colors.semantic.headingText,
    marginBottom: 2,
  },
  headerSubtitle: {
    fontSize: 13,
    color: Colors.semantic.tabInactive,
    fontWeight: '500',
  },
  optionsButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(245, 245, 245, 0.8)',
    justifyContent: 'center',
    alignItems: 'center',
    marginLeft: 12,
  },
  messagesContainer: {
    flex: 1,
    backgroundColor: '#FAFAFA',
  },
  messagesContent: {
    padding: 20,
    paddingBottom: 12,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 40,
  },
  loadingText: {
    fontSize: 16,
    color: Colors.semantic.tabInactive,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 60,
    gap: 16,
  },
  emptyIconContainer: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: 'rgba(245, 245, 245, 0.8)',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 8,
  },
  emptyIcon: {
    fontSize: 32,
  },
  emptyText: {
    fontSize: 20,
    fontWeight: '600',
    color: Colors.semantic.headingText,
    textAlign: 'center',
  },
  emptySubtext: {
    fontSize: 16,
    color: Colors.semantic.tabInactive,
    textAlign: 'center',
  },
  messageContainer: {
    marginBottom: 16,
  },
  ownMessageContainer: {
    alignItems: 'flex-end',
  },
  otherMessageContainer: {
    alignItems: 'flex-start',
  },
  messageBubble: {
    maxWidth: width * 0.75,
    borderRadius: 20,
    paddingHorizontal: 18,
    paddingVertical: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.08,
    shadowRadius: 3,
    elevation: 2,
  },
  ownMessageBubble: {
    backgroundColor: Colors.primary,
    borderBottomRightRadius: 6,
  },
  otherMessageBubble: {
    backgroundColor: Colors.white,
    borderBottomLeftRadius: 6,
    borderWidth: 0.5,
    borderColor: 'rgba(229, 231, 235, 0.8)',
  },
  messageText: {
    fontSize: 17,
    lineHeight: 22,
  },
  ownMessageText: {
    color: Colors.white,
  },
  otherMessageText: {
    color: Colors.semantic.bodyText,
  },
  messageFooter: {
    marginTop: 6,
    alignItems: 'flex-end',
  },
  ownMessageFooter: {
    alignItems: 'flex-end',
  },
  otherMessageFooter: {
    alignItems: 'flex-start',
  },
  messageTime: {
    fontSize: 11,
    color: Colors.semantic.tabInactive,
    fontWeight: '500',
  },
  seenText: {
    fontSize: 10,
    color: Colors.semantic.tabInactive,
    fontWeight: '500',
    marginTop: 2,
  },
  inputContainer: {
    paddingHorizontal: 20,
    paddingTop: 12,
    backgroundColor: Colors.white,
    borderTopWidth: 0.5,
    borderTopColor: 'rgba(229, 231, 235, 0.6)',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: -1 },
    shadowOpacity: 0.05,
    shadowRadius: 3,
    elevation: 4,
  },
  inputRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    backgroundColor: 'rgba(245, 245, 245, 0.8)',
    borderRadius: 24,
    paddingHorizontal: 4,
    paddingVertical: 4,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: 'rgba(229, 231, 235, 0.5)',
  },
  attachButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'transparent',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 8,
  },
  textInput: {
    flex: 1,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 17,
    color: Colors.semantic.inputText,
    backgroundColor: 'transparent',
    maxHeight: 120,
    minHeight: 36,
  },
  sendButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: Colors.semantic.tabInactive,
    justifyContent: 'center',
    alignItems: 'center',
    marginLeft: 12,
    overflow: 'hidden',
    shadowColor: Colors.primary,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.2,
    shadowRadius: 4,
    elevation: 3,
  },
  sendButtonDisabled: {
    backgroundColor: Colors.semantic.tabInactive,
    shadowOpacity: 0,
    elevation: 0,
  },
  sendButtonGradient: {
    width: '100%',
    height: '100%',
    justifyContent: 'center',
    alignItems: 'center',
  },
});