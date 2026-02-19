import { useEffect, useMemo, useState } from 'react';
import { cropImageToSquareFile } from './imageCrop';
import { resolveMediaUrl } from '../services/api';

const parseError = (error) =>
  String(error?.response?.data?.message || error?.message || 'Settings update failed');

const normalizeWallpaperPath = (value) => {
  if (!value) {
    return null;
  }

  const raw = String(value).trim();

  if (!raw) {
    return null;
  }

  try {
    const parsed = new URL(raw, window.location.origin);

    if (parsed.pathname.startsWith('/uploads/')) {
      return parsed.pathname;
    }

    if (parsed.protocol === 'http:' || parsed.protocol === 'https:') {
      return parsed.toString();
    }
  } catch {
    if (raw.startsWith('/uploads/')) {
      return raw.split('?')[0];
    }
  }

  return null;
};

const getPanelTitle = (mode) => {
  if (mode === 'profile') {
    return 'Profile Settings';
  }

  if (mode === 'chat') {
    return 'Chat Settings';
  }

  return 'Settings';
};

const getPermissionLabel = (permission) => {
  if (permission === 'granted') {
    return 'Enabled';
  }

  if (permission === 'denied') {
    return 'Blocked';
  }

  if (permission === 'default') {
    return 'Not enabled';
  }

  return 'Unsupported';
};

