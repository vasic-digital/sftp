import { en, I18nKey } from './en';

/**
 * Minimal i18n helper. English-first; additional locales register here later
 * without touching call sites (t(key) stays the only API).
 */
const dictionaries: Record<string, Record<string, string>> = { en };
let activeLocale = 'en';

export function setLocale(locale: string): void {
  if (dictionaries[locale]) activeLocale = locale;
}

export function getLocale(): string {
  return activeLocale;
}

/** Translate a key with optional {placeholder} interpolation. */
export function t(key: I18nKey, params?: Record<string, string | number>): string {
  const table = dictionaries[activeLocale] ?? en;
  let value: string = table[key] ?? en[key] ?? key;
  if (params) {
    for (const [name, replacement] of Object.entries(params)) {
      value = value.replace(
        new RegExp(`\\{${name}\\}`, 'g'),
        String(replacement).replace(/\$/g, '$$$$'),
      );
    }
  }
  return value;
}

export type { I18nKey };
