import { useEffect, useMemo, useRef, useState } from 'react';
import { formatDuration } from '../../utils/format';
import { resolveMediaUrl } from '../../services/api';

export const VoiceMessagePlayer = ({ message, compact = false }) => {
  const audioRef = useRef(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState((message.voiceDurationMs || 0) / 1000);

  const src = resolveMediaUrl(message.mediaUrl);

  const progress = useMemo(() => {
    if (!duration || Number.isNaN(duration)) {
      return 0;
    }

    return Math.min(100, (currentTime / duration) * 100);
  }, [currentTime, duration]);

  useEffect(() => {
    const audio = audioRef.current;

    if (!audio) {
      return undefined;
    }

    const onTimeUpdate = () => {
      setCurrentTime(audio.currentTime || 0);
    };

    const onLoadedMetadata = () => {
      if (audio.duration && Number.isFinite(audio.duration)) {
        setDuration(audio.duration);
      }
    };

    const onPause = () => setIsPlaying(false);
    const onPlay = () => setIsPlaying(true);

    audio.addEventListener('timeupdate', onTimeUpdate);
    audio.addEventListener('loadedmetadata', onLoadedMetadata);
    audio.addEventListener('pause', onPause);
    audio.addEventListener('play', onPlay);

    return () => {
      audio.removeEventListener('timeupdate', onTimeUpdate);
      audio.removeEventListener('loadedmetadata', onLoadedMetadata);
      audio.removeEventListener('pause', onPause);
      audio.removeEventListener('play', onPlay);
    };
  }, []);

  const togglePlayback = () => {
    const audio = audioRef.current;

    if (!audio) {
      return;
    }

    if (isPlaying) {
      audio.pause();
      return;
    }

    audio.play();
  };

  const currentDuration = formatDuration(currentTime * 1000);
  const totalDuration = formatDuration(duration * 1000 || message.voiceDurationMs || 0);

  return (
    <div className={`flex w-full items-center gap-3 ${compact ? '' : 'min-w-[220px]'} max-w-full`}>
      <audio ref={audioRef} src={src} preload="metadata" />
      <button
        type="button"
        onClick={togglePlayback}
        className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-cyan-600 text-white transition hover:bg-cyan-500"
      >
        {isPlaying ? (
          <svg viewBox="0 0 24 24" className="h-4 w-4" fill="currentColor">
            <path d="M8 6h3v12H8zm5 0h3v12h-3z" />
          </svg>
        ) : (
          <svg viewBox="0 0 24 24" className="h-4 w-4" fill="currentColor">
            <path d="M8 5v14l11-7z" />
          </svg>
        )}
      </button>

      <div className="min-w-0 flex-1">
        <div className="h-1.5 w-full overflow-hidden rounded-full bg-cyan-100">
          <span
            className="block h-full rounded-full bg-cyan-600 transition-all"
            style={{ width: `${progress}%` }}
          />
        </div>
        <p className="mt-1 flex items-center justify-between text-[11px] text-slate-500">
          <span>{currentDuration}</span>
          <span>{totalDuration}</span>
        </p>
      </div>
    </div>
  );
};
