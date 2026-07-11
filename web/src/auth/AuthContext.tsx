import { createContext, useContext, useEffect, useMemo, useState } from 'react';
import { apiClient, clearTokens, isAuthenticated } from '../api/client';

interface AuthContextValue {
  authenticated: boolean;
  login: (username: string, password: string) => Promise<void>;
  logout: () => void;
  sessionExpired: boolean;
  clearSessionExpired: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [authenticated, setAuthenticated] = useState<boolean>(isAuthenticated());
  const [sessionExpired, setSessionExpired] = useState(false);

  useEffect(() => {
    apiClient.onSessionExpired = () => {
      clearTokens();
      setAuthenticated(false);
      setSessionExpired(true);
    };
    return () => {
      apiClient.onSessionExpired = undefined;
    };
  }, []);

  const value = useMemo<AuthContextValue>(
    () => ({
      authenticated,
      sessionExpired,
      clearSessionExpired: () => setSessionExpired(false),
      login: async (username, password) => {
        await apiClient.login(username, password);
        setAuthenticated(true);
        setSessionExpired(false);
      },
      logout: () => {
        apiClient.logout();
        setAuthenticated(false);
      },
    }),
    [authenticated, sessionExpired],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
