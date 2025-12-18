import 'package:flutter/material.dart';

class AppColors {
  static const bgTop = Color(0xFF0A1226);
  static const bgBottom = Color(0xFF17365A);
  static const textPrimary = Color(0xFFF4F7FF);
  static const textSecondary = Color(0xFFB7C4DD);
  static const glassFill = Color(0x1FFFFFFF);
  static const glassBorder = Color(0x33FFFFFF);
  static const divider = Color(0x26FFFFFF);
  static const glow = Color(0x33FFFFFF);
  static const accent = Color(0xFF9FB7FF);
}

class AppTheme {
  static ThemeData build() {
    final base = ThemeData.dark();
    return base.copyWith(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bgTop,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accent,
        onPrimary: AppColors.textPrimary,
        surface: AppColors.glassFill,
        onSurface: AppColors.textPrimary,
        background: AppColors.bgTop,
        onBackground: AppColors.textPrimary,
      ),
      textTheme: base.textTheme.copyWith(
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
      ),
      iconTheme: const IconThemeData(
        color: AppColors.textPrimary,
      ),
      dividerColor: AppColors.divider,
      cardTheme: CardThemeData(
        color: AppColors.glassFill,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.textPrimary,
          foregroundColor: const Color(0xFF0B1430),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.divider),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
