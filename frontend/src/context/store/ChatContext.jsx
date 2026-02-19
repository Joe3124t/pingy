import {
  createContext,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import api, { getAccessToken } from '../../services/api';
import { connectSocket, disconnectSocket } from '../../services/socket';
import { useAuth } from '../../hooks/useAuth';
import { encryptConversationText } from '../../encryption/e2eeService';

export const ChatContext = createContext(null);
const PENDING_NOTIFICATION_CONVERSATION_KEY = 'pingy:pending-notification-conversation-id';

const createClientId = () => {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) {
    return crypto.randomUUID();
  }

  return `client-${Date.now()}-${Math.random().toString(16).slice(2)}`;
};

const sortConversations = (conversations) => {
  return [...conversations].sort((left, right) => {
    const leftTime = left.lastMessageCreatedAt || left.lastMessageAt || left.updatedAt || left.createdAt;
    const rightTime = right.lastMessageCreatedAt || right.lastMessageAt || right.updatedAt || right.createdAt;

    return new Date(rightTime || 0).getTime() - new Date(leftTime || 0).getTime();
  });
};

const sortMessages = (messages) => {
  return [...messages].sort(
    (left, right) => new Date(left.createdAt).getTime() - new Date(right.createdAt).getTime(),
  );
};

const normalizeReactions = (reactions) => {
  if (!Array.isArray(reactions)) {
    return [];
  }

  return reactions.map((entry) => ({
    emoji: entry?.emoji,
    count: Number(entry?.count || 0),
    reactedByMe: Boolean(entry?.reactedByMe),
  }));
};

const isIosDevice = () => {
  if (typeof navigator === 'undefined') {
    return false;
  }

  const userAgent = navigator.userAgent || '';
  const isAppleMobile = /iPad|iPhone|iPod/.test(userAgent);
  const isTouchMac = navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1;

  return isAppleMobile || isTouchMac;
};

const isStandaloneDisplay = () => {
  if (typeof window === 'undefined') {
    return false;
  }

  return (
    window.matchMedia?.('(display-mode: standalone)').matches ||
    window.navigator?.standalone === true
  );
};

const toPermissionState = (value) => {
  if (value === 'granted' || value === 'denied' || value === 'default') {
    return value;
  }

  return 'unsupported';
};

const supportsWebPush = () =>
  typeof window !== 'undefined' &&
  typeof navigator !== 'undefined' &&
  'serviceWorker' in navigator &&
  'PushManager' in window;

const urlBase64ToUint8Array = (base64String) => {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const normalized = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = window.atob(normalized);
  const outputArray = new Uint8Array(rawData.length);

  for (let index = 0; index < rawData.length; index += 1) {
    outputArray[index] = rawData.charCodeAt(index);
  }

  return outputArray;
};

