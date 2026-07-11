/**
 * SFTP design tokens — KMP pack (commonMain).
 *
 * Derived 1:1 from the JSON files under docs/design/tokens (OpenDesign token model).
 * Single source of truth = the JSON; this file is a typed mirror.
 * When the JSON changes, regenerate this file in the same commit.
 *
 * Compose-friendly: colors as androidx.compose.ui.graphics.Color,
 * text styles as TextStyle, spacing/radius as Dp. Pure common code —
 * no platform imports.
 */
package digital.vasic.sftp.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** A 10-step palette scale (50..900), hex values mirrored from color.json. */
class PaletteScale(
    val s50: Color,
    val s100: Color,
    val s200: Color,
    val s300: Color,
    val s400: Color,
    val s500: Color,
    val s600: Color,
    val s700: Color,
    val s800: Color,
    val s900: Color,
)

/** Semantic color roles for one theme (roles map in color.json). */
class ColorRoles(
    val background: Color,
    val surface: Color,
    val surfaceElevated: Color,
    val border: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textDisabled: Color,
    val accent: Color,
    val accentHover: Color,
    val accentOn: Color,
    val link: Color,
    val focusRing: Color,
    val successMain: Color,
    val successSurface: Color,
    val warningMain: Color,
    val warningSurface: Color,
    val errorMain: Color,
    val errorSurface: Color,
    val infoMain: Color,
    val infoSurface: Color,
)

/** Full color token set for one theme. */
class ColorTokens(
    val primary: PaletteScale,
    val secondary: PaletteScale,
    val neutral: PaletteScale,
    val success: PaletteScale,
    val warning: PaletteScale,
    val error: PaletteScale,
    val info: PaletteScale,
    val roles: ColorRoles,
)

private fun c(hex: Long): Color = Color(0xFF000000 or hex)

object LightColors {
    val tokens = ColorTokens(
        primary = PaletteScale(
            c(0xEEF2FF), c(0xE0E7FF), c(0xC7D2FE), c(0xA5B4FC), c(0x818CF8),
            c(0x6366F1), c(0x4F46E5), c(0x4338CA), c(0x3730A3), c(0x312E81),
        ),
        secondary = PaletteScale(
            c(0xF0FDFA), c(0xCCFBF1), c(0x99F6E4), c(0x5EEAD4), c(0x2DD4BF),
            c(0x14B8A6), c(0x0D9488), c(0x0F766E), c(0x115E59), c(0x134E4A),
        ),
        neutral = PaletteScale(
            c(0xF8FAFC), c(0xF1F5F9), c(0xE2E8F0), c(0xCBD5E1), c(0x94A3B8),
            c(0x64748B), c(0x475569), c(0x334155), c(0x1E293B), c(0x0F172A),
        ),
        success = PaletteScale(
            c(0xECFDF5), c(0xD1FAE5), c(0xA7F3D0), c(0x6EE7B7), c(0x34D399),
            c(0x10B981), c(0x059669), c(0x047857), c(0x065F46), c(0x064E3B),
        ),
        warning = PaletteScale(
            c(0xFFFBEB), c(0xFEF3C7), c(0xFDE68A), c(0xFCD34D), c(0xFBBF24),
            c(0xF59E0B), c(0xD97706), c(0xB45309), c(0x92400E), c(0x78350F),
        ),
        error = PaletteScale(
            c(0xFEF2F2), c(0xFEE2E2), c(0xFECACA), c(0xFCA5A5), c(0xF87171),
            c(0xEF4444), c(0xDC2626), c(0xB91C1C), c(0x991B1B), c(0x7F1D1D),
        ),
        info = PaletteScale(
            c(0xF0F9FF), c(0xE0F2FE), c(0xBAE6FD), c(0x7DD3FC), c(0x38BDF8),
            c(0x0EA5E9), c(0x0284C7), c(0x0369A1), c(0x075985), c(0x0C4A6E),
        ),
        roles = ColorRoles(
            background = c(0xF8FAFC),
            surface = c(0xF1F5F9),
            surfaceElevated = Color(0xFFFFFFFF),
            border = c(0xE2E8F0),
            textPrimary = c(0x0F172A),
            textSecondary = c(0x475569),
            textDisabled = c(0x94A3B8),
            accent = c(0x4F46E5),
            accentHover = c(0x4338CA),
            accentOn = Color(0xFFFFFFFF),
            link = c(0x0284C7),
            focusRing = c(0x818CF8),
            successMain = c(0x059669), successSurface = c(0xECFDF5),
            warningMain = c(0xD97706), warningSurface = c(0xFFFBEB),
            errorMain = c(0xDC2626), errorSurface = c(0xFEF2F2),
            infoMain = c(0x0284C7), infoSurface = c(0xF0F9FF),
        ),
    )
}

