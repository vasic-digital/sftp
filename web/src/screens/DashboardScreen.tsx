import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { apiClient } from '../api/client';
import { Account, Permission } from '../api/types';
import { t, I18nKey } from '../i18n';

const PERMISSION_KEYS: Record<Permission, I18nKey> = {
  read_only: 'permission.read_only',
  read_write: 'permission.read_write',
  public: 'permission.public',
};

export function DashboardScreen() {
  const navigate = useNavigate();
  const [accounts, setAccounts] = useState<Account[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [syncing, setSyncing] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    try {
      const list = await apiClient.listAccounts();
      setAccounts(list);
    } catch {
      setError(t('common.error'));
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function onSync() {
    setSyncing(true);
    setNotice(null);
    setError(null);
    try {
      await apiClient.sync();
      setNotice(t('dashboard.sync.ok'));
    } catch {
      setError(t('dashboard.sync.failed'));
    } finally {
      setSyncing(false);
    }
  }

  async function onDelete(username: string) {
    if (!window.confirm(t('dashboard.deleteConfirm', { username }))) return;
    try {
      await apiClient.deleteAccount(username);
      await load();
    } catch {
      setError(t('common.error'));
    }
  }

  return (
    <>
      <div className="page-head">
        <h1>{t('dashboard.heading')}</h1>
        <div className="btn-row">
          <span className="badge on">{t('dashboard.status.ok')}</span>
          {accounts && (
            <span className="hint">{t('dashboard.count', { count: accounts.length })}</span>
          )}
          <button className="btn secondary" onClick={onSync} disabled={syncing}>
            {syncing ? t('dashboard.syncing') : t('dashboard.sync')}
          </button>
          <button className="btn" onClick={() => navigate('/accounts/new')}>
            {t('nav.newAccount')}
          </button>
        </div>
      </div>

      {error && <div className="alert error">{error}</div>}
      {notice && <div className="alert success">{notice}</div>}

      {accounts === null && !error ? (
        <p>{t('common.loading')}</p>
      ) : accounts !== null && accounts.length === 0 && !error ? (
        <div className="card">{t('dashboard.empty')}</div>
      ) : accounts !== null && accounts.length > 0 ? (
        <table className="data">
          <thead>
            <tr>
              <th>{t('table.username')}</th>
              <th>{t('table.permission')}</th>
              <th>{t('table.uid')}</th>
              <th>{t('table.gid')}</th>
              <th>{t('table.homeDir')}</th>
              <th>{t('table.enabled')}</th>
              <th>{t('table.actions')}</th>
            </tr>
          </thead>
          <tbody>
            {accounts.map((acc) => (
              <tr key={acc.username}>
                <td className="mono">{acc.username}</td>
                <td>
                  <span className={`badge ${acc.permission === 'public' ? 'public' : ''}`}>
                    {t(PERMISSION_KEYS[acc.permission])}
                  </span>
                </td>
                <td>{acc.uid ?? t('common.none')}</td>
                <td>{acc.gid ?? t('common.none')}</td>
                <td className="mono">{acc.home_dir || t('common.none')}</td>
                <td>
                  <span className={`badge ${acc.enabled ? 'on' : 'off'}`}>
                    {acc.enabled ? t('common.yes') : t('common.no')}
                  </span>
                </td>
                <td className="actions">
                  <button
                    className="btn secondary"
                    onClick={() => navigate(`/accounts/${encodeURIComponent(acc.username)}/edit`)}
                  >
                    {t('common.edit')}
                  </button>
                  <button className="btn danger" onClick={() => onDelete(acc.username)}>
                    {t('common.delete')}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
    </>
  );
}
