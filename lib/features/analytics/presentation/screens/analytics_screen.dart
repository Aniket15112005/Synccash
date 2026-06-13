import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import 'package:synccash/features/analytics/presentation/providers/analytics_provider.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────
const _bg        = Color(0xFF0D0F13);
const _cardBg    = Color(0xFF181B22);
const _cardBdr   = Color(0xFF252830);
const _textPri   = Colors.white;
const _textSec   = Color(0xFF7A8494);
const _retail    = Color(0xFF5B8DEF);
const _wholesale = Color(0xFFEFA83D);
const _incCol    = Color(0xFF4DB87E);
const _expCol    = Color(0xFFE05C5C);
const _c1        = Color(0xFF9B76FF);
const _c2        = Color(0xFF4ECDC4);
const _c3        = Color(0xFFFF8C69);

final _chartColors = [_retail, _wholesale, _c1, _c2, _c3,
  const Color(0xFFF06292), const Color(0xFF81C784)];

// ─── Screen ───────────────────────────────────────────────────────────────────
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bgCtrl;
  late final AnimationController _entryCtrl;
  int _pieTouched = -1;
  int _catTouched = -1;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(vsync: this,
        duration: const Duration(seconds: 12))..repeat(reverse: true);
    _entryCtrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 700))..forward();
  }

  @override
  void dispose() { _bgCtrl.dispose(); _entryCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cashbookId = ref.watch(currentCashbookIdProvider);
    if (cashbookId == null) {
      return const Scaffold(backgroundColor: _bg,
          body: Center(child: Text('No cashbook', style: TextStyle(color: _textSec))));
    }
    final asyncData    = ref.watch(analyticsDataProvider(cashbookId));
    final activeFilter = ref.watch(analyticsFilterProvider);

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          _AnimBg(controller: _bgCtrl),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(context),
                _FilterBar(
                  active: activeFilter,
                  onSelect: (f) {
                    ref.read(analyticsFilterProvider.notifier).select(f);
                    setState(() { _pieTouched = -1; _catTouched = -1; });
                    _entryCtrl.forward(from: 0);
                  },
                ),
                Expanded(
                  child: asyncData.when(
                    loading: () => const Center(
                        child: CircularProgressIndicator(color: _retail, strokeWidth: 1.5)),
                    error: (e, _) => Center(child: Text('Error', style: TextStyle(color: _textSec))),
                    data: (data) => FadeTransition(
                      opacity: _entryCtrl,
                      child: _buildBody(data, activeFilter),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
    child: Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        const Text('Analytics', style: TextStyle(
            color: _textPri, fontSize: 22,
            fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        const Spacer(),
        _LiveBadge(),
      ],
    ),
  );

  Widget _buildBody(AnalyticsData data, AnalyticsFilter filter) {
    if (data.totalCount == 0) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bar_chart_rounded, color: _cardBdr, size: 56),
          const SizedBox(height: 14),
          Text('No entries for ${filter.label}',
              style: const TextStyle(color: _textSec, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('Try a wider time range',
              style: TextStyle(color: Color(0xFF4A4F5C), fontSize: 13)),
        ]),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _QuickStats(data: data),
        const SizedBox(height: 20),

        // ── SPENDING INSIGHTS ─────────────────────────────────────────────
        _SpendingInsights(data: data, entryCtrl: _entryCtrl),
        const SizedBox(height: 20),

        // ── DAY OF WEEK PATTERN ───────────────────────────────────────────
        _SectionCard(
          title: 'Spending Pattern',
          subtitle: 'Expense by day of week',
          icon: Icons.calendar_view_week_rounded,
          child: _DayOfWeekChart(data: data),
        ),
        const SizedBox(height: 16),

        // ── INCOME VS EXPENSE RATIO GAUGE ─────────────────────────────────
        _SectionCard(
          title: 'Income vs Expense Ratio',
          subtitle: 'How your money flows',
          icon: Icons.swap_horiz_rounded,
          child: _RatioGauge(data: data),
        ),
        const SizedBox(height: 16),

        // ── RETAIL VS WHOLESALE PIE ───────────────────────────────────────
        _SectionCard(
          title: 'Retail vs Wholesale',
          subtitle: 'Total amount by sales type',
          icon: Icons.donut_large_rounded,
          child: _RetailWholesalePie(
            data: data,
            touchedIndex: _pieTouched,
            onTouch: (i) => setState(() => _pieTouched = i),
          ),
        ),
        const SizedBox(height: 16),

        // ── CREATOR CHART ─────────────────────────────────────────────────
        _SectionCard(
          title: 'Entries by Creator',
          subtitle: 'Income & expense per person',
          icon: Icons.people_alt_rounded,
          child: _CreatorChart(data: data),
        ),
        const SizedBox(height: 16),

        // ── MONTHLY OVERVIEW ──────────────────────────────────────────────
        _SectionCard(
          title: 'Monthly Overview',
          subtitle: 'Income vs Expense trend',
          icon: Icons.bar_chart_rounded,
          child: _MonthlyChart(data: data),
        ),
        const SizedBox(height: 16),

        // ── CATEGORY BREAKDOWN ────────────────────────────────────────────
        _SectionCard(
          title: 'Category Breakdown',
          subtitle: 'All categories ranked by amount',
          icon: Icons.category_rounded,
          child: _CategoryBreakdown(
            data: data,
            touchedIndex: _catTouched,
            onTouch: (i) => setState(() => _catTouched = i),
          ),
        ),
        const SizedBox(height: 16),

        // ── SUMMARY REPORT ────────────────────────────────────────────────
        _SummaryReport(data: data),
      ]),
    );
  }
}

