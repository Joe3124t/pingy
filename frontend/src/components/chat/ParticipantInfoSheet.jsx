import { useState } from 'react';
import { formatLastSeen } from '../../utils/format';
import { resolveMediaUrl } from '../../services/api';
import { StatusDot } from './StatusDot';

const ContactAvatar = ({ username, avatarUrl }) => {
  const [hasError, setHasError] = useState(false);
  const resolvedAvatar = avatarUrl && !hasError ? resolveMediaUrl(avatarUrl) : null;
  const initial = username?.charAt(0)?.toUpperCase() || '?';

  if (resolvedAvatar) {
    return (
      <img
        src={resolvedAvatar}
        alt={username || 'Avatar'}
        className="h-20 w-20 rounded-3xl object-cover"
        onError={() => setHasError(true)}
      />
    );
  }

  return (
    <div className="flex h-20 w-20 items-center justify-center rounded-3xl bg-gradient-to-br from-cyan-600 to-sky-500 font-heading text-2xl font-bold text-white">
      {initial}
    </div>
  );
};

export const ParticipantInfoSheet = ({
  open,
  onClose,
  conversation,
  isDarkMode = false,
}) => {
  if (!open || !conversation) {
    return null;
  }

  const statusText = conversation.participantIsOnline
    ? 'Online now'
    : formatLastSeen(conversation.participantLastSeen);

  const cardTone = isDarkMode
    ? 'border-slate-800 bg-slate-950 text-slate-100'
    : 'border-slate-200 bg-white text-slate-900';
  const rowTone = isDarkMode
    ? 'border-slate-800 bg-slate-900/70 text-slate-200'
    : 'border-slate-200 bg-slate-50 text-slate-700';
  const subtleText = isDarkMode ? 'text-slate-400' : 'text-slate-500';

  return (
    <div className="absolute inset-0 z-50 flex justify-end bg-slate-950/40">
      <section className={`h-full w-full max-w-md overflow-y-auto border-l p-5 sm:p-6 ${cardTone}`}>
        <div className="flex items-center justify-between">
          <h2 className="font-heading text-2xl font-semibold">Contact info</h2>
          <button
            type="button"
            onClick={onClose}
            className={`rounded-xl border px-3 py-2 text-sm font-semibold transition ${
              isDarkMode
                ? 'border-slate-700 text-slate-300 hover:border-slate-500 hover:text-slate-100'
                : 'border-slate-200 text-slate-600 hover:border-slate-300 hover:text-slate-900'
            }`}
          >
            Close
          </button>
        </div>

        <div className="mt-6 flex items-center gap-4">
          <ContactAvatar
            username={conversation.participantUsername}
            avatarUrl={conversation.participantAvatarUrl}
          />

          <div className="min-w-0">
            <p className="truncate font-heading text-2xl font-semibold">
              {conversation.participantUsername}
            </p>
            <p className={`mt-1 flex items-center gap-2 text-sm ${subtleText}`}>
              <StatusDot online={conversation.participantIsOnline} />
              <span>{statusText}</span>
            </p>
          </div>
        </div>

        <div className="mt-6 space-y-3">
          <div className={`rounded-2xl border px-4 py-3 ${rowTone}`}>
            <p className={`text-xs uppercase tracking-[0.16em] ${subtleText}`}>Username</p>
            <p className="mt-1 break-all text-sm font-semibold">{conversation.participantUsername}</p>
          </div>

          <div className={`rounded-2xl border px-4 py-3 ${rowTone}`}>
            <p className={`text-xs uppercase tracking-[0.16em] ${subtleText}`}>Presence</p>
            <p className="mt-1 text-sm font-medium">{statusText}</p>
          </div>

          <div className={`rounded-2xl border px-4 py-3 ${rowTone}`}>
            <p className={`text-xs uppercase tracking-[0.16em] ${subtleText}`}>Encryption</p>
            <p className="mt-1 text-sm font-medium">End-to-end encryption is active</p>
          </div>

          <div className={`rounded-2xl border px-4 py-3 ${rowTone}`}>
            <p className={`text-xs uppercase tracking-[0.16em] ${subtleText}`}>Conversation status</p>
            <p className="mt-1 text-sm font-medium">
              {conversation.isBlocked ? 'This conversation is blocked' : 'Messaging is available'}
            </p>
          </div>
        </div>
      </section>
    </div>
  );
};
