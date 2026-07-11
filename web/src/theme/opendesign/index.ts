/**
 * OpenDesign theme pack for the SFTP web client.
 * Mirrors docs/design/tokens/*.json (single source of truth).
 */
export * from './tokens';
export { toCssVariables, toCssRule, buildThemeStylesheet, applyTheme } from './theme';
export type { CssVarMap } from './theme';
