// lib/features/daily/cards/presentation/widgets/daily_credit_card_widget.dart
//
// The animated "physical card" visual used across the Daily Cards
// sub-feature — the chooser screen and the card detail screen. Purely
// presentational; takes plain data in, has no Firestore/provider knowledge.

import 'package:flutter/material.dart';

/// Palette of card gradients. `colorIndex` on DailyCardEntity picks one of
/// these so a given card always renders the same way.
const List<List<Color>> kDailyCardGradients = [
  [Color(0xFF3A3A42), Color(0xFF17171B)], // graphite
  [Color(0xFF6D5DFB), Color(0xFF2E1F8F)], // violet
  [Color(0xFF1F8F6B), Color(0xFF0B3A2C)], // emerald
  [Color(0xFFE0A63A), Color(0xFF7A4A0A)], // amber
  [Color(0xFF3E7BFA), Color(0xFF12244F)], // sapphire
  [Color(0xFFD65C8A), Color(0xFF5A1638)], // rose
];

class DailyCreditCardWidget extends StatefulWidget {
  final String name;
  final String? number;
  final String? bankName;
  final int colorIndex;

  /// Renders a taller, more detailed card when true (detail screen); a
  /// compact version otherwise (chooser screen).
  final bool expanded;

  const DailyCreditCardWidget({
    super.key,
    required this.name,
    this.number,
    this.bankName,
    required this.colorIndex,
    this.expanded = false,
  });

  @override
  State<DailyCreditCardWidget> createState() => _DailyCreditCardWidgetState();
}

class _DailyCreditCardWidgetState extends State<DailyCreditCardWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheenController;

  @override
  void initState() {
    super.initState();
    _sheenController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _sheenController.dispose();
    super.dispose();
  }

  String get _maskedNumber {
    final raw = widget.number?.trim();
    if (raw == null || raw.isEmpty) return '•••• •••• •••• ••••';
    final digits = raw.replaceAll(RegExp(r'\s+'), '');
    final last4 =
        digits.length >= 4 ? digits.substring(digits.length - 4) : digits;
    return '•••• •••• •••• $last4';
  }

  @override
  Widget build(BuildContext context) {
    final gradient =
        kDailyCardGradients[widget.colorIndex % kDailyCardGradients.length];
    final height = widget.expanded ? 200.0 : 168.0;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Opacity(
        opacity: scale.clamp(0.0, 1.0),
        child: Transform.scale(scale: scale, child: child),
      ),
      child: Container(
        height: height,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: gradient.last.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Animated diagonal sheen sweep.
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: AnimatedBuilder(
                  animation: _sheenController,
                  builder: (context, _) {
                    final t = _sheenController.value;
                    return Align(
                      alignment: Alignment(-3 + t * 6, -1),
                      child: Transform.rotate(
                        angle: -0.5,
                        child: Container(
                          width: 90,
                          height: 400,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.0),
                                Colors.white.withValues(alpha: 0.10),
                                Colors.white.withValues(alpha: 0.0),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.bankName?.isNotEmpty == true
                          ? widget.bankName!
                          : 'Daily Card',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    Icon(Icons.wifi_rounded,
                        color: Colors.white.withValues(alpha: 0.85), size: 22),
                  ],
                ),
                // chip
                Container(
                  width: 38,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.85),
                        Colors.white.withValues(alpha: 0.45),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                Text(
                  _maskedNumber,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    Text(
                      'VISA',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
