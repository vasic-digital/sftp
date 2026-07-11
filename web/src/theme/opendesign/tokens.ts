/**
 * SFTP design tokens — web pack (TypeScript).
 *
 * Derived 1:1 from docs/design/tokens/*.json (OpenDesign token model).
 * Single source of truth = the JSON; this file is a typed mirror.
 * When the JSON changes, regenerate this file in the same commit.
 *
 * No React / framework dependency — plain typed objects so any binding layer
 * (React context, CSS variables, CSS-in-JS) can consume them.
 */

export type ThemeName = 'light' | 'dark';

export type PaletteStep = 50 | 100 | 200 | 300 | 400 | 500 | 600 | 700 | 800 | 900;

export type PaletteFamily =
  | 'primary'
  | 'secondary'
  | 'neutral'
  | 'success'
  | 'warning'
  | 'error'
  | 'info';

export type PaletteScale = Record<PaletteStep, string>;

export interface ColorRoles {
  background: string;
  surface: string;
  surfaceElevated: string;
  border: string;
  textPrimary: string;
  textSecondary: string;
  textDisabled: string;
  accent: string;
  accentHover: string;
  accentOn: string;
  link: string;
  focusRing: string;
  successMain: string;
  successSurface: string;
  warningMain: string;
  warningSurface: string;
  errorMain: string;
  errorSurface: string;
  infoMain: string;
  infoSurface: string;
}

export interface ColorTheme {
  palette: Record<PaletteFamily, PaletteScale>;
  roles: ColorRoles;
}

export interface TypeScaleStep {
  size: number;
  lineHeight: number;
  weight: 400 | 500 | 600 | 700;
  letterSpacing: number;
  family: 'sans' | 'mono';
}

export interface TypographyTokens {
  families: {
    sans: string;
    mono: string;
  };
  weights: {
    regular: 400;
    medium: 500;
    semibold: 600;
    bold: 700;
  };
  scale: Record<
    | 'displayLarge'
    | 'displayMedium'
    | 'displaySmall'
    | 'headlineLarge'
    | 'headlineMedium'
    | 'headlineSmall'
    | 'titleLarge'
    | 'titleMedium'
    | 'titleSmall'
    | 'bodyLarge'
    | 'bodyMedium'
    | 'bodySmall'
    | 'labelLarge'
    | 'labelMedium'
    | 'labelSmall',
    TypeScaleStep
  >;
}

export interface SpacingTokens {
  baseUnit: 4;
  scale: Record<string, number>;
  semantic: Record<string, string>;
}

export interface RadiusTokens {
  scale: Record<'none' | 'xs' | 'sm' | 'md' | 'lg' | 'xl' | 'xxl' | 'full', number>;
  semantic: Record<string, string>;
}

export interface ElevationTokens {
  levels: Record<0 | 1 | 2 | 3 | 4 | 5, string>;
  semantic: Record<string, string>;
}

export interface ThemeTokens {
  color: ColorTheme;
  typography: TypographyTokens;
  spacing: SpacingTokens;
  radius: RadiusTokens;
  elevation: ElevationTokens;
}

/* ------------------------------------------------------------------ */
/* Typography (theme-independent)                                      */
/* ------------------------------------------------------------------ */

export const typography: TypographyTokens = {
  families: {
    sans: "Inter, system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif",
    mono: "'JetBrains Mono', 'SF Mono', 'Cascadia Code', Menlo, Consolas, monospace",
  },
  weights: { regular: 400, medium: 500, semibold: 600, bold: 700 },
  scale: {
    displayLarge: { size: 57, lineHeight: 64, weight: 700, letterSpacing: -0.25, family: 'sans' },
    displayMedium: { size: 45, lineHeight: 52, weight: 700, letterSpacing: 0, family: 'sans' },
    displaySmall: { size: 36, lineHeight: 44, weight: 700, letterSpacing: 0, family: 'sans' },
    headlineLarge: { size: 32, lineHeight: 40, weight: 600, letterSpacing: 0, family: 'sans' },
    headlineMedium: { size: 28, lineHeight: 36, weight: 600, letterSpacing: 0, family: 'sans' },
    headlineSmall: { size: 24, lineHeight: 32, weight: 600, letterSpacing: 0, family: 'sans' },
    titleLarge: { size: 22, lineHeight: 28, weight: 600, letterSpacing: 0, family: 'sans' },
    titleMedium: { size: 16, lineHeight: 24, weight: 500, letterSpacing: 0.15, family: 'sans' },
    titleSmall: { size: 14, lineHeight: 20, weight: 500, letterSpacing: 0.1, family: 'sans' },
    bodyLarge: { size: 16, lineHeight: 24, weight: 400, letterSpacing: 0.5, family: 'sans' },
    bodyMedium: { size: 14, lineHeight: 20, weight: 400, letterSpacing: 0.25, family: 'sans' },
    bodySmall: { size: 12, lineHeight: 16, weight: 400, letterSpacing: 0.4, family: 'sans' },
    labelLarge: { size: 14, lineHeight: 20, weight: 500, letterSpacing: 0.1, family: 'sans' },
    labelMedium: { size: 12, lineHeight: 16, weight: 500, letterSpacing: 0.5, family: 'sans' },
    labelSmall: { size: 11, lineHeight: 16, weight: 500, letterSpacing: 0.5, family: 'sans' },
  },
};

