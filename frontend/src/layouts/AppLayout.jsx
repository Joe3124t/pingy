import { useEffect, useMemo, useState } from 'react';
import clsx from 'clsx';
import { ConversationList } from '../components/chat/ConversationList';
import { ChatHeader } from '../components/chat/ChatHeader';
import { MessageList } from '../components/chat/MessageList';
import { MessageComposer } from '../components/chat/MessageComposer';
import { ParticipantInfoSheet } from '../components/chat/ParticipantInfoSheet';
import { useChat } from '../hooks/useChat';
import { useAuth } from '../hooks/useAuth';
import { SettingsPanel } from '../settings/SettingsPanel';

const resolveThemeMode = (mode) => {
  if (mode === 'dark') {
    return 'dark';
  }

  if (mode === 'light') {
    return 'light';
  }

  if (typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches) {
    return 'dark';
  }

  return 'light';
};

export const AppLayout = ({ currentUser, onLogout }) => {
  const {
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
    sendTextMessage,
    sendMediaMessage,
    markSeen,
    searchUsers,
    createDirectConversation,
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
  } = useChat();

  const {
    updateProfile,
    uploadAvatar,
    uploadDefaultWallpaper,
    updatePrivacy,
    updateChatPreferences,
    deleteAccount,
  } = useAuth();

  const [mobileSidebarOpen, setMobileSidebarOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [settingsMode, setSettingsMode] = useState('general');
  const [participantInfoOpen, setParticipantInfoOpen] = useState(false);
  const [themePreviewMode, setThemePreviewMode] = useState(null);
  const [pendingDeleteScope, setPendingDeleteScope] = useState(null);
  const [pendingBlockTarget, setPendingBlockTarget] = useState(null);
  const [resolvedTheme, setResolvedTheme] = useState(() => resolveThemeMode(currentUser?.themeMode));

  useEffect(() => {
    const preferredMode = themePreviewMode || currentUser?.themeMode || 'auto';
    const mediaQuery =
      typeof window !== 'undefined'
        ? window.matchMedia('(prefers-color-scheme: dark)')
        : null;

    const applyTheme = () => {
      const nextTheme = resolveThemeMode(preferredMode);
      setResolvedTheme(nextTheme);
      document.documentElement.dataset.theme = nextTheme;

      const themeMeta = document.querySelector('meta[name="theme-color"]');

      if (themeMeta) {
        themeMeta.setAttribute('content', nextTheme === 'dark' ? '#020617' : '#0e7490');
      }
    };

    applyTheme();

    if (preferredMode !== 'auto' || !mediaQuery) {
      return undefined;
    }

    mediaQuery.addEventListener('change', applyTheme);

    return () => {
      mediaQuery.removeEventListener('change', applyTheme);
    };
  }, [currentUser?.themeMode, themePreviewMode]);

  useEffect(() => {
    setParticipantInfoOpen(false);
  }, [activeConversationId]);

  const openSettings = (mode = 'general') => {
    setSettingsMode(mode);
    setSettingsOpen(true);
  };

  const closeSettings = () => {
    setSettingsOpen(false);
    setThemePreviewMode(null);
  };

  const handleSelectConversation = async (conversationId) => {
    await selectConversation(conversationId);
    setMobileSidebarOpen(false);
  };

  const handleSendFile = async ({ conversationId, file, replyToMessageId }) => {
    await sendMediaMessage({
      conversationId,
      file,
      replyToMessageId,
    });

    await markSeen(conversationId);
  };

  const handleSendVoice = async ({ conversationId, file, durationMs, replyToMessageId }) => {
    await sendMediaMessage({
      conversationId,
      file,
      type: 'voice',
      voiceDurationMs: durationMs,
      replyToMessageId,
    });

    await markSeen(conversationId);
  };

  const hasConversation = Boolean(activeConversationId && activeConversation);

  const wallpaperHint = useMemo(() => {
    if (activeConversation?.wallpaperUrl) {
      return 'custom';
    }

    if (currentUser?.defaultWallpaperUrl) {
      return 'default';
    }

    return 'none';
  }, [activeConversation?.wallpaperUrl, currentUser?.defaultWallpaperUrl]);

  const openDeleteModal = (scope) => {
    setPendingDeleteScope(scope);
  };

  const confirmDeleteConversation = async () => {
    if (!activeConversation || !pendingDeleteScope) {
      return;
    }

    await deleteConversation({
      conversationId: activeConversation.conversationId,
      scope: pendingDeleteScope,
    });

    setPendingDeleteScope(null);
  };

  const handleBlockToggle = (participantId) => {
    if (!participantId || !activeConversation) {
      return;
    }

    const blockedByMe = Boolean(activeConversation.blockedByMe);
    const blockedByParticipant = Boolean(activeConversation.blockedByParticipant);

    if (blockedByParticipant && !blockedByMe) {
      return;
    }

    setPendingBlockTarget({
      userId: participantId,
      username: activeConversation?.participantUsername || 'this user',
      action: blockedByMe ? 'unblock' : 'block',
    });
  };

  const confirmBlockToggle = async () => {
    if (!pendingBlockTarget?.userId) {
      return;
    }

    if (pendingBlockTarget.action === 'unblock') {
      await unblockUser(pendingBlockTarget.userId);
    } else {
      await blockUser(pendingBlockTarget.userId);
    }

    setPendingBlockTarget(null);
  };

  return (
    <div
      className={clsx(
        'relative min-h-screen min-h-[100dvh] overflow-hidden px-0 pt-[env(safe-area-inset-top)] pb-[env(safe-area-inset-bottom)] sm:px-4 sm:py-4',
        resolvedTheme === 'dark' ? 'bg-slate-950' : 'bg-slate-100',
      )}
    >
      <div
        className={clsx(
          'pointer-events-none absolute inset-0 -z-10',
          resolvedTheme === 'dark'
            ? 'bg-[radial-gradient(circle_at_15%_20%,rgba(14,116,144,0.28),transparent_42%),radial-gradient(circle_at_82%_78%,rgba(6,182,212,0.2),transparent_45%),linear-gradient(160deg,#020617,#0f172a,#111827)]'
            : 'bg-[radial-gradient(circle_at_12%_18%,rgba(14,116,144,0.14),transparent_45%),radial-gradient(circle_at_88%_82%,rgba(20,184,166,0.16),transparent_48%),linear-gradient(145deg,#f8fafc,#eef2ff,#ecfeff)]',
        )}
      />

      <div
        className={clsx(
          'pingy-app-shell mx-auto flex w-full max-w-[1600px] overflow-hidden rounded-none border-0 shadow-none backdrop-blur-md sm:rounded-[28px] sm:border sm:shadow-panel',
          resolvedTheme === 'dark'
            ? 'border-slate-800/70 bg-slate-900/70'
            : 'border-slate-200/70 bg-white/65',
        )}
      >
        <div
          className={clsx(
            'absolute inset-y-0 left-0 z-20 w-full max-w-sm transition-transform duration-300 md:relative md:translate-x-0',
            resolvedTheme === 'dark' ? 'bg-slate-900/95' : 'bg-white/95',
            mobileSidebarOpen ? 'translate-x-0' : '-translate-x-[102%]',
          )}
        >
          <ConversationList
            currentUser={currentUser}
            conversations={conversations}
            activeConversationId={activeConversationId}
            onSelectConversation={handleSelectConversation}
            loading={isLoadingConversations}
            searchResults={userSearchResults}
            onSearchUsers={searchUsers}
            onStartConversation={createDirectConversation}
            onOpenProfile={() => {
              setMobileSidebarOpen(false);
              openSettings('profile');
            }}
            isDarkMode={resolvedTheme === 'dark'}
          />

          <div
            className={clsx(
                'border-t px-5 py-4',
                resolvedTheme === 'dark' ? 'border-slate-800 bg-slate-900' : 'border-slate-200 bg-white',
              )}
            >
              <button
                type="button"
                onClick={onLogout}
                className={clsx(
                  'w-full rounded-xl border px-3 py-2 text-sm font-semibold transition',
                  resolvedTheme === 'dark'
                    ? 'border-slate-700 text-slate-300 hover:border-rose-400 hover:bg-rose-950/30 hover:text-rose-200'
                    : 'border-slate-200 text-slate-600 hover:border-rose-300 hover:bg-rose-50 hover:text-rose-700',
                )}
              >
                Log out
              </button>
          </div>
        </div>

        {mobileSidebarOpen ? (
          <button
            type="button"
            onClick={() => setMobileSidebarOpen(false)}
            className="absolute inset-0 z-10 bg-slate-950/30 md:hidden"
            aria-label="Close sidebar"
          />
        ) : null}

        <section className="relative z-0 flex min-w-0 flex-1 flex-col">
          <ChatHeader
            conversation={activeConversation}
            typingUser={typingUser}
            socketState={socketState}
            onOpenSidebar={() => setMobileSidebarOpen(true)}
            onOpenAccountSettings={() => openSettings('general')}
            onOpenChatSettings={() => openSettings('chat')}
            onOpenParticipantInfo={() => setParticipantInfoOpen(true)}
            onBlockUser={handleBlockToggle}
            onUnblockUser={handleBlockToggle}
            onDeleteConversation={openDeleteModal}
            isDarkMode={resolvedTheme === 'dark'}
          />

          {hasConversation ? (
            <>
              <div
                className={clsx(
                  'relative z-10 flex items-center justify-between border-b px-6 py-2 text-xs',
                  resolvedTheme === 'dark'
                    ? 'border-slate-800/70 bg-slate-900/60 text-slate-300'
                    : 'border-slate-200/60 bg-white/70 text-slate-500',
                )}
              >
                <span>Wallpaper: {wallpaperHint}</span>
                <span>E2EE active</span>
              </div>

              <MessageList
                messages={activeMessages}
                currentUserId={currentUser.id}
                typingUser={typingUser}
                loading={isLoadingMessages}
                activeConversation={activeConversation}
                isDarkMode={resolvedTheme === 'dark'}
                defaultWallpaperUrl={currentUser?.defaultWallpaperUrl}
                onReactMessage={toggleMessageReaction}
                onReplyMessage={(message) => {
                  if (!activeConversationId) {
                    return;
                  }

                  setReplyDraft(activeConversationId, message);
                }}
                onDeleteMessage={(message) =>
                  hideMessageLocally({
                    conversationId: activeConversationId,
                    messageId: message.id,
                  })
                }
              />

              <MessageComposer
                conversationId={activeConversationId}
                isBlocked={Boolean(activeConversation?.isBlocked)}
                onSendText={sendTextMessage}
                onSendFile={handleSendFile}
                onSendVoice={handleSendVoice}
                onTypingStart={emitTypingStart}
                onTypingStop={emitTypingStop}
                replyTarget={activeReplyDraft}
                onCancelReply={() => clearReplyDraft(activeConversationId)}
                isDarkMode={resolvedTheme === 'dark'}
              />
            </>
          ) : (
            <div className="flex flex-1 items-center justify-center px-6 text-center">
              <div
                className={clsx(
                  'max-w-sm rounded-3xl border border-dashed px-8 py-8',
                  resolvedTheme === 'dark'
                    ? 'border-slate-700 bg-slate-900/60 text-slate-300'
                    : 'border-slate-300 bg-white/70 text-slate-600',
                )}
              >
                <img src="/pingy-logo-192.png" alt="Pingy" className="mx-auto h-16 w-16 rounded-2xl" />
                <h3
                  className={clsx(
                    'mt-4 font-heading text-2xl font-semibold',
                    resolvedTheme === 'dark' ? 'text-slate-100' : 'text-slate-900',
                  )}
                >
                  No active chat
                </h3>
                <p className="mt-2 text-sm">
                  Search for a user on the left and open a direct conversation to start messaging.
                </p>
                <button
                  type="button"
                  onClick={() => setMobileSidebarOpen(true)}
                  className="mt-5 rounded-xl bg-cyan-700 px-4 py-2 text-sm font-semibold text-white transition hover:bg-cyan-600 md:hidden"
                >
                  Open chats
                </button>
              </div>
            </div>
          )}

          <ParticipantInfoSheet
            open={participantInfoOpen}
            onClose={() => setParticipantInfoOpen(false)}
            conversation={activeConversation}
            isDarkMode={resolvedTheme === 'dark'}
          />

          <SettingsPanel
            open={settingsOpen}
            onClose={closeSettings}
            user={currentUser}
            blockedUsers={blockedUsers}
            onUnblockUser={unblockUser}
            onUpdateProfile={updateProfile}
            onUploadAvatar={uploadAvatar}
            onUploadDefaultWallpaper={uploadDefaultWallpaper}
            onUpdatePrivacy={updatePrivacy}
            onUpdateChat={updateChatPreferences}
            activeConversation={activeConversation}
            onSetConversationWallpaper={setConversationWallpaper}
            onUploadConversationWallpaper={uploadConversationWallpaper}
            onResetConversationWallpaper={resetConversationWallpaper}
            onDeleteAccount={deleteAccount}
            notificationPermission={notificationPermission}
            notificationSupportHint={notificationSupportHint}
            onEnableNotifications={requestNotificationPermission}
            onSendNotificationTest={sendNotificationTest}
            mode={settingsMode}
            isDarkMode={resolvedTheme === 'dark'}
            onPreviewTheme={setThemePreviewMode}
          />

          {pendingDeleteScope ? (
            <div className="absolute inset-0 z-50 flex items-center justify-center bg-slate-950/30 px-4">
              <div className="w-full max-w-md rounded-2xl border border-slate-200 bg-white p-5 shadow-lg">
                <h3 className="font-heading text-xl font-semibold text-slate-900">Delete conversation?</h3>
                <p className="mt-2 text-sm text-slate-600">
                  {pendingDeleteScope === 'both'
                    ? 'This will soft-delete chat history for both users.'
                    : 'This will clear chat history from your account only.'}
                </p>

                <div className="mt-4 flex items-center justify-end gap-2">
                  <button
                    type="button"
                    onClick={() => setPendingDeleteScope(null)}
                    className="rounded-xl border border-slate-200 px-3 py-2 text-sm font-semibold text-slate-700"
                  >
                    Cancel
                  </button>
                  <button
                    type="button"
                    onClick={confirmDeleteConversation}
                    className="rounded-xl bg-rose-600 px-3 py-2 text-sm font-semibold text-white"
                  >
                    Confirm delete
                  </button>
                </div>
              </div>
            </div>
          ) : null}

          {pendingBlockTarget ? (
            <div className="absolute inset-0 z-50 flex items-center justify-center bg-slate-950/30 px-4">
              <div className="w-full max-w-md rounded-2xl border border-slate-200 bg-white p-5 shadow-lg">
                <h3 className="font-heading text-xl font-semibold text-slate-900">
                  {pendingBlockTarget.action === 'unblock' ? 'Unblock user?' : 'Block user?'}
                </h3>
                <p className="mt-2 text-sm text-slate-600">
                  {pendingBlockTarget.action === 'unblock'
                    ? `You will be able to message ${pendingBlockTarget.username} again.`
                    : `You and ${pendingBlockTarget.username} will no longer be able to message each other or view presence.`}
                </p>

                <div className="mt-4 flex items-center justify-end gap-2">
                  <button
                    type="button"
                    onClick={() => setPendingBlockTarget(null)}
                    className="rounded-xl border border-slate-200 px-3 py-2 text-sm font-semibold text-slate-700"
                  >
                    Cancel
                  </button>
                  <button
                    type="button"
                    onClick={confirmBlockToggle}
                    className={clsx(
                      'rounded-xl px-3 py-2 text-sm font-semibold text-white',
                      pendingBlockTarget.action === 'unblock' ? 'bg-cyan-700' : 'bg-rose-600',
                    )}
                  >
                    {pendingBlockTarget.action === 'unblock' ? 'Confirm unblock' : 'Confirm block'}
                  </button>
                </div>
              </div>
            </div>
          ) : null}
        </section>
      </div>
    </div>
  );
};
