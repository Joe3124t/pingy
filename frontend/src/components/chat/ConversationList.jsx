import { useEffect, useMemo, useState } from 'react';
import { buildConversationPreview, formatMessageTime } from '../../utils/format';
import { useDebouncedValue } from '../../hooks/useDebouncedValue';
import { StatusDot } from './StatusDot';
import { resolveMediaUrl } from '../../services/api';

const Avatar = ({ name, avatarUrl }) => {
  const initial = (name || '?').trim().charAt(0).toUpperCase();

  if (avatarUrl) {
    return (
      <img
        src={resolveMediaUrl(avatarUrl)}
        alt={name || 'Avatar'}
        className="h-11 w-11 rounded-2xl object-cover"
        loading="lazy"
      />
    );
  }

  return (
    <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-gradient-to-br from-cyan-600 to-sky-500 font-heading text-sm font-semibold text-white">
      {initial}
    </div>
  );
};

export const ConversationList = ({
  conversations,
  activeConversationId,
  onSelectConversation,
  loading,
  searchResults,
  onSearchUsers,
  onStartConversation,
  currentUser,
  onOpenProfile,
  isDarkMode = false,
}) => {
  const [query, setQuery] = useState('');
  const debouncedQuery = useDebouncedValue(query, 250);

  useEffect(() => {
    onSearchUsers(debouncedQuery);
  }, [debouncedQuery, onSearchUsers]);

  const filteredConversations = useMemo(() => {
    if (!query.trim()) {
      return conversations;
    }

    const keyword = query.trim().toLowerCase();

    return conversations.filter((conversation) => {
      const participantName = conversation.participantUsername?.toLowerCase() || '';
      const preview = buildConversationPreview(conversation).toLowerCase();
      return participantName.includes(keyword) || preview.includes(keyword);
    });
  }, [conversations, query]);

  const showUserSearch = query.trim().length > 0;

  return (
    <aside
      className={`flex h-full flex-col border-r backdrop-blur-md ${
        isDarkMode ? 'border-slate-800/80 bg-slate-900/85' : 'border-slate-200/80 bg-white/85'
      }`}
    >
      <div
        className={`border-b px-5 pb-5 pt-6 ${
          isDarkMode ? 'border-slate-800/80' : 'border-slate-200/80'
        }`}
      >
        <div className="flex items-center gap-2">
          <img src="/pingy-logo-192.png" alt="Pingy" className="h-7 w-7 rounded-lg" />
          <p className="font-heading text-xs uppercase tracking-[0.25em] text-cyan-700">
            Pingy Workspace
          </p>
        </div>

        <button
          type="button"
          onClick={onOpenProfile}
          className={`mt-4 flex w-full items-center gap-3 rounded-2xl px-2 py-2 text-left transition ${
            isDarkMode ? 'hover:bg-slate-800/80' : 'hover:bg-slate-100'
          }`}
        >
          <Avatar name={currentUser?.username} avatarUrl={currentUser?.avatarUrl} />
          <div className="min-w-0">
            <p className={`truncate text-sm font-bold ${isDarkMode ? 'text-slate-100' : 'text-slate-900'}`}>
              {currentUser?.username}
            </p>
            <p className={`truncate text-xs ${isDarkMode ? 'text-slate-400' : 'text-slate-500'}`}>
              {currentUser?.email}
            </p>
          </div>
        </button>

        <label className="relative mt-5 block">
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search chats or start a new one"
            className={`w-full rounded-2xl border px-4 py-3 pr-10 text-sm outline-none transition focus:border-cyan-500 focus:ring-2 focus:ring-cyan-200 ${
              isDarkMode
                ? 'border-slate-700 bg-slate-800 text-slate-100 placeholder:text-slate-500 focus:bg-slate-800'
                : 'border-slate-200 bg-slate-50 text-slate-800 focus:bg-white'
            }`}
          />
          <span
            className={`pointer-events-none absolute right-4 top-1/2 -translate-y-1/2 ${
              isDarkMode ? 'text-slate-500' : 'text-slate-400'
            }`}
          >
            <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="2">
              <circle cx="11" cy="11" r="7" />
              <path d="m20 20-3.5-3.5" strokeLinecap="round" />
            </svg>
          </span>
        </label>
      </div>

      <div className="flex-1 overflow-y-auto px-3 pb-3 pt-4">
        {showUserSearch ? (
          <section className="mb-4">
            <p className={`px-3 text-xs font-semibold uppercase tracking-[0.2em] ${isDarkMode ? 'text-slate-500' : 'text-slate-400'}`}>
              People
            </p>
            <div className="mt-2 space-y-1">
              {searchResults.length === 0 ? (
                <p className={`px-3 py-2 text-xs ${isDarkMode ? 'text-slate-500' : 'text-slate-400'}`}>
                  No matching users
                </p>
              ) : (
                searchResults.map((person) => (
                  <button
                    key={person.id}
                    type="button"
                    onClick={() => onStartConversation(person.id)}
                    className={`flex w-full items-center gap-3 rounded-xl px-3 py-2 text-left transition ${
                      isDarkMode ? 'hover:bg-slate-800' : 'hover:bg-cyan-50'
                    }`}
                  >
                    <Avatar name={person.username} avatarUrl={person.avatarUrl} />
                    <div className="min-w-0">
                      <p className={`truncate text-sm font-semibold ${isDarkMode ? 'text-slate-100' : 'text-slate-900'}`}>
                        {person.username}
                      </p>
                      <p className={`truncate text-xs ${isDarkMode ? 'text-slate-400' : 'text-slate-500'}`}>
                        {person.email}
                      </p>
                    </div>
                  </button>
                ))
              )}
            </div>
          </section>
        ) : null}

        <section>
          <p className={`px-3 text-xs font-semibold uppercase tracking-[0.2em] ${isDarkMode ? 'text-slate-500' : 'text-slate-400'}`}>
            Conversations
          </p>
          <div className="mt-2 space-y-1">
            {loading ? (
              <p className={`px-3 py-2 text-sm ${isDarkMode ? 'text-slate-500' : 'text-slate-400'}`}>
                Loading conversations...
              </p>
            ) : filteredConversations.length === 0 ? (
              <p className={`px-3 py-2 text-sm ${isDarkMode ? 'text-slate-500' : 'text-slate-400'}`}>
                No conversations yet.
              </p>
            ) : (
              filteredConversations.map((conversation) => {
                const isActive = conversation.conversationId === activeConversationId;
                const preview = buildConversationPreview(conversation);

                return (
                  <button
                    key={conversation.conversationId}
                    type="button"
                    onClick={() => onSelectConversation(conversation.conversationId)}
                    className={`group flex w-full items-start gap-3 rounded-2xl px-3 py-3 text-left transition ${
                      isActive
                        ? 'bg-gradient-to-r from-cyan-600 to-sky-500 text-white shadow-md'
                        : isDarkMode
                          ? 'hover:bg-slate-800/80'
                          : 'hover:bg-slate-100/80'
                    }`}
                  >
                    <div className="relative mt-0.5">
                      <Avatar
                        name={conversation.participantUsername}
                        avatarUrl={conversation.participantAvatarUrl}
                      />
                      <span className="absolute -bottom-0.5 -right-0.5">
                        <StatusDot online={conversation.participantIsOnline} />
                      </span>
                    </div>

                    <div className="min-w-0 flex-1">
                      <div className="flex items-center justify-between gap-2">
                        <p
                          className={`truncate text-sm font-semibold ${
                            isActive ? 'text-white' : isDarkMode ? 'text-slate-100' : 'text-slate-900'
                          }`}
                        >
                          {conversation.participantUsername}
                        </p>
                        <p
                          className={`text-[11px] ${
                            isActive ? 'text-cyan-100' : isDarkMode ? 'text-slate-500' : 'text-slate-400'
                          }`}
                        >
                          {formatMessageTime(conversation.lastMessageCreatedAt || conversation.lastMessageAt)}
                        </p>
                      </div>

                      <p
                        className={`mt-1 truncate text-xs ${
                          isActive
                            ? 'text-cyan-100'
                            : isDarkMode
                              ? 'text-slate-400 group-hover:text-slate-300'
                              : 'text-slate-500 group-hover:text-slate-600'
                        }`}
                      >
                        {preview}
                      </p>

                      {conversation.isBlocked ? (
                        <p
                          className={`mt-1 text-[11px] font-semibold ${
                            isActive ? 'text-amber-100' : 'text-amber-600'
                          }`}
                        >
                          Blocked
                        </p>
                      ) : null}
                    </div>

                    {conversation.unreadCount > 0 ? (
                      <span
                        className={`ml-1 inline-flex min-w-6 items-center justify-center rounded-full px-1.5 py-0.5 text-xs font-semibold ${
                          isActive ? 'bg-white/20 text-white' : 'bg-cyan-600 text-white'
                        }`}
                      >
                        {conversation.unreadCount}
                      </span>
                    ) : null}
                  </button>
                );
              })
            )}
          </div>
        </section>
      </div>
    </aside>
  );
};
