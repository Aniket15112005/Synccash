import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/cashbook/presentation/providers/cashbook_provider.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen>
    with SingleTickerProviderStateMixin {
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();
  bool _createLoading = false;
  bool _joinLoading = false;
  late final AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _bgController.dispose();
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _createLedger() async {
    if (_createLoading) return;
    setState(() => _createLoading = true);
    try {
      final user = ref.read(authProvider).value;
      if (user != null) {
        await ref.read(cashbookRepositoryProvider).createCashbook(user.uid);
      }
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
        setState(() => _createLoading = false);
      }
    }
  }

  Future<void> _joinLedger() async {
    final code = _codeController.text.trim();
    if (code.length != 6 || _joinLoading) return;
    _codeFocus.unfocus();
    setState(() => _joinLoading = true);
    try {
      final user = ref.read(authProvider).value;
      await ref.read(cashbookRepositoryProvider).joinCashbook(user!.uid, code);
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
        setState(() => _joinLoading = false);
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF2a1f1f),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111318),
      body: Stack(children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _bgController,
            builder: (_, __) => CustomPaint(
              painter: _NetworkPainter(_bgController.value),
            ),
          ),
        ),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                _buildHeader(),
                const SizedBox(height: 36),
                _buildCreateCard(),
                const SizedBox(height: 20),
                _buildDivider(),
                const SizedBox(height: 20),
                _buildJoinCard(),
                const SizedBox(height: 28),
                _buildFooter(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildHeader() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF4f6ef7), Color(0xFF8b5cf6)],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.sync_alt_rounded, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 10),
        const Text('SYNCCASH',
            style: TextStyle(
              color: Color(0xFF6b7280),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.5,
            )),
      ]),
      const SizedBox(height: 20),
      const Text('Secure Sync',
          style: TextStyle(
            color: Color(0xFFe5e7eb),
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          )),
      const SizedBox(height: 6),
      const Text('Connect your financial network node',
          style: TextStyle(color: Color(0xFF6b7280), fontSize: 14)),
    ]);
  }

  Widget _buildCreateCard() {
    return _GlassCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _IconBadge(icon: Icons.grid_view_rounded, color: const Color(0xFF4f6ef7)),
          const SizedBox(width: 12),
          const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New Network Node',
                  style: TextStyle(color: Color(0xFFe5e7eb), fontSize: 15, fontWeight: FontWeight.w600)),
              SizedBox(height: 2),
              Text('Initialize a fresh financial ledger',
                  style: TextStyle(color: Color(0xFF6b7280), fontSize: 12)),
            ],
          )),
        ]),
        const SizedBox(height: 16),
        _GradientButton(
          label: 'Generate Sync Node Key',
          icon: Icons.add_rounded,
          loading: _createLoading,
          gradient: const LinearGradient(
            colors: [Color(0xFF4f6ef7), Color(0xFF6366f1)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          onTap: _createLedger,
        ),
      ],
    ));
  }

  Widget _buildDivider() {
    return Row(children: [
      Expanded(child: Container(height: 1, color: const Color(0xFF1f2937))),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: Text('OR CONNECT',
            style: TextStyle(
              color: Color(0xFF374151),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            )),
      ),
      Expanded(child: Container(height: 1, color: const Color(0xFF1f2937))),
    ]);
  }

  Widget _buildJoinCard() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _codeController,
      builder: (_, value, __) {
        final code = value.text;
        final isReady = code.length == 6;

        return _GlassCard(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _IconBadge(icon: Icons.link_rounded, color: const Color(0xFF8b5cf6)),
              const SizedBox(width: 12),
              const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Join via Invite',
                      style: TextStyle(color: Color(0xFFe5e7eb), fontSize: 15, fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text('Enter your 6-digit secure token',
                      style: TextStyle(color: Color(0xFF6b7280), fontSize: 12)),
                ],
              )),
            ]),
            const SizedBox(height: 16),

            // Token input field
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: const Color(0xFF1a1d25),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isReady
                      ? const Color(0xFF8b5cf6).withOpacity(0.5)
                      : const Color(0xFF2d3240),
                  width: 1.2,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: isReady ? const Color(0xFF8b5cf6) : const Color(0xFF4b5563),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    focusNode: _codeFocus,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    style: const TextStyle(
                      color: Color(0xFFe5e7eb),
                      fontSize: 20,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '_ _ _ _ _ _',
                      hintStyle: TextStyle(
                        color: Color(0xFF374151),
                        letterSpacing: 6,
                        fontSize: 18,
                      ),
                      counterText: '',
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) {
                      final digits = v.replaceAll(RegExp(r'\D'), '');
                      if (digits != v) {
                        _codeController.value = _codeController.value.copyWith(
                          text: digits,
                          selection: TextSelection.collapsed(offset: digits.length),
                        );
                      }
                    },
                  ),
                ),
                if (isReady)
                  Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22c55e).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, size: 14, color: Color(0xFF22c55e)),
                  ),
              ]),
            ),

            Padding(
              padding: const EdgeInsets.only(left: 4, top: 6, bottom: 12),
              child: Text('${code.length}/6 digits entered',
                  style: const TextStyle(color: Color(0xFF374151), fontSize: 11)),
            ),

            _GradientButton(
              label: 'Establish Connection',
              icon: Icons.arrow_forward_rounded,
              loading: _joinLoading,
              enabled: isReady,
              gradient: isReady
                  ? const LinearGradient(
                      colors: [Color(0xFF7c3aed), Color(0xFF8b5cf6)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : const LinearGradient(
                      colors: [Color(0xFF1f2937), Color(0xFF1f2937)]),
              onTap: _joinLedger,
            ),
          ],
        ));
      },
    );
  }

  Widget _buildFooter() {
    return const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.shield_outlined, size: 12, color: Color(0xFF374151)),
      SizedBox(width: 5),
      Text('All connections are end-to-end encrypted',
          style: TextStyle(color: Color(0xFF374151), fontSize: 11)),
    ]);
  }
}

