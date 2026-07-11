import { FormEvent, useState } from 'react';
import { getApiBase, getDefaultApiBase, setApiBaseOverride } from '../api/client';
import { useTheme } from '../theme/ThemeProvider';
import { t } from '../i18n';

export function SettingsScreen() {
  const { preference, setPreference } = useTheme();
  const [apiBase, setApiBase] = useState(getApiBase());
  const [saved, setSaved] = useState(false);

  function onSaveApiBase(e: FormEvent) {
    e.preventDefault();
    const trimmed = apiBase.trim();
    setApiBaseOverride(trimmed === getDefaultApiBase() ? null : trimmed);
    setSaved(true);
    window.setTimeout(() => setSaved(false), 2500);
  }

  return (
    <>
      <div className="page-head">
        <h1>{t('settings.heading')}</h1>
      </div>

      <div className="card card-form" style={{ marginBottom: 'var(--sftp-space-6)' }}>
        <h2>{t('settings.theme')}</h2>
        <div className="btn-row">
          {(['light', 'dark', 'system'] as const).map((pref) => (
            <button
              key={pref}
              className={`btn ${preference === pref ? '' : 'secondary'}`}
              onClick={() => setPreference(pref)}
            >
              {t(`settings.theme.${pref}` as const)}
            </button>
          ))}
        </div>
      </div>

      <div className="card card-form" style={{ marginBottom: 'var(--sftp-space-6)' }}>
        <h2>{t('settings.apiBase')}</h2>
        <p className="hint">{t('settings.apiBase.hint')}</p>
        <form onSubmit={onSaveApiBase}>
          <div className="field">
            <input
              aria-label={t('settings.apiBase')}
              value={apiBase}
              onChange={(e) => setApiBase(e.target.value)}
            />
          </div>
          {saved && <div className="alert success">{t('settings.apiBase.saved')}</div>}
          <button className="btn" type="submit">
            {t('common.save')}
          </button>
        </form>
      </div>

      <div className="card card-form">
        <h2>{t('settings.about')}</h2>
        <p className="hint">{t('settings.version', { version: __APP_VERSION__ })}</p>
        <p className="hint">{t('settings.apiDefault', { base: getDefaultApiBase() })}</p>
      </div>
    </>
  );
}
