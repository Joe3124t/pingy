import { useEffect, useMemo, useState } from 'react';
import { useVoiceRecorder } from '../../hooks/useVoiceRecorder';
import { formatDuration } from '../../utils/format';

export const VoiceRecorder = ({ onSendVoice, disabled, isDarkMode = false }) => {
  const {
    isRecording,
    durationMs,
    audioBlob,
    audioMimeType,
    error,
    startRecording,
    stopRecording,
    resetRecording,
  } = useVoiceRecorder();

  const [isSending, setIsSending] = useState(false);

  const previewUrl = useMemo(() => {
    if (!audioBlob) {
      return null;
    }

    return URL.createObjectURL(audioBlob);
  }, [audioBlob]);

  useEffect(() => {
    return () => {
      if (previewUrl) {
        URL.revokeObjectURL(previewUrl);
      }
    };
  }, [previewUrl]);

  const send = async () => {
    if (!audioBlob || disabled || isSending) {
      return;
    }

    setIsSending(true);

    try {
      const extension = audioMimeType.includes('ogg') ? 'ogg' : audioMimeType.includes('mp4') ? 'm4a' : 'webm';
      const file = new File([audioBlob], `voice-${Date.now()}.${extension}`, {
        type: audioMimeType,
      });

      await onSendVoice({ file, durationMs });
      resetRecording();
    } finally {
      setIsSending(false);
    }
  };

  return (
    <div
      className={`rounded-2xl border px-3 py-2 ${
        isDarkMode ? 'border-slate-700 bg-slate-800/90' : 'border-slate-200 bg-slate-50'
      }`}
    >
      {!audioBlob ? (
        <div className="flex items-center gap-3">
          <button
            type="button"
            disabled={disabled}
            onClick={isRecording ? stopRecording : startRecording}
            className={`inline-flex h-10 w-10 items-center justify-center rounded-full text-white transition ${
              isRecording
                ? 'bg-rose-500 shadow-[0_0_0_10px_rgba(244,63,94,0.15)] hover:bg-rose-400'
                : 'bg-cyan-700 hover:bg-cyan-600'
            } disabled:cursor-not-allowed disabled:opacity-60`}
          >
            {isRecording ? (
              <span className="h-3 w-3 animate-pulse rounded-sm bg-white" />
            ) : (
              <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M12 15a3 3 0 0 0 3-3V7a3 3 0 1 0-6 0v5a3 3 0 0 0 3 3Z" />
                <path d="M19 11a7 7 0 0 1-14 0M12 18v3M8 21h8" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            )}
          </button>

          <div className="min-w-0 flex-1">
            <p
              className={`text-xs font-semibold uppercase tracking-[0.16em] ${
                isDarkMode ? 'text-slate-400' : 'text-slate-500'
              }`}
            >
              Voice message
            </p>
            <div className="mt-1 flex items-center gap-2">
              <span className={`font-mono text-sm ${isDarkMode ? 'text-slate-100' : 'text-slate-700'}`}>
                {formatDuration(durationMs)}
              </span>
              {isRecording ? (
                <div className="flex items-end gap-1">
                  {Array.from({ length: 8 }).map((_, index) => (
                    <span
                      key={index}
                      className="w-1 rounded bg-rose-500/90 animate-pulseSoft"
                      style={{ height: `${6 + ((index % 4) + 1) * 4}px`, animationDelay: `${index * 80}ms` }}
                    />
                  ))}
                </div>
              ) : (
                <span className={`text-xs ${isDarkMode ? 'text-slate-400' : 'text-slate-500'}`}>
                  Tap to record
                </span>
              )}
            </div>
          </div>
        </div>
      ) : (
        <div className="space-y-2">
          <audio controls src={previewUrl || ''} className="w-full" />
          <div className="flex items-center justify-between gap-3">
            <p className={`text-xs ${isDarkMode ? 'text-slate-400' : 'text-slate-500'}`}>
              Duration {formatDuration(durationMs)}
            </p>
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={resetRecording}
                className={`rounded-xl border px-3 py-1.5 text-xs font-semibold transition ${
                  isDarkMode
                    ? 'border-slate-700 text-slate-300 hover:border-slate-500 hover:text-slate-100'
                    : 'border-slate-200 text-slate-600 hover:border-slate-300 hover:text-slate-900'
                }`}
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={disabled || isSending}
                onClick={send}
                className="rounded-xl bg-cyan-700 px-3 py-1.5 text-xs font-semibold text-white transition hover:bg-cyan-600 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {isSending ? 'Sending...' : 'Send voice'}
              </button>
            </div>
          </div>
        </div>
      )}

      {error ? <p className="mt-2 text-xs text-rose-600">{error}</p> : null}
    </div>
  );
};
