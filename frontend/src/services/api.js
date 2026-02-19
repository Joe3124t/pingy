import axios from 'axios';

const API_BASE_URL = import.meta.env.VITE_API_URL || '/api';
const AUTH_STORAGE_KEY = 'pingy.auth.v1';
export const SESSION_EXPIRED_EVENT = 'pingy:session-expired';

const inferApiOrigin = () => {
  if (API_BASE_URL.startsWith('/')) {
    if (typeof window !== 'undefined') {
      return window.location.origin;
    }

    return 'http://localhost:4000';
  }

  try {
    return new URL(API_BASE_URL).origin;
  } catch {
    return 'http://localhost:4000';
  }
};

const API_ORIGIN = inferApiOrigin();

let accessToken = null;
let refreshToken = null;
let refreshInFlight = null;

const readStoredSession = () => {
  if (typeof window === 'undefined') {
    return null;
  }

  const raw = window.localStorage.getItem(AUTH_STORAGE_KEY);

  if (!raw) {
    return null;
  }

  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
};

const persistSession = () => {
  if (typeof window === 'undefined') {
    return;
  }

  if (!accessToken || !refreshToken) {
    window.localStorage.removeItem(AUTH_STORAGE_KEY);
    return;
  }

  window.localStorage.setItem(
    AUTH_STORAGE_KEY,
    JSON.stringify({ accessToken, refreshToken }),
  );
};

export const bootstrapSessionFromStorage = () => {
  const stored = readStoredSession();

  if (!stored?.accessToken || !stored?.refreshToken) {
    return null;
  }

  accessToken = stored.accessToken;
  refreshToken = stored.refreshToken;

  return { accessToken, refreshToken };
};

export const setSessionTokens = (tokens) => {
  accessToken = tokens?.accessToken || null;
  refreshToken = tokens?.refreshToken || null;
  persistSession();
};

export const clearSessionTokens = () => {
  accessToken = null;
  refreshToken = null;
  persistSession();
};

export const getAccessToken = () => accessToken;
export const getRefreshToken = () => refreshToken;
export const getApiOrigin = () => API_ORIGIN;

export const resolveMediaUrl = (mediaUrl) => {
  if (!mediaUrl) {
    return '';
  }

  if (/^https?:\/\//i.test(mediaUrl)) {
    return mediaUrl;
  }

  const withSlash = mediaUrl.startsWith('/') ? mediaUrl : `/${mediaUrl}`;
  return `${API_ORIGIN}${withSlash}`;
};

const apiClient = axios.create({
  baseURL: API_BASE_URL,
  timeout: 15000,
});

const refreshClient = axios.create({
  baseURL: API_BASE_URL,
  timeout: 15000,
});

const runTokenRefresh = async () => {
  if (!refreshToken) {
    throw new Error('No refresh token available');
  }

  const response = await refreshClient.post('/auth/refresh', {
    refreshToken,
  });

  const tokens = response.data?.tokens;

  if (!tokens?.accessToken || !tokens?.refreshToken) {
    throw new Error('Refresh response did not include valid tokens');
  }

  setSessionTokens(tokens);
  return tokens.accessToken;
};

apiClient.interceptors.request.use((config) => {
  if (accessToken) {
    config.headers.Authorization = `Bearer ${accessToken}`;
  }

  return config;
});

apiClient.interceptors.response.use(
  (response) => response,
  async (error) => {
    const status = error?.response?.status;
    const originalRequest = error?.config;

    if (!originalRequest || status !== 401 || originalRequest._retry || originalRequest.url?.includes('/auth/refresh')) {
      return Promise.reject(error);
    }

    if (!refreshToken) {
      clearSessionTokens();

      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event(SESSION_EXPIRED_EVENT));
      }

      return Promise.reject(error);
    }

    originalRequest._retry = true;

    try {
      if (!refreshInFlight) {
        refreshInFlight = runTokenRefresh().finally(() => {
          refreshInFlight = null;
        });
      }

      const nextAccessToken = await refreshInFlight;
      originalRequest.headers.Authorization = `Bearer ${nextAccessToken}`;
      return apiClient(originalRequest);
    } catch (refreshError) {
      clearSessionTokens();

      if (typeof window !== 'undefined') {
        window.dispatchEvent(new Event(SESSION_EXPIRED_EVENT));
      }

      return Promise.reject(refreshError);
    }
  },
);

export default apiClient;
