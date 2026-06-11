import 'dart:math';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // All staggered animations on one 1300 ms controller
  late final Animation<double> _ringsIn;
  late final Animation<double> _particleOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _nameOpacity;
  late final Animation<double> _nameSlide;
  late final Animation<double> _ruleWidth;
  late final Animation<double> _tagOpacity;
  late final Animation<double> _shimmerPos;
  late final Animation<double> _breathe;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );

    Animation<double> iv(double s, double e, [Curve c = Curves.easeOut]) =>
        CurvedAnimation(parent: _ctrl, curve: Interval(s, e, curve: c));

    _ringsIn         = iv(0.0,  0.55);
    _particleOpacity = iv(0.05, 0.45);
    _logoScale       = iv(0.10, 0.50, const _Spring());
    _logoOpacity     = iv(0.10, 0.38);
    _nameOpacity     = iv(0.38, 0.65);
    _nameSlide       = iv(0.38, 0.65, Curves.easeOutCubic);
    _ruleWidth       = iv(0.45, 0.68);
    _tagOpacity      = iv(0.55, 0.80);
    _shimmerPos      = iv(0.42, 0.82, Curves.easeInOut);
    _breathe         = Tween<double>(begin: 1.0, end: 0.72).animate(
        CurvedAnimation(parent: _ctrl,
            curve: const Interval(0.50, 1.0, curve: Curves.easeInOut)));

    _ctrl.forward().then((_) {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080a0e),
      body: Stack(children: [
        // Background rings + particles
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CustomPaint(
              painter: _SplashBgPainter(
                ringsProgress:   _ringsIn.value,
                particleOpacity: _particleOpacity.value,
                breathe:         1 + 0.014 * sin(_ctrl.value * 2 * pi * 2),
                ctrlValue:       _ctrl.value,
              ),
            ),
          ),
        ),

        // Scan line
        AnimatedBuilder(
          animation: _ringsIn,
          builder: (_, __) {
            final p = _ringsIn.value;
            if (p <= 0 || p >= 1) return const SizedBox.shrink();
            return Positioned(
              top: MediaQuery.of(context).size.height * p,
              left: 0, right: 0,
              child: Opacity(
                opacity: (0.5 - (p - 0.5).abs()) * 1.4,
                child: Container(
                  height: 1,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.transparent,
                      Color(0x3DC8D6E8),
                      Color(0x61C8D6E8),
                      Color(0x3DC8D6E8),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
            );
          },
        ),

        // Centre content
        Center(
          child: Transform.translate(
            offset: const Offset(0, -28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Logo
              AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => Opacity(
                  opacity: _logoOpacity.value,
                  child: Transform.scale(
                    scale: 0.35 + _logoScale.value * 0.65,
                    child: _LogoBox(breatheOpacity: _breathe.value),
                  ),
                ),
              ),
              const SizedBox(height: 26),

              // App name + shimmer
              AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => Opacity(
                  opacity: _nameOpacity.value,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - _nameSlide.value)),
                    child: Stack(alignment: Alignment.center, children: [
                      const Text('SyncCash',
                          style: TextStyle(
                            color: Color(0xCDD0D8E8),
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                            height: 1,
                          )),
                      ShaderMask(
                        shaderCallback: (rect) {
                          final pos = -0.3 + _shimmerPos.value * 1.6;
                          return LinearGradient(
                            colors: const [
                              Colors.transparent,
                              Color(0x99FFFFFF),
                              Color(0x44FFFFFF),
                              Colors.transparent,
                            ],
                            stops: [
                              (pos - 0.18).clamp(0.0, 1.0),
                              pos.clamp(0.0, 1.0),
                              (pos + 0.05).clamp(0.0, 1.0),
                              (pos + 0.20).clamp(0.0, 1.0),
                            ],
                          ).createShader(rect);
                        },
                        child: const Text('SyncCash',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1,
                              height: 1,
                            )),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Rule
              AnimatedBuilder(
                animation: _ruleWidth,
                builder: (_, __) => SizedBox(
                  width: 80 * _ruleWidth.value,
                  height: 0.5,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.transparent,
                        Color(0x4DAAB9CD),
                        Colors.transparent,
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 11),

              // Tagline
              AnimatedBuilder(
                animation: _tagOpacity,
                builder: (_, __) => Opacity(
                  opacity: _tagOpacity.value,
                  child: const Text(
                    'FINANCIAL SYNC PLATFORM',
                    style: TextStyle(
                      color: Color(0xFF586474),
                      fontSize: 10,
                      letterSpacing: 2.8,
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ─── Logo box with corner brackets ──────────────────────────────────────────

class _LogoBox extends StatelessWidget {
  const _LogoBox({required this.breatheOpacity});
  final double breatheOpacity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88, height: 88,
      child: Stack(children: [
        Container(
          width: 88, height: 88,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0x24C3D0E1), width: 1),
            color: const Color(0x07FFFFFF),
          ),
          child: Center(
            child: Opacity(
              opacity: breatheOpacity,
              child: CustomPaint(size: const Size(42, 42), painter: _IconPainter()),
            ),
          ),
        ),
        // Corners
        Positioned(top: -1, left: -1,   child: _Corner(top: true,  left: true)),
        Positioned(top: -1, right: -1,  child: _Corner(top: true,  left: false)),
        Positioned(bottom: -1, left: -1,  child: _Corner(top: false, left: true)),
        Positioned(bottom: -1, right: -1, child: _Corner(top: false, left: false)),
      ]),
    );
  }
}

class _Corner extends StatelessWidget {
  const _Corner({required this.top, required this.left});
  final bool top, left;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 13, height: 13,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top:    top  ? const BorderSide(color: Color(0x8DD2DEEE), width: 1.5) : BorderSide.none,
            bottom: !top ? const BorderSide(color: Color(0x8DD2DEEE), width: 1.5) : BorderSide.none,
            left:   left  ? const BorderSide(color: Color(0x8DD2DEEE), width: 1.5) : BorderSide.none,
            right:  !left ? const BorderSide(color: Color(0x8DD2DEEE), width: 1.5) : BorderSide.none,
          ),
          borderRadius: BorderRadius.only(
            topLeft:     (top  && left)  ? const Radius.circular(4) : Radius.zero,
            topRight:    (top  && !left) ? const Radius.circular(4) : Radius.zero,
            bottomLeft:  (!top && left)  ? const Radius.circular(4) : Radius.zero,
            bottomRight: (!top && !left) ? const Radius.circular(4) : Radius.zero,
          ),
        ),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size sz) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = const Color(0xE5D7E1EE);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xF2D7E1EE);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xE5D7E1EE);

    final lx = sz.width * 0.285, rx = sz.width * 0.715, cy = sz.height * 0.5;
    canvas.drawCircle(Offset(lx, cy), 5.8, ring);
    canvas.drawCircle(Offset(rx, cy), 5.8, ring);
    canvas.drawLine(Offset(lx + 5.8, cy), Offset(rx - 5.8, cy), line);
    canvas.drawCircle(Offset(lx, cy), 2.2, fill);
    canvas.drawCircle(Offset(rx, cy), 2.2, fill);
  }
  @override
  bool shouldRepaint(_) => false;
}