// ─── Animated background ──────────────────────────────────────────────────────
class _AnimBg extends StatelessWidget {
  final AnimationController controller;
  const _AnimBg({required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, __) {
      final t = controller.value;
      return Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(math.sin(t * math.pi * 2) * 0.5,
                              math.cos(t * math.pi) * 0.4),
            radius: 1.6,
            colors: [
              Color.lerp(const Color(0xFF151820), const Color(0xFF0D0F13), t)!,
              const Color(0xFF0D0F13),
            ],
          ),
        ),
      );
    },
  );
}

// ─── Live badge ───────────────────────────────────────────────────────────────
class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardBdr)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6,
          decoration: const BoxDecoration(color: _incCol, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      const Text('Live', style: TextStyle(color: _textSec, fontSize: 12)),
    ]),
  );
}

// ─── Filter bar ───────────────────────────────────────────────────────────────
class _FilterBar extends StatelessWidget {
  final AnalyticsFilter active;
  final ValueChanged<AnalyticsFilter> onSelect;
  const _FilterBar({required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 38,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: AnalyticsFilter.values.map((f) {
        final on = f == active;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onSelect(f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: on ? _retail : _cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: on ? _retail : _cardBdr),
              ),
              child: Text(f.label, style: TextStyle(
                color: on ? Colors.white : _textSec,
                fontSize: 13,
                fontWeight: on ? FontWeight.w600 : FontWeight.normal,
              )),
            ),
          ),
        );
      }).toList(),
    ),
  );
}

