import { useMemo, useRef, useState } from 'react';
import { VoiceRecorder } from './VoiceRecorder';

const ACCEPTED_FILES = '.jpg,.jpeg,.png,.webp,.mp4,.pdf,.docx,audio/webm,audio/ogg,audio/mpeg,audio/mp4,audio/wav';

const parseApiError = (error) => {
  const message = error?.response?.data?.message || error?.message || 'Action failed';
  return String(message);
};

const buildReplyPreviewText = (message) => {
  if (!message) {
    return '';
  }

  if (message.type === 'text') {
    if (!message.isEncrypted && typeof message.body === 'string' && message.body.trim()) {
      return message.body.trim().slice(0, 120);
    }

    return 'Replying to a message';
  }

  if (message.type === 'voice') {
    return 'Replying to a voice message';
  }

  if (message.type === 'image') {
    return 'Replying to an image';
  }

  if (message.type === 'video') {
    return 'Replying to a video';
  }

  return message.mediaName ? `Replying to ${message.mediaName}` : 'Replying to a file';
};

export const MessageComposer = ({
  conversationId,
  isBlocked,
  disabled,
  onSendText,
  onSendFile,
  onSendVoice,
  onTypingStart,
  onTypingStop,
  replyTarget,
  onCancelReply,
  isDarkMode = false,
}) => {
  const [text, setText] = useState('');
  const [isSending, setIsSending] = useState(false);
  const [error, setError] = useState('');
  const [showVoiceRecorder, setShowVoiceRecorder] = useState(false);

  const fileInputRef = useRef(null);
  const typingTimeoutRef = useRef(null);
  const typingActiveRef = useRef(false);

  const replyPreviewText = useMemo(() => buildReplyPreviewText(replyTarget), [replyTarget]);

  const stopTypingSignal = () => {
    if (!typingActiveRef.current || !conversationId) {
      return;
    }

    onTypingStop(conversationId);
    typingActiveRef.current = false;
  };

  const scheduleTypingStop = () => {
    if (typingTimeoutRef.current) {
      window.clearTimeout(typingTimeoutRef.current);
    }

    typingTimeoutRef.current = window.setTimeout(() => {
      stopTypingSignal();
    }, 1400);
  };

  const handleTextChange = (event) => {
    const nextText = event.target.value;
    setText(nextText);

    if (!conversationId) {
      return;
    }

    if (nextText.trim().length > 0) {
      if (!typingActiveRef.current) {
        onTypingStart(conversationId);
        typingActiveRef.current = true;
      }

      scheduleTypingStop();
      return;
    }

    stopTypingSignal();
  };

  const sendText = async (event) => {
    event.preventDefault();
    const body = text.trim();

    if (!body || !conversationId || disabled || isSending || isBlocked) {
      return;
    }

    setError('');
    setIsSending(true);

    try {
      await onSendText({
        conversationId,
        body,
        replyToMessageId: replyTarget?.id,
      });
      setText('');
    } catch (sendError) {
      setError(parseApiError(sendError));
    } finally {
      stopTypingSignal();
      setIsSending(false);
    }
  };

  const triggerAttachment = () => {
    if (disabled || !conversationId || isBlocked) {
      return;
    }

    fileInputRef.current?.click();
  };

  const handleFileChange = async (event) => {
    const selectedFile = event.target.files?.[0];

    if (!selectedFile || disabled || !conversationId || isBlocked) {
      return;
    }

    setError('');
    setIsSending(true);

    try {
      await onSendFile({
        conversationId,
        file: selectedFile,
        replyToMessageId: replyTarget?.id,
      });
    } catch (uploadError) {
      setError(parseApiError(uploadError));
    } finally {
      setIsSending(false);
      event.target.value = '';
    }
  };

  const handleSendVoice = async ({ file, durationMs }) => {
    if (disabled || !conversationId || isBlocked) {
      return;
    }

    setError('');

    try {
      await onSendVoice({
        conversationId,
        file,
        durationMs,
        replyToMessageId: replyTarget?.id,
      });
      setShowVoiceRecorder(false);
    } catch (voiceError) {
      setError(parseApiError(voiceError));
      throw voiceError;
    }
  };

  return (
    <div
      className={`border-t px-3 py-3 backdrop-blur-sm sm:px-6 sm:py-4 ${
        isDarkMode ? 'border-slate-800/80 bg-slate-900/85' : 'border-slate-200/80 bg-white/90'
      }`}
    >
      <form onSubmit={sendText} className="mx-auto w-full max-w-3xl space-y-3">
        {replyTarget ? (
          <div
            className={`flex items-start justify-between gap-3 rounded-2xl border px-3 py-2 ${
              isDarkMode ? 'border-cyan-800/60 bg-cyan-950/40 text-slate-200' : 'border-cyan-200 bg-cyan-50 text-slate-700'
            }`}
          >
            <div className="min-w-0">
              <p className="text-xs font-semibold text-cyan-600">
                Replying to {replyTarget.senderUsername || 'message'}
              </p>
              <p className="truncate text-xs">{replyPreviewText}</p>
            </div>
            <button
              type="button"
              onClick={onCancelReply}
              className={`rounded-lg px-2 py-1 text-xs font-semibold ${
                isDarkMode ? 'text-slate-300 hover:bg-slate-800' : 'text-slate-600 hover:bg-white'
              }`}
            >
              Cancel
            </button>
          </div>
        ) : null}

        {showVoiceRecorder ? (
          <VoiceRecorder
            onSendVoice={handleSendVoice}
            disabled={disabled || isSending}
            isDarkMode={isDarkMode}
          />
        ) : null}

        <div className="flex items-end gap-2 sm:gap-3">
          <button
            type="button"
            disabled={disabled || isSending || !conversationId || isBlocked}
            onClick={triggerAttachment}
            className={`inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl border text-lg transition disabled:cursor-not-allowed disabled:opacity-50 ${
              isDarkMode
                ? 'border-slate-700 bg-slate-800 text-slate-300 hover:border-cyan-500 hover:text-cyan-300'
                : 'border-slate-200 bg-white text-slate-500 hover:border-cyan-500 hover:text-cyan-700'
            }`}
            title="Attach file"
          >
            <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M12 5v14M5 12h14" strokeLinecap="round" />
            </svg>
          </button>

          <input
            ref={fileInputRef}
            type="file"
            accept={ACCEPTED_FILES}
            className="hidden"
            onChange={handleFileChange}
          />

          <label className="relative flex-1">
            <textarea
              value={text}
              onChange={handleTextChange}
              onBlur={stopTypingSignal}
              placeholder={
                !conversationId
                  ? 'Select a conversation to chat'
                  : isBlocked
                    ? 'Messaging is disabled for blocked users'
                    : 'Write a message...'
              }
              rows={1}
              className={`max-h-40 w-full resize-y rounded-2xl border px-4 py-3 pr-12 text-base outline-none transition focus:border-cyan-500 focus:ring-2 focus:ring-cyan-200 sm:text-sm ${
                isDarkMode
                  ? 'border-slate-700 bg-slate-800 text-slate-100 placeholder:text-slate-500 focus:bg-slate-800'
                  : 'border-slate-200 bg-slate-50 text-slate-900 focus:bg-white'
              }`}
              disabled={disabled || !conversationId || isSending || isBlocked}
            />
          </label>

          <button
            type="button"
            disabled={disabled || isSending || !conversationId || isBlocked}
            onClick={() => setShowVoiceRecorder((current) => !current)}
            className={`inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl border transition disabled:cursor-not-allowed disabled:opacity-50 ${
              showVoiceRecorder
                ? 'border-cyan-600 bg-cyan-600 text-white'
                : isDarkMode
                  ? 'border-slate-700 bg-slate-800 text-slate-300 hover:border-cyan-500 hover:text-cyan-300'
                  : 'border-slate-200 bg-white text-slate-500 hover:border-cyan-500 hover:text-cyan-700'
            }`}
            title="Record voice message"
          >
            <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M12 15a3 3 0 0 0 3-3V7a3 3 0 1 0-6 0v5a3 3 0 0 0 3 3Z" />
              <path d="M19 11a7 7 0 0 1-14 0M12 18v3M8 21h8" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>

          <button
            type="submit"
            disabled={disabled || isSending || !conversationId || !text.trim() || isBlocked}
            className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-cyan-700 text-sm font-semibold text-white transition hover:bg-cyan-600 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {isSending ? (
              <span className="text-[11px]">...</span>
            ) : (
              <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M21 3 10 14" strokeLinecap="round" />
                <path d="m21 3-7 18-4-7-7-4 18-7Z" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            )}
          </button>
        </div>

        {isBlocked ? (
          <p className="text-xs text-amber-600">
            This conversation is blocked. Unblock the user from menu or settings to send messages.
          </p>
        ) : null}

        {error ? <p className="text-xs text-rose-600">{error}</p> : null}
      </form>
    </div>
  );
};
