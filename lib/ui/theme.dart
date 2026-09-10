import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// The app's look.
///
/// ayeaye is a precision instrument for people who live in a task list all
/// day, so the palette stays cool and quiet and lets *status* carry the
/// colour: a calm slate shell, one deep nautical teal for anything
/// interactive, and priority reds and ambers reserved for the few rows that
/// have actually earned attention. A list where everything shouts is a list
/// where nothing does.
class AppTheme {
  /// Deep harbour teal. Distinctive enough to be the app's own, dark enough to
  /// carry white text at small sizes.
  static const seed = Color(0xFF0D5C6B);
  static const seedDark = Color(0xFF5EC5D6);

  /// Reserved for "you are the one holding this" — the single most important
  /// signal in the product.
  static const attention = Color(0xFFB45309);
  static const attentionDark = Color(0xFFFBBF24);

  static ShadColorScheme get _light => ShadSlateColorScheme.light().copyWith(
        background: const Color(0xFFFAFBFC),
        card: Colors.white,
        primary: seed,
        primaryForeground: Colors.white,
        ring: seed,
        selection: const Color(0x330D5C6B),
      );

  static ShadColorScheme get _dark => ShadSlateColorScheme.dark().copyWith(
        background: const Color(0xFF0A1014),
        card: const Color(0xFF111A1F),
        popover: const Color(0xFF111A1F),
        primary: seedDark,
        primaryForeground: const Color(0xFF04252C),
        ring: seedDark,
        selection: const Color(0x445EC5D6),
      );

  static ShadThemeData light() => _build(Brightness.light, _light);
  static ShadThemeData dark() => _build(Brightness.dark, _dark);

  static ShadThemeData _build(Brightness brightness, ShadColorScheme colors) =>
      ShadThemeData(
        brightness: brightness,
        colorScheme: colors,
        // Slightly softer than the shadcn default; large radii read as toy-like
        // on a dense list, sharp corners as unfinished.
        radius: const BorderRadius.all(Radius.circular(8)),
      );

  /// Keeps the Material widgets the app still relies on — `Scaffold`,
  /// `RefreshIndicator`, the text selection handles — in step with the Shad
  /// palette, so nothing shows through in stock Material blue.
  static ThemeData material(BuildContext context, ThemeData base) {
    final colors = ShadTheme.of(context).colorScheme;
    final isDark = base.brightness == Brightness.dark;
    return base.copyWith(
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light())
          .copyWith(
        primary: colors.primary,
        onPrimary: colors.primaryForeground,
        surface: colors.card,
        onSurface: colors.foreground,
        error: colors.destructive,
      ),
      dividerColor: colors.border,
      splashFactory: InkSparkle.splashFactory,
      progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.primary),
    );
  }
}

/// Spacing scale. Using named steps rather than raw numbers keeps rhythm
/// consistent across twenty-odd screens written at different times.
class Gap {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

extension ShadContext on BuildContext {
  ShadThemeData get shad => ShadTheme.of(this);
  ShadColorScheme get colors => ShadTheme.of(this).colorScheme;
  ShadTextTheme get texts => ShadTheme.of(this).textTheme;
  bool get isDark => ShadTheme.of(this).brightness == Brightness.dark;

  /// The attention colour, picked for the current brightness.
  Color get attention => isDark ? AppTheme.attentionDark : AppTheme.attention;
}