// ─── Section card wrapper ─────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Widget child;
  const _SectionCard({required this.title, required this.subtitle,
      required this.icon, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBdr)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(children: [
          Icon(icon, color: _textSec, size: 18),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(
                color: _textPri, fontWeight: FontWeight.w600, fontSize: 15)),
            Text(subtitle, style: const TextStyle(color: _textSec, fontSize: 12)),
          ]),
        ]),
      ),
      child,
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPENDING INSIGHTS — horizontal scroll cards with animated counters
// ═══════════════════════════════════════════════════════════════════════════════
class _SpendingInsights extends StatelessWidget {
  final AnalyticsData data;
  final AnimationController entryCtrl;
  const _SpendingInsights({required this.data, required this.entryCtrl});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(left: 2, bottom: 12),
        child: Text('Spending Insights',
            style: TextStyle(color: _textPri, fontSize: 17,
                fontWeight: FontWeight.w700, letterSpacing: 0.3)),
      ),
      SizedBox(
        height: 128,
        child: ListView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          children: [
            _InsightCard(
              delay: 0,
              icon: Icons.trending_up_rounded,
              color: _incCol,
              title: 'Daily Avg Expense',
              value: '₹${CurrencyFormatter.format(data.dailyAvgExpense)}',
              subtitle: 'over ${data.activeDays} active days',
              entryCtrl: entryCtrl,
            ),
            _InsightCard(
              delay: 60,
              icon: Icons.savings_rounded,
              color: data.savingsRate > 0.2 ? _incCol : _expCol,
              title: 'Savings Rate',
              value: '${(data.savingsRate * 100).toStringAsFixed(1)}%',
              subtitle: data.savingsRate > 0.2 ? 'healthy savings' : 'low savings',
              entryCtrl: entryCtrl,
              progressValue: data.savingsRate,
              progressColor: data.savingsRate > 0.2 ? _incCol : _expCol,
            ),
            _InsightCard(
              delay: 120,
              icon: Icons.category_rounded,
              color: _retail,
              title: 'Top Category',
              value: data.topCategoryName,
              subtitle: '₹${CurrencyFormatter.format(data.topCategoryAmount)}',
              entryCtrl: entryCtrl,
            ),
            _InsightCard(
              delay: 180,
              icon: Icons.calendar_today_rounded,
              color: _wholesale,
              title: 'Peak Spend Day',
              value: data.peakDayName,
              subtitle: '₹${CurrencyFormatter.format(data.peakDayAmount)} spent',
              entryCtrl: entryCtrl,
            ),
            _InsightCard(
              delay: 240,
              icon: Icons.star_rounded,
              color: _c1,
              title: 'Biggest Entry',
              value: data.highestTx != null
                  ? '₹${CurrencyFormatter.format(data.highestTx!.amount)}'
                  : '—',
              subtitle: data.highestTx?.category ?? '',
              entryCtrl: entryCtrl,
            ),
            _InsightCard(
              delay: 300,
              icon: Icons.receipt_long_rounded,
              color: _c2,
              title: 'Total Entries',
              value: '${data.totalCount}',
              subtitle: '${data.incomeCount} in · ${data.expenseCount} out',
              entryCtrl: entryCtrl,
            ),
          ],
        ),
      ),
    ]);
  }
}

class _InsightCard extends StatelessWidget {
  final int delay;
  final IconData icon;
  final Color color;
  final String title, value, subtitle;
  final AnimationController entryCtrl;
  final double? progressValue;
  final Color? progressColor;