/* ------------------------------------------------------------------ */
/* Spacing / radius (theme-independent)                                */
/* ------------------------------------------------------------------ */

export const spacing: SpacingTokens = {
  baseUnit: 4,
  scale: {
    '0': 0, '0.5': 2, '1': 4, '1.5': 6, '2': 8, '3': 12, '4': 16, '5': 20,
    '6': 24, '7': 28, '8': 32, '10': 40, '12': 48, '14': 56, '16': 64,
    '20': 80, '24': 96, '32': 128,
  },
  semantic: {
    gutterPage: '6', gutterSection: '8', stackTight: '2', stackDefault: '4',
    stackLoose: '6', insetControl: '3', insetCard: '5', insetModal: '6',
    touchTargetMin: '12',
  },
};

export const radius: RadiusTokens = {
  scale: { none: 0, xs: 2, sm: 4, md: 8, lg: 12, xl: 16, xxl: 24, full: 9999 },
  semantic: {
    button: 'md', input: 'md', card: 'lg', modal: 'xl',
    chip: 'full', avatar: 'full', tooltip: 'sm',
  },
};

/* ------------------------------------------------------------------ */
/* Light theme                                                         */
/* ------------------------------------------------------------------ */

const lightColor: ColorTheme = {
  palette: {
    primary: { 50: '#EEF2FF', 100: '#E0E7FF', 200: '#C7D2FE', 300: '#A5B4FC', 400: '#818CF8', 500: '#6366F1', 600: '#4F46E5', 700: '#4338CA', 800: '#3730A3', 900: '#312E81' },
    secondary: { 50: '#F0FDFA', 100: '#CCFBF1', 200: '#99F6E4', 300: '#5EEAD4', 400: '#2DD4BF', 500: '#14B8A6', 600: '#0D9488', 700: '#0F766E', 800: '#115E59', 900: '#134E4A' },
    neutral: { 50: '#F8FAFC', 100: '#F1F5F9', 200: '#E2E8F0', 300: '#CBD5E1', 400: '#94A3B8', 500: '#64748B', 600: '#475569', 700: '#334155', 800: '#1E293B', 900: '#0F172A' },
    success: { 50: '#ECFDF5', 100: '#D1FAE5', 200: '#A7F3D0', 300: '#6EE7B7', 400: '#34D399', 500: '#10B981', 600: '#059669', 700: '#047857', 800: '#065F46', 900: '#064E3B' },
    warning: { 50: '#FFFBEB', 100: '#FEF3C7', 200: '#FDE68A', 300: '#FCD34D', 400: '#FBBF24', 500: '#F59E0B', 600: '#D97706', 700: '#B45309', 800: '#92400E', 900: '#78350F' },
    error: { 50: '#FEF2F2', 100: '#FEE2E2', 200: '#FECACA', 300: '#FCA5A5', 400: '#F87171', 500: '#EF4444', 600: '#DC2626', 700: '#B91C1C', 800: '#991B1B', 900: '#7F1D1D' },
    info: { 50: '#F0F9FF', 100: '#E0F2FE', 200: '#BAE6FD', 300: '#7DD3FC', 400: '#38BDF8', 500: '#0EA5E9', 600: '#0284C7', 700: '#0369A1', 800: '#075985', 900: '#0C4A6E' },
  },
  roles: {
    background: '#F8FAFC', // neutral.50
    surface: '#F1F5F9', // neutral.100
    surfaceElevated: '#FFFFFF',
    border: '#E2E8F0', // neutral.200
    textPrimary: '#0F172A', // neutral.900
    textSecondary: '#475569', // neutral.600
    textDisabled: '#94A3B8', // neutral.400
    accent: '#4F46E5', // primary.600
    accentHover: '#4338CA', // primary.700
    accentOn: '#FFFFFF',
    link: '#0284C7', // info.600
    focusRing: '#818CF8', // primary.400
    successMain: '#059669', successSurface: '#ECFDF5',
    warningMain: '#D97706', warningSurface: '#FFFBEB',
    errorMain: '#DC2626', errorSurface: '#FEF2F2',
    infoMain: '#0284C7', infoSurface: '#F0F9FF',
  },
};

