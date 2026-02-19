import { useEffect, useRef, useState } from 'react';
import { formatLastSeen } from '../../utils/format';
import { StatusDot } from './StatusDot';
import { resolveMediaUrl } from '../../services/api';

const SettingsIcon = ({ className = 'h-4 w-4' }) => (
  <svg
    viewBox="0 0 24 24"
    className={className}
    fill="none"
    stroke="currentColor"
    strokeWidth="1.8"
    strokeLinecap="round"
    strokeLinejoin="round"
    aria-hidden="true"
  >
    <circle cx="12" cy="12" r="3.2" />
    <path d="M19.4 15a1 1 0 0 0 .2 1.1l.1.1a2 2 0 0 1 0 2.8 2 2 0 0 1-2.8 0l-.1-.1a1 1 0 0 0-1.1-.2 1 1 0 0 0-.6.9V20a2 2 0 0 1-4 0v-.2a1 1 0 0 0-.6-.9 1 1 0 0 0-1.1.2l-.1.1a2 2 0 0 1-2.8 0 2 2 0 0 1 0-2.8l.1-.1A1 1 0 0 0 6 15a1 1 0 0 0-.9-.6H5a2 2 0 0 1 0-4h.2a1 1 0 0 0 .9-.6 1 1 0 0 0-.2-1.1l-.1-.1a2 2 0 0 1 0-2.8 2 2 0 0 1 2.8 0l.1.1a1 1 0 0 0 1.1.2h.1a1 1 0 0 0 .6-.9V4a2 2 0 0 1 4 0v.2a1 1 0 0 0 .6.9 1 1 0 0 0 1.1-.2l.1-.1a2 2 0 0 1 2.8 0 2 2 0 0 1 0 2.8l-.1.1a1 1 0 0 0-.2 1.1v.1a1 1 0 0 0 .9.6H20a2 2 0 0 1 0 4h-.2a1 1 0 0 0-.9.6z" />
  </svg>
);

const HeaderAvatar = ({ username, avatarUrl }) => {
  const [hasError, setHasError] = useState(false);
  const resolvedAvatar = avatarUrl && !hasError ? resolveMediaUrl(avatarUrl) : null;
  const initial = username?.charAt(0)?.toUpperCase() || '?';

  if (resolvedAvatar) {
    return (
      <img
        src={resolvedAvatar}
        alt={username || 'Avatar'}
        className="h-12 w-12 rounded-2xl object-cover"
        onError={() => setHasError(true)}
      />
    );
  }

  return (
    <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-br from-cyan-600 to-sky-500 font-heading text-sm font-semibold text-white">
      {initial}
    </div>
  );
};

