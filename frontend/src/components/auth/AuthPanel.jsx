import { useMemo, useState } from 'react';
import { useAuth } from '../../hooks/useAuth';

const initialFormState = {
  username: '',
  email: '',
  password: '',
};

const parseApiError = (error) => {
  const message =
    error?.response?.data?.message ||
    error?.response?.data?.details?.[0]?.message ||
    error?.message ||
    'Authentication failed';

  return String(message);
};

export const AuthPanel = () => {
  const { login, register, requestPasswordReset, confirmPasswordReset } = useAuth();
  const [mode, setMode] = useState('login');
  const [view, setView] = useState('auth');
  const [form, setForm] = useState(initialFormState);
  const [resetEmail, setResetEmail] = useState('');
  const [resetCode, setResetCode] = useState('');
  const [resetPassword, setResetPassword] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  const title = useMemo(() => {
    if (view === 'forgotRequest') {
      return 'Forgot password';
    }

    if (view === 'forgotConfirm') {
      return 'Verify reset code';
    }

    return mode === 'login' ? 'Welcome back' : 'Create your account';
  }, [mode, view]);

  const subtitle = useMemo(() => {
    if (view === 'forgotRequest') {
      return 'Enter your account email and we will send a 6-digit reset code.';
    }

    if (view === 'forgotConfirm') {
      return 'Enter the code from your email and set a new password.';
    }

    return 'Secure realtime messaging with media and voice support.';
  }, [view]);

  const handleChange = (event) => {
    const { name, value } = event.target;
    setForm((previous) => ({
      ...previous,
      [name]: value,
    }));
  };

  const clearAlerts = () => {
    setError('');
    setSuccess('');
  };

  const switchMode = (nextMode) => {
    setMode(nextMode);
    setView('auth');
    clearAlerts();
  };

  const openForgotPassword = () => {
    setView('forgotRequest');
    setResetEmail(form.email || resetEmail);
    setResetCode('');
    setResetPassword('');
    clearAlerts();
  };

  const goBackToLogin = () => {
    setView('auth');
    setMode('login');
    clearAlerts();
  };

  const handleAuthSubmit = async (event) => {
    event.preventDefault();
    clearAlerts();
    setIsSubmitting(true);

    try {
      if (mode === 'login') {
        await login({
          email: form.email,
          password: form.password,
        });
      } else {
        await register({
          username: form.username,
          email: form.email,
          password: form.password,
        });
      }

      setForm(initialFormState);
    } catch (submitError) {
      setError(parseApiError(submitError));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleForgotRequestSubmit = async (event) => {
    event.preventDefault();
    clearAlerts();
    setIsSubmitting(true);

    try {
      const response = await requestPasswordReset({ email: resetEmail });
      setSuccess(
        response?.message ||
          'If an account with that email exists, a reset code was sent.',
      );
      setView('forgotConfirm');
    } catch (submitError) {
      setError(parseApiError(submitError));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleForgotConfirmSubmit = async (event) => {
    event.preventDefault();
    clearAlerts();
    setIsSubmitting(true);

    try {
      await confirmPasswordReset({
        email: resetEmail,
        code: resetCode,
        newPassword: resetPassword,
      });

      setSuccess('Password reset successful. Log in with your new password.');
      setView('auth');
      setMode('login');
      setForm((previous) => ({
        ...previous,
        email: resetEmail,
        password: '',
      }));
      setResetCode('');
      setResetPassword('');
    } catch (submitError) {
      setError(parseApiError(submitError));
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden px-4 py-12">
      <div className="pointer-events-none absolute inset-0 -z-10 bg-[radial-gradient(circle_at_20%_10%,rgba(45,212,191,0.18),transparent_45%),radial-gradient(circle_at_80%_70%,rgba(14,116,144,0.20),transparent_50%),linear-gradient(135deg,#f0f9ff,#f8fafc_55%,#ecfeff)]" />

      <div className="w-full max-w-md rounded-3xl border border-slate-200/80 bg-white/90 p-8 shadow-panel backdrop-blur-sm">
        <div className="flex items-center gap-2">
          <img src="/pingy-logo-192.png" alt="Pingy" className="h-8 w-8 rounded-lg" />
          <p className="font-heading text-sm uppercase tracking-[0.24em] text-cyan-700">Pingy</p>
        </div>
        <h1 className="mt-3 font-heading text-3xl font-semibold text-slate-900">{title}</h1>
        <p className="mt-2 text-sm text-slate-600">{subtitle}</p>

        {view === 'auth' ? (
          <div className="mt-7 grid grid-cols-2 rounded-2xl bg-slate-100 p-1 text-sm font-semibold">
            <button
              type="button"
              onClick={() => switchMode('login')}
              className={`rounded-xl px-4 py-2 transition ${
                mode === 'login' ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500 hover:text-slate-800'
              }`}
            >
              Login
            </button>
            <button
              type="button"
              onClick={() => switchMode('register')}
              className={`rounded-xl px-4 py-2 transition ${
                mode === 'register'
                  ? 'bg-white text-slate-900 shadow-sm'
                  : 'text-slate-500 hover:text-slate-800'
              }`}
            >
              Register
            </button>
          </div>
        ) : null}

        {view === 'auth' ? (
          <form onSubmit={handleAuthSubmit} className="mt-6 space-y-4">
            {mode === 'register' ? (
              <label className="block">
                <span className="mb-2 block text-sm font-semibold text-slate-700">Username</span>
                <input
                  type="text"
                  name="username"
                  value={form.username}
                  onChange={handleChange}
                  required
                  minLength={3}
                  maxLength={30}
                  className="w-full rounded-xl border border-slate-200 bg-white px-4 py-3 text-slate-900 outline-none transition focus:border-cyan-500 focus:ring-2 focus:ring-cyan-200"
                />
              </label>
            ) : null}

            <label className="block">
              <span className="mb-2 block text-sm font-semibold text-slate-700">Email</span>
              <input
                type="email"
                name="email"
                value={form.email}
                onChange={handleChange}
                required
                className="w-full rounded-xl border border-slate-200 bg-white px-4 py-3 text-slate-900 outline-none transition focus:border-cyan-500 focus:ring-2 focus:ring-cyan-200"
              />
            </label>

            <label className="block">
              <div className="mb-2 flex items-center justify-between">
                <span className="block text-sm font-semibold text-slate-700">Password</span>
                {mode === 'login' ? (
                  <button
                    type="button"
                    onClick={openForgotPassword}
                    className="text-xs font-semibold text-cyan-700 transition hover:text-cyan-600"
                  >
                    Forgot password?
                  </button>
                ) : null}
              </div>
              <input
                type="password"
                name="password"
                value={form.password}
                onChange={handleChange}
                required
                minLength={8}
                className="w-full rounded-xl border border-slate-200 bg-white px-4 py-3 text-slate-900 outline-none transition focus:border-cyan-500 focus:ring-2 focus:ring-cyan-200"
              />
            </label>

            {error ? (
              <p className="rounded-xl border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-700">{error}</p>
            ) : null}

            {success ? (
              <p className="rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-700">{success}</p>
            ) : null}

            <button
              type="submit"
              disabled={isSubmitting}
              className="w-full rounded-xl bg-cyan-700 px-4 py-3 font-semibold text-white transition hover:bg-cyan-600 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isSubmitting ? 'Please wait...' : mode === 'login' ? 'Login to Pingy' : 'Create account'}
            </button>
          </form>
        ) : null}

        {view === 'forgotRequest' ? (
          <form onSubmit={handleForgotRequestSubmit} className="mt-6 space-y-4">
            <label className="block">
              <span className="mb-2 block text-sm font-semibold text-slate-700">Email</span>
              <input
                type="email"
                value={resetEmail}
                onChange={(event) => setResetEmail(event.target.value)}
                required
                className="w-full rounded-xl border border-slate-200 bg-white px-4 py-3 text-slate-900 outline-none transition focus:border-cyan-500 focus:ring-2 focus:ring-cyan-200"
              />
            </label>

            {error ? (
              <p className="rounded-xl border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-700">{error}</p>
            ) : null}

            {success ? (
              <p className="rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-700">{success}</p>
            ) : null}

            <button
              type="submit"
              disabled={isSubmitting}
              className="w-full rounded-xl bg-cyan-700 px-4 py-3 font-semibold text-white transition hover:bg-cyan-600 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isSubmitting ? 'Sending code...' : 'Send reset code'}
            </button>

            <button
              type="button"
              onClick={goBackToLogin}
              className="w-full rounded-xl border border-slate-200 px-4 py-3 font-semibold text-slate-700 transition hover:border-slate-300"
            >
              Back to login
            </button>
          </form>
        ) : null}

        {view === 'forgotConfirm' ? (
          <form onSubmit={handleForgotConfirmSubmit} className="mt-6 space-y-4">
            <label className="block">
              <span className="mb-2 block text-sm font-semibold text-slate-700">Email</span>
              <input
                type="email"
                value={resetEmail}
                onChange={(event) => setResetEmail(event.target.value)}
                required
                className="w-full rounded-xl border border-slate-200 bg-white px-4 py-3 text-slate-900 outline-none transition focus:border-cyan-500 focus:ring-2 focus:ring-cyan-200"
              />
            </label>

            <label className="block">
              <span className="mb-2 block text-sm font-semibold text-slate-700">6-digit code</span>
              <input
                type="text"
                value={resetCode}
                onChange={(event) => setResetCode(event.target.value.replace(/\D/g, '').slice(0, 6))}
                required
                inputMode="numeric"
                pattern="[0-9]{6}"
                maxLength={6}
                className="w-full rounded-xl border border-slate-200 bg-white px-4 py-3 tracking-[0.4em] text-slate-900 outline-none transition focus:border-cyan-500 focus:ring-2 focus:ring-cyan-200"
              />
            </label>

            <label className="block">
              <span className="mb-2 block text-sm font-semibold text-slate-700">New password</span>
              <input
                type="password"
                value={resetPassword}
                onChange={(event) => setResetPassword(event.target.value)}
                required
                minLength={8}
                className="w-full rounded-xl border border-slate-200 bg-white px-4 py-3 text-slate-900 outline-none transition focus:border-cyan-500 focus:ring-2 focus:ring-cyan-200"
              />
            </label>

            {error ? (
              <p className="rounded-xl border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-700">{error}</p>
            ) : null}

            {success ? (
              <p className="rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-700">{success}</p>
            ) : null}

            <button
              type="submit"
              disabled={isSubmitting}
              className="w-full rounded-xl bg-cyan-700 px-4 py-3 font-semibold text-white transition hover:bg-cyan-600 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isSubmitting ? 'Updating password...' : 'Reset password'}
            </button>

            <div className="grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => {
                  setView('forgotRequest');
                  clearAlerts();
                }}
                className="rounded-xl border border-slate-200 px-4 py-3 text-sm font-semibold text-slate-700 transition hover:border-slate-300"
              >
                Resend code
              </button>
              <button
                type="button"
                onClick={goBackToLogin}
                className="rounded-xl border border-slate-200 px-4 py-3 text-sm font-semibold text-slate-700 transition hover:border-slate-300"
              >
                Back
              </button>
            </div>
          </form>
        ) : null}
      </div>
    </div>
  );
};
