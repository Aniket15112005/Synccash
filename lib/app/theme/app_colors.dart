import 'package:flutter/material.dart';

class AppColors {
  // ─────────────────────────────────────────────
  // BACKGROUND & SURFACES
  // ─────────────────────────────────────────────

  static const Color background = Color(0xFF111113);
  static const Color surface = Color(0xFF1A1A1D);
  static const Color surfaceVariant = Color(0xFF222226);

  static const Color border = Color(0xFF2C2C31);

  // ─────────────────────────────────────────────
  // PRIMARY BRAND COLORS
  // ─────────────────────────────────────────────

  static const Color primary = Color(0xFFB8B8C0);
  static const Color secondary = Color(0xFF8D8D96);

  // ─────────────────────────────────────────────
  // FINANCE COLORS
  // ─────────────────────────────────────────────

  static const Color income = Color(0xFF5CB87A);
  static const Color expense = Color(0xFFD96C6C);

  // ─────────────────────────────────────────────
  // TEXT COLORS
  // ─────────────────────────────────────────────

  static const Color textPrimary = Color(0xFFE8E8EA);
  static const Color textSecondary = Color(0xFF7A7A82);
  static const Color textMuted = Color(0xFF4A4A52);

  // ─────────────────────────────────────────────
  // USER BADGES
  // ─────────────────────────────────────────────

  static const Color userABadge = Color(0xFF70707A);
  static const Color userBBadge = Color(0xFF5CB87A);

  // ─────────────────────────────────────────────
  // TRANSACTION TAGS
  // ─────────────────────────────────────────────

  static const Color tag = Color(0xFF2A2A2E);
  static const Color tagText = Color(0xFF9A9AA4);

  // ─────────────────────────────────────────────
  // EXTRA COLORS FOR FUTURE UI
  // ─────────────────────────────────────────────

  static const Color cardDark = Color(0xFF16181C);
  static const Color cardDarker = Color(0xFF131417);

  static const Color grey100 = Color(0xFFF5F5F5);
  static const Color grey200 = Color(0xFFE5E5E5);
  static const Color grey300 = Color(0xFFD4D4D4);
  static const Color grey400 = Color(0xFFA3A3A3);
  static const Color grey500 = Color(0xFF737373);
  static const Color grey600 = Color(0xFF525252);
  static const Color grey700 = Color(0xFF404040);
  static const Color grey800 = Color(0xFF262626);
  static const Color grey900 = Color(0xFF171717);

  // ─────────────────────────────────────────────
  // GRADIENTS
  // ─────────────────────────────────────────────

  static const LinearGradient darkGradient = LinearGradient(
    colors: [
      Color(0xFF1A1A1D),
      Color(0xFF222226),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient premiumGradient = LinearGradient(
    colors: [
      Color(0xFF232328),
      Color(0xFF1A1A1D),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ─────────────────────────────────────────────
  // SHADOW COLORS
  // ─────────────────────────────────────────────

  static const Color shadowDark = Color(0x99000000);
  static const Color shadowLight = Color(0x22000000);
}