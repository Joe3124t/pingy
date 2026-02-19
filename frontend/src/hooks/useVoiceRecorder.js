import { useCallback, useEffect, useRef, useState } from 'react';

const MIME_CANDIDATES = [
  'audio/webm;codecs=opus',
  'audio/webm',
  'audio/ogg;codecs=opus',
  'audio/mp4',
];

const getSupportedMimeType = () => {
  if (typeof MediaRecorder === 'undefined') {
    return null;
  }

  return MIME_CANDIDATES.find((type) => MediaRecorder.isTypeSupported(type)) || null;
};

export const useVoiceRecorder = () => {
  const [isRecording, setIsRecording] = useState(false);
  const [durationMs, setDurationMs] = useState(0);
  const [audioBlob, setAudioBlob] = useState(null);
  const [audioMimeType, setAudioMimeType] = useState('audio/webm');
  const [error, setError] = useState('');

  const mediaRecorderRef = useRef(null);
  const streamRef = useRef(null);
  const chunksRef = useRef([]);
  const timerRef = useRef(null);
  const startedAtRef = useRef(0);

  const clearTimer = () => {
    if (timerRef.current) {
      window.clearInterval(timerRef.current);
      timerRef.current = null;
    }
  };

  const stopTracks = () => {
    if (!streamRef.current) {
      return;
    }

    streamRef.current.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
  };

  const resetRecording = useCallback(() => {
    setDurationMs(0);
    setAudioBlob(null);
    setError('');
  }, []);

  const startRecording = useCallback(async () => {
    try {
      if (typeof navigator === 'undefined' || !navigator.mediaDevices?.getUserMedia) {
        setError('Audio recording is not supported in this browser.');
        return;
      }

      resetRecording();

      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mimeType = getSupportedMimeType();
      const mediaRecorder = mimeType
        ? new MediaRecorder(stream, { mimeType })
        : new MediaRecorder(stream);

      streamRef.current = stream;
      mediaRecorderRef.current = mediaRecorder;
      chunksRef.current = [];
      startedAtRef.current = Date.now();
      setAudioMimeType(mimeType || 'audio/webm');

      mediaRecorder.ondataavailable = (event) => {
        if (event.data.size > 0) {
          chunksRef.current.push(event.data);
        }
      };

      mediaRecorder.onstop = () => {
        clearTimer();
        setIsRecording(false);

        const finalDuration = Date.now() - startedAtRef.current;
        setDurationMs(finalDuration);

        const blob = new Blob(chunksRef.current, {
          type: mimeType || 'audio/webm',
        });

        setAudioBlob(blob);
        stopTracks();
      };

      mediaRecorder.start();
      setIsRecording(true);

      timerRef.current = window.setInterval(() => {
        setDurationMs(Date.now() - startedAtRef.current);
      }, 200);
    } catch {
      setError('Microphone access denied. Please allow audio permissions.');
      clearTimer();
      stopTracks();
      setIsRecording(false);
    }
  }, [resetRecording]);

  const stopRecording = useCallback(() => {
    const recorder = mediaRecorderRef.current;

    if (!recorder || recorder.state === 'inactive') {
      return;
    }

    recorder.stop();
  }, []);

  useEffect(() => {
    return () => {
      clearTimer();
      stopTracks();

      if (mediaRecorderRef.current && mediaRecorderRef.current.state !== 'inactive') {
        mediaRecorderRef.current.stop();
      }
    };
  }, []);

  return {
    isRecording,
    durationMs,
    audioBlob,
    audioMimeType,
    error,
    startRecording,
    stopRecording,
    resetRecording,
  };
};