  const _InsightCard({
    required this.delay,
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.entryCtrl,
    this.progressValue,
    this.progressColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: entryCtrl,
      builder: (_, child) {
        final progress = ((entryCtrl.value * 1000 - delay) / 300).clamp(0.0, 1.0);
        final curve = Curves.easeOutCubic.transform(progress);
        return Opacity(
          opacity: curve,
          child: Transform.translate(
            offset: Offset(20 * (1 - curve), 0),
            child: child,
          ),
        );
      },
      child: Container(
        width: 148,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cardBdr),
          // Subtle top accent line
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withOpacity(0.08), Colors.transparent],
            stops: const [0.0, 0.4],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 15),
              ),
            ]),
            const Spacer(),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3)),
            const SizedBox(height: 2),
            Text(title,
                style: const TextStyle(color: _textPri, fontSize: 11,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(subtitle,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _textSec, fontSize: 10)),
            if (progressValue != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progressValue,
                  backgroundColor: _cardBdr,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      progressColor ?? color),
                  minHeight: 3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DAY OF WEEK CHART
// ═══════════════════════════════════════════════════════════════════════════════
class _DayOfWeekChart extends StatelessWidget {
  final AnalyticsData data;
  const _DayOfWeekChart({required this.data});

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final dow = data.spendingByDayOfWeek;
    if (dow.isEmpty) {
      return const Padding(padding: EdgeInsets.all(32),
          child: Center(child: Text('No expense data', style: TextStyle(color: _textSec))));
    }

    double maxY = 0;
    for (int i = 1; i <= 7; i++) {
      final v = dow[i] ?? 0;
      if (v > maxY) maxY = v;
    }
    if (maxY == 0) maxY = 1;

    final groups = List.generate(7, (i) {
      final v = dow[i + 1] ?? 0;
      final isPeak = v == maxY && v > 0;
      return BarChartGroupData(x: i, barRods: [
        BarChartRodData(
          toY: v,
          width: 22,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          gradient: LinearGradient(
            begin: Alignment.bottomCenter, end: Alignment.topCenter,
            colors: isPeak
                ? [_expCol.withOpacity(0.7), _expCol]
                : [_retail.withOpacity(0.3), _retail.withOpacity(0.7)],
          ),
        ),
      ]);
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 16),
      child: Column(children: [
        SizedBox(
          height: 160,
          child: BarChart(BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY * 1.3,
            barGroups: groups,
            gridData: FlGridData(
              show: true, drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: _cardBdr, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              show: true,
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 28,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= 7) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_days[idx],
                        style: const TextStyle(color: _textSec, fontSize: 11)),
                  );
                },
              )),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => const Color(0xFF252830),
                getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                  '${_days[group.x]}\n',
                  const TextStyle(color: _textSec, fontSize: 11),
                  children: [TextSpan(
                    text: '₹${CurrencyFormatter.format(rod.toY)}',
                    style: const TextStyle(color: _expCol,
                        fontWeight: FontWeight.bold, fontSize: 13),
                  )],
                ),
              ),
            ),
          )),
        ),
        const SizedBox(height: 8),
        Text('Peak: ${data.peakDayName} · ₹${CurrencyFormatter.format(data.peakDayAmount)}',
            style: const TextStyle(color: _textSec, fontSize: 12)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INCOME VS EXPENSE RATIO GAUGE
// ═══════════════════════════════════════════════════════════════════════════════
class _RatioGauge extends StatelessWidget {
  final AnalyticsData data;
  const _RatioGauge({required this.data});

  @override
  Widget build(BuildContext context) {
    final ratio   = data.incomeExpenseRatio.clamp(0.0, 1.0);
    final total   = data.totalIncome + data.totalExpense;
    final incPct  = total > 0 ? data.totalIncome  / total * 100 : 50.0;
    final expPct  = total > 0 ? data.totalExpense / total * 100 : 50.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(children: [
        // Ratio bar
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Row(children: [
            Expanded(
              flex: (incPct * 10).round().clamp(1, 999),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOut,
                builder: (_, v, __) => Container(
                  height: 36,
                  color: _incCol.withOpacity(0.6 + 0.4 * v),
                  alignment: Alignment.center,
                  child: incPct > 15 ? Text('${incPct.toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white,
                          fontSize: 12, fontWeight: FontWeight.w600)) : null,
                ),
              ),
            ),
            Expanded(
              flex: (expPct * 10).round().clamp(1, 999),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOut,
                builder: (_, v, __) => Container(
                  height: 36,
                  color: _expCol.withOpacity(0.6 + 0.4 * v),
                  alignment: Alignment.center,
                  child: expPct > 15 ? Text('${expPct.toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white,
                          fontSize: 12, fontWeight: FontWeight.w600)) : null,
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          _ratioLabel(_incCol, 'Income', '₹${CurrencyFormatter.format(data.totalIncome)}',
              '${incPct.toStringAsFixed(1)}%'),
          const Spacer(),
          _ratioLabel(_expCol, 'Expense', '₹${CurrencyFormatter.format(data.totalExpense)}',
              '${expPct.toStringAsFixed(1)}%', rightAlign: true),
        ]),
      ]),
    );
  }

  Widget _ratioLabel(Color c, String label, String amt, String pct,
      {bool rightAlign = false}) {
    final align = rightAlign ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(crossAxisAlignment: align, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (!rightAlign) ...[
          Container(width: 8, height: 8,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        Text(label, style: const TextStyle(color: _textSec, fontSize: 12)),
        if (rightAlign) ...[
          const SizedBox(width: 6),
          Container(width: 8, height: 8,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        ],
      ]),
      const SizedBox(height: 2),
      Text(amt, style: TextStyle(color: c, fontSize: 14, fontWeight: FontWeight.w700)),
      Text(pct, style: const TextStyle(color: _textSec, fontSize: 11)),
    ]);
  }
}