object DarkColors {
    val tokens = ColorTokens(
        primary = PaletteScale(
            c(0x1E1B4B), c(0x2A2660), c(0x3730A3), c(0x4338CA), c(0x4F46E5),
            c(0x818CF8), c(0xA5B4FC), c(0xC7D2FE), c(0xE0E7FF), c(0xEEF2FF),
        ),
        secondary = PaletteScale(
            c(0x042F2E), c(0x134E4A), c(0x115E59), c(0x0F766E), c(0x0D9488),
            c(0x2DD4BF), c(0x5EEAD4), c(0x99F6E4), c(0xCCFBF1), c(0xF0FDFA),
        ),
        neutral = PaletteScale(
            c(0x0B1120), c(0x0F172A), c(0x1E293B), c(0x334155), c(0x475569),
            c(0x64748B), c(0x94A3B8), c(0xCBD5E1), c(0xE2E8F0), c(0xF8FAFC),
        ),
        success = PaletteScale(
            c(0x022C22), c(0x064E3B), c(0x065F46), c(0x047857), c(0x059669),
            c(0x34D399), c(0x6EE7B7), c(0xA7F3D0), c(0xD1FAE5), c(0xECFDF5),
        ),
        warning = PaletteScale(
            c(0x451A03), c(0x78350F), c(0x92400E), c(0xB45309), c(0xD97706),
            c(0xFBBF24), c(0xFCD34D), c(0xFDE68A), c(0xFEF3C7), c(0xFFFBEB),
        ),
        error = PaletteScale(
            c(0x450A0A), c(0x7F1D1D), c(0x991B1B), c(0xB91C1C), c(0xDC2626),
            c(0xF87171), c(0xFCA5A5), c(0xFECACA), c(0xFEE2E2), c(0xFEF2F2),
        ),
        info = PaletteScale(
            c(0x082F49), c(0x0C4A6E), c(0x075985), c(0x0369A1), c(0x0284C7),
            c(0x38BDF8), c(0x7DD3FC), c(0xBAE6FD), c(0xE0F2FE), c(0xF0F9FF),
        ),
        roles = ColorRoles(
            background = c(0x0B1120),
            surface = c(0x0F172A),
            surfaceElevated = c(0x1E293B),
            border = c(0x334155),
            textPrimary = c(0xF8FAFC),
            textSecondary = c(0x94A3B8),
            textDisabled = c(0x475569),
            accent = c(0x818CF8),
            accentHover = c(0x4F46E5),
            accentOn = c(0x0B1120),
            link = c(0x38BDF8),
            focusRing = c(0x818CF8),
            successMain = c(0x34D399), successSurface = c(0x022C22),
            warningMain = c(0xFBBF24), warningSurface = c(0x451A03),
            errorMain = c(0xF87171), errorSurface = c(0x450A0A),
            infoMain = c(0x38BDF8), infoSurface = c(0x082F49),
        ),
    )
}

/** Typography tokens (theme-independent). Mirrors typography.json. */
object AppTypography {
    val sans: FontFamily = FontFamily.SansSerif
    val mono: FontFamily = FontFamily.Monospace

    val displayLarge = TextStyle(fontFamily = sans, fontSize = 57.sp, lineHeight = 64.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.25).sp)
    val displayMedium = TextStyle(fontFamily = sans, fontSize = 45.sp, lineHeight = 52.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.sp)
    val displaySmall = TextStyle(fontFamily = sans, fontSize = 36.sp, lineHeight = 44.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.sp)
    val headlineLarge = TextStyle(fontFamily = sans, fontSize = 32.sp, lineHeight = 40.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.sp)
    val headlineMedium = TextStyle(fontFamily = sans, fontSize = 28.sp, lineHeight = 36.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.sp)
    val headlineSmall = TextStyle(fontFamily = sans, fontSize = 24.sp, lineHeight = 32.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.sp)
    val titleLarge = TextStyle(fontFamily = sans, fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.sp)
    val titleMedium = TextStyle(fontFamily = sans, fontSize = 16.sp, lineHeight = 24.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.15.sp)
    val titleSmall = TextStyle(fontFamily = sans, fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.1.sp)
    val bodyLarge = TextStyle(fontFamily = sans, fontSize = 16.sp, lineHeight = 24.sp, fontWeight = FontWeight.Normal, letterSpacing = 0.5.sp)
    val bodyMedium = TextStyle(fontFamily = sans, fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Normal, letterSpacing = 0.25.sp)
    val bodySmall = TextStyle(fontFamily = sans, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Normal, letterSpacing = 0.4.sp)
    val labelLarge = TextStyle(fontFamily = sans, fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.1.sp)
    val labelMedium = TextStyle(fontFamily = sans, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.5.sp)
    val labelSmall = TextStyle(fontFamily = sans, fontSize = 11.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.5.sp)
}

/** Spacing scale on the 4pt grid (theme-independent). Mirrors spacing.json. */
object AppSpacing {
    val s0 = 0.dp
    val s0_5 = 2.dp
    val s1 = 4.dp
    val s1_5 = 6.dp
    val s2 = 8.dp
    val s3 = 12.dp
    val s4 = 16.dp
    val s5 = 20.dp
    val s6 = 24.dp
    val s7 = 28.dp
    val s8 = 32.dp
    val s10 = 40.dp
    val s12 = 48.dp
    val s14 = 56.dp
    val s16 = 64.dp
    val s20 = 80.dp
    val s24 = 96.dp
    val s32 = 128.dp

    val gutterPage = s6
    val gutterSection = s8
    val stackTight = s2
    val stackDefault = s4
    val stackLoose = s6
    val insetControl = s3
    val insetCard = s5
    val insetModal = s6
    val touchTargetMin = s12
}

/** Corner radius scale (theme-independent). Mirrors radius.json. */
object AppRadius {
    val none = 0.dp
    val xs = 2.dp
    val sm = 4.dp
    val md = 8.dp
    val lg = 12.dp
    val xl = 16.dp
    val xxl = 24.dp
    // full = pill/circle; Compose consumers use CircleShape / RoundedCornerShape(50%)

    val button = md
    val input = md
    val card = lg
    val modal = xl
    val tooltip = sm
}

/**
 * Elevation levels 0-5 in dp for Compose shadowElevation/tonalElevation.
 * Mirrors elevation.json level N = N*2 dp; light/dark shadow *appearance*
 * is handled by Material's tonal overlay in dark theme.
 */
object AppElevation {
    val l0 = 0.dp
    val l1 = 2.dp
    val l2 = 4.dp
    val l3 = 6.dp
    val l4 = 8.dp
    val l5 = 10.dp

    val cardResting = l1
    val cardHover = l2
    val dropdown = l3
    val modal = l4
    val toast = l5
}