export const ChatProvider = ({ children }) => {
  const { user, isAuthenticated } = useAuth();

  const [conversations, setConversations] = useState([]);
  const [activeConversationId, setActiveConversationId] = useState(null);
  const [messagesByConversation, setMessagesByConversation] = useState({});
  const [typingByConversation, setTypingByConversation] = useState({});
  const [replyDraftByConversation, setReplyDraftByConversation] = useState({});
  const [userSearchResults, setUserSearchResults] = useState([]);
  const [blockedUsers, setBlockedUsers] = useState([]);
  const [socketState, setSocketState] = useState('offline');
  const [isLoadingConversations, setIsLoadingConversations] = useState(false);
  const [isLoadingMessages, setIsLoadingMessages] = useState(false);
  const [notificationPermission, setNotificationPermission] = useState(() =>
    typeof Notification === 'undefined' ? 'unsupported' : toPermissionState(Notification.permission),
  );
  const [notificationSupportHint, setNotificationSupportHint] = useState('');

  const socketRef = useRef(null);
  const activeConversationRef = useRef(activeConversationId);
  const conversationsRef = useRef(conversations);
  const messagesRef = useRef(messagesByConversation);
  const typingTimeoutsRef = useRef(new Map());

  useEffect(() => {
    activeConversationRef.current = activeConversationId;
  }, [activeConversationId]);

  useEffect(() => {
    conversationsRef.current = conversations;
  }, [conversations]);

  useEffect(() => {
    messagesRef.current = messagesByConversation;
  }, [messagesByConversation]);

  const patchConversationPresence = useCallback((presenceUpdate) => {
    setConversations((previous) =>
      previous.map((conversation) => {
        if (conversation.participantId !== presenceUpdate.userId) {
          return conversation;
        }

        return {
          ...conversation,
          participantIsOnline: presenceUpdate.isOnline,
          participantLastSeen: presenceUpdate.lastSeen || conversation.participantLastSeen,
        };
      }),
    );
  }, []);

  const applyMessageToState = useCallback(
    (message) => {
      const normalizedMessage = {
        ...message,
        reactions: normalizeReactions(message?.reactions),
      };

      setMessagesByConversation((previous) => {
        const existing = previous[normalizedMessage.conversationId] || [];
        const index = existing.findIndex((item) => item.id === normalizedMessage.id);
        const nextMessages =
          index === -1
            ? [...existing, normalizedMessage]
            : existing.map((item) => (item.id === normalizedMessage.id ? normalizedMessage : item));

        return {
          ...previous,
          [normalizedMessage.conversationId]: sortMessages(nextMessages),
        };
      });

      setConversations((previous) => {
        const index = previous.findIndex(
          (conversation) => conversation.conversationId === normalizedMessage.conversationId,
        );

        if (index === -1) {
          return previous;
        }

        const current = previous[index];
        const isIncoming = normalizedMessage.senderId !== user?.id;
        const isActiveConversation =
          activeConversationRef.current && activeConversationRef.current === normalizedMessage.conversationId;

        const updated = {
          ...current,
          lastMessageId: normalizedMessage.id,
          lastMessageType: normalizedMessage.type,
          lastMessageBody:
            normalizedMessage.type === 'text'
              ? normalizedMessage.isEncrypted
                ? 'Message'
                : normalizedMessage.body || 'Message'
              : normalizedMessage.body,
          lastMessageIsEncrypted: Boolean(normalizedMessage.isEncrypted),
          lastMessageMediaName: normalizedMessage.mediaName,
          lastMessageCreatedAt: normalizedMessage.createdAt,
          lastMessageSenderId: normalizedMessage.senderId,
          lastMessageAt: normalizedMessage.createdAt,
          participantUsername:
            normalizedMessage.senderId !== user?.id && normalizedMessage.senderUsername
              ? normalizedMessage.senderUsername
              : current.participantUsername,
          participantAvatarUrl:
            normalizedMessage.senderId !== user?.id && normalizedMessage.senderAvatarUrl
              ? normalizedMessage.senderAvatarUrl
              : current.participantAvatarUrl,
          unreadCount:
            isIncoming && !isActiveConversation
              ? (current.unreadCount || 0) + 1
              : isActiveConversation
                ? 0
                : current.unreadCount || 0,
        };

        const next = [...previous];
        next[index] = updated;
        return sortConversations(next);
      });
    },
    [user?.id],
  );

  const patchMessageLifecycle = useCallback((update, field) => {
    setMessagesByConversation((previous) => {
      const current = previous[update.conversationId] || [];

      if (!current.length) {
        return previous;
      }

      const next = current.map((message) => {
        if (message.id !== update.id) {
          return message;
        }

        return {
          ...message,
          deliveredAt: update.deliveredAt || message.deliveredAt,
          seenAt: field === 'seenAt' ? update.seenAt || message.seenAt : message.seenAt,
        };
      });

      return {
        ...previous,
        [update.conversationId]: next,
      };
    });
  }, []);

  const patchMessageReactions = useCallback((update) => {
    if (!update?.conversationId || !update?.messageId) {
      return;
    }

    setMessagesByConversation((previous) => {
      const current = previous[update.conversationId] || [];

      if (!current.length) {
        return previous;
      }

      const next = current.map((message) =>
        message.id === update.messageId
          ? {
              ...message,
              reactions: normalizeReactions(update.reactions),
            }
          : message,
      );

      return {
        ...previous,
        [update.conversationId]: next,
      };
    });
  }, []);

  const patchParticipantProfile = useCallback((update) => {
    if (!update?.userId) {
      return;
    }

    setConversations((previous) =>
      previous.map((conversation) =>
        conversation.participantId === update.userId
          ? {
              ...conversation,
              participantUsername: update.username || conversation.participantUsername,
              participantAvatarUrl: update.avatarUrl || conversation.participantAvatarUrl,
            }
          : conversation,
      ),
    );

    setMessagesByConversation((previous) => {
      const next = {};

      Object.entries(previous).forEach(([conversationId, messages]) => {
        next[conversationId] = messages.map((message) =>
          message.senderId === update.userId
            ? {
                ...message,
                senderUsername: update.username || message.senderUsername,
                senderAvatarUrl: update.avatarUrl || message.senderAvatarUrl,
              }
            : message,
        );
      });

      return next;
    });
  }, []);

  const patchConversationWallpaper = useCallback((update) => {
    if (!update?.conversationId) {
      return;
    }

    setConversations((previous) =>
      previous.map((conversation) =>
        conversation.conversationId === update.conversationId
          ? {
              ...conversation,
              wallpaperUrl: update.wallpaperUrl || null,
              blurIntensity: Number(update.blurIntensity || 0),
            }
          : conversation,
      ),
    );
  }, []);

  const clearReplyDraft = useCallback((conversationId) => {
    if (!conversationId) {
      return;
    }

    setReplyDraftByConversation((previous) => {
      if (!previous[conversationId]) {
        return previous;
      }

      const next = { ...previous };
      delete next[conversationId];
      return next;
    });
  }, []);

  const setReplyDraft = useCallback((conversationId, message) => {
    if (!conversationId || !message?.id) {
      return;
    }

    setReplyDraftByConversation((previous) => ({
      ...previous,
      [conversationId]: message,
    }));
  }, []);

  const registerPushSubscription = useCallback(async () => {
    if (!isAuthenticated || !supportsWebPush()) {
      return {
        ok: false,
      };
    }

    const registration = await navigator.serviceWorker.register('/sw.js');
    let subscription = await registration.pushManager.getSubscription();

    if (!subscription) {
      const capabilityResponse = await api.get('/users/me/push/public-key');
      const publicKey = String(capabilityResponse.data?.publicKey || '').trim();
      const enabled = Boolean(capabilityResponse.data?.enabled);

      if (!enabled || !publicKey) {
        throw new Error('Push notifications are not configured yet');
      }

      subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(publicKey),
      });
    }

    await api.post('/users/me/push-subscriptions', {
      subscription: subscription.toJSON(),
    });

    return {
      ok: true,
      endpoint: subscription.endpoint,
    };
  }, [isAuthenticated]);

  const refreshNotificationPermission = useCallback(() => {
    if (typeof window === 'undefined') {
      setNotificationPermission('unsupported');
      setNotificationSupportHint('');
      return {
        permission: 'unsupported',
        supported: false,
        hint: '',
      };
    }

    const ios = isIosDevice();
    const standalone = isStandaloneDisplay();
    const pushSupported = supportsWebPush();

    if (typeof Notification === 'undefined' || !pushSupported) {
      const hint =
        ios && !standalone
          ? 'On iPhone: Share > Add to Home Screen, open Pingy from Home Screen, then tap Enable.'
          : 'This browser does not support push notifications.';

      setNotificationPermission('unsupported');
      setNotificationSupportHint(hint);

      return {
        permission: 'unsupported',
        supported: false,
        hint,
      };
    }

    const permission = toPermissionState(Notification.permission);
    let hint = '';

    if (ios && !standalone) {
      hint = 'Open Pingy from Home Screen first. iPhone notifications only work in installed mode.';
    } else if (permission === 'denied') {
      hint = 'Notifications are blocked. Enable them from browser settings for this site.';
    }

    setNotificationPermission(permission);
    setNotificationSupportHint(hint);

    return {
      permission,
      supported: true,
      hint,
    };
  }, []);

  const requestNotificationPermission = useCallback(async () => {
    const capability = refreshNotificationPermission();

    if (!capability.supported || capability.permission === 'unsupported') {
      return capability;
    }

    let permission = capability.permission;

    if (permission !== 'granted') {
      try {
        permission = toPermissionState(await Notification.requestPermission());
      } catch {
        permission = toPermissionState(Notification.permission);
      }
    }

    setNotificationPermission(permission);

    if (permission === 'denied') {
      setNotificationSupportHint(
        'Notifications are blocked. Enable them from browser settings for this site.',
      );
    }

    if (permission === 'granted') {
      try {
        await registerPushSubscription();
        setNotificationSupportHint('');
      } catch (error) {
        const message =
          error?.response?.data?.message ||
          error?.message ||
          'Push registration failed';
        setNotificationSupportHint(String(message));
      }
    }

    return {
      permission,
      supported: true,
      hint: permission === 'denied' ? 'blocked' : '',
    };
  }, [refreshNotificationPermission, registerPushSubscription]);

  useEffect(() => {
    const syncNotificationState = () => {
      refreshNotificationPermission();
    };

    syncNotificationState();

    if (typeof window === 'undefined') {
      return undefined;
    }

    document.addEventListener('visibilitychange', syncNotificationState);
    window.addEventListener('focus', syncNotificationState);

    return () => {
      document.removeEventListener('visibilitychange', syncNotificationState);
      window.removeEventListener('focus', syncNotificationState);
    };
  }, [refreshNotificationPermission]);

  useEffect(() => {
    if (!isAuthenticated || notificationPermission !== 'granted') {
      return;
    }

    registerPushSubscription().catch(() => {
      // Registration errors are surfaced when user taps Enable.
    });
  }, [isAuthenticated, notificationPermission, registerPushSubscription]);

  const sendNotificationTest = useCallback(() => {
    if (typeof window === 'undefined' || typeof Notification === 'undefined') {
      return false;
    }

    if (Notification.permission !== 'granted') {
      return false;
    }

    const notification = new Notification('Pingy', {
      body: 'Notifications are enabled.',
      icon: '/pingy-logo-192.png',
      badge: '/pingy-logo-192.png',
      tag: 'pingy-notification-test',
    });

    notification.onclick = () => {
      window.focus();
    };

    return true;
  }, []);

  const showIncomingNotification = useCallback(
    (message) => {
      if (typeof window === 'undefined' || typeof Notification === 'undefined') {
        return;
      }

      const title =
        conversationsRef.current.find(
          (conversation) => conversation.conversationId === message.conversationId,
        )?.participantUsername ||
        message.senderUsername ||
        'Pingy';

      const body =
        message.type === 'text'
          ? 'New message'
          : message.type === 'voice'
            ? 'Voice message'
            : message.type === 'image'
              ? 'Image'
              : message.type === 'video'
                ? 'Video'
                : 'File';

      const notify = () => {
        const notification = new Notification(title, {
          body,
          icon: '/pingy-logo-192.png',
          badge: '/pingy-logo-192.png',
          tag: `pingy-msg-${message.id}`,
        });

        notification.onclick = () => {
          window.focus();
          try {
            window.localStorage.setItem(
              PENDING_NOTIFICATION_CONVERSATION_KEY,
              String(message.conversationId),
            );
          } catch {
            // Ignore storage errors.
          }

          setActiveConversationId(message.conversationId);
        };
      };

      if (Notification.permission === 'granted') {
        notify();
      }
    },
    [],
  );

  const markSeen = useCallback(
    async (conversationId, messageIds) => {
      if (!conversationId || !isAuthenticated) {
        return;
      }

      const payload = {
        messageIds:
          messageIds ||
          (messagesRef.current[conversationId] || [])
            .filter((message) => message.recipientId === user?.id && !message.seenAt)
            .map((message) => message.id),
      };

      if (!payload.messageIds.length) {
        setConversations((previous) =>
          previous.map((conversation) =>
            conversation.conversationId === conversationId
              ? {
                  ...conversation,
                  unreadCount: 0,
                }
              : conversation,
          ),
        );
        return;
      }

      const socket = socketRef.current;

      if (socket?.connected) {
        socket.emit('message:seen', { conversationId, messageIds: payload.messageIds });
      } else {
        await api.post(`/messages/${conversationId}/seen`, payload);
      }

      setConversations((previous) =>
        previous.map((conversation) =>
          conversation.conversationId === conversationId
            ? {
                ...conversation,
                unreadCount: 0,
              }
            : conversation,
        ),
      );
    },
    [isAuthenticated, user?.id],
  );

  const joinConversationRoom = useCallback((conversationId) => {
    const socket = socketRef.current;

    if (!socket?.connected || !conversationId) {
      return;
    }

    socket.emit('conversation:join', { conversationId });
  }, []);

  const loadMessages = useCallback(
    async (conversationId, { silent = false } = {}) => {
      if (!conversationId || !isAuthenticated) {
        return [];
      }

      if (!silent) {
        setIsLoadingMessages(true);
      }

      try {
        const response = await api.get(`/messages/${conversationId}`, {
          params: { limit: 80 },
        });

        const messages = sortMessages(
          (response.data?.messages || []).map((message) => ({
            ...message,
            reactions: normalizeReactions(message?.reactions),
          })),
        );

        setMessagesByConversation((previous) => ({
          ...previous,
          [conversationId]: messages,
        }));

        return messages;
      } finally {
        if (!silent) {
          setIsLoadingMessages(false);
        }
      }
    },
    [isAuthenticated],
  );

  const refreshConversations = useCallback(async () => {
    if (!isAuthenticated) {
      return;
    }

    setIsLoadingConversations(true);

    try {
      const response = await api.get('/conversations');
      const nextConversations = sortConversations(response.data?.conversations || []);

      setConversations(nextConversations);

      if (nextConversations.length === 0) {
        setActiveConversationId(null);
        return;
      }

      setActiveConversationId((current) => {
        if (current && nextConversations.some((conversation) => conversation.conversationId === current)) {
          return current;
        }

        return null;
      });
    } finally {
      setIsLoadingConversations(false);
    }
  }, [isAuthenticated]);

  const refreshBlockedUsers = useCallback(async () => {
    if (!isAuthenticated) {
      return [];
    }

    const response = await api.get('/users/blocked');
    const nextBlockedUsers = response.data?.blockedUsers || [];
    setBlockedUsers(nextBlockedUsers);
    return nextBlockedUsers;
  }, [isAuthenticated]);

  const selectConversation = useCallback(
    async (conversationId) => {
      setActiveConversationId(conversationId);
      joinConversationRoom(conversationId);

      if (!messagesRef.current[conversationId]) {
        await loadMessages(conversationId);
      }

      await markSeen(conversationId);
    },
    [joinConversationRoom, loadMessages, markSeen],
  );

  useEffect(() => {
    if (!isAuthenticated || typeof window === 'undefined') {
      return;
    }

    let pendingConversationId = null;
    let fromQueryParam = false;

    try {
      pendingConversationId = window.localStorage.getItem(PENDING_NOTIFICATION_CONVERSATION_KEY);
    } catch {
      pendingConversationId = null;
    }

    if (!pendingConversationId) {
      const url = new URL(window.location.href);
      const queryConversationId = String(url.searchParams.get('conversationId') || '').trim();

      if (queryConversationId) {
        pendingConversationId = queryConversationId;
        fromQueryParam = true;
      }
    }

    if (!pendingConversationId) {
      return;
    }

    const exists = conversations.some(
      (conversation) => conversation.conversationId === pendingConversationId,
    );

    if (!exists) {
      return;
    }

    try {
      window.localStorage.removeItem(PENDING_NOTIFICATION_CONVERSATION_KEY);
    } catch {
      // Ignore storage errors.
    }

    if (fromQueryParam) {
      const url = new URL(window.location.href);
      url.searchParams.delete('conversationId');
      window.history.replaceState({}, '', `${url.pathname}${url.search}${url.hash}`);
    }

    selectConversation(pendingConversationId).catch(() => {
      // Ignore selection errors.
    });
  }, [conversations, isAuthenticated, selectConversation]);

  const sendTextMessage = useCallback(
    async ({ conversationId, body, replyToMessageId }) => {
      const targetConversationId = conversationId || activeConversationRef.current;

      if (!targetConversationId) {
        throw new Error('No conversation selected');
      }

      const targetConversation = conversationsRef.current.find(
        (conversationItem) => conversationItem.conversationId === targetConversationId,
      );

      if (!targetConversation) {
        throw new Error('Conversation not found');
      }

      if (targetConversation.isBlocked) {
        throw new Error('You cannot send messages in a blocked conversation');
      }

      if (!targetConversation.participantPublicKeyJwk) {
        throw new Error('Recipient encryption key is unavailable');
      }

      const socket = socketRef.current;
      const encryptedPayload = await encryptConversationText({
        userId: user.id,
        peerUserId: targetConversation.participantId,
        peerPublicKeyJwk: targetConversation.participantPublicKeyJwk,
        plaintext: body,
      });

      const effectiveReplyToMessageId =
        replyToMessageId || replyDraftByConversation[targetConversationId]?.id || undefined;

      const payload = {
        conversationId: targetConversationId,
        body: encryptedPayload,
        isEncrypted: true,
        clientId: createClientId(),
        ...(effectiveReplyToMessageId ? { replyToMessageId: effectiveReplyToMessageId } : {}),
      };

      if (socket?.connected) {
        const result = await new Promise((resolve, reject) => {
          socket.emit('message:send', payload, (response) => {
            if (response?.ok) {
              resolve(response.message);
              return;
            }

            reject(new Error(response?.message || 'Message failed to send'));
          });
        });

        clearReplyDraft(targetConversationId);
        return result;
      }

      const response = await api.post(`/messages/${targetConversationId}`, payload);
      clearReplyDraft(targetConversationId);
      return response.data?.message;
    },
    [clearReplyDraft, replyDraftByConversation, user?.id],
  );

  const sendMediaMessage = useCallback(
    async ({ conversationId, file, type, body, voiceDurationMs, replyToMessageId }) => {
      const targetConversationId = conversationId || activeConversationRef.current;

      if (!targetConversationId) {
        throw new Error('No conversation selected');
      }

      const formData = new FormData();
      formData.append('file', file);
      formData.append('clientId', createClientId());

      if (type) {
        formData.append('type', type);
      }

      if (body) {
        formData.append('body', body);
      }

      if (typeof voiceDurationMs === 'number') {
        formData.append('voiceDurationMs', String(voiceDurationMs));
      }

      const effectiveReplyToMessageId =
        replyToMessageId || replyDraftByConversation[targetConversationId]?.id;

      if (effectiveReplyToMessageId) {
        formData.append('replyToMessageId', String(effectiveReplyToMessageId));
      }

      const response = await api.post(`/messages/${targetConversationId}/upload`, formData, {
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      });

      clearReplyDraft(targetConversationId);
      return response.data?.message;
    },
    [clearReplyDraft, replyDraftByConversation],
  );

  const searchUsers = useCallback(
    async (queryText) => {
      const text = String(queryText || '').trim();

      if (!text) {
        setUserSearchResults([]);
        return;
      }

      const response = await api.get('/users', {
        params: {
          query: text,
          limit: 12,
        },
      });

      setUserSearchResults(response.data?.users || []);
    },
    [],
  );

  const createDirectConversation = useCallback(
    async (recipientId) => {
      const response = await api.post('/conversations/direct', { recipientId });
      const conversationId = response.data?.conversation?.id;

      await refreshConversations();

      if (conversationId) {
        await selectConversation(conversationId);
      }
    },
    [refreshConversations, selectConversation],
  );

  const blockUser = useCallback(async (userId) => {
    const response = await api.post(`/users/${userId}/block`);
    const nextBlockedUsers = response.data?.blockedUsers || [];
    setBlockedUsers(nextBlockedUsers);
    await refreshConversations();
  }, [refreshConversations]);

  const unblockUser = useCallback(async (userId) => {
    const response = await api.delete(`/users/${userId}/block`);
    const nextBlockedUsers = response.data?.blockedUsers || [];
    setBlockedUsers(nextBlockedUsers);
    await refreshConversations();
  }, [refreshConversations]);

  const deleteConversation = useCallback(
    async ({ conversationId, scope = 'self' }) => {
      await api.delete(`/conversations/${conversationId}`, {
        params: { scope },
      });

      setMessagesByConversation((previous) => {
        const next = { ...previous };
        delete next[conversationId];
        return next;
      });

      const nextConversations = conversationsRef.current.filter(
        (conversation) => conversation.conversationId !== conversationId,
      );
      setConversations(nextConversations);

      if (activeConversationRef.current === conversationId) {
        setActiveConversationId(null);
      }
    },
    [],
  );

  const setConversationWallpaper = useCallback(
    async ({ conversationId, wallpaperUrl, blurIntensity }) => {
      const response = await api.put(`/conversations/${conversationId}/wallpaper`, {
        wallpaperUrl,
        blurIntensity,
      });
      const settings = response.data?.settings;

      if (!settings) {
        return null;
      }

      setConversations((previous) =>
        previous.map((conversation) =>
          conversation.conversationId === conversationId
            ? {
                ...conversation,
                wallpaperUrl: settings.wallpaperUrl,
                blurIntensity: settings.blurIntensity,
              }
            : conversation,
        ),
      );

      return settings;
    },
    [],
  );

  const uploadConversationWallpaper = useCallback(
    async ({ conversationId, file, blurIntensity = 0 }) => {
      const formData = new FormData();
      formData.append('wallpaper', file);
      formData.append('blurIntensity', String(Number(blurIntensity) || 0));

      const response = await api.post(
        `/conversations/${conversationId}/wallpaper/upload`,
        formData,
        {
          headers: {
            'Content-Type': 'multipart/form-data',
          },
        },
      );
      const settings = response.data?.settings;

      if (!settings) {
        return null;
      }

      setConversations((previous) =>
        previous.map((conversation) =>
          conversation.conversationId === conversationId
            ? {
                ...conversation,
                wallpaperUrl: settings.wallpaperUrl,
                blurIntensity: settings.blurIntensity,
              }
            : conversation,
        ),
      );

      return settings;
    },
    [],
  );

  const resetConversationWallpaper = useCallback(async (conversationId) => {
    await api.delete(`/conversations/${conversationId}/wallpaper`);

    setConversations((previous) =>
      previous.map((conversation) =>
        conversation.conversationId === conversationId
          ? {
              ...conversation,
              wallpaperUrl: null,
              blurIntensity: 0,
            }
          : conversation,
      ),
    );
  }, []);

  const hideMessageLocally = useCallback(({ conversationId, messageId }) => {
    setMessagesByConversation((previous) => ({
      ...previous,
      [conversationId]: (previous[conversationId] || []).filter((message) => message.id !== messageId),
    }));
  }, []);

  const toggleMessageReaction = useCallback(
    async ({ messageId, emoji }) => {
      if (!messageId || !emoji) {
        return null;
      }

      const response = await api.put(`/messages/${messageId}/reaction`, { emoji });
      const update = response.data?.update || null;

      if (update) {
        patchMessageReactions(update);
      }

      return update;
    },
    [patchMessageReactions],
  );

  const emitTypingStart = useCallback((conversationId) => {
    const socket = socketRef.current;

    if (socket?.connected) {
      socket.emit('typing:start', { conversationId });
    }
  }, []);

  const emitTypingStop = useCallback((conversationId) => {
    const socket = socketRef.current;

    if (socket?.connected) {
      socket.emit('typing:stop', { conversationId });
    }
  }, []);

  useEffect(() => {
    if (!isAuthenticated || !user) {
      setConversations([]);
      setMessagesByConversation({});
      setTypingByConversation({});
      setReplyDraftByConversation({});
      setUserSearchResults([]);
      setBlockedUsers([]);
      setActiveConversationId(null);
      setSocketState('offline');
      disconnectSocket();
      socketRef.current = null;
      return;
    }

    refreshConversations();
    refreshBlockedUsers();
  }, [isAuthenticated, refreshBlockedUsers, refreshConversations, user]);

  useEffect(() => {
    if (!isAuthenticated || !user) {
      return;
    }

    const token = getAccessToken();

    if (!token) {
      return;
    }

    const socket = connectSocket(token);
    socketRef.current = socket;

    const handleConnect = () => {
      setSocketState('online');

      conversationsRef.current.forEach((conversation) => {
        socket.emit('conversation:join', {
          conversationId: conversation.conversationId,
        });
      });

      if (activeConversationRef.current) {
        socket.emit('conversation:join', {
          conversationId: activeConversationRef.current,
        });
      }
    };

    const handleDisconnect = () => {
      setSocketState('offline');
    };

    const handlePresenceSnapshot = (payload) => {
      const onlineUserIds = new Set(payload?.onlineUserIds || []);

      setConversations((previous) =>
        previous.map((conversation) => ({
          ...conversation,
          participantIsOnline: onlineUserIds.has(conversation.participantId),
        })),
      );
    };

    const handlePresenceUpdate = (payload) => {
      patchConversationPresence(payload);
    };

    const handleIncomingMessage = (message) => {
      applyMessageToState(message);

      const appVisible =
        typeof document !== 'undefined' &&
        document.visibilityState === 'visible' &&
        (typeof document.hasFocus !== 'function' || document.hasFocus());

      const shouldNotify =
        message.senderId !== user.id && !appVisible;

      if (shouldNotify) {
        showIncomingNotification(message);
      }

      if (
        message.conversationId === activeConversationRef.current &&
        message.recipientId === user.id &&
        !message.seenAt
      ) {
        window.setTimeout(() => {
          markSeen(message.conversationId, [message.id]);
        }, 180);
      }
    };

    const handleDelivered = (update) => {
      patchMessageLifecycle(update, 'deliveredAt');
    };

    const handleSeen = (update) => {
      patchMessageLifecycle(update, 'seenAt');

      setConversations((previous) =>
        previous.map((conversation) =>
          conversation.conversationId === update.conversationId
            ? {
                ...conversation,
                unreadCount: 0,
              }
            : conversation,
        ),
      );
    };

    const handleReaction = (update) => {
      patchMessageReactions(update);
    };

    const handleProfileUpdate = (payload) => {
      patchParticipantProfile(payload);
    };

    const handleTypingStart = (payload) => {
      if (!payload?.conversationId || payload.userId === user.id) {
        return;
      }

      setTypingByConversation((previous) => ({
        ...previous,
        [payload.conversationId]: payload.username || 'Typing...',
      }));

      const timeoutId = window.setTimeout(() => {
        setTypingByConversation((previous) => {
          const next = { ...previous };
          delete next[payload.conversationId];
          return next;
        });
      }, 2200);

      const existing = typingTimeoutsRef.current.get(payload.conversationId);

      if (existing) {
        window.clearTimeout(existing);
      }

      typingTimeoutsRef.current.set(payload.conversationId, timeoutId);
    };

    const handleTypingStop = (payload) => {
      if (!payload?.conversationId) {
        return;
      }

      const existing = typingTimeoutsRef.current.get(payload.conversationId);

      if (existing) {
        window.clearTimeout(existing);
        typingTimeoutsRef.current.delete(payload.conversationId);
      }

      setTypingByConversation((previous) => {
        const next = { ...previous };
        delete next[payload.conversationId];
        return next;
      });
    };

    const handleConversationWallpaper = (payload) => {
      patchConversationWallpaper(payload);
    };

    socket.on('connect', handleConnect);
    socket.on('disconnect', handleDisconnect);
    socket.on('presence:snapshot', handlePresenceSnapshot);
    socket.on('presence:update', handlePresenceUpdate);
    socket.on('message:new', handleIncomingMessage);
    socket.on('message:delivered', handleDelivered);
    socket.on('message:seen', handleSeen);
    socket.on('message:reaction', handleReaction);
    socket.on('profile:update', handleProfileUpdate);
    socket.on('typing:start', handleTypingStart);
    socket.on('typing:stop', handleTypingStop);
    socket.on('conversation:wallpaper', handleConversationWallpaper);

    return () => {
      typingTimeoutsRef.current.forEach((timeoutId) => {
        window.clearTimeout(timeoutId);
      });
      typingTimeoutsRef.current.clear();

      socket.off('connect', handleConnect);
      socket.off('disconnect', handleDisconnect);
      socket.off('presence:snapshot', handlePresenceSnapshot);
      socket.off('presence:update', handlePresenceUpdate);
      socket.off('message:new', handleIncomingMessage);
      socket.off('message:delivered', handleDelivered);
      socket.off('message:seen', handleSeen);
      socket.off('message:reaction', handleReaction);
      socket.off('profile:update', handleProfileUpdate);
      socket.off('typing:start', handleTypingStart);
      socket.off('typing:stop', handleTypingStop);
      socket.off('conversation:wallpaper', handleConversationWallpaper);
      disconnectSocket();
      socketRef.current = null;
      setSocketState('offline');
    };
  }, [
    applyMessageToState,
    isAuthenticated,
    markSeen,
    patchMessageReactions,
    patchParticipantProfile,
    patchConversationPresence,
    patchConversationWallpaper,
    patchMessageLifecycle,
    showIncomingNotification,
    user,
  ]);

  useEffect(() => {
    if (!activeConversationId) {
      return;
    }

    joinConversationRoom(activeConversationId);
  }, [activeConversationId, joinConversationRoom]);

  const activeConversation = useMemo(
    () =>
      conversations.find((conversation) => conversation.conversationId === activeConversationId) || null,
    [activeConversationId, conversations],
  );

  const activeMessages = useMemo(
    () => messagesByConversation[activeConversationId] || [],
    [activeConversationId, messagesByConversation],
  );

  const activeReplyDraft = useMemo(
    () => (activeConversationId ? replyDraftByConversation[activeConversationId] || null : null),
    [activeConversationId, replyDraftByConversation],
  );

  const typingUser = activeConversationId ? typingByConversation[activeConversationId] : null;

  const contextValue = useMemo(
    () => ({
      conversations,
      activeConversationId,
      activeConversation,
      activeMessages,
      typingUser,
      activeReplyDraft,
      userSearchResults,
      blockedUsers,
      notificationPermission,
      notificationSupportHint,
      socketState,
      isLoadingConversations,
      isLoadingMessages,
      selectConversation,
      refreshConversations,
      loadMessages,
      sendTextMessage,
      sendMediaMessage,
      markSeen,
      searchUsers,
      createDirectConversation,
      refreshBlockedUsers,
      blockUser,
      unblockUser,
      deleteConversation,
      setConversationWallpaper,
      uploadConversationWallpaper,
      resetConversationWallpaper,
      hideMessageLocally,
      setReplyDraft,
      clearReplyDraft,
      toggleMessageReaction,
      emitTypingStart,
      emitTypingStop,
      requestNotificationPermission,
      sendNotificationTest,
      refreshNotificationPermission,
    }),
    [
      activeConversation,
      activeConversationId,
      activeMessages,
      blockedUsers,
      blockUser,
      conversations,
      clearReplyDraft,
      createDirectConversation,
      deleteConversation,
      emitTypingStart,
      emitTypingStop,
      notificationPermission,
      notificationSupportHint,
      isLoadingConversations,
      isLoadingMessages,
      loadMessages,
      markSeen,
      refreshNotificationPermission,
      refreshBlockedUsers,
      refreshConversations,
      requestNotificationPermission,
      resetConversationWallpaper,
      sendNotificationTest,
      uploadConversationWallpaper,
      searchUsers,
      selectConversation,
      setConversationWallpaper,
      sendMediaMessage,
      sendTextMessage,
      setReplyDraft,
      socketState,
      toggleMessageReaction,
      typingUser,
      activeReplyDraft,
      unblockUser,
      userSearchResults,
      hideMessageLocally,
    ],
  );

  return <ChatContext.Provider value={contextValue}>{children}</ChatContext.Provider>;
};