// ─── Reusable widgets ─────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161922),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1f2937), width: 1),
      ),
      child: child,
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25), width: 1),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.gradient,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final bool loading, enabled;
  final Gradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (enabled && !loading) ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.45,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: double.infinity, height: 50,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 16,
                        color: enabled ? Colors.white : const Color(0xFF4b5563)),
                    const SizedBox(width: 8),
                    Text(label,
                        style: TextStyle(
                          color: enabled ? Colors.white : const Color(0xFF4b5563),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        )),
                  ]),
          ),
        ),
      ),
    );
  }
}

// ─── Background network painter ───────────────────────────────────────────────

class _NetworkPainter extends CustomPainter {
  _NetworkPainter(this.t);
  final double t;

  static const int _count = 55;
  static const double _linkDist = 130;
  static final List<_Node> _nodes = _generateNodes();

  static List<_Node> _generateNodes() {
    final rng = Random(42);
    return List.generate(_count, (_) => _Node(
      x:      rng.nextDouble(),
      y:      rng.nextDouble(),
      phase:  rng.nextDouble() * 2 * pi,
      speedX: (rng.nextDouble() - 0.5) * 0.018,
      speedY: (rng.nextDouble() - 0.5) * 0.018,
      radius: rng.nextDouble() * 1.4 + 0.6,
    ));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final angle = t * 2 * pi;
    final positions = _nodes.map((n) => Offset(
      ((n.x + sin(angle * n.speedX * 60 + n.phase) * 0.12) % 1.0) * size.width,
      ((n.y + cos(angle * n.speedY * 60 + n.phase + 1.2) * 0.12) % 1.0) * size.height,
    )).toList();

    final linePaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.7;
    final dotPaint  = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color.fromRGBO(150, 165, 185, 0.4);

    for (int i = 0; i < _count; i++) {
      for (int j = i + 1; j < _count; j++) {
        final d = (positions[i] - positions[j]).distance;
        if (d < _linkDist) {
          linePaint.color = Color.fromRGBO(140, 155, 175, (1 - d / _linkDist) * 0.13);
          canvas.drawLine(positions[i], positions[j], linePaint);
        }
      }
    }
    for (int i = 0; i < _count; i++) {
      canvas.drawCircle(positions[i], _nodes[i].radius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_NetworkPainter old) => old.t != t;
}

class _Node {
  const _Node({
    required this.x, required this.y, required this.phase,
    required this.speedX, required this.speedY, required this.radius,
  });
  final double x, y, phase, speedX, speedY, radius;
}