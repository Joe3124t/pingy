import { useContext } from 'react';
import { ChatContext } from '../context/store/ChatContext';

export const useChat = () => {
  const context = useContext(ChatContext);

  if (!context) {
    throw new Error('useChat must be used inside ChatProvider');
  }

  return context;
};
