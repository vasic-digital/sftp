/**
 * Theme provider contract — maps ThemeTokens onto CSS custom properties.
 *
 * The web app binds tokens to CSS variables on :root (light) and
 * [data-theme="dark"] (dark) so components consume ONLY variables and a
 * theme switch is a single attribute flip. This file is vanilla TS: the
 * React binding (ThemeProvider component) is authored by the web stream on
 * top of this contract.
 *
 * Variable naming: --sftp-<group>-<key> (kebab-case). Roles resolve to their
 * final hex values at binding time (the JSON role references are already
 * resolved in tokens.ts).
 */

import { ThemeTokens, ThemeName, themes } from './tokens';

/** Kebab-case kebab-ify of a camelCase token key. */
function kebab(key: string): string {
  return key.replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase();
}

export type CssVarMap = Record<string, string>;

/**
 * Flatten a theme's tokens into CSS custom properties.
 * Output example: '--sftp-color-role-accent': '#4F46E5'.
 */
export function toCssVariables(theme: ThemeTokens): CssVarMap {
  const vars: CssVarMap = {};

  for (const [family, scale] of Object.entries(theme.color.palette)) {
    for (const [step, value] of Object.entries(scale)) {
      vars[`--sftp-color-${family}-${step}`] = value;
    }
  }
  for (const [role, value] of Object.entries(theme.color.roles)) {
    vars[`--sftp-color-role-${kebab(role)}`] = value;
  }
  for (const [step, spec] of Object.entries(theme.typography.scale)) {
    const name = kebab(step);
    vars[`--sftp-type-${name}-size`] = `${spec.size}px`;
    vars[`--sftp-type-${name}-line-height`] = `${spec.lineHeight}px`;
    vars[`--sftp-type-${name}-weight`] = String(spec.weight);
    vars[`--sftp-type-${name}-letter-spacing`] = `${spec.letterSpacing}px`;
  }
  vars['--sftp-font-sans'] = theme.typography.families.sans;
  vars['--sftp-font-mono'] = theme.typography.families.mono;
  for (const [key, value] of Object.entries(theme.spacing.scale)) {
    vars[`--sftp-space-${key.replace('.', '-')}`] = `${value}px`;
  }
  for (const [key, value] of Object.entries(theme.radius.scale)) {
    vars[`--sftp-radius-${key}`] = `${value}px`;
  }
  for (const [level, shadow] of Object.entries(theme.elevation.levels)) {
    vars[`--sftp-elevation-${level}`] = shadow;
  }

  return vars;
}

/**
 * Render the variable map as a CSS rule body. `selector` defaults to the
 * theme-appropriate root hook.
 */
export function toCssRule(vars: CssVarMap, selector: string): string {
  const body = Object.entries(vars)
    .map(([name, value]) => `  ${name}: ${value};`)
    .join('\n');
  return `${selector} {\n${body}\n}`;
}

/** Full stylesheet binding both themes. Inject once at app bootstrap. */
export function buildThemeStylesheet(): string {
  const light = toCssRule(toCssVariables(themes.light), ':root, [data-theme="light"]');
  const dark = toCssRule(toCssVariables(themes.dark), '[data-theme="dark"]');
  return `${light}\n\n${dark}\n`;
}

/**
 * Apply a theme to a DOM element's inline style (test/SSR-escape hatch;
 * the stylesheet path is the default). No-op outside a browser-like env.
 */
export function applyTheme(element: HTMLElement, themeName: ThemeName): void {
  const vars = toCssVariables(themes[themeName]);
  for (const [name, value] of Object.entries(vars)) {
    element.style.setProperty(name, value);
  }
  element.setAttribute('data-theme', themeName);
}
