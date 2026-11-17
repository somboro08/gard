import 'package:flutter/material.dart';

/// Palette « WhatsApp » déclinée en or + noir.
/// Sombre : fond noir, accent or. Clair : fond blanc chaud, accent or.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.sheet,
    required this.card,
    required this.field,
    required this.divider,
    required this.text,
    required this.textSoft,
    required this.gold,
    required this.onGold,
    required this.goldText,
    required this.goldTint,
    required this.success,
    required this.successTint,
    required this.danger,
    required this.dangerTint,
    required this.warn,
    required this.warnTint,
  });

  final Color bg;
  final Color sheet;
  final Color card;
  final Color field;
  final Color divider;
  final Color text;
  final Color textSoft;
  final Color gold;
  final Color onGold;
  final Color goldText;
  final Color goldTint;
  final Color success;
  final Color successTint;
  final Color danger;
  final Color dangerTint;
  final Color warn;
  final Color warnTint;

  static const light = AppPalette(
    bg: Color(0xFFFFFFFF),
    sheet: Color(0xFFFFFFFF),
    card: Color(0xFFF7F5EF),
    field: Color(0xFFF2EFE6),
    divider: Color(0xFFE8E4D8),
    text: Color(0xFF111111),
    textSoft: Color(0xFF667781),
    gold: Color(0xFFF5B800),
    onGold: Color(0xFF111111),
    goldText: Color(0xFF8A6100),
    goldTint: Color(0xFFFFF0BF),
    success: Color(0xFF1E8E5A),
    successTint: Color(0xFFDDF4E7),
    danger: Color(0xFFC93C3C),
    dangerTint: Color(0xFFFBE3E3),
    warn: Color(0xFFA85F00),
    warnTint: Color(0xFFFFE8C2),
  );

  static const dark = AppPalette(
    bg: Color(0xFF0B0B0B),
    sheet: Color(0xFF171717),
    card: Color(0xFF161616),
    field: Color(0xFF1E1E1E),
    divider: Color(0xFF272727),
    text: Color(0xFFF1F1F1),
    textSoft: Color(0xFF9A9A9A),
    gold: Color(0xFFF5B800),
    onGold: Color(0xFF111111),
    goldText: Color(0xFFF7C948),
    goldTint: Color(0xFF3A2E08),
    success: Color(0xFF4CC38A),
    successTint: Color(0xFF123222),
    danger: Color(0xFFFF6B6B),
    dangerTint: Color(0xFF3B1818),
    warn: Color(0xFFFFB454),
    warnTint: Color(0xFF3A2A10),
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      bg: l(bg, other.bg),
      sheet: l(sheet, other.sheet),
      card: l(card, other.card),
      field: l(field, other.field),
      divider: l(divider, other.divider),
      text: l(text, other.text),
      textSoft: l(textSoft, other.textSoft),
      gold: l(gold, other.gold),
      onGold: l(onGold, other.onGold),
      goldText: l(goldText, other.goldText),
      goldTint: l(goldTint, other.goldTint),
      success: l(success, other.success),
      successTint: l(successTint, other.successTint),
      danger: l(danger, other.danger),
      dangerTint: l(dangerTint, other.dangerTint),
      warn: l(warn, other.warn),
      warnTint: l(warnTint, other.warnTint),
    );
  }
}

extension PaletteContext on BuildContext {
  AppPalette get pal => Theme.of(this).extension<AppPalette>()!;
  TextTheme get tt => Theme.of(this).textTheme;
}

/// Thème Material 3 : typographie système (Roboto / SF, comme WhatsApp),
/// mais plus grande et plus lisible.
ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.light ? AppPalette.light : AppPalette.dark;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.gold,
    onPrimary: p.onGold,
    primaryContainer: p.goldTint,
    onPrimaryContainer: p.goldText,
    secondary: p.gold,
    onSecondary: p.onGold,
    secondaryContainer: p.goldTint,
    onSecondaryContainer: p.goldText,
    error: p.danger,
    onError: Colors.white,
    surface: p.bg,
    onSurface: p.text,
    surfaceContainerHighest: p.field,
    outline: p.divider,
    outlineVariant: p.divider,
  );

  final text = TextTheme(
    headlineMedium: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: p.text, height: 1.15),
    headlineSmall: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.text, height: 1.2),
    titleLarge: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: p.text),
    titleMedium: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: p.text),
    titleSmall: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.text),
    bodyLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: p.text),
    bodyMedium: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w400, color: p.text),
    bodySmall: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w400, color: p.textSoft),
    labelLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.text),
    labelMedium: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.text),
    labelSmall: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.textSoft),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    textTheme: text,
    extensions: <ThemeExtension<dynamic>>[p],
    iconTheme: IconThemeData(color: p.text, size: 24),
    dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.gold),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.gold,
      selectionHandleColor: p.gold,
      selectionColor: p.gold.withOpacity(0.30),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 76,
      elevation: 0,
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.goldTint,
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 14.5,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? p.text : p.textSoft,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 26,
          color: states.contains(WidgetState.selected) ? p.text : p.textSoft,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.sheet,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: p.sheet,
      showDragHandle: true,
      dragHandleColor: p.divider,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.text,
      contentTextStyle: TextStyle(fontSize: 16, color: p.bg, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