// ─── Quick stats ──────────────────────────────────────────────────────────────
class _QuickStats extends StatelessWidget {
  final AnalyticsData data;
  const _QuickStats({required this.data});
  @override
  Widget build(BuildContext context) {
    final pos = data.netBalance >= 0;
    return Column(children: [
      Container(
        width: double.infinity, padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: _cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _cardBdr)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Net Balance', style: TextStyle(color: _textSec, fontSize: 13)),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: data.netBalance.abs()),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOut,
            builder: (_, v, __) => Text('₹${CurrencyFormatter.format(v)}',
                style: TextStyle(color: pos ? _incCol : _expCol,
                    fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          ),
          const SizedBox(height: 4),
          Text(pos ? '▲ Surplus' : '▼ Deficit',
              style: TextStyle(color: pos ? _incCol : _expCol,
                  fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _StatTile(label: 'Income',
            value: '₹${CurrencyFormatter.format(data.totalIncome)}',
            color: _incCol, sub: '${data.incomeCount} entries')),
        const SizedBox(width: 10),
        Expanded(child: _StatTile(label: 'Expense',
            value: '₹${CurrencyFormatter.format(data.totalExpense)}',
            color: _expCol, sub: '${data.expenseCount} entries')),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _StatTile(label: 'Transactions',
            value: '${data.totalCount}', color: _retail, sub: 'total entries')),
        const SizedBox(width: 10),
        Expanded(child: _StatTile(label: 'Avg. Amount',
            value: '₹${CurrencyFormatter.format(data.avgAmount)}',
            color: _wholesale, sub: 'per entry')),
      ]),
    ]);
  }
}

class _StatTile extends StatelessWidget {
  final String label, value, sub;
  final Color color;
  const _StatTile({required this.label, required this.value,
      required this.color, required this.sub});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBdr)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: _textSec, fontSize: 12)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 17)),
      const SizedBox(height: 2),
      Text(sub, style: const TextStyle(color: _textSec, fontSize: 11)),
    ]),
  );
}

// ─── Retail vs Wholesale pie ───────────────────────────────────────────────────
class _RetailWholesalePie extends StatelessWidget {
  final AnalyticsData data;
  final int touchedIndex;
  final ValueChanged<int> onTouch;
  const _RetailWholesalePie({required this.data,
      required this.touchedIndex, required this.onTouch});

