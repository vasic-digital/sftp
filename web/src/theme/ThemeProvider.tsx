/**
 * React binding over the OpenDesign token contract (§11.4.162).
 * Injects the token stylesheet once and flips data-theme on <html>.
 * Components consume ONLY CSS variables — no hardcoded colors.
 */
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { buildThemeStylesheet, ThemeName } from './opendesign';

type ThemePreference = ThemeName | 'system';

interface ThemeContextValue {
  preference: ThemePreference;
  resolved: ThemeName;
  setPreference: (pref: ThemePreference) => void;
}

const STORAGE_KEY = 'sftp.theme';
const ThemeContext = createContext<ThemeContextValue | null>(null);

let stylesheetInjected = false;
function injectStylesheet(): void {
  if (stylesheetInjected || typeof document === 'undefined') return;
  const style = document.createElement('style');
  style.id = 'sftp-opendesign-tokens';
  style.textContent = buildThemeStylesheet();
  document.head.appendChild(style);
  stylesheetInjected = true;
}

function systemTheme(): ThemeName {
  if (typeof window === 'undefined' || !window.matchMedia) return 'light';
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function initialPreference(): ThemePreference {
  if (typeof localStorage === 'undefined') return 'system';
  const stored = localStorage.getItem(STORAGE_KEY);
  return stored === 'light' || stored === 'dark' || stored === 'system' ? stored : 'system';
}

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [preference, setPreferenceState] = useState<ThemePreference>(initialPreference);
  const [system, setSystem] = useState<ThemeName>(systemTheme);

  useEffect(() => {
    injectStylesheet();
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const handler = (e: MediaQueryListEvent) => setSystem(e.matches ? 'dark' : 'light');
    mq.addEventListener('change', handler);
    return () => mq.removeEventListener('change', handler);
  }, []);

  const resolved: ThemeName = preference === 'system' ? system : preference;

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', resolved);
  }, [resolved]);

  const setPreference = useCallback((pref: ThemePreference) => {
    setPreferenceState(pref);
    localStorage.setItem(STORAGE_KEY, pref);
  }, []);

  const value = useMemo(
    () => ({ preference, resolved, setPreference }),
    [preference, resolved, setPreference],
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error('useTheme must be used within ThemeProvider');
  return ctx;
}
