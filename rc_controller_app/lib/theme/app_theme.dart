import 'package:flutter/material.dart';

class AppTheme {
  // Base Colors
  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color surfaceHighlight = Color(0xFF2A2A2A);
  
  // Neon Accent Colors by Mode
  static const Color modeNormal = Color(0xFF00E5FF); // Cyan/Blue
  static const Color modeSport = Color(0xFFFF1744);  // Neon Red
  static const Color modeDrift = Color(0xFFD500F9);  // Purple
  static const Color modeCrawl = Color(0xFF00E676);  // Green
  
  static const Color estop = Color(0xFFFF3D00); // Red
  static const Color textMain = Colors.white;
  static const Color textMuted = Colors.white54;

  static Color getModeColor(String mode) {
    switch (mode) {
      case 'sport': return modeSport;
      case 'drift': return modeDrift;
      case 'crawl': return modeCrawl;
      case 'normal':
      default: return modeNormal;
    }
  }

  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: modeNormal,
        surface: surface,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: modeNormal,
        inactiveTrackColor: surfaceHighlight,
        thumbColor: modeNormal,
        overlayColor: modeNormal.withValues(alpha: 0.2),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: textMain, fontWeight: FontWeight.bold),
        bodyMedium: TextStyle(color: textMuted),
      ),
    );
  }
}
