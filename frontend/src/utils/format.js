const shortTimeFormatter = new Intl.DateTimeFormat([], {
  hour: '2-digit',
  minute: '2-digit',
});

const dateTimeFormatter = new Intl.DateTimeFormat([], {
  month: 'short',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});

export const formatMessageTime = (isoDate) => {
  if (!isoDate) {
    return '';
  }

  const date = new Date(isoDate);
  return shortTimeFormatter.format(date);
};

export const formatLastSeen = (isoDate) => {
  if (!isoDate) {
    return 'last seen recently';
  }

  const timestamp = new Date(isoDate);
  const diffMs = Date.now() - timestamp.getTime();
  const diffMinutes = Math.floor(diffMs / 60000);

  if (diffMinutes < 1) {
    return 'last seen just now';
  }

  if (diffMinutes < 60) {
    return `last seen ${diffMinutes}m ago`;
  }

  if (diffMinutes < 1440) {
    const hours = Math.floor(diffMinutes / 60);
    return `last seen ${hours}h ago`;
  }

  return `last seen ${dateTimeFormatter.format(timestamp)}`;
};

export const formatDuration = (durationMs = 0) => {
  const totalSeconds = Math.max(0, Math.floor(durationMs / 1000));
  const minutes = Math.floor(totalSeconds / 60)
    .toString()
    .padStart(2, '0');
  const seconds = (totalSeconds % 60).toString().padStart(2, '0');

  return `${minutes}:${seconds}`;
};

export const formatBytes = (bytes = 0) => {
  if (!bytes) {
    return '0 B';
  }

  const units = ['B', 'KB', 'MB', 'GB'];
  const exponent = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  const value = bytes / 1024 ** exponent;

  return `${value.toFixed(exponent === 0 ? 0 : 1)} ${units[exponent]}`;
};

export const buildConversationPreview = (conversation) => {
  if (!conversation?.lastMessageId) {
    return 'No messages yet';
  }

  if (conversation.lastMessageType === 'text') {
    if (conversation.lastMessageIsEncrypted) {
      return 'Message';
    }

    return conversation.lastMessageBody || 'Message';
  }

  if (conversation.lastMessageType === 'image') {
    return 'Photo';
  }

  if (conversation.lastMessageType === 'video') {
    return 'Video';
  }

  if (conversation.lastMessageType === 'voice') {
    return 'Voice message';
  }

  return conversation.lastMessageMediaName || 'File';
};
