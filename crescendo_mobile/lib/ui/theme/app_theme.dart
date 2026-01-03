import 'package:flutter/material.dart';

class AppThemeController {
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);
  static final ValueNotifier<bool> magicalMode = ValueNotifier<bool>(false);
}

class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final bool isDark;
  final bool isMagical;
  final Color bgTop;
  final Color bgBottom;
  final Color surface0;
  final Color surface1;
  final Color surface2;
  final Color borderSubtle;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color iconMuted;
  final Color blueAccent;
  final Color lavenderGlow;
  final Color goldAccent;
  final Color mintAccent;
  final Color glassFill;
  final Color glassBorder;
  final Color glow;

  const AppThemeColors({
    required this.isDark,
    required this.isMagical,
    required this.bgTop,
    required this.bgBottom,
    required this.surface0,
    required this.surface1,
    required this.surface2,
    required this.borderSubtle,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.iconMuted,
    required this.blueAccent,
    required this.lavenderGlow,
    required this.goldAccent,
    required this.mintAccent,
    required this.glassFill,
    required this.glassBorder,
    required this.glow,
  });

  static const dark = AppThemeColors(
    isDark: true,
    isMagical: false,
    bgTop: Color(0xFF0A1226),
    bgBottom: Color(0xFF17365A),
    surface0: Color(0xFF0A1226),
    surface1: Color(0x1FFFFFFF),
    surface2: Color(0x26FFFFFF),
    borderSubtle: Color(0x33FFFFFF),
    divider: Color(0x26FFFFFF),
    textPrimary: Color(0xFFF4F7FF),
    textSecondary: Color(0xFFB7C4DD),
    iconMuted: Color(0xFFB7C4DD),
    blueAccent: Color(0xFF9FB7FF),
    lavenderGlow: Color(0xFFB8A6FF),
    goldAccent: Color(0xFFFBC57D),
    mintAccent: Color(0xFF9FE6B2),
    glassFill: Color(0x1FFFFFFF),
    glassBorder: Color(0x33FFFFFF),
    glow: Color(0x33FFFFFF),
  );

  static const light = AppThemeColors(
    isDark: false,
    isMagical: false,
    bgTop: Color(0xFFF7FBFF), // Very light blue
    bgBottom: Color(0xFFE6E6FA), // Soft periwinkle
    surface0: Color(0xFFF7FBFF),
    surface1: Color(0xFFFFFFFF), // White for glass cards
    surface2: Color(0xFFF3E8FF), // Pale lavender
    borderSubtle: Color(0x40FFFFFF), // White at ~0.25 opacity
    divider: Color(0x26FFFFFF), // White at ~0.15 opacity
    textPrimary: Color(0xFF0D0D0D), // Near-black/navy
    textSecondary: Color(0xFF5C6270), // Muted slate
    iconMuted: Color(0xFF9CA3AF), // Mid-gray
    blueAccent: Color(0xFF60A5FA), // Light blue
    lavenderGlow: Color(0xFF8B5CF6), // Saturated purple (primary accent)
    goldAccent: Color(0xFF8B5CF6), // Using purple instead of gold
    mintAccent: Color(0xFF60A5FA), // Using blue instead of mint
    glassFill: Color(0xBFFFFFFF), // White at ~0.75 opacity
    glassBorder: Color(0x40FFFFFF), // White at ~0.25 opacity
    glow: Color(0x1A8B5CF6), // Purple glow at low opacity
  );

  static const magical = AppThemeColors(
    isDark: true,
    isMagical: true,
    bgTop: Color(0xFF1B1E3C),
    bgBottom: Color(0xFF3E2F6E),
    surface0: Color(0xFF171A3A),
    surface1: Color(0x26FFFFFF),
    surface2: Color(0x33FFFFFF),
    borderSubtle: Color(0x33FFFFFF),
    divider: Color(0x26FFFFFF),
    textPrimary: Color(0xFFF7F8FF),
    textSecondary: Color(0xBFF7F8FF),
    iconMuted: Color(0xBFF7F8FF),
    blueAccent: Color(0xFF7FE9F3),
    lavenderGlow: Color(0xFFB8A6FF),
    goldAccent: Color(0xFFF4A3C4),
    mintAccent: Color(0xFFB8A6FF),
    glassFill: Color(0x26FFFFFF),
    glassBorder: Color(0x33FFFFFF),
    glow: Color(0x66B8A6FF),
  );

  static AppThemeColors of(BuildContext context) {
    final ext = Theme.of(context).extension<AppThemeColors>();
    return ext ?? (Theme.of(context).brightness == Brightness.dark ? dark : light);
  }

  @override
  AppThemeColors copyWith({
    bool? isDark,
    bool? isMagical,
    Color? bgTop,
    Color? bgBottom,
    Color? surface0,
    Color? surface1,
    Color? surface2,
    Color? borderSubtle,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? iconMuted,
    Color? blueAccent,
    Color? lavenderGlow,
    Color? goldAccent,
    Color? mintAccent,
    Color? glassFill,
    Color? glassBorder,
    Color? glow,
  }) {
    return AppThemeColors(
      isDark: isDark ?? this.isDark,
      isMagical: isMagical ?? this.isMagical,
      bgTop: bgTop ?? this.bgTop,
      bgBottom: bgBottom ?? this.bgBottom,
      surface0: surface0 ?? this.surface0,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      iconMuted: iconMuted ?? this.iconMuted,
      blueAccent: blueAccent ?? this.blueAccent,
      lavenderGlow: lavenderGlow ?? this.lavenderGlow,
      goldAccent: goldAccent ?? this.goldAccent,
      mintAccent: mintAccent ?? this.mintAccent,
      glassFill: glassFill ?? this.glassFill,
      glassBorder: glassBorder ?? this.glassBorder,
      glow: glow ?? this.glow,
    );
  }

  // Helper getters for gradients
  LinearGradient get backgroundGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [bgTop, surface2, bgBottom],
        stops: const [0.0, 0.5, 1.0],
      );

  // Accent colors
  Color get accentPurple => lavenderGlow;
  Color get accentBlue => blueAccent;

  // Glass card styling
  Color get surfaceGlass => glassFill;
  Color get borderGlass => glassBorder;

  // Border radius tokens
  static const double radiusSm = 14.0;
  static const double radiusMd = 20.0;
  static const double radiusLg = 26.0;

  // Shadow tokens
  List<BoxShadow> get elevationShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 20,
          spreadRadius: 0,
          offset: const Offset(0, 4),
        ),
      ];

  @override
  ThemeExtension<AppThemeColors> lerp(
    ThemeExtension<AppThemeColors>? other,
    double t,
  ) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      isDark: t < 0.5 ? isDark : other.isDark,
      isMagical: t < 0.5 ? isMagical : other.isMagical,
      bgTop: Color.lerp(bgTop, other.bgTop, t)!,
      bgBottom: Color.lerp(bgBottom, other.bgBottom, t)!,
      surface0: Color.lerp(surface0, other.surface0, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      iconMuted: Color.lerp(iconMuted, other.iconMuted, t)!,
      blueAccent: Color.lerp(blueAccent, other.blueAccent, t)!,
      lavenderGlow: Color.lerp(lavenderGlow, other.lavenderGlow, t)!,
      goldAccent: Color.lerp(goldAccent, other.goldAccent, t)!,
      mintAccent: Color.lerp(mintAccent, other.mintAccent, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
    );
  }
}

