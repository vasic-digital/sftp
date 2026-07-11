import { FormEvent, useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { apiClient } from '../api/client';
import { AccountRequest, ApiError, Permission } from '../api/types';
import { t } from '../i18n';

/**
 * Account editor (new + edit). Enforces the public-access guard:
 * permission defaults to read_write (NEVER public), and selecting "public"
 * requires an explicit acknowledgement checkbox before submit is allowed.
 */
export function AccountEditorScreen() {
  const { username } = useParams<{ username: string }>();
  const isEdit = Boolean(username);
  const navigate = useNavigate();

  const [form, setForm] = useState<AccountRequest>({
    username: '',
    permission: 'read_write',
    enabled: true,
  });
  const [password, setPassword] = useState('');
  const [publicAck, setPublicAck] = useState(false);
  const [loading, setLoading] = useState(isEdit);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!isEdit || !username) return;
    apiClient
      .getAccount(username)
      .then((acc) => {
        setForm({
          username: acc.username,
          permission: acc.permission,
          uid: acc.uid,
          gid: acc.gid,
          home_dir: acc.home_dir,
          enabled: acc.enabled,
        });
      })
      .catch(() => setLoadError(t('editor.load.failed')))
      .finally(() => setLoading(false));
  }, [isEdit, username]);

  function patch<K extends keyof AccountRequest>(key: K, value: AccountRequest[K]) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    if (!form.username.trim()) {
      setError(t('editor.username.required'));
      return;
    }
    if (form.permission === 'public' && !publicAck) {
      setError(t('editor.publicAck.required'));
      return;
    }
    const payload: AccountRequest = {
      ...form,
      username: form.username.trim(),
      public_acknowledged: form.permission === 'public' ? publicAck : undefined,
      password: password || undefined,
    };
    setBusy(true);
    try {
      if (isEdit && username) {
        await apiClient.updateAccount(username, payload);
      } else {
        await apiClient.createAccount(payload);
      }
      navigate('/');
    } catch (err) {
      if (err instanceof ApiError && err.status === 422) {
        setError(t('editor.publicAck.required'));
      } else {
        setError(t('editor.failed'));
      }
    } finally {
      setBusy(false);
    }
  }

  if (loading) return <p>{t('common.loading')}</p>;
  if (loadError) return <div className="alert error">{loadError}</div>;

  return (
    <>
      <div className="page-head">
        <h1>
          {isEdit ? t('editor.edit.heading', { username: username ?? '' }) : t('editor.new.heading')}
        </h1>
      </div>
      <div className="card card-form">
        {error && <div className="alert error">{error}</div>}
        <form onSubmit={onSubmit}>
          <div className="field">
            <label htmlFor="acc-username">{t('editor.username')}</label>
            <input
              id="acc-username"
              value={form.username}
              disabled={isEdit}
              onChange={(e) => patch('username', e.target.value)}
            />
          </div>

          <div className="field">
            <label htmlFor="acc-password">{t('editor.password')}</label>
            <input
              id="acc-password"
              type="password"
              autoComplete="new-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
            <span className="hint">
              {isEdit ? t('editor.password.hint.edit') : t('editor.password.hint.new')}
            </span>
          </div>

          <div className="field">
            <label htmlFor="acc-permission">{t('editor.permission')}</label>
            <select
              id="acc-permission"
              value={form.permission}
              onChange={(e) => {
                const next = e.target.value as Permission;
                patch('permission', next);
                if (next !== 'public') setPublicAck(false);
              }}
            >
              <option value="read_only">{t('permission.read_only')}</option>
              <option value="read_write">{t('permission.read_write')}</option>
              <option value="public">{t('permission.public')}</option>
            </select>
          </div>

          {form.permission === 'public' && (
            <>
              <div className="alert warning">{t('editor.publicWarning')}</div>
              <div className="checkbox-row">
                <input
                  id="acc-public-ack"
                  type="checkbox"
                  checked={publicAck}
                  onChange={(e) => setPublicAck(e.target.checked)}
                />
                <label htmlFor="acc-public-ack">{t('editor.publicAck')}</label>
              </div>
            </>
          )}

          <div className="field">
            <label htmlFor="acc-home">{t('editor.homeDir')}</label>
            <input
              id="acc-home"
              value={form.home_dir ?? ''}
              onChange={(e) => patch('home_dir', e.target.value)}
            />
          </div>

          <div className="btn-row">
            <div className="field" style={{ flex: 1 }}>
              <label htmlFor="acc-uid">{t('editor.uid')}</label>
              <input
                id="acc-uid"
                type="number"
                value={form.uid ?? ''}
                onChange={(e) =>
                  patch('uid', e.target.value === '' ? null : Number(e.target.value))
                }
              />
            </div>
            <div className="field" style={{ flex: 1 }}>
              <label htmlFor="acc-gid">{t('editor.gid')}</label>
              <input
                id="acc-gid"
                type="number"
                value={form.gid ?? ''}
                onChange={(e) =>
                  patch('gid', e.target.value === '' ? null : Number(e.target.value))
                }
              />
            </div>
          </div>

          <div className="checkbox-row">
            <input
              id="acc-enabled"
              type="checkbox"
              checked={form.enabled ?? true}
              onChange={(e) => patch('enabled', e.target.checked)}
            />
            <label htmlFor="acc-enabled">{t('editor.enabled')}</label>
          </div>

          <div className="btn-row">
            <button
              className="btn"
              type="submit"
              disabled={busy || (form.permission === 'public' && !publicAck)}
            >
              {isEdit ? t('editor.submit.edit') : t('editor.submit.new')}
            </button>
            <button className="btn secondary" type="button" onClick={() => navigate('/')}>
              {t('common.cancel')}
            </button>
          </div>
        </form>
      </div>
    </>
  );
}