export const SettingsPanel = ({
  open,
  onClose,
  user,
  blockedUsers,
  onUnblockUser,
  onUpdateProfile,
  onUploadAvatar,
  onUploadDefaultWallpaper,
  onUpdatePrivacy,
  onUpdateChat,
  activeConversation,
  onSetConversationWallpaper,
  onUploadConversationWallpaper,
  onResetConversationWallpaper,
  onDeleteAccount,
  notificationPermission = 'default',
  notificationSupportHint = '',
  onEnableNotifications,
  onSendNotificationTest,
  mode = 'general',
  isDarkMode = false,
  onPreviewTheme,
}) => {
  const [profileForm, setProfileForm] = useState({ username: '', bio: '' });
  const [privacyForm, setPrivacyForm] = useState({
    showOnlineStatus: true,
    readReceiptsEnabled: true,
  });
  const [chatForm, setChatForm] = useState({
    themeMode: 'auto',
  });
  const [wallpaperForm, setWallpaperForm] = useState({
    blurIntensity: 0,
  });
  const [conversationWallpaperFile, setConversationWallpaperFile] = useState(null);
  const [confirmDeleteValue, setConfirmDeleteValue] = useState('');
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    setProfileForm({
      username: user?.username || '',
      bio: user?.bio || '',
    });
    setPrivacyForm({
      showOnlineStatus: Boolean(user?.showOnlineStatus ?? true),
      readReceiptsEnabled: Boolean(user?.readReceiptsEnabled ?? true),
    });
    setChatForm({
      themeMode: user?.themeMode || 'auto',
    });
  }, [user]);

  useEffect(() => {
    setWallpaperForm({
      blurIntensity: Number(activeConversation?.blurIntensity || 0),
    });
    setConversationWallpaperFile(null);
  }, [activeConversation]);

  useEffect(() => {
    if (!onPreviewTheme) {
      return undefined;
    }

    if (!open) {
      onPreviewTheme(null);
      return undefined;
    }

    onPreviewTheme(chatForm.themeMode);
    return () => onPreviewTheme(null);
  }, [chatForm.themeMode, onPreviewTheme, open]);

  const avatarUrl = useMemo(() => resolveMediaUrl(user?.avatarUrl || ''), [user?.avatarUrl]);
  const defaultWallpaperUrl = useMemo(
    () => resolveMediaUrl(user?.defaultWallpaperUrl || ''),
    [user?.defaultWallpaperUrl],
  );
  const conversationWallpaperUrl = useMemo(
    () => resolveMediaUrl(activeConversation?.wallpaperUrl || ''),
    [activeConversation?.wallpaperUrl],
  );

  if (!open) {
    return null;
  }

  const showProfileSection = mode !== 'chat';
  const showPrivacySection = mode !== 'chat';
  const showChatSection = mode !== 'profile';
  const showConversationWallpaperSection = Boolean(activeConversation) && mode !== 'profile';
  const showDangerSection = mode !== 'chat';

  const submit = async (handler) => {
    setError('');
    setIsSaving(true);

    try {
      await handler();
    } catch (submitError) {
      setError(parseError(submitError));
    } finally {
      setIsSaving(false);
    }
  };

  const panelTone = isDarkMode
    ? 'border-slate-800 bg-slate-950 text-slate-100'
    : 'border-slate-200 bg-white text-slate-900';
  const cardTone = isDarkMode ? 'border-slate-800 bg-slate-900/70' : 'border-slate-200 bg-white';
  const inputTone = isDarkMode
    ? 'border-slate-700 bg-slate-800 text-slate-100 placeholder:text-slate-500 focus:border-cyan-500'
    : 'border-slate-200 bg-white text-slate-900 focus:border-cyan-500';
  const subtleText = isDarkMode ? 'text-slate-400' : 'text-slate-500';
  const titleTone = isDarkMode ? 'text-slate-100' : 'text-slate-900';
  const notificationsEnabled = notificationPermission === 'granted';
  const notificationsSupported = notificationPermission !== 'unsupported';

  return (
    <div className="absolute inset-0 z-40 flex justify-end bg-slate-950/40">
      <section className={`h-full w-full max-w-xl overflow-y-auto border-l p-5 sm:p-6 ${panelTone}`}>
        <div className="flex items-center justify-between">
          <h2 className={`font-heading text-2xl font-semibold ${titleTone}`}>{getPanelTitle(mode)}</h2>
          <button
            type="button"
            onClick={onClose}
            className={`rounded-xl border px-3 py-2 text-sm font-semibold transition ${
              isDarkMode
                ? 'border-slate-700 text-slate-300 hover:border-slate-500 hover:text-slate-100'
                : 'border-slate-200 text-slate-600 hover:border-slate-300 hover:text-slate-900'
            }`}
          >
            Close
          </button>
        </div>

        {error ? (
          <p className="mt-4 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-700">
            {error}
          </p>
        ) : null}

        <div className="mt-6 space-y-7">
          {showProfileSection ? (
            <section className={`rounded-2xl border p-4 ${cardTone}`}>
              <h3 className={`font-heading text-lg font-semibold ${titleTone}`}>Profile</h3>
              <div className="mt-3 flex items-center gap-3">
                <img
                  src={avatarUrl || '/pingy-logo-192.png'}
                  alt="Avatar"
                  className="h-16 w-16 rounded-2xl object-cover"
                />
                <label
                  className={`rounded-xl border px-3 py-2 text-sm font-semibold transition ${
                    isDarkMode
                      ? 'border-slate-700 text-slate-300 hover:border-slate-500 hover:text-slate-100'
                      : 'border-slate-200 text-slate-700 hover:border-slate-300'
                  }`}
                >
                  Upload avatar
                  <input
                    type="file"
                    accept="image/png,image/jpeg,image/webp"
                    className="hidden"
                    onChange={(event) => {
                      const file = event.target.files?.[0];

                      if (!file) {
                        return;
                      }

                      submit(async () => {
                        const cropped = await cropImageToSquareFile(file, 512);
                        await onUploadAvatar(cropped);
                      });

                      event.target.value = '';
                    }}
                  />
                </label>
              </div>

              <div className="mt-4 space-y-3">
                <label className="block">
                  <span className={`mb-1 block text-sm font-semibold ${isDarkMode ? 'text-slate-200' : 'text-slate-700'}`}>
                    Username
                  </span>
                  <input
                    value={profileForm.username}
                    onChange={(event) =>
                      setProfileForm((prev) => ({ ...prev, username: event.target.value }))
                    }
                    className={`w-full rounded-xl border px-3 py-2 text-sm outline-none ${inputTone}`}
                  />
                </label>

                <label className="block">
                  <span className={`mb-1 block text-sm font-semibold ${isDarkMode ? 'text-slate-200' : 'text-slate-700'}`}>
                    Bio
                  </span>
                  <textarea
                    value={profileForm.bio}
                    onChange={(event) =>
                      setProfileForm((prev) => ({ ...prev, bio: event.target.value }))
                    }
                    rows={3}
                    className={`w-full rounded-xl border px-3 py-2 text-sm outline-none ${inputTone}`}
                  />
                </label>

                <button
                  type="button"
                  disabled={isSaving}
                  onClick={() => submit(() => onUpdateProfile(profileForm))}
                  className="rounded-xl bg-cyan-700 px-4 py-2 text-sm font-semibold text-white transition hover:bg-cyan-600 disabled:opacity-60"
                >
                  Save profile
                </button>
              </div>
            </section>
          ) : null}

          {showPrivacySection ? (
            <section className={`rounded-2xl border p-4 ${cardTone}`}>
              <h3 className={`font-heading text-lg font-semibold ${titleTone}`}>Privacy</h3>
              <div className="mt-3 space-y-3">
                <label className={`flex items-center justify-between gap-2 rounded-xl border px-3 py-2 ${isDarkMode ? 'border-slate-700' : 'border-slate-200'}`}>
                  <span className={`text-sm font-semibold ${isDarkMode ? 'text-slate-200' : 'text-slate-700'}`}>
                    Show online status
                  </span>
                  <input
                    type="checkbox"
                    checked={privacyForm.showOnlineStatus}
                    onChange={(event) =>
                      setPrivacyForm((prev) => ({ ...prev, showOnlineStatus: event.target.checked }))
                    }
                  />
                </label>

                <label className={`flex items-center justify-between gap-2 rounded-xl border px-3 py-2 ${isDarkMode ? 'border-slate-700' : 'border-slate-200'}`}>
                  <span className={`text-sm font-semibold ${isDarkMode ? 'text-slate-200' : 'text-slate-700'}`}>
                    Send read receipts
                  </span>
                  <input
                    type="checkbox"
                    checked={privacyForm.readReceiptsEnabled}
                    onChange={(event) =>
                      setPrivacyForm((prev) => ({
                        ...prev,
                        readReceiptsEnabled: event.target.checked,
                      }))
                    }
                  />
                </label>

                <div className={`rounded-xl border px-3 py-3 ${isDarkMode ? 'border-slate-700' : 'border-slate-200'}`}>
                  <div className="flex items-center justify-between gap-3">
                    <div>
                      <p className={`text-sm font-semibold ${isDarkMode ? 'text-slate-200' : 'text-slate-700'}`}>
                        Notifications
                      </p>
                      <p className={`mt-0.5 text-xs ${subtleText}`}>
                        Status: {getPermissionLabel(notificationPermission)}
                      </p>
                    </div>

                    <div className="flex items-center gap-2">
                      <button
                        type="button"
                        disabled={isSaving || !notificationsSupported || notificationsEnabled}
                        onClick={() =>
                          submit(async () => {
                            await onEnableNotifications?.();
                          })
                        }
                        className={`rounded-xl px-3 py-2 text-xs font-semibold text-white transition disabled:cursor-not-allowed disabled:opacity-60 ${
                          notificationsEnabled ? 'bg-emerald-600' : 'bg-cyan-700 hover:bg-cyan-600'
                        }`}
                      >
                        {notificationsEnabled ? 'Enabled' : 'Enable'}
                      </button>

                      <button
                        type="button"
                        disabled={isSaving || !notificationsEnabled}
                        onClick={() =>
                          submit(async () => {
                            const ok = onSendNotificationTest?.();

                            if (!ok) {
                              throw new Error('Notifications are not enabled yet');
                            }
                          })
                        }
                        className={`rounded-xl border px-3 py-2 text-xs font-semibold transition disabled:cursor-not-allowed disabled:opacity-60 ${
                          isDarkMode
                            ? 'border-slate-700 text-slate-300 hover:border-slate-500 hover:text-slate-100'
                            : 'border-slate-200 text-slate-700 hover:border-slate-300'
                        }`}
                      >
                        Test
                      </button>
                    </div>
                  </div>

                  {notificationSupportHint ? (
                    <p className={`mt-2 text-xs ${subtleText}`}>{notificationSupportHint}</p>
                  ) : null}
                </div>

                <button
                  type="button"
                  disabled={isSaving}
                  onClick={() => submit(() => onUpdatePrivacy(privacyForm))}
                  className="rounded-xl bg-cyan-700 px-4 py-2 text-sm font-semibold text-white transition hover:bg-cyan-600 disabled:opacity-60"
                >
                  Save privacy
                </button>
              </div>

              <div className="mt-5">
                <h4 className={`text-sm font-semibold ${isDarkMode ? 'text-slate-200' : 'text-slate-700'}`}>
                  Blocked users
                </h4>
                <div className="mt-2 space-y-2">
                  {blockedUsers?.length ? (
                    blockedUsers.map((entry) => (
                      <div
                        key={entry.id}
                        className={`flex items-center justify-between rounded-xl border px-3 py-2 ${
                          isDarkMode ? 'border-slate-700' : 'border-slate-200'
                        }`}
                      >
                        <span className={`text-sm ${isDarkMode ? 'text-slate-200' : 'text-slate-700'}`}>
                          {entry.username}
                        </span>
                        <button
                          type="button"
                          onClick={() => submit(() => onUnblockUser(entry.id))}
                          className={`rounded-lg border px-2 py-1 text-xs font-semibold transition ${
                            isDarkMode
                              ? 'border-slate-700 text-slate-300 hover:border-slate-500 hover:text-slate-100'
                              : 'border-slate-200 text-slate-700 hover:border-slate-300'
                          }`}
                        >
                          Unblock
                        </button>
                      </div>
                    ))
                  ) : (
                    <p className={`text-sm ${subtleText}`}>No blocked users.</p>
                  )}
                </div>
              </div>
            </section>
          ) : null}

          {showChatSection ? (
            <section className={`rounded-2xl border p-4 ${cardTone}`}>
              <h3 className={`font-heading text-lg font-semibold ${titleTone}`}>Chat</h3>
              <div className="mt-3 space-y-3">
                <label className="block">
                  <span className={`mb-1 block text-sm font-semibold ${isDarkMode ? 'text-slate-200' : 'text-slate-700'}`}>
                    Theme mode
                  </span>
                  <select
                    value={chatForm.themeMode}
                    onChange={(event) =>
                      setChatForm((prev) => ({ ...prev, themeMode: event.target.value }))
                    }
                    className={`w-full rounded-xl border px-3 py-2 text-sm outline-none ${inputTone}`}
                  >
                    <option value="auto">Auto</option>
                    <option value="light">Light</option>
                    <option value="dark">Dark</option>
                  </select>
                </label>

                <div className={`rounded-xl border p-3 ${isDarkMode ? 'border-slate-700' : 'border-slate-200'}`}>
                  <p className={`text-sm font-semibold ${isDarkMode ? 'text-slate-200' : 'text-slate-700'}`}>
                    Default wallpaper
                  </p>
                  {defaultWallpaperUrl ? (
                    <img
                      src={defaultWallpaperUrl}
                      alt="Default wallpaper"
                      className="mt-2 h-24 w-full rounded-xl object-cover"
                    />
                  ) : (
                    <p className={`mt-2 text-xs ${subtleText}`}>No default wallpaper selected.</p>
                  )}

                  <div className="mt-3 flex items-center gap-2">
                    <label
                      className={`rounded-xl border px-3 py-2 text-sm font-semibold transition ${
                        isDarkMode
                          ? 'border-slate-700 text-slate-300 hover:border-slate-500 hover:text-slate-100'
                          : 'border-slate-200 text-slate-700 hover:border-slate-300'
                      }`}
                    >
                      Upload wallpaper
                      <input
                        type="file"
                        accept="image/png,image/jpeg,image/webp"
                        className="hidden"
                        onChange={(event) => {
                          const file = event.target.files?.[0];

                          if (!file) {
                            return;
                          }

                          submit(() => onUploadDefaultWallpaper(file));
                          event.target.value = '';
                        }}
                      />
                    </label>

                    <button
                      type="button"
                      disabled={isSaving}
                      onClick={() =>
                        submit(() =>
                          onUpdateChat({
                            themeMode: chatForm.themeMode,
                            defaultWallpaperUrl: null,
                          }),
                        )
                      }
                      className={`rounded-xl border px-3 py-2 text-sm font-semibold transition ${
                        isDarkMode
                          ? 'border-slate-700 text-slate-300 hover:border-slate-500 hover:text-slate-100'
                          : 'border-slate-200 text-slate-700 hover:border-slate-300'
                      }`}
                    >
                      Reset wallpaper
                    </button>
                  </div>
                </div>

                <button
                  type="button"
                  disabled={isSaving}
                  onClick={() => submit(() => onUpdateChat({ themeMode: chatForm.themeMode }))}
                  className="rounded-xl bg-cyan-700 px-4 py-2 text-sm font-semibold text-white transition hover:bg-cyan-600 disabled:opacity-60"
                >
                  Save chat settings
                </button>
              </div>
            </section>
          ) : null}

          {showConversationWallpaperSection ? (
            <section className={`rounded-2xl border p-4 ${cardTone}`}>
              <h3 className={`font-heading text-lg font-semibold ${titleTone}`}>Conversation Wallpaper</h3>
              <p className={`mt-1 text-sm ${subtleText}`}>Upload a wallpaper image for this chat.</p>

              <div className="mt-3 space-y-3">
                {conversationWallpaperUrl ? (
                  <img
                    src={conversationWallpaperUrl}
                    alt="Conversation wallpaper"
                    className="h-24 w-full rounded-xl object-cover"
                  />
                ) : (
                  <p className={`text-xs ${subtleText}`}>No conversation wallpaper selected.</p>
                )}

                <label
                  className={`rounded-xl border px-3 py-2 text-sm font-semibold transition ${
                    isDarkMode
                      ? 'border-slate-700 text-slate-300 hover:border-slate-500 hover:text-slate-100'
                      : 'border-slate-200 text-slate-700 hover:border-slate-300'
                  }`}
                >
                  Upload conversation wallpaper
                  <input
                    type="file"
                    accept="image/png,image/jpeg,image/webp"
                    className="hidden"
                    onChange={(event) => {
                      const file = event.target.files?.[0];
                      setConversationWallpaperFile(file || null);
                    }}
                  />
                </label>

                {conversationWallpaperFile ? (
                  <p className={`text-xs ${subtleText}`}>Selected: {conversationWallpaperFile.name}</p>
                ) : null}

                <label className="block">
                  <span className={`mb-1 block text-sm font-semibold ${isDarkMode ? 'text-slate-200' : 'text-slate-700'}`}>
                    Blur intensity
                  </span>
                  <input
                    type="range"
                    min={0}
                    max={20}
                    value={wallpaperForm.blurIntensity}
                    onChange={(event) =>
                      setWallpaperForm((prev) => ({
                        ...prev,
                        blurIntensity: Number(event.target.value),
                      }))
                    }
                    className="w-full"
                  />
                </label>

                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    disabled={isSaving}
                    onClick={() =>
                      submit(async () => {
                        if (conversationWallpaperFile) {
                          await onUploadConversationWallpaper({
                            conversationId: activeConversation.conversationId,
                            file: conversationWallpaperFile,
                            blurIntensity: wallpaperForm.blurIntensity,
                          });
                          setConversationWallpaperFile(null);
                          return;
                        }

                        const normalized = normalizeWallpaperPath(activeConversation?.wallpaperUrl);

                        if (!normalized) {
                          throw new Error('Upload wallpaper image first');
                        }

                        await onSetConversationWallpaper({
                          conversationId: activeConversation.conversationId,
                          wallpaperUrl: normalized,
                          blurIntensity: wallpaperForm.blurIntensity,
                        });
                      })
                    }
                    className="rounded-xl bg-cyan-700 px-4 py-2 text-sm font-semibold text-white transition hover:bg-cyan-600 disabled:opacity-60"
                  >
                    Save wallpaper
                  </button>

                  <button
                    type="button"
                    disabled={isSaving}
                    onClick={() =>
                      submit(async () => {
                        await onResetConversationWallpaper(activeConversation.conversationId);
                        setWallpaperForm({ blurIntensity: 0 });
                        setConversationWallpaperFile(null);
                      })
                    }
                    className={`rounded-xl border px-4 py-2 text-sm font-semibold transition ${
                      isDarkMode
                        ? 'border-slate-700 text-slate-300 hover:border-slate-500 hover:text-slate-100'
                        : 'border-slate-200 text-slate-700 hover:border-slate-300'
                    }`}
                  >
                    Reset
                  </button>
                </div>
              </div>
            </section>
          ) : null}

          {showDangerSection ? (
            <section className={`rounded-2xl border p-4 ${isDarkMode ? 'border-rose-900/60 bg-rose-950/20' : 'border-rose-200 bg-rose-50/70'}`}>
              <h3 className="font-heading text-lg font-semibold text-rose-600">Danger Zone</h3>
              <p className={`mt-1 text-sm ${isDarkMode ? 'text-rose-200/80' : 'text-rose-700/80'}`}>
                Delete account will remove your profile and all related data permanently.
              </p>

              {!showDeleteConfirm ? (
                <button
                  type="button"
                  onClick={() => setShowDeleteConfirm(true)}
                  className="mt-3 rounded-xl bg-rose-600 px-4 py-2 text-sm font-semibold text-white transition hover:bg-rose-500"
                >
                  Delete account
                </button>
              ) : (
                <div className="mt-3 space-y-3">
                  <p className={`text-xs ${isDarkMode ? 'text-rose-200/80' : 'text-rose-700'}`}>
                    Type <strong>DELETE</strong> to confirm account deletion.
                  </p>
                  <input
                    value={confirmDeleteValue}
                    onChange={(event) => setConfirmDeleteValue(event.target.value)}
                    placeholder="Type DELETE"
                    className={`w-full rounded-xl border px-3 py-2 text-sm outline-none ${inputTone}`}
                  />
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={() => {
                        setShowDeleteConfirm(false);
                        setConfirmDeleteValue('');
                      }}
                      className={`rounded-xl border px-3 py-2 text-sm font-semibold transition ${
                        isDarkMode
                          ? 'border-slate-700 text-slate-300 hover:border-slate-500 hover:text-slate-100'
                          : 'border-slate-300 text-slate-700 hover:border-slate-400'
                      }`}
                    >
                      Cancel
                    </button>
                    <button
                      type="button"
                      disabled={isSaving || confirmDeleteValue !== 'DELETE'}
                      onClick={() =>
                        submit(async () => {
                          await onDeleteAccount?.();
                        })
                      }
                      className="rounded-xl bg-rose-600 px-3 py-2 text-sm font-semibold text-white transition hover:bg-rose-500 disabled:cursor-not-allowed disabled:opacity-60"
                    >
                      Confirm delete
                    </button>
                  </div>
                </div>
              )}
            </section>
          ) : null}
        </div>
      </section>
    </div>
  );
};
