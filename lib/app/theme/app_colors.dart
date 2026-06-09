import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF0A0E17);
  static const Color surface = Color(0xFF141A29);
  static const Color surfaceVariant = Color(0xFF1E2638);
  
  static const Color primary = Color(0xFF2F6BFF);
  static const Color secondary = Color(0xFF00E5FF);
  
  static const Color income = Color(0xFF00E676);
  static const Color expense = Color(0xFFFF3D00);
  
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF7B8B9B);
  static const Color textMuted = Color(0xFF4E5D78);

  static const Color userABadge = Color(0xFF2979FF);
  static const Color userBBadge = Color(0xFF00C853);

  static const LinearGradient premiumGradient = LinearGradient(
    colors: [Color(0xFF2F6BFF), Color(0xFF00E5FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}