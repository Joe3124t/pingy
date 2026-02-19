import { useEffect, useMemo, useState } from 'react';
import clsx from 'clsx';
import { resolveMediaUrl } from '../../services/api';
import { formatBytes, formatMessageTime } from '../../utils/format';
import { VoiceMessagePlayer } from './VoiceMessagePlayer';
import { decryptConversationText } from '../../encryption/e2eeService';

const CheckIcon = ({ colorClass }) => (
  <svg viewBox="0 0 16 16" className={clsx('h-3.5 w-3.5', colorClass)} fill="none">
    <path d="M3.2 8.5L6.1 11.4L12.7 4.8" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

const MessageTicks = ({ message }) => {
  if (message.seenAt) {
    return (
      <span className="inline-flex items-center">
        <CheckIcon colorClass="text-cyan-200" />
        <CheckIcon colorClass="-ml-1.5 text-cyan-200" />
      </span>
    );
  }

  if (message.deliveredAt) {
    return (
      <span className="inline-flex items-center">
        <CheckIcon colorClass="text-slate-300" />
        <CheckIcon colorClass="-ml-1.5 text-slate-300" />
      </span>
    );
  }

  return <CheckIcon colorClass="text-slate-300" />;
};

const REACTION_OPTIONS = ['\u{1F44D}', '\u{2764}\u{FE0F}', '\u{1F602}', '\u{1F62E}', '\u{1F622}', '\u{1F525}'];

const FileCard = ({ message, own }) => {
  const href = resolveMediaUrl(message.mediaUrl);

  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer"
      className={clsx(
        'flex max-w-xs items-center gap-3 rounded-xl border px-3 py-2 text-sm transition hover:opacity-90',
        own ? 'border-cyan-300/40 bg-cyan-500/25 text-cyan-50' : 'border-slate-200 bg-slate-50 text-slate-700',
      )}
    >
      <span className={clsx('rounded-lg px-2 py-1 text-[10px] font-semibold uppercase', own ? 'bg-white/15' : 'bg-slate-200')}>
        FILE
      </span>
      <span className="min-w-0 flex-1">
        <span className="block truncate font-semibold">{message.mediaName || 'Attachment'}</span>
        <span className={clsx('block text-xs', own ? 'text-cyan-100' : 'text-slate-500')}>
          {formatBytes(Number(message.mediaSize || 0))}
        </span>
      </span>
    </a>
  );
};

const ActionButton = ({ onClick, children }) => (
  <button
    type="button"
    onClick={onClick}
    className="rounded-lg bg-slate-900/80 px-2 py-1 text-[11px] font-semibold text-white transition hover:bg-slate-900"
  >
    {children}
  </button>
);

const buildReplyPreviewText = (replyTo) => {
  if (!replyTo) {
    return '';
  }

  if (replyTo.type === 'text') {
    if (!replyTo.isEncrypted && typeof replyTo.body === 'string' && replyTo.body.trim()) {
      return replyTo.body.trim().slice(0, 120);
    }

    return 'Message';
  }

  if (replyTo.type === 'image') {
    return 'Image';
  }

  if (replyTo.type === 'video') {
    return 'Video';
  }

  if (replyTo.type === 'voice') {
    return 'Voice message';
  }

  return replyTo.mediaName || 'File';
};