export const ChatHeader = ({
  conversation,
  typingUser,
  socketState,
  onOpenSidebar,
  onOpenAccountSettings,
  onOpenChatSettings,
  onOpenParticipantInfo,
  onBlockUser,
  onUnblockUser,
  onDeleteConversation,
  isDarkMode = false,
}) => {
  const [menuOpen, setMenuOpen] = useState(false);
  const menuContainerRef = useRef(null);
  const blockedByMe = Boolean(conversation?.blockedByMe);
  const blockedByParticipant = Boolean(conversation?.blockedByParticipant);

  useEffect(() => {
    if (!menuOpen) {
      return undefined;
    }

    const handleOutsidePress = (event) => {
      if (!menuContainerRef.current?.contains(event.target)) {
        setMenuOpen(false);
      }
    };

    document.addEventListener('mousedown', handleOutsidePress);
    document.addEventListener('touchstart', handleOutsidePress);

    return () => {
      document.removeEventListener('mousedown', handleOutsidePress);
      document.removeEventListener('touchstart', handleOutsidePress);
    };
  }, [menuOpen]);

  if (!conversation) {
    return (
      <header
        className={`relative z-30 flex min-h-20 items-center justify-between gap-3 border-b px-4 py-3 backdrop-blur-sm sm:px-6 ${
          isDarkMode ? 'border-slate-800/80 bg-slate-900/85' : 'border-slate-200/80 bg-white/85'
        }`}
      >
        <div className="flex min-w-0 items-center gap-3">
          <img src="/pingy-logo-192.png" alt="Pingy" className="h-9 w-9 rounded-xl sm:h-10 sm:w-10" />
          <div className="min-w-0">
            <h2
              className={`truncate font-heading text-lg font-semibold sm:text-xl ${
                isDarkMode ? 'text-slate-100' : 'text-slate-900'
              }`}
            >
              Select a conversation
            </h2>
            <p className={`hidden text-xs sm:block sm:text-sm ${isDarkMode ? 'text-slate-400' : 'text-slate-500'}`}>
              Choose a chat from the sidebar to begin messaging.
            </p>
          </div>
        </div>

        <button
          type="button"
          onClick={onOpenSidebar}
          className={`rounded-xl border px-3 py-2 text-sm font-semibold transition md:hidden ${
            isDarkMode
              ? 'border-slate-700 text-slate-300 hover:border-slate-500 hover:text-slate-100'
              : 'border-slate-200 text-slate-600 hover:border-slate-300 hover:text-slate-900'
          }`}
        >
          Chats
        </button>
      </header>
    );
  }

  const statusText = typingUser
    ? `${typingUser} is typing...`
    : conversation.participantIsOnline
      ? 'Online'
      : formatLastSeen(conversation.participantLastSeen);

  return (
    <header
      className={`relative z-30 flex h-20 items-center justify-between border-b px-3 backdrop-blur-sm sm:px-6 ${
        isDarkMode ? 'border-slate-800/80 bg-slate-900/85' : 'border-slate-200/80 bg-white/85'
      }`}
    >
      <div className="flex min-w-0 items-center gap-2 sm:gap-3">
        <button
          type="button"
          onClick={onOpenSidebar}
          className={`rounded-xl border px-3 py-2 text-sm font-semibold transition md:hidden ${
            isDarkMode
              ? 'border-slate-700 text-slate-300 hover:border-slate-500 hover:text-slate-100'
              : 'border-slate-200 text-slate-600 hover:border-slate-300 hover:text-slate-900'
          }`}
        >
          Chats
        </button>

        <img src="/pingy-logo-192.png" alt="Pingy" className="hidden h-10 w-10 rounded-xl sm:block" />

        <button
          type="button"
          onClick={onOpenParticipantInfo}
          className={`flex min-w-0 items-center gap-2 rounded-xl px-1 py-1 text-left transition sm:gap-3 ${
            isDarkMode ? 'hover:bg-slate-800/70' : 'hover:bg-slate-100/80'
          }`}
          aria-label="Open contact info"
        >
          <HeaderAvatar username={conversation.participantUsername} avatarUrl={conversation.participantAvatarUrl} />

          <div className="min-w-0">
            <p className={`truncate font-heading text-lg font-semibold ${isDarkMode ? 'text-slate-100' : 'text-slate-900'}`}>
              {conversation.participantUsername}
            </p>
            <p className={`flex items-center gap-2 text-xs ${isDarkMode ? 'text-slate-400' : 'text-slate-500'}`}>
              <StatusDot online={conversation.participantIsOnline} />
              <span>{statusText}</span>
            </p>
          </div>
        </button>
      </div>

      <div className="flex items-center gap-2">
        <p
          className={`hidden rounded-full border px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] sm:block ${
            isDarkMode
              ? 'border-slate-700 bg-slate-800 text-slate-300'
              : 'border-slate-200 bg-white text-slate-500'
          }`}
        >
          Socket {socketState}
        </p>

        <button
          type="button"
          onClick={onOpenChatSettings}
          className={`inline-flex items-center gap-1.5 rounded-xl border px-2.5 py-2 text-xs font-semibold transition sm:px-3 sm:text-sm ${
            isDarkMode
              ? 'border-slate-700 text-slate-300 hover:border-slate-500 hover:text-slate-100'
              : 'border-slate-200 text-slate-600 hover:border-slate-300 hover:text-slate-900'
          }`}
          aria-label="Open chat settings"
          title="Chat settings"
        >
          <SettingsIcon className="h-4 w-4" />
          <span className="hidden sm:inline">Chat settings</span>
        </button>

        <div className="relative" ref={menuContainerRef}>
          <button
            type="button"
            onClick={() => setMenuOpen((current) => !current)}
            className={`rounded-xl border px-3 py-2 text-sm font-semibold transition ${
              isDarkMode
                ? 'border-slate-700 text-slate-300 hover:border-slate-500 hover:text-slate-100'
                : 'border-slate-200 text-slate-600 hover:border-slate-300 hover:text-slate-900'
            }`}
          >
            Menu
          </button>

          {menuOpen ? (
            <div
              className={`absolute right-0 top-full z-[90] mt-2 w-56 rounded-xl border p-1 shadow-2xl ${
                isDarkMode ? 'border-slate-700 bg-slate-900' : 'border-slate-200 bg-white'
              }`}
            >
              <button
                type="button"
                onClick={() => {
                  setMenuOpen(false);
                  onOpenAccountSettings?.();
                }}
                className={`block w-full rounded-lg px-3 py-2 text-left text-sm transition ${
                  isDarkMode
                    ? 'text-slate-200 hover:bg-slate-800'
                    : 'text-slate-700 hover:bg-slate-100'
                }`}
              >
                Account settings
              </button>

              <button
                type="button"
                onClick={() => {
                  setMenuOpen(false);
                  if (blockedByParticipant && !blockedByMe) {
                    return;
                  }

                  if (blockedByMe) {
                    onUnblockUser?.(conversation.participantId);
                  } else {
                    onBlockUser?.(conversation.participantId);
                  }
                }}
                disabled={blockedByParticipant && !blockedByMe}
                className={`block w-full rounded-lg px-3 py-2 text-left text-sm transition ${
                  blockedByParticipant && !blockedByMe
                    ? isDarkMode
                      ? 'cursor-not-allowed text-slate-500'
                      : 'cursor-not-allowed text-slate-400'
                    : isDarkMode
                    ? 'text-slate-200 hover:bg-slate-800'
                    : 'text-slate-700 hover:bg-slate-100'
                }`}
              >
                {blockedByParticipant && !blockedByMe
                  ? 'You are blocked'
                  : blockedByMe
                    ? 'Unblock user'
                    : 'Block user'}
              </button>

              <button
                type="button"
                onClick={() => {
                  setMenuOpen(false);
                  onDeleteConversation?.('self');
                }}
                className={`block w-full rounded-lg px-3 py-2 text-left text-sm transition ${
                  isDarkMode
                    ? 'text-slate-200 hover:bg-slate-800'
                    : 'text-slate-700 hover:bg-slate-100'
                }`}
              >
                Delete chat for me
              </button>

              <button
                type="button"
                onClick={() => {
                  setMenuOpen(false);
                  onDeleteConversation?.('both');
                }}
                className="block w-full rounded-lg px-3 py-2 text-left text-sm text-rose-600 transition hover:bg-rose-50"
              >
                Delete chat for both
              </button>
            </div>
          ) : null}
        </div>
      </div>
    </header>
  );
};