  static Color _cc(String cat, int i) {
    final l = cat.toLowerCase();
    if (l.contains('retail'))    return _retail;
    if (l.contains('wholesale')) return _wholesale;
    return _chartColors[i % _chartColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final sorted = data.sortedCategories;
    if (sorted.isEmpty) return const Padding(padding: EdgeInsets.all(32),
        child: Center(child: Text('No data', style: TextStyle(color: _textSec))));
    final total = sorted.fold<double>(0, (s, e) => s + e.value);
    final sections = sorted.asMap().entries.map((e) {
      final i = e.key; final cat = e.value.key; final amt = e.value.value;
      final touched = i == touchedIndex;
      return PieChartSectionData(
        color: _cc(cat, i), value: amt,
        title: touched ? '₹${CurrencyFormatter.format(amt)}' : '',
        radius: touched ? 92.0 : 80.0,
        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        titlePositionPercentageOffset: 0.65,
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(children: [
        SizedBox(
          height: 220,
          child: Stack(alignment: Alignment.center, children: [
            PieChart(PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (FlTouchEvent ev, PieTouchResponse? r) {
                  if (!ev.isInterestedForInteractions || r == null ||
                      r.touchedSection == null) { onTouch(-1); return; }
                  onTouch(r.touchedSection!.touchedSectionIndex);
                },
              ),
              sections: sections, sectionsSpace: 2, centerSpaceRadius: 48,
            )),
            Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Total', style: TextStyle(color: _textSec, fontSize: 11)),
              Text('₹${CurrencyFormatter.format(total)}',
                  style: const TextStyle(color: _textPri,
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12, runSpacing: 8, alignment: WrapAlignment.center,
          children: sorted.asMap().entries.map((e) {
            final i = e.key; final cat = e.value.key; final amt = e.value.value;
            final pct = total > 0 ? (amt / total * 100) : 0;
            return _LegendItem(color: _cc(cat, i), label: cat,
                amount: '₹${CurrencyFormatter.format(amt)}',
                pct: '${pct.toStringAsFixed(1)}%');
          }).toList(),
        ),
      ]),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color; final String label, amount, pct;
  const _LegendItem({required this.color, required this.label,
      required this.amount, required this.pct});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 6),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: _textPri,
          fontSize: 12, fontWeight: FontWeight.w500)),
      Text('$amount · $pct', style: const TextStyle(color: _textSec, fontSize: 11)),
    ]),
  ]);
}

// ─── Creator bar chart ────────────────────────────────────────────────────────
class _CreatorChart extends StatelessWidget {
  final AnalyticsData data;
  const _CreatorChart({required this.data});
  @override
  Widget build(BuildContext context) {
    final creators = data.creators;
    if (creators.isEmpty) return const Padding(padding: EdgeInsets.all(32),
        child: Center(child: Text('No data', style: TextStyle(color: _textSec))));
    final cc = [_c1, _c2, _c3];
    double maxY = 0;
    for (final c in creators) {
      final inc = data.creatorIncome[c]  ?? 0;
      final exp = data.creatorExpense[c] ?? 0;
      if (inc > maxY) maxY = inc; if (exp > maxY) maxY = exp;
    }
    if (maxY == 0) maxY = 1;
    final groups = creators.asMap().entries.map((e) {
      final c = e.value;
      return BarChartGroupData(x: e.key, barsSpace: 4, barRods: [
        BarChartRodData(toY: data.creatorIncome[c]  ?? 0, color: _incCol, width: 14,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
        BarChartRodData(toY: data.creatorExpense[c] ?? 0, color: _expCol, width: 14,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
      ]);
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 16),
      child: Column(children: [
        SizedBox(height: 200,
          child: BarChart(BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY * 1.25, barGroups: groups,
            gridData: FlGridData(show: true, drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(color: _cardBdr, strokeWidth: 1)),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(show: true,
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 28,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= creators.length) return const SizedBox();
                  return Padding(padding: const EdgeInsets.only(top: 6),
                      child: Text(creators[idx].split(' ').first,
                          style: const TextStyle(color: _textSec, fontSize: 11)));
                },
              )),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF252830),
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${creators[gi]}\n${ri == 0 ? 'Income' : 'Expense'}\n',
                const TextStyle(color: _textSec, fontSize: 11),
                children: [TextSpan(
                  text: '₹${CurrencyFormatter.format(rod.toY)}',
                  style: TextStyle(color: ri == 0 ? _incCol : _expCol,
                      fontWeight: FontWeight.bold, fontSize: 13),
                )],
              ),
            )),
          )),
        ),
        const SizedBox(height: 12),
        ...creators.asMap().entries.map((e) {
          final c = e.value; final idx = e.key;
          return Padding(padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(width: 10, height: 10,
                  decoration: BoxDecoration(color: cc[idx % cc.length], shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(c, style: const TextStyle(
                  color: _textPri, fontWeight: FontWeight.w500, fontSize: 13))),
              Text('${data.creatorCount[c] ?? 0} entries',
                  style: const TextStyle(color: _textSec, fontSize: 12)),
              const SizedBox(width: 12),
              Text('₹${CurrencyFormatter.format(data.creatorIncome[c] ?? 0)}',
                  style: const TextStyle(color: _incCol, fontSize: 12)),
              const SizedBox(width: 6),
              Text('₹${CurrencyFormatter.format(data.creatorExpense[c] ?? 0)}',
                  style: const TextStyle(color: _expCol, fontSize: 12)),
            ]),
          );
        }),
      ]),
    );
  }
}