const lightElevation: ElevationTokens = {
  levels: {
    0: 'none',
    1: '0 1px 2px 0 rgba(15, 23, 42, 0.06), 0 1px 3px 0 rgba(15, 23, 42, 0.10)',
    2: '0 2px 4px 0 rgba(15, 23, 42, 0.06), 0 4px 8px 0 rgba(15, 23, 42, 0.10)',
    3: '0 4px 8px 0 rgba(15, 23, 42, 0.08), 0 8px 16px 0 rgba(15, 23, 42, 0.12)',
    4: '0 8px 16px 0 rgba(15, 23, 42, 0.10), 0 16px 32px 0 rgba(15, 23, 42, 0.14)',
    5: '0 12px 24px 0 rgba(15, 23, 42, 0.12), 0 24px 48px 0 rgba(15, 23, 42, 0.16)',
  },
  semantic: { cardResting: '1', cardHover: '2', dropdown: '3', modal: '4', toast: '5' },
};

export const lightTheme: ThemeTokens = {
  color: lightColor,
  typography,
  spacing,
  radius,
  elevation: lightElevation,
};

/* ------------------------------------------------------------------ */
/* Dark theme (chromatic scales luminance-inverted, accent stays 500)  */
/* ------------------------------------------------------------------ */

const darkColor: ColorTheme = {
  palette: {
    primary: { 50: '#1E1B4B', 100: '#2A2660', 200: '#3730A3', 300: '#4338CA', 400: '#4F46E5', 500: '#818CF8', 600: '#A5B4FC', 700: '#C7D2FE', 800: '#E0E7FF', 900: '#EEF2FF' },
    secondary: { 50: '#042F2E', 100: '#134E4A', 200: '#115E59', 300: '#0F766E', 400: '#0D9488', 500: '#2DD4BF', 600: '#5EEAD4', 700: '#99F6E4', 800: '#CCFBF1', 900: '#F0FDFA' },
    neutral: { 50: '#0B1120', 100: '#0F172A', 200: '#1E293B', 300: '#334155', 400: '#475569', 500: '#64748B', 600: '#94A3B8', 700: '#CBD5E1', 800: '#E2E8F0', 900: '#F8FAFC' },
    success: { 50: '#022C22', 100: '#064E3B', 200: '#065F46', 300: '#047857', 400: '#059669', 500: '#34D399', 600: '#6EE7B7', 700: '#A7F3D0', 800: '#D1FAE5', 900: '#ECFDF5' },
    warning: { 50: '#451A03', 100: '#78350F', 200: '#92400E', 300: '#B45309', 400: '#D97706', 500: '#FBBF24', 600: '#FCD34D', 700: '#FDE68A', 800: '#FEF3C7', 900: '#FFFBEB' },
    error: { 50: '#450A0A', 100: '#7F1D1D', 200: '#991B1B', 300: '#B91C1C', 400: '#DC2626', 500: '#F87171', 600: '#FCA5A5', 700: '#FECACA', 800: '#FEE2E2', 900: '#FEF2F2' },
    info: { 50: '#082F49', 100: '#0C4A6E', 200: '#075985', 300: '#0369A1', 400: '#0284C7', 500: '#38BDF8', 600: '#7DD3FC', 700: '#BAE6FD', 800: '#E0F2FE', 900: '#F0F9FF' },
  },
  roles: {
    background: '#0B1120', // neutral.50
    surface: '#0F172A', // neutral.100
    surfaceElevated: '#1E293B', // neutral.200
    border: '#334155', // neutral.300
    textPrimary: '#F8FAFC', // neutral.900
    textSecondary: '#94A3B8', // neutral.600
    textDisabled: '#475569', // neutral.400
    accent: '#818CF8', // primary.500
    accentHover: '#4F46E5', // primary.400
    accentOn: '#0B1120', // neutral.50
    link: '#38BDF8', // info.500
    focusRing: '#818CF8', // primary.500
    successMain: '#34D399', successSurface: '#022C22',
    warningMain: '#FBBF24', warningSurface: '#451A03',
    errorMain: '#F87171', errorSurface: '#450A0A',
    infoMain: '#38BDF8', infoSurface: '#082F49',
  },
};

const darkElevation: ElevationTokens = {
  levels: {
    0: 'none',
    1: '0 1px 2px 0 rgba(0, 0, 0, 0.40), 0 1px 3px 0 rgba(0, 0, 0, 0.50)',
    2: '0 2px 4px 0 rgba(0, 0, 0, 0.40), 0 4px 8px 0 rgba(0, 0, 0, 0.50)',
    3: '0 4px 8px 0 rgba(0, 0, 0, 0.45), 0 8px 16px 0 rgba(0, 0, 0, 0.55)',
    4: '0 8px 16px 0 rgba(0, 0, 0, 0.50), 0 16px 32px 0 rgba(0, 0, 0, 0.60)',
    5: '0 12px 24px 0 rgba(0, 0, 0, 0.55), 0 24px 48px 0 rgba(0, 0, 0, 0.65)',
  },
  semantic: { cardResting: '1', cardHover: '2', dropdown: '3', modal: '4', toast: '5' },
};

export const darkTheme: ThemeTokens = {
  color: darkColor,
  typography,
  spacing,
  radius,
  elevation: darkElevation,
};

export const themes: Record<ThemeName, ThemeTokens> = {
  light: lightTheme,
  dark: darkTheme,
};