class AppTheme {
  static ThemeData dark() => _build(AppThemeColors.dark, Brightness.dark);
  static ThemeData light() => _build(AppThemeColors.light, Brightness.light);
  static ThemeData magical() =>
      _build(AppThemeColors.magical, Brightness.dark);

  static ThemeData _build(AppThemeColors colors, Brightness brightness) {
    final base = ThemeData(brightness: brightness);
    return base.copyWith(
      useMaterial3: true,
      scaffoldBackgroundColor: colors.surface0,
      colorScheme: base.colorScheme.copyWith(
        primary: colors.lavenderGlow, // Use purple as primary
        onPrimary: Colors.white,
        secondary: colors.blueAccent,
        onSecondary: Colors.white,
        surface: colors.surface1,
        onSurface: colors.textPrimary,
        background: colors.surface0,
        onBackground: colors.textPrimary,
      ),
      textTheme: base.textTheme.copyWith(
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          color: colors.textSecondary,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: colors.textSecondary,
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          color: colors.textSecondary,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
      ),
      iconTheme: IconThemeData(
        color: colors.iconMuted,
      ),
      dividerColor: colors.divider,
      cardTheme: CardThemeData(
        color: colors.glassFill,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        elevation: 0,
        shadowColor: Colors.black.withOpacity(0.08),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.lavenderGlow, // Purple primary
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.lavenderGlow,
          side: BorderSide(color: colors.lavenderGlow.withOpacity(0.5), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        colors,
      ],
    );
  }
}
