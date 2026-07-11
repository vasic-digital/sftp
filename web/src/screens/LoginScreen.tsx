import { FormEvent, useEffect, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { apiClient } from '../api/client';
import { useAuth } from '../auth/AuthContext';
import { t } from '../i18n';

type HealthState = 'checking' | 'ok' | 'down';

export function LoginScreen() {
  const { login, authenticated, sessionExpired, clearSessionExpired } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [health, setHealth] = useState<HealthState>('checking');

  useEffect(() => {
    apiClient
      .health()
      .then(() => setHealth('ok'))
      .catch(() => setHealth('down'));
  }, []);

  useEffect(() => {
    if (authenticated) {
      const from = (location.state as { from?: string } | null)?.from ?? '/';
      navigate(from, { replace: true });
    }
  }, [authenticated, navigate, location.state]);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await login(username.trim(), password);
    } catch {
      setError(t('login.failed'));
    } finally {
      setBusy(false);
    }
  }

  const healthLabel =
    health === 'checking'
      ? t('login.health.checking')
      : health === 'ok'
        ? t('login.health.ok')
        : t('login.health.down');

  return (
    <div className="login-wrap">
      <div className="card login-card">
        <h1>{t('app.title')}</h1>
        <p className="hint">{t('app.tagline')}</p>
        <div
          className={`alert ${health === 'ok' ? 'success' : health === 'down' ? 'error' : 'info'}`}
          data-testid="health-status"
        >
          {healthLabel}
        </div>
        {sessionExpired && (
          <div className="alert warning" onClick={clearSessionExpired}>
            {t('auth.sessionExpired')}
          </div>
        )}
        {error && <div className="alert error">{error}</div>}
        <form onSubmit={onSubmit}>
          <div className="field">
            <label htmlFor="username">{t('login.username')}</label>
            <input
              id="username"
              autoComplete="username"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              required
            />
          </div>
          <div className="field">
            <label htmlFor="password">{t('login.password')}</label>
            <input
              id="password"
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
            />
          </div>
          <button className="btn" type="submit" disabled={busy || health === 'down'}>
            {t('login.submit')}
          </button>
        </form>
      </div>
    </div>
  );
}
