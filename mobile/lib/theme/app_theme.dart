import 'package:flutter/material.dart';

class AppColors {
  static const Color sand = Color(0xFFD6C2A8);
  static const Color sunGold = Color(0xFFD4A84F);

  static const Color deepBlue = Color(0xFF1C2A3A);
  static const Color blueGrey = Color(0xFF6E7B87);

  static const Color textLight = Color(0xFFF2F2F2);
  static const Color textMuted = Color(0xFFCCCCCC);
}

class AppTheme {
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.sunGold,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: Colors.black,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: AppColors.textLight),
      ),

      // ✅ ElevatedButton (Left/Right etc.)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.sunGold,
          foregroundColor: AppColors.deepBlue,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ✅ FloatingActionButton (Settings/Refresh/Fav)
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.sand,
        foregroundColor: AppColors.deepBlue,
      ),
    );
  }
}