// ─── Monthly chart ────────────────────────────────────────────────────────────
class _MonthlyChart extends StatelessWidget {
  final AnalyticsData data;
  const _MonthlyChart({required this.data});
  @override
  Widget build(BuildContext context) {
    final months = data.sortedMonths;
    if (months.isEmpty) return const Padding(padding: EdgeInsets.all(32),
        child: Center(child: Text('No data', style: TextStyle(color: _textSec))));
    double maxY = 0;
    for (final m in months) {
      final inc = data.monthlyIncome[m]  ?? 0;
      final exp = data.monthlyExpense[m] ?? 0;
      if (inc > maxY) maxY = inc; if (exp > maxY) maxY = exp;
    }
    if (maxY == 0) maxY = 1;
    final fmt = DateFormat('MMM');
    final groups = months.asMap().entries.map((e) {
      final m = e.value;
      return BarChartGroupData(x: e.key, barsSpace: 3, barRods: [
        BarChartRodData(toY: data.monthlyIncome[m]  ?? 0, color: _incCol, width: 10,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
        BarChartRodData(toY: data.monthlyExpense[m] ?? 0, color: _expCol, width: 10,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
      ]);
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 16),
      child: Column(children: [
        SizedBox(height: 200,
          child: BarChart(BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY * 1.25, barGroups: groups,
            gridData: FlGridData(show: true, drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(color: _cardBdr, strokeWidth: 1)),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(show: true,
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 28,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= months.length) return const SizedBox();
                  final p = months[idx].split('-');
                  final dt = DateTime(int.parse(p[0]), int.parse(p[1]));
                  return Padding(padding: const EdgeInsets.only(top: 6),
                      child: Text(fmt.format(dt),
                          style: const TextStyle(color: _textSec, fontSize: 11)));
                },
              )),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF252830),
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${ri == 0 ? 'Income' : 'Expense'}\n',
                const TextStyle(color: _textSec, fontSize: 11),
                children: [TextSpan(
                  text: '₹${CurrencyFormatter.format(rod.toY)}',
                  style: TextStyle(color: ri == 0 ? _incCol : _expCol,
                      fontWeight: FontWeight.bold, fontSize: 13),
                )],
              ),
            )),
          )),
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _dot(_incCol, 'Income'), const SizedBox(width: 16), _dot(_expCol, 'Expense'),
        ]),
      ]),
    );
  }
  Widget _dot(Color c, String l) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(l, style: const TextStyle(color: _textSec, fontSize: 12)),
  ]);
}

// ─── Category breakdown ───────────────────────────────────────────────────────
class _CategoryBreakdown extends StatelessWidget {
  final AnalyticsData data;
  final int touchedIndex;
  final ValueChanged<int> onTouch;
  const _CategoryBreakdown({required this.data,
      required this.touchedIndex, required this.onTouch});

