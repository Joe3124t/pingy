import { useEffect, useRef } from 'react';
import { MessageBubble } from './MessageBubble';
import { resolveMediaUrl } from '../../services/api';

export const MessageList = ({
  messages,
  currentUserId,
  typingUser,
  loading,
  activeConversation,
  onDeleteMessage,
  onReactMessage,
  onReplyMessage,
  defaultWallpaperUrl,
  isDarkMode = false,
}) => {
  const containerRef = useRef(null);
  const bottomRef = useRef(null);

  useEffect(() => {
    if (!bottomRef.current) {
      return;
    }

    bottomRef.current.scrollIntoView({ behavior: 'smooth', block: 'end' });
  }, [messages.length, typingUser]);

  if (loading) {
    return (
      <div className="flex flex-1 items-center justify-center text-sm text-slate-500">
        Loading messages...
      </div>
    );
  }

  const conversationWallpaper = activeConversation?.wallpaperUrl || defaultWallpaperUrl || null;
  const resolvedWallpaper = conversationWallpaper ? resolveMediaUrl(conversationWallpaper) : null;
  const blurIntensity = Number(activeConversation?.blurIntensity || 0);

  const backgroundStyle = resolvedWallpaper
    ? {
        backgroundImage: isDarkMode
          ? `linear-gradient(180deg, rgba(2,6,23,0.28), rgba(15,23,42,0.36)), url(${resolvedWallpaper})`
          : `linear-gradient(180deg, rgba(255,255,255,0.22), rgba(248,250,252,0.28)), url(${resolvedWallpaper})`,
        backgroundSize: 'cover',
        backgroundPosition: 'center',
      }
    : {
        backgroundImage: isDarkMode
          ? 'radial-gradient(circle at 20% 10%, rgba(14,165,233,0.12), transparent 42%), radial-gradient(circle at 80% 90%, rgba(45,212,191,0.12), transparent 38%), linear-gradient(180deg, rgba(2,6,23,0.45), rgba(15,23,42,0.45))'
          : 'radial-gradient(circle at 20% 10%, rgba(14,165,233,0.08), transparent 40%), radial-gradient(circle at 80% 90%, rgba(45,212,191,0.08), transparent 36%)',
      };

  return (
    <div className="relative flex-1 overflow-hidden">
      <div
        className="pointer-events-none absolute inset-0"
        style={{
          ...backgroundStyle,
          filter: blurIntensity > 0 ? `blur(${blurIntensity}px)` : undefined,
          transform: blurIntensity > 0 ? 'scale(1.05)' : undefined,
        }}
      />

      <div
        ref={containerRef}
        className="relative z-10 h-full overflow-y-auto px-4 py-5 sm:px-6"
      >
        <div className="mx-auto flex w-full max-w-3xl flex-col gap-3">
          {messages.length === 0 ? (
            <div
              className={`mx-auto mt-10 rounded-2xl border border-dashed px-6 py-4 text-center text-sm ${
                isDarkMode
                  ? 'border-slate-700 bg-slate-900/70 text-slate-300'
                  : 'border-slate-300 bg-white/70 text-slate-500'
              }`}
            >
              No messages yet. Start with a hello.
            </div>
          ) : (
            messages.map((message) => (
              <MessageBubble
                key={message.id}
                message={message}
                own={message.senderId === currentUserId}
                currentUserId={currentUserId}
                peerUserId={activeConversation?.participantId}
                peerPublicKeyJwk={activeConversation?.participantPublicKeyJwk}
                onDeleteMessage={onDeleteMessage}
                onReactMessage={onReactMessage}
                onReplyMessage={onReplyMessage}
              />
            ))
          )}

          {typingUser ? (
            <div
              className={`inline-flex w-fit items-center gap-2 rounded-full px-4 py-2 text-xs shadow-sm ${
                isDarkMode ? 'bg-slate-900 text-slate-300' : 'bg-white text-slate-500'
              }`}
            >
              <span>{typingUser} is typing</span>
              <span className="inline-flex items-center gap-1">
                <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-cyan-500 [animation-delay:0ms]" />
                <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-cyan-500 [animation-delay:120ms]" />
                <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-cyan-500 [animation-delay:240ms]" />
              </span>
            </div>
          ) : null}

          <div ref={bottomRef} />
        </div>
      </div>
    </div>
  );
};
