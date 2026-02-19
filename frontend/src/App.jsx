import { AuthPanel } from './components/auth/AuthPanel';
import { AppLayout } from './layouts/AppLayout';
import { useAuth } from './hooks/useAuth';

const InitializingScreen = () => {
  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-100">
      <div className="flex items-center gap-3 rounded-2xl border border-slate-200 bg-white px-6 py-4 text-sm font-semibold text-slate-600 shadow-sm">
        <img src="/pingy-logo-192.png" alt="Pingy" className="h-8 w-8 rounded-lg" />
        <span>Booting Pingy...</span>
      </div>
    </div>
  );
};

const App = () => {
  const { user, isInitializing, logout } = useAuth();

  if (isInitializing) {
    return <InitializingScreen />;
  }

  if (!user) {
    return <AuthPanel />;
  }

  return <AppLayout currentUser={user} onLogout={logout} />;
};

export default App;