  static Color _cc(String cat, int i) {
    final l = cat.toLowerCase();
    if (l.contains('retail'))    return _retail;
    if (l.contains('wholesale')) return _wholesale;
    return _chartColors[i % _chartColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final sorted = data.sortedCategories;
    if (sorted.isEmpty) return const Padding(padding: EdgeInsets.all(32),
        child: Center(child: Text('No data', style: TextStyle(color: _textSec))));
    final total = sorted.fold<double>(0, (s, e) => s + e.value);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        children: sorted.asMap().entries.map((entry) {
          final i = entry.key; final cat = entry.value.key; final amt = entry.value.value;
          final count = data.categoryCount[cat] ?? 0;
          final pct = total > 0 ? amt / total : 0;
          final color = _cc(cat, i);
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 8, height: 8,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(cat, style: const TextStyle(
                    color: _textPri, fontSize: 13, fontWeight: FontWeight.w500))),
                Text('$count entries', style: const TextStyle(color: _textSec, fontSize: 12)),
                const SizedBox(width: 10),
                Text('₹${CurrencyFormatter.format(amt)}',
                    style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: pct.toDouble()),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOut,
                builder: (_, v, __) => ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: v, backgroundColor: _cardBdr,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 5,
                  ),
                ),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Summary report ───────────────────────────────────────────────────────────
class _SummaryReport extends StatelessWidget {
  final AnalyticsData data;
  const _SummaryReport({required this.data});

  static (String, int)? _top(AnalyticsData d) {
    if (d.creatorCount.isEmpty) return null;
    final t = d.creatorCount.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return (t.key, t.value);
  }

  @override
  Widget build(BuildContext context) {
    final highest = data.highestTx;
    final tc = _top(data);
    final sr = data.totalIncome > 0
        ? (data.netBalance / data.totalIncome * 100) : 0.0;

    return Container(
      decoration: BoxDecoration(color: _cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cardBdr)),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.summarize_rounded, color: _textSec, size: 18),
          const SizedBox(width: 8),
          const Text('Summary Report', style: TextStyle(
              color: _textPri, fontWeight: FontWeight.w600, fontSize: 15)),
        ]),
        const SizedBox(height: 16),
        _R(icon: Icons.arrow_upward_rounded,   color: _incCol, label: 'Total Income',
            value: '₹${CurrencyFormatter.format(data.totalIncome)}'),
        _R(icon: Icons.arrow_downward_rounded, color: _expCol, label: 'Total Expense',
            value: '₹${CurrencyFormatter.format(data.totalExpense)}'),
        _R(icon: Icons.account_balance_wallet_rounded,
            color: data.netBalance >= 0 ? _incCol : _expCol,
            label: 'Net Balance',
            value: '₹${CurrencyFormatter.format(data.netBalance.abs())}  ${data.netBalance >= 0 ? '▲' : '▼'}'),
        const Divider(color: _cardBdr, height: 24),
        if (highest != null) ...[
          _R(icon: Icons.star_rounded, color: _wholesale, label: 'Highest Entry',
              value: '₹${CurrencyFormatter.format(highest.amount)} · ${highest.category}'),
          _R(icon: Icons.person_rounded, color: _retail, label: 'By', value: highest.creatorName),
        ],
        if (tc != null)
          _R(icon: Icons.emoji_events_rounded, color: _c1, label: 'Most Active',
              value: '${tc.$1} · ${tc.$2} entries'),
        _R(icon: Icons.savings_rounded,
            color: sr >= 0 ? _incCol : _expCol,
            label: 'Savings Rate', value: '${sr.toStringAsFixed(1)}%'),
        _R(icon: Icons.receipt_long_rounded, color: _textSec, label: 'Total Entries',
            value: '${data.totalCount}  (${data.incomeCount} in · ${data.expenseCount} out)'),
      ]),
    );
  }
}

class _R extends StatelessWidget {
  final IconData icon; final Color color; final String label, value;
  const _R({required this.icon, required this.color,
      required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [
      Container(width: 30, height: 30,
        decoration: BoxDecoration(color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 16)),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(color: _textSec, fontSize: 13)),
      const Spacer(),
      Flexible(child: Text(value,
          style: const TextStyle(color: _textPri,
              fontWeight: FontWeight.w500, fontSize: 13),
          textAlign: TextAlign.end)),
    ]),
  );
}
