import { createContext, useCallback, useEffect, useMemo, useState } from 'react';
import api, {
  bootstrapSessionFromStorage,
  clearSessionTokens,
  getRefreshToken,
  SESSION_EXPIRED_EVENT,
  setSessionTokens,
} from '../../services/api';
import { clearE2EECaches, ensureUserE2EEIdentity } from '../../encryption/e2eeService';

export const AuthContext = createContext(null);

export const AuthProvider = ({ children }) => {
  const [user, setUser] = useState(null);
  const [isInitializing, setIsInitializing] = useState(true);

  const syncPublicEncryptionKey = useCallback(async (nextUser) => {
    if (!nextUser?.id) {
      return;
    }

    try {
      const identity = await ensureUserE2EEIdentity(nextUser.id);
      await api.put('/crypto/public-key', {
        publicKeyJwk: identity.publicKeyJwk,
        algorithm: 'ECDH-P256',
      });
    } catch (error) {
      // Keep auth flow alive even if encryption bootstrap fails.
      // eslint-disable-next-line no-console
      console.error('Failed to bootstrap E2EE identity', error);
    }
  }, []);

  const fetchCurrentUser = useCallback(async () => {
    const response = await api.get('/auth/me');
    const nextUser = response.data?.user || null;
    setUser(nextUser);
    await syncPublicEncryptionKey(nextUser);
    return nextUser;
  }, [syncPublicEncryptionKey]);

  const initializeSession = useCallback(async () => {
    const stored = bootstrapSessionFromStorage();

    if (!stored) {
      setIsInitializing(false);
      return;
    }

    try {
      await fetchCurrentUser();
    } catch {
      clearSessionTokens();
      setUser(null);
    } finally {
      setIsInitializing(false);
    }
  }, [fetchCurrentUser]);

  useEffect(() => {
    initializeSession();
  }, [initializeSession]);

  useEffect(() => {
    const handleSessionExpired = () => {
      clearSessionTokens();
      clearE2EECaches();
      setUser(null);
    };

    window.addEventListener(SESSION_EXPIRED_EVENT, handleSessionExpired);

    return () => {
      window.removeEventListener(SESSION_EXPIRED_EVENT, handleSessionExpired);
    };
  }, []);

  const applyAuthResponse = async (payload) => {
    const nextUser = payload?.user || null;
    const nextTokens = payload?.tokens;

    if (!nextTokens?.accessToken || !nextTokens?.refreshToken) {
      throw new Error('Invalid auth response: missing tokens');
    }

    setSessionTokens(nextTokens);
    setUser(nextUser);
    await syncPublicEncryptionKey(nextUser);

    return nextUser;
  };

  const register = async (form) => {
    const response = await api.post('/auth/register', form);
    return applyAuthResponse(response.data);
  };

  const login = async (form) => {
    const response = await api.post('/auth/login', form);
    return applyAuthResponse(response.data);
  };

  const requestPasswordReset = useCallback(async ({ email }) => {
    const response = await api.post('/auth/forgot-password/request', { email });
    return response.data;
  }, []);

  const confirmPasswordReset = useCallback(async ({ email, code, newPassword }) => {
    const response = await api.post('/auth/forgot-password/confirm', {
      email,
      code,
      newPassword,
    });
    return response.data;
  }, []);

  const logout = async () => {
    const token = getRefreshToken();

    try {
      if (token) {
        await api.post('/auth/logout', { refreshToken: token });
      }
    } catch {
      // Ignore logout API errors and clear session locally.
    } finally {
      clearSessionTokens();
      clearE2EECaches();
      setUser(null);
    }
  };

  const deleteAccount = useCallback(async () => {
    try {
      await api.delete('/users/me');
    } finally {
      clearSessionTokens();
      clearE2EECaches();
      setUser(null);
    }
  }, []);

  const updateProfile = useCallback(async (payload) => {
    const response = await api.patch('/users/me/profile', payload);
    const nextUser = response.data?.user || null;

    if (nextUser) {
      setUser(nextUser);
    }

    return nextUser;
  }, []);

  const uploadAvatar = useCallback(async (file) => {
    const formData = new FormData();
    formData.append('avatar', file);

    const response = await api.post('/users/me/avatar', formData, {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
    });

    const nextUser = response.data?.user || null;

    if (nextUser) {
      setUser(nextUser);
    }

    return nextUser;
  }, []);

  const updatePrivacy = useCallback(async (payload) => {
    const response = await api.patch('/users/me/privacy', payload);
    const nextUser = response.data?.user || null;

    if (nextUser) {
      setUser(nextUser);
    }

    return nextUser;
  }, []);

  const updateChatPreferences = useCallback(async (payload) => {
    const response = await api.patch('/users/me/chat', payload);
    const nextUser = response.data?.user || null;

    if (nextUser) {
      setUser(nextUser);
    }

    return nextUser;
  }, []);

  const uploadDefaultWallpaper = useCallback(async (file) => {
    const formData = new FormData();
    formData.append('wallpaper', file);

    const response = await api.post('/users/me/chat/wallpaper', formData, {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
    });

    const nextUser = response.data?.user || null;

    if (nextUser) {
      setUser(nextUser);
    }

    return nextUser;
  }, []);

  const contextValue = useMemo(
    () => ({
      user,
      isAuthenticated: Boolean(user),
      isInitializing,
      register,
      login,
      requestPasswordReset,
      confirmPasswordReset,
      logout,
      deleteAccount,
      refetchUser: fetchCurrentUser,
      updateProfile,
      uploadAvatar,
      uploadDefaultWallpaper,
      updatePrivacy,
      updateChatPreferences,
    }),
    [
      fetchCurrentUser,
      isInitializing,
      deleteAccount,
      requestPasswordReset,
      confirmPasswordReset,
      updateChatPreferences,
      updatePrivacy,
      updateProfile,
      uploadAvatar,
      uploadDefaultWallpaper,
      user,
    ],
  );

  return <AuthContext.Provider value={contextValue}>{children}</AuthContext.Provider>;
};
