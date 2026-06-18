import 'package:flutter/material.dart';

class AppTheme {
  static const _green = Color(0xFF4CAF50);
  static const _bgLight = Color(0xFFFAF9F6);

  static final light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _green,
      brightness: Brightness.light,
      surface: _bgLight,
    ),
    scaffoldBackgroundColor: _bgLight,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _green,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.grey[700],
        side: BorderSide(color: Colors.grey[300]!),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _bgLight,
      elevation: 0,
      centerTitle: true,
    ),
  );
}