// ─── Background painter ───────────────────────────────────────────────────────

class _SplashBgPainter extends CustomPainter {
  const _SplashBgPainter({
    required this.ringsProgress,
    required this.particleOpacity,
    required this.breathe,
    required this.ctrlValue,
  });
  final double ringsProgress, particleOpacity, breathe, ctrlValue;

  static const int _n = 52;
  static final List<_Pt> _pts = _makePts();

  static List<_Pt> _makePts() {
    double r(int n) { double x = sin(n + 1.0) * 43758.5453; return x - x.floor(); }
    return List.generate(_n, (i) => _Pt(
      angle: r(i * 3) * 2 * pi,
      dist:  0.12 + r(i * 7) * 0.42,
      dAngle: (r(i * 11) - 0.5) * 0.0005,
      rad:   r(i * 13) * 1.25 + 0.35,
      op:    r(i * 17) * 0.35 + 0.08,
    ));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final S  = min(size.width, size.height);

    const defs = [
      (s: 0.72, e: 0.48, a: 0.09, d: 0.00),
      (s: 0.90, e: 0.60, a: 0.06, d: 0.025),
      (s: 1.10, e: 0.75, a: 0.04, d: 0.050),
      (s: 1.32, e: 0.92, a: 0.028,d: 0.075),
    ];

    final rp = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.75;
    for (final rd in defs) {
      final p    = ((ringsProgress - rd.d) / (1 - rd.d)).clamp(0.0, 1.0);
      final ease = 1 - pow(1 - p, 3).toDouble();
      final R    = ((rd.s + (rd.e - rd.s) * ease) * S * 0.5) * breathe;
      rp.color   = Color.fromRGBO(210, 220, 232, rd.a * min(1.0, p * 3));
      canvas.drawCircle(Offset(cx, cy), R, rp);
    }

    // Tick marks
    final tf = ((ringsProgress - 0.6) / 0.4).clamp(0.0, 1.0);
    if (tf > 0) {
      final R = 0.48 * S * 0.5 * breathe;
      for (int i = 0; i < 24; i++) {
        final a = i / 24 * 2 * pi;
        final long = i % 6 == 0;
        rp
          ..strokeWidth = long ? 0.9 : 0.6
          ..color = Color.fromRGBO(200, 212, 226, (long ? 0.28 : 0.14) * tf);
        canvas.drawLine(
          Offset(cx + cos(a) * R, cy + sin(a) * R),
          Offset(cx + cos(a) * (R - (long ? 9.0 : 5.0)),
                 cy + sin(a) * (R - (long ? 9.0 : 5.0))),
          rp,
        );
      }
    }

    // Particles
    if (particleOpacity > 0) {
      final pp = Paint()..style = PaintingStyle.fill;
      for (final p in _pts) {
        p.angle += p.dAngle;
        pp.color = Color.fromRGBO(185, 198, 216, p.op * particleOpacity);
        canvas.drawCircle(
          Offset(cx + cos(p.angle) * p.dist * S * 0.5,
                 cy + sin(p.angle) * p.dist * S * 0.5),
          p.rad, pp,
        );
      }
    }

    // Centre glow
    final gf = ((ctrlValue - 0.30) / 0.20).clamp(0.0, 1.0);
    if (gf > 0) {
      canvas.drawCircle(Offset(cx, cy), 90,
        Paint()
          ..shader = RadialGradient(colors: [
            Color.fromRGBO(225, 232, 242, 0.05 * gf),
            const Color(0x00E1E8F2),
          ]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 90))
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_SplashBgPainter o) =>
      o.ringsProgress != ringsProgress || o.ctrlValue != ctrlValue;
}

class _Pt {
  _Pt({required this.angle, required this.dist,
       required this.dAngle, required this.rad, required this.op});
  double angle;
  final double dist, dAngle, rad, op;
}

class _Spring extends Curve {
  const _Spring();
  @override
  double transformInternal(double t) {
    const c1 = 1.70158, c3 = c1 + 1;
    return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2);
  }
}