export const MessageBubble = ({
  message,
  own,
  currentUserId,
  peerUserId,
  peerPublicKeyJwk,
  onDeleteMessage,
  onReactMessage,
  onReplyMessage,
}) => {
  const [decryptedBody, setDecryptedBody] = useState('');
  const [decryptionFallback, setDecryptionFallback] = useState('');
  const [showReactionPicker, setShowReactionPicker] = useState(false);
  const [reactionBusyEmoji, setReactionBusyEmoji] = useState('');

  const mediaUrl = resolveMediaUrl(message.mediaUrl);

  useEffect(() => {
    let isCancelled = false;

    const decrypt = async () => {
      if (!(message.type === 'text' && message.isEncrypted)) {
        setDecryptedBody(typeof message.body === 'string' ? message.body : '');
        setDecryptionFallback('');
        return;
      }

      if (!peerPublicKeyJwk || !currentUserId || !peerUserId) {
        setDecryptedBody('');
        setDecryptionFallback('Message');
        return;
      }

      try {
        const plaintext = await decryptConversationText({
          userId: currentUserId,
          peerUserId,
          peerPublicKeyJwk,
          payload: message.body,
        });

        if (!isCancelled) {
          setDecryptedBody(plaintext);
          setDecryptionFallback('');
        }
      } catch {
        if (!isCancelled) {
          setDecryptedBody('');
          if (typeof message.body === 'string') {
            try {
              const parsed = JSON.parse(message.body);
              setDecryptionFallback(typeof parsed === 'string' ? parsed : 'Message');
            } catch {
              setDecryptionFallback(message.body || 'Message');
            }
          } else {
            setDecryptionFallback('Message');
          }
        }
      }
    };

    decrypt();

    return () => {
      isCancelled = true;
    };
  }, [currentUserId, message.body, message.isEncrypted, message.type, peerPublicKeyJwk, peerUserId]);

  const textBody = useMemo(() => {
    if (message.type !== 'text') {
      return message.body || '';
    }

    if (message.isEncrypted) {
      return decryptedBody || decryptionFallback || '';
    }

    return message.body || '';
  }, [decryptedBody, decryptionFallback, message.body, message.isEncrypted, message.type]);

  const copyMessage = async () => {
    if (!textBody) {
      return;
    }

    try {
      await navigator.clipboard.writeText(textBody);
    } catch {
      // Ignore clipboard errors.
    }
  };

  const reactions = Array.isArray(message.reactions) ? message.reactions : [];
  const replyPreviewText = buildReplyPreviewText(message.replyTo);

  const handleReactionToggle = async (emoji) => {
    if (!onReactMessage || !emoji || reactionBusyEmoji) {
      return;
    }

    try {
      setReactionBusyEmoji(emoji);
      await onReactMessage({
        messageId: message.id,
        emoji,
      });
      setShowReactionPicker(false);
    } catch {
      // Ignore reaction errors in UI.
    } finally {
      setReactionBusyEmoji('');
    }
  };

  return (
    <article className={clsx('group flex w-full', own ? 'justify-end' : 'justify-start')}>
      <div className={clsx('relative max-w-[82%] sm:max-w-[72%]', own ? 'items-end' : 'items-start')}>
        <div className="pointer-events-none absolute -top-8 left-0 right-0 flex justify-end gap-1 opacity-0 transition group-hover:pointer-events-auto group-hover:opacity-100">
          <ActionButton onClick={() => onReplyMessage?.(message)}>Reply</ActionButton>
          <ActionButton onClick={() => setShowReactionPicker((current) => !current)}>React</ActionButton>
          <ActionButton onClick={copyMessage}>Copy</ActionButton>
          {own ? <ActionButton onClick={() => onDeleteMessage?.(message)}>Delete</ActionButton> : null}
        </div>

        {showReactionPicker ? (
          <div
            className={clsx(
              'absolute -top-12 z-20 flex items-center gap-1 rounded-full border px-2 py-1 shadow-lg',
              own ? 'right-0' : 'left-0',
              own ? 'border-cyan-400/30 bg-cyan-950/95' : 'border-slate-200 bg-white/95',
            )}
          >
            {REACTION_OPTIONS.map((emoji) => (
              <button
                key={emoji}
                type="button"
                onClick={() => handleReactionToggle(emoji)}
                disabled={Boolean(reactionBusyEmoji)}
                className={clsx(
                  'inline-flex h-7 w-7 items-center justify-center rounded-full text-sm transition',
                  reactionBusyEmoji === emoji
                    ? 'scale-95 opacity-70'
                    : own
                      ? 'hover:bg-cyan-800/70'
                      : 'hover:bg-slate-100',
                )}
              >
                {emoji}
              </button>
            ))}
          </div>
        ) : null}

        <div
          className={clsx(
            'rounded-[22px] px-4 py-3 shadow-sm',
            own
              ? 'rounded-br-sm bg-gradient-to-br from-cyan-700 to-sky-600 text-white'
              : 'rounded-bl-sm border border-slate-200 bg-white text-slate-800',
          )}
        >
          {message.replyTo ? (
            <div
              className={clsx(
                'mb-2 rounded-xl border-l-4 px-3 py-2 text-xs',
                own
                  ? 'border-cyan-200/80 bg-cyan-800/45 text-cyan-50'
                  : 'border-cyan-500/70 bg-cyan-50 text-cyan-700',
              )}
            >
              <p className="font-semibold">
                {message.replyTo.senderUsername || (message.replyTo.senderId === currentUserId ? 'You' : 'Message')}
              </p>
              <p className="truncate">{replyPreviewText}</p>
            </div>
          ) : null}

          {message.type === 'image' ? (
            <a href={mediaUrl} target="_blank" rel="noreferrer" className="block overflow-hidden rounded-xl">
              <img src={mediaUrl} alt={message.mediaName || 'Image attachment'} className="max-h-72 w-full object-cover" loading="lazy" />
            </a>
          ) : null}

          {message.type === 'video' ? (
            <video controls className="max-h-72 w-full rounded-xl border border-slate-200/30">
              <source src={mediaUrl} type={message.mediaMime || 'video/mp4'} />
            </video>
          ) : null}

          {message.type === 'file' ? <FileCard message={message} own={own} /> : null}

          {message.type === 'voice' ? <VoiceMessagePlayer message={message} compact /> : null}

          {textBody ? (
            <p
              className={clsx(
                'whitespace-pre-wrap break-words text-sm leading-relaxed',
                message.type !== 'text' ? 'mt-2' : '',
                own ? 'text-white' : 'text-slate-800',
              )}
            >
              {textBody}
            </p>
          ) : null}

          {reactions.length > 0 ? (
            <div className="mt-2 flex flex-wrap justify-end gap-1">
              {reactions.map((reaction) => (
                <button
                  key={reaction.emoji}
                  type="button"
                  onClick={() => handleReactionToggle(reaction.emoji)}
                  className={clsx(
                    'inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-semibold transition',
                    reaction.reactedByMe
                      ? own
                        ? 'border-cyan-200/70 bg-white/20 text-white'
                        : 'border-cyan-300 bg-cyan-50 text-cyan-700'
                      : own
                        ? 'border-cyan-300/40 bg-cyan-500/20 text-cyan-100'
                        : 'border-slate-200 bg-slate-50 text-slate-600',
                  )}
                >
                  <span>{reaction.emoji}</span>
                  <span>{reaction.count}</span>
                </button>
              ))}
            </div>
          ) : null}

          <div className={clsx('mt-2 flex items-center justify-end gap-1 text-[11px]', own ? 'text-cyan-100' : 'text-slate-400')}>
            <span>{formatMessageTime(message.createdAt)}</span>
            {own ? <MessageTicks message={message} /> : null}
            <button
              type="button"
              onClick={() => setShowReactionPicker((current) => !current)}
              className={clsx(
                'ml-1 inline-flex h-5 w-5 items-center justify-center rounded-full text-xs transition',
                own ? 'text-cyan-100 hover:bg-white/20' : 'text-slate-500 hover:bg-slate-100',
              )}
              aria-label="React to message"
            >
              +
            </button>
          </div>
        </div>
      </div>
    </article>
  );
};

