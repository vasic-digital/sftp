import { describe, expect, it } from 'vitest';
import { getLocale, setLocale, t } from './index';
import { en } from './en';

describe('i18n', () => {
  it('resolves a known key', () => {
    expect(t('app.title')).toBe('SFTP Admin');
  });

  it('interpolates params', () => {
    expect(t('dashboard.count', { count: 3 })).toBe('3 account(s)');
  });

  it('falls back to the key for unknown keys', () => {
    expect(t('nonexistent.key' as never)).toBe('nonexistent.key');
  });

  it('keeps English active for unknown locales', () => {
    setLocale('xx');
    expect(getLocale()).toBe('en');
  });

  it('every dictionary value is non-empty', () => {
    for (const value of Object.values(en)) {
      expect(value.length).toBeGreaterThan(0);
    }
  });
});
