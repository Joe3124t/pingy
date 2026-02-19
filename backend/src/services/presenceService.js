const connectionsByUser = new Map();

const addSocketConnection = (userId, socketId) => {
  const current = connectionsByUser.get(userId) || new Set();
  const wasOnline = current.size > 0;

  current.add(socketId);
  connectionsByUser.set(userId, current);

  return {
    wasOnline,
    isNowOnline: true,
    count: current.size,
  };
};

const removeSocketConnection = (userId, socketId) => {
  const current = connectionsByUser.get(userId);

  if (!current) {
    return {
      wasOnline: false,
      isNowOnline: false,
      count: 0,
    };
  }

  const wasOnline = current.size > 0;
  current.delete(socketId);

  if (current.size === 0) {
    connectionsByUser.delete(userId);
  }

  return {
    wasOnline,
    isNowOnline: current.size > 0,
    count: current.size,
  };
};

const isUserOnline = (userId) => {
  const sockets = connectionsByUser.get(userId);
  return Boolean(sockets && sockets.size > 0);
};

const getOnlineUserIds = () => Array.from(connectionsByUser.keys());

module.exports = {
  addSocketConnection,
  removeSocketConnection,
  isUserOnline,
  getOnlineUserIds,
};
