/**
 * SftpTheme — single theme entry point for the KMP shared UI layer.
 *
 * Binds the OpenDesign tokens (Tokens.kt) to Compose Material (Material 2
 * primitives, which ship with the compose.material artifact the mobile
 * stream wires in the shared module). Pure commonMain: only
 * androidx.compose imports, no platform code.
 *
 * NOTE (honest gap, §11.4.6): this file compiles once the mobile stream
 * adds the Compose dependencies to the shared module's build.gradle.kts
 * (org.jetbrains.compose + compose.material + compose.ui). Until then it
 * is source-only and is excluded from no other target — it simply has no
 * classpath yet. The binding (colors/typography/shapes) is intentionally
 * complete so wiring the deps is sufficient, no source change needed.
 */
package digital.vasic.sftp.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.MaterialTheme
import androidx.compose.material.Shapes
import androidx.compose.material.Typography
import androidx.compose.material.darkColors
import androidx.compose.material.lightColors
import androidx.compose.runtime.Composable

private val LightMaterialColors = lightColors(
    primary = LightColors.tokens.roles.accent,
    primaryVariant = LightColors.tokens.roles.accentHover,
    onPrimary = LightColors.tokens.roles.accentOn,
    secondary = LightColors.tokens.secondary.s600,
    secondaryVariant = LightColors.tokens.secondary.s700,
    onSecondary = LightColors.tokens.secondary.s50,
    background = LightColors.tokens.roles.background,
    onBackground = LightColors.tokens.roles.textPrimary,
    surface = LightColors.tokens.roles.surfaceElevated,
    onSurface = LightColors.tokens.roles.textPrimary,
    error = LightColors.tokens.roles.errorMain,
    onError = LightColors.tokens.error.s50,
)

private val DarkMaterialColors = darkColors(
    primary = DarkColors.tokens.roles.accent,
    primaryVariant = DarkColors.tokens.roles.accentHover,
    onPrimary = DarkColors.tokens.roles.accentOn,
    secondary = DarkColors.tokens.secondary.s500,
    secondaryVariant = DarkColors.tokens.secondary.s400,
    onSecondary = DarkColors.tokens.secondary.s50,
    background = DarkColors.tokens.roles.background,
    onBackground = DarkColors.tokens.roles.textPrimary,
    surface = DarkColors.tokens.roles.surfaceElevated,
    onSurface = DarkColors.tokens.roles.textPrimary,
    error = DarkColors.tokens.roles.errorMain,
    onError = DarkColors.tokens.error.s50,
)

private val AppShapes = Shapes(
    small = RoundedCornerShape(AppRadius.sm),
    medium = RoundedCornerShape(AppRadius.md),
    large = RoundedCornerShape(AppRadius.lg),
)

private val AppMaterialTypography = Typography(
    h1 = AppTypography.displayLarge,
    h2 = AppTypography.displayMedium,
    h3 = AppTypography.displaySmall,
    h4 = AppTypography.headlineLarge,
    h5 = AppTypography.headlineMedium,
    h6 = AppTypography.headlineSmall,
    subtitle1 = AppTypography.titleMedium,
    subtitle2 = AppTypography.titleSmall,
    body1 = AppTypography.bodyLarge,
    body2 = AppTypography.bodyMedium,
    caption = AppTypography.bodySmall,
    button = AppTypography.labelLarge,
    overline = AppTypography.labelSmall,
)

/**
 * Application theme. Wraps MaterialTheme with the SFTP token binding.
 *
 * @param darkTheme selects the dark token pack. Callers typically source
 *        this from isSystemInDarkTheme() plus an in-app override setting.
 */
@Composable
fun SftpTheme(
    darkTheme: Boolean,
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colors = if (darkTheme) DarkMaterialColors else LightMaterialColors,
        typography = AppMaterialTypography,
        shapes = AppShapes,
        content = content,
    )
}

/** Semantic roles of the active theme — for surfaces/components Material does not cover. */
val sftpColorRoles: ColorRoles
    @Composable
    get() = if (MaterialTheme.colors.isLight) {
        LightColors.tokens.roles
    } else {
        DarkColors.tokens.roles
    }
