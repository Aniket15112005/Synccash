import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import 'package:synccash/features/analytics/presentation/providers/analytics_provider.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';

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

  void _showDrillDown(BuildContext ctx, List<TransactionEntity> txs, String title) {
    if (txs.isEmpty) return;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.2,
        maxChildSize: 0.78,
        expand: false,
        builder: (_, scrollController) => _DrillDownSheet(
          title: title,
          transactions: txs,
          scrollController: scrollController,
        ),
      ),
    );
  }

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
                    error: (e, _) => const Center(child: Text('Error', style: TextStyle(color: _textSec))),
                    data: (data) => FadeTransition(
                      opacity: _entryCtrl,
                      child: _buildBody(context, data, activeFilter),
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

  Widget _buildBody(BuildContext context, AnalyticsData data, AnalyticsFilter filter) {
    if (data.totalCount == 0) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.bar_chart_rounded, color: _cardBdr, size: 56),
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

        // ── BURN RATE FORECAST ────────────────────────────────────────────
        _BurnRateForecast(data: data),
        const SizedBox(height: 16),

        // ── DAY OF WEEK PATTERN ───────────────────────────────────────────
        _SectionCard(
          title: 'Spending Pattern',
          subtitle: 'Expense by day of week',
          icon: Icons.calendar_view_week_rounded,
          child: _DayOfWeekChart(
            data: data,
            onDrillDown: (txs, title) => _showDrillDown(context, txs, title),
          ),
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
          subtitle: 'Total amount by sales type — tap a section for details',
          icon: Icons.donut_large_rounded,
          child: _RetailWholesalePie(
            data: data,
            touchedIndex: _pieTouched,
            onTouch: (i) => setState(() => _pieTouched = i),
            onDrillDown: (txs, title) => _showDrillDown(context, txs, title),
          ),
        ),
        const SizedBox(height: 16),

        // ── CREATOR CHART ─────────────────────────────────────────────────
        _SectionCard(
          title: 'Entries by Creator',
          subtitle: 'Income & expense per person — tap a bar for details',
          icon: Icons.people_alt_rounded,
          child: _CreatorChart(
            data: data,
            onDrillDown: (txs, title) => _showDrillDown(context, txs, title),
          ),
        ),
        const SizedBox(height: 16),

        // ── MONTHLY OVERVIEW ──────────────────────────────────────────────
        _SectionCard(
          title: 'Monthly Overview',
          subtitle: 'Income vs Expense — tap a bar for details',
          icon: Icons.bar_chart_rounded,
          child: _MonthlyChart(
            data: data,
            onDrillDown: (txs, title) => _showDrillDown(context, txs, title),
          ),
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

        // ── RECURRING TRANSACTION DETECTOR ────────────────────────────────
        _RecurringDetector(
          data: data,
          onDrillDown: (txs, title) => _showDrillDown(context, txs, title),
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
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.08), Colors.transparent],
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
                  color: color.withValues(alpha: 0.15),
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
  final void Function(List<TransactionEntity>, String) onDrillDown;
  const _DayOfWeekChart({required this.data, required this.onDrillDown});

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
                ? [_expCol.withValues(alpha: 0.7), _expCol]
                : [_retail.withValues(alpha: 0.3), _retail.withValues(alpha: 0.7)],
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
              touchCallback: (FlTouchEvent event, BarTouchResponse? resp) {
                if (event is! FlTapUpEvent) return;
                if (resp == null || resp.spot == null) return;
                final gi = resp.spot!.touchedBarGroupIndex;
                if (gi < 0 || gi >= 7) return;
                final dow = gi + 1;
                final filtered = data.transactions
                    .where((tx) => tx.createdAt.weekday == dow && tx.type != 'income')
                    .toList()
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                onDrillDown(filtered, '${_days[gi]} · Expenses');
              },
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
    final total   = data.totalIncome + data.totalExpense;
    final incPct  = total > 0 ? data.totalIncome  / total * 100 : 50.0;
    final expPct  = total > 0 ? data.totalExpense / total * 100 : 50.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(children: [
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
                  color: _incCol.withValues(alpha: 0.6 + 0.4 * v),
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
                  color: _expCol.withValues(alpha: 0.6 + 0.4 * v),
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
  final void Function(List<TransactionEntity>, String) onDrillDown;
  const _RetailWholesalePie({required this.data,
      required this.touchedIndex, required this.onTouch,
      required this.onDrillDown});

  static Color _cc(String cat, int i) {
    final l = cat.toLowerCase();
    if (l.contains('retail'))    return _retail;
    if (l.contains('wholesale')) return _wholesale;
    return _chartColors[i % _chartColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final sorted = data.sortedCategories;
    if (sorted.isEmpty) {
      return const Padding(padding: EdgeInsets.all(32),
          child: Center(child: Text('No data', style: TextStyle(color: _textSec))));
    }
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
                  final idx = r.touchedSection!.touchedSectionIndex;
                  onTouch(idx);
                  if (ev is FlTapUpEvent && idx >= 0 && idx < sorted.length) {
                    final cat = sorted[idx].key;
                    final filtered = data.transactions
                        .where((tx) => tx.category == cat)
                        .toList()
                      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                    onDrillDown(filtered, '$cat · All Entries');
                  }
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
  final void Function(List<TransactionEntity>, String) onDrillDown;
  const _CreatorChart({required this.data, required this.onDrillDown});
  @override
  Widget build(BuildContext context) {
    final creators = data.creators;
    if (creators.isEmpty) {
      return const Padding(padding: EdgeInsets.all(32),
          child: Center(child: Text('No data', style: TextStyle(color: _textSec))));
    }
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
            barTouchData: BarTouchData(
              touchCallback: (FlTouchEvent event, BarTouchResponse? resp) {
                if (event is! FlTapUpEvent) return;
                if (resp == null || resp.spot == null) return;
                final gi = resp.spot!.touchedBarGroupIndex;
                final ri = resp.spot!.touchedRodDataIndex;
                if (gi < 0 || gi >= creators.length) return;
                final creator = creators[gi];
                final type = ri == 0 ? 'income' : 'expense';
                final filtered = data.transactions
                    .where((tx) => tx.creatorName == creator && tx.type == type)
                    .toList()
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                final label = '$creator · ${ri == 0 ? 'Income' : 'Expense'}';
                onDrillDown(filtered, label);
              },
              touchTooltipData: BarTouchTooltipData(
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
  final void Function(List<TransactionEntity>, String) onDrillDown;
  const _MonthlyChart({required this.data, required this.onDrillDown});
  @override
  Widget build(BuildContext context) {
    final months = data.sortedMonths;
    if (months.isEmpty) {
      return const Padding(padding: EdgeInsets.all(32),
          child: Center(child: Text('No data', style: TextStyle(color: _textSec))));
    }
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
            barTouchData: BarTouchData(
              touchCallback: (FlTouchEvent event, BarTouchResponse? resp) {
                if (event is! FlTapUpEvent) return;
                if (resp == null || resp.spot == null) return;
                final gi = resp.spot!.touchedBarGroupIndex;
                final ri = resp.spot!.touchedRodDataIndex;
                if (gi < 0 || gi >= months.length) return;
                final mk = months[gi];
                final type = ri == 0 ? 'income' : 'expense';
                final filtered = data.transactions.where((tx) {
                  final k = '${tx.createdAt.year}-${tx.createdAt.month.toString().padLeft(2, '0')}';
                  return k == mk && tx.type == type;
                }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                final parts = mk.split('-');
                final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]));
                final label = '${DateFormat('MMMM yyyy').format(dt)} · ${ri == 0 ? 'Income' : 'Expense'}';
                onDrillDown(filtered, label);
              },
              touchTooltipData: BarTouchTooltipData(
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
    if (sorted.isEmpty) {
      return const Padding(padding: EdgeInsets.all(32),
          child: Center(child: Text('No data', style: TextStyle(color: _textSec))));
    }
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
        const Row(children: [
          Icon(Icons.summarize_rounded, color: _textSec, size: 18),
          SizedBox(width: 8),
          Text('Summary Report', style: TextStyle(
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
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12),
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

// ═══════════════════════════════════════════════════════════════════════════════
// BURN RATE FORECAST
// ═══════════════════════════════════════════════════════════════════════════════
class _BurnRateForecast extends StatefulWidget {
  final AnalyticsData data;
  const _BurnRateForecast({required this.data});
  @override
  State<_BurnRateForecast> createState() => _BurnRateForecastState();
}

class _BurnRateForecastState extends State<_BurnRateForecast> {
  int _periodDays = 30;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: _periodDays));

    final recentExp = widget.data.transactions
        .where((tx) => tx.type != 'income' && tx.createdAt.isAfter(cutoff))
        .toList();
    final recentInc = widget.data.transactions
        .where((tx) => tx.type == 'income' && tx.createdAt.isAfter(cutoff))
        .toList();

    final totalExp = recentExp.fold<double>(0, (s, tx) => s + tx.amount);
    final totalInc = recentInc.fold<double>(0, (s, tx) => s + tx.amount);
    final dailyExp = totalExp / _periodDays;
    final dailyInc = totalInc / _periodDays;
    final netDaily = dailyInc - dailyExp;
    final balance  = widget.data.netBalance;

    int? daysLeft;
    if (dailyExp > 0 && balance > 0) {
      daysLeft = (balance / dailyExp).floor();
    }

    // Colour & status
    Color accent;
    String statusLabel;
    IconData statusIcon;
    if (daysLeft == null) {
      accent = _textSec;
      statusLabel = balance <= 0 ? 'Balance already negative' : 'No expenses in period';
      statusIcon = Icons.info_outline_rounded;
    } else if (daysLeft > 60) {
      accent = _incCol;
      statusLabel = 'Healthy runway';
      statusIcon = Icons.check_circle_outline_rounded;
    } else if (daysLeft > 30) {
      accent = _wholesale;
      statusLabel = 'Moderate — keep an eye on spending';
      statusIcon = Icons.warning_amber_rounded;
    } else {
      accent = _expCol;
      statusLabel = 'Low runway — reduce expenses';
      statusIcon = Icons.local_fire_department_rounded;
    }

    final progress = daysLeft == null ? 0.0 : (daysLeft / 90).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBdr),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.08), Colors.transparent],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.local_fire_department_rounded, color: accent, size: 17),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Burn Rate Forecast',
                    style: TextStyle(color: _textPri, fontWeight: FontWeight.w600, fontSize: 15)),
                Text('How long will your balance last?',
                    style: TextStyle(color: _textSec, fontSize: 12)),
              ]),
            ),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Period pills ─────────────────────────────────────────────
            Row(children: [
              const Text('Based on last', style: TextStyle(color: _textSec, fontSize: 12)),
              const SizedBox(width: 10),
              ...[30, 60, 90].map((d) {
                final on = d == _periodDays;
                return GestureDetector(
                  onTap: () => setState(() => _periodDays = d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: on ? accent : _cardBdr,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: on ? accent : Colors.transparent),
                    ),
                    child: Text('${d}d', style: TextStyle(
                      color: on ? Colors.white : _textSec,
                      fontSize: 12,
                      fontWeight: on ? FontWeight.w700 : FontWeight.normal,
                    )),
                  ),
                );
              }),
            ]),

            const SizedBox(height: 22),

            // ── Big number ───────────────────────────────────────────────
            if (daysLeft != null) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                TweenAnimationBuilder<double>(
                  key: ValueKey(_periodDays),
                  tween: Tween(begin: 0, end: daysLeft.toDouble()),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOut,
                  builder: (_, v, __) => Text('~${v.toInt()}',
                      style: TextStyle(
                          color: accent,
                          fontSize: 54,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -2)),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 6),
                  child: Text('days', style: TextStyle(
                      color: accent.withValues(alpha: 0.65),
                      fontSize: 20,
                      fontWeight: FontWeight.w600)),
                ),
              ]),
              Text(
                'At your current pace, your balance runs out in ~$daysLeft days',
                style: const TextStyle(color: _textSec, fontSize: 13, height: 1.4),
              ),
            ] else ...[
              Text('—', style: TextStyle(
                  color: accent, fontSize: 54, fontWeight: FontWeight.w900)),
              Text(statusLabel,
                  style: const TextStyle(color: _textSec, fontSize: 13)),
            ],

            const SizedBox(height: 20),

            // ── Status row ───────────────────────────────────────────────
            Row(children: [
              Icon(statusIcon, color: accent, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(statusLabel,
                    style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 8),

            // ── Runway bar ───────────────────────────────────────────────
            TweenAnimationBuilder<double>(
              key: ValueKey(_periodDays),
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOut,
              builder: (_, v, __) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: v,
                      backgroundColor: _cardBdr,
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                      minHeight: 10,
                    ),
                  ),
                  // 30-day and 60-day markers
                  ...[ (1/3, '30d'), (2/3, '60d') ].map((pair) {
                    return Positioned(
                      left: (MediaQuery.of(context).size.width - 64) * pair.$1 - 12,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Container(
                          width: 1,
                          color: _cardBg.withValues(alpha: 0.6),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 5),
            const Row(children: [
              Text('0d', style: TextStyle(color: _textSec, fontSize: 10)),
              Spacer(),
              Text('30d', style: TextStyle(color: _textSec, fontSize: 10)),
              Spacer(),
              Text('60d', style: TextStyle(color: _textSec, fontSize: 10)),
              Spacer(),
              Text('90d+', style: TextStyle(color: _textSec, fontSize: 10)),
            ]),

            const SizedBox(height: 18),
            const Divider(color: _cardBdr, height: 1),
            const SizedBox(height: 14),

            // ── Daily breakdown tiles ─────────────────────────────────────
            Row(children: [
              Expanded(child: _BurnTile(
                icon: Icons.arrow_downward_rounded,
                label: 'Daily Burn',
                value: '₹${CurrencyFormatter.format(dailyExp)}',
                color: _expCol,
              )),
              const SizedBox(width: 8),
              Expanded(child: _BurnTile(
                icon: Icons.arrow_upward_rounded,
                label: 'Daily Income',
                value: '₹${CurrencyFormatter.format(dailyInc)}',
                color: _incCol,
              )),
              const SizedBox(width: 8),
              Expanded(child: _BurnTile(
                icon: netDaily >= 0
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                label: 'Net / Day',
                value: '${netDaily >= 0 ? '+' : '-'}₹${CurrencyFormatter.format(netDaily.abs())}',
                color: netDaily >= 0 ? _incCol : _expCol,
              )),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _BurnTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _BurnTile({required this.icon, required this.label,
      required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.18)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 13),
      const SizedBox(height: 5),
      Text(value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: _textSec, fontSize: 10)),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// RECURRING TRANSACTION DETECTOR
// ═══════════════════════════════════════════════════════════════════════════════

class _RecurringItem {
  final String label;
  final String sublabel;
  final double avgAmount;
  final double totalAmount;
  final int count;
  final String type;       // 'income' or 'expense'
  final Color color;
  final List<String> months;
  final String detectedBy; // 'category' or 'description'

  const _RecurringItem({
    required this.label,
    required this.sublabel,
    required this.avgAmount,
    required this.totalAmount,
    required this.count,
    required this.type,
    required this.color,
    required this.months,
    required this.detectedBy,
  });
}

class _RecurringDetector extends StatefulWidget {
  final AnalyticsData data;
  final void Function(List<TransactionEntity>, String) onDrillDown;
  const _RecurringDetector({required this.data, required this.onDrillDown});
  @override
  State<_RecurringDetector> createState() => _RecurringDetectorState();
}

class _RecurringDetectorState extends State<_RecurringDetector> {
  int _tab = 0; // 0 = By Category, 1 = By Client / Description

  // ── Detection: group by category, require 2+ distinct months ─────────────
  List<_RecurringItem> _byCategory() {
    final txs = widget.data.transactions;
    final groups = <String, List<TransactionEntity>>{};
    for (final tx in txs) {
      groups.putIfAbsent(tx.category, () => []).add(tx);
    }
    final items = <_RecurringItem>[];
    for (final entry in groups.entries) {
      final list = entry.value;
      final months = <String>{};
      for (final tx in list) {
        months.add('${tx.createdAt.year}-${tx.createdAt.month.toString().padLeft(2, '0')}');
      }
      if (months.length < 2) continue;

      final incList = list.where((tx) => tx.type == 'income').toList();
      final expList = list.where((tx) => tx.type != 'income').toList();

      void addItem(List<TransactionEntity> sub, String type, Color col) {
        if (sub.isEmpty) return;
        final total = sub.fold<double>(0, (s, tx) => s + tx.amount);
        items.add(_RecurringItem(
          label: entry.key,
          sublabel: '${months.length} months  ·  ${sub.length}× recorded',
          avgAmount: total / sub.length,
          totalAmount: total,
          count: sub.length,
          type: type,
          color: col,
          months: months.toList()..sort(),
          detectedBy: 'category',
        ));
      }

      if (expList.isNotEmpty) addItem(expList, 'expense', _expCol);
      if (incList.isNotEmpty) addItem(incList, 'income',  _incCol);
    }

    final exp = items.where((i) => i.type == 'expense').toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    final inc = items.where((i) => i.type == 'income').toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    return [...exp, ...inc];
  }

  // ── Detection: group by normalised description (first 3 words) ────────────
  List<_RecurringItem> _byDescription() {
    final txs = widget.data.transactions
        .where((tx) => tx.description.trim().isNotEmpty)
        .toList();

    final groups = <String, List<TransactionEntity>>{};
    for (final tx in txs) {
      final raw   = tx.description.trim();
      final words = raw.split(RegExp(r'\s+')).take(3).join(' ').toLowerCase();
      if (words.isEmpty) continue;
      groups.putIfAbsent(words, () => []).add(tx);
    }

    final items = <_RecurringItem>[];
    for (final entry in groups.entries) {
      final list = entry.value;
      final months = <String>{};
      for (final tx in list) {
        months.add('${tx.createdAt.year}-${tx.createdAt.month.toString().padLeft(2, '0')}');
      }
      if (months.length < 2) continue;

      final incList = list.where((tx) => tx.type == 'income').toList();
      final expList = list.where((tx) => tx.type != 'income').toList();

      // Display label = full description of first transaction (capitalised)
      final raw = list.first.description.trim();
      final displayLabel = raw.length > 32 ? '${raw.substring(0, 30)}…' : raw;
      final catLabel = list.map((tx) => tx.category).toSet().join(', ');

      void addItem(List<TransactionEntity> sub, String type, Color col) {
        if (sub.isEmpty) return;
        final total = sub.fold<double>(0, (s, tx) => s + tx.amount);
        items.add(_RecurringItem(
          label: displayLabel,
          sublabel: '$catLabel  ·  ${months.length} months',
          avgAmount: total / sub.length,
          totalAmount: total,
          count: sub.length,
          type: type,
          color: col,
          months: months.toList()..sort(),
          detectedBy: 'description',
        ));
      }

      if (expList.isNotEmpty) addItem(expList, 'expense', _expCol);
      if (incList.isNotEmpty) addItem(incList, 'income',  _incCol);
    }

    final exp = items.where((i) => i.type == 'expense').toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    final inc = items.where((i) => i.type == 'income').toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    return [...exp, ...inc];
  }

  @override
  Widget build(BuildContext context) {
    final items = _tab == 0 ? _byCategory() : _byDescription();

    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBdr),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1060), Colors.transparent],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: _c1.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.repeat_rounded, color: _c1, size: 17),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Recurring Patterns',
                    style: TextStyle(color: _textPri, fontWeight: FontWeight.w600, fontSize: 15)),
                Text('Transactions repeating across months',
                    style: TextStyle(color: _textSec, fontSize: 12)),
              ]),
            ),
          ]),
        ),

        // ── Tab selector ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0D0F13),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(children: [
              _RecurringTab(
                label: 'By Category',
                icon: Icons.category_rounded,
                active: _tab == 0,
                onTap: () => setState(() => _tab = 0),
              ),
              _RecurringTab(
                label: 'By Client / Desc',
                icon: Icons.person_search_rounded,
                active: _tab == 1,
                onTap: () => setState(() => _tab = 1),
              ),
            ]),
          ),
        ),

        const SizedBox(height: 14),

        // ── Content ────────────────────────────────────────────────────────
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(children: [
              const Icon(Icons.search_off_rounded, color: _cardBdr, size: 40),
              const SizedBox(height: 10),
              Text(
                _tab == 1
                    ? 'No recurring patterns found in descriptions.\nMake sure transactions have descriptions filled in.'
                    : 'No recurring patterns found yet.\nPatterns appear when the same category appears in 2+ months.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textSec, fontSize: 13, height: 1.5),
              ),
            ]),
          )
        else ...[
          // ── Expense section ─────────────────────────────────────────────
          _RecurringSectionHeader(
            icon: Icons.arrow_downward_rounded,
            label: 'Expenses',
            color: _expCol,
            count: items.where((i) => i.type == 'expense').length,
          ),
          ...items.where((i) => i.type == 'expense').map((item) =>
            _RecurringRow(
              item: item,
              onDrillDown: () {
                final txs = widget.data.transactions.where((tx) {
                  if (item.detectedBy == 'category') {
                    return tx.category == item.label && tx.type != 'income';
                  } else {
                    final raw = tx.description.trim();
                    final key = raw.split(RegExp(r'\s+')).take(3).join(' ').toLowerCase();
                    final itemKey = item.label.toLowerCase().split(RegExp(r'\s+')).take(3).join(' ');
                    return key == itemKey && tx.type != 'income';
                  }
                }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                widget.onDrillDown(txs, '${item.label} · Recurring');
              },
            ),
          ),

          if (items.any((i) => i.type == 'income')) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(color: _cardBdr, height: 1),
            ),
            _RecurringSectionHeader(
              icon: Icons.arrow_upward_rounded,
              label: 'Income',
              color: _incCol,
              count: items.where((i) => i.type == 'income').length,
            ),
            ...items.where((i) => i.type == 'income').map((item) =>
              _RecurringRow(
                item: item,
                onDrillDown: () {
                  final txs = widget.data.transactions.where((tx) {
                    if (item.detectedBy == 'category') {
                      return tx.category == item.label && tx.type == 'income';
                    } else {
                      final raw = tx.description.trim();
                      final key = raw.split(RegExp(r'\s+')).take(3).join(' ').toLowerCase();
                      final itemKey = item.label.toLowerCase().split(RegExp(r'\s+')).take(3).join(' ');
                      return key == itemKey && tx.type == 'income';
                    }
                  }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                  widget.onDrillDown(txs, '${item.label} · Recurring');
                },
              ),
            ),
          ],

          const SizedBox(height: 8),
        ],
      ]),
    );
  }
}

class _RecurringTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _RecurringTab({required this.label, required this.icon,
      required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? _cardBg : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: active ? Border.all(color: _cardBdr) : null,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 13,
              color: active ? _c1 : _textSec),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              color: active ? _textPri : _textSec)),
        ]),
      ),
    ),
  );
}

class _RecurringSectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final int count;
  const _RecurringSectionHeader({required this.icon, required this.label,
      required this.color, required this.count});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Row(children: [
      Icon(icon, color: color, size: 13),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(
          color: color, fontSize: 12, fontWeight: FontWeight.w700,
          letterSpacing: 0.5)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('$count', style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    ]),
  );
}

class _RecurringRow extends StatelessWidget {
  final _RecurringItem item;
  final VoidCallback onDrillDown;
  const _RecurringRow({required this.item, required this.onDrillDown});

  String _monthBadge(String m) {
    final parts = m.split('-');
    if (parts.length < 2) return m;
    final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    return DateFormat('MMM yy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDrillDown,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: item.color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: item.color.withValues(alpha: 0.18)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Icon
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.repeat_rounded, color: item.color, size: 17),
          ),
          const SizedBox(width: 10),

          // Details
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _textPri, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                // Expense / Income badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.type == 'income' ? '↑ Income' : '↓ Expense',
                    style: TextStyle(color: item.color, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
              const SizedBox(height: 3),
              Text(item.sublabel,
                  style: const TextStyle(color: _textSec, fontSize: 11)),
              const SizedBox(height: 8),

              // Amount row
              Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('₹${CurrencyFormatter.format(item.avgAmount)}',
                      style: TextStyle(
                          color: item.color, fontSize: 14, fontWeight: FontWeight.w800)),
                  const Text('avg / occurrence',
                      style: TextStyle(color: _textSec, fontSize: 10)),
                ]),
                const SizedBox(width: 20),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('₹${CurrencyFormatter.format(item.totalAmount)}',
                      style: const TextStyle(
                          color: _textPri, fontSize: 13, fontWeight: FontWeight.w600)),
                  const Text('total across months',
                      style: TextStyle(color: _textSec, fontSize: 10)),
                ]),
                const Spacer(),
                // Tap hint
                Icon(Icons.chevron_right_rounded, color: item.color.withValues(alpha: 0.5), size: 18),
              ]),

              const SizedBox(height: 8),

              // Month chips
              Wrap(
                spacing: 5, runSpacing: 5,
                children: item.months.map((m) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: _cardBdr,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_monthBadge(m),
                      style: const TextStyle(color: _textSec, fontSize: 10)),
                )).toList(),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DRILL-DOWN BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════
class _DrillDownSheet extends StatelessWidget {
  final String title;
  final List<TransactionEntity> transactions;
  final ScrollController scrollController;

  const _DrillDownSheet({
    required this.title,
    required this.transactions,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final total    = transactions.fold<double>(0, (s, tx) => s + tx.amount);
    final hasInc   = transactions.any((tx) => tx.type == 'income');
    final hasExp   = transactions.any((tx) => tx.type != 'income');
    final incTotal = transactions.where((tx) => tx.type == 'income')
        .fold<double>(0, (s, tx) => s + tx.amount);
    final expTotal = transactions.where((tx) => tx.type != 'income')
        .fold<double>(0, (s, tx) => s + tx.amount);
    final isMixed  = hasInc && hasExp;
    final color    = isMixed ? _retail
        : (hasInc ? _incCol : _expCol);
    final fmt      = DateFormat('dd MMM · hh:mm a');

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF181B22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── Drag handle ──────────────────────────────────────────────────────
        Container(
          width: 38, height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF3A3F4B),
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // ── Header ───────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.receipt_long_rounded, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${transactions.length} entries',
                      style: const TextStyle(color: _textSec, fontSize: 12)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('₹${CurrencyFormatter.format(total)}',
                    style: TextStyle(color: color,
                        fontSize: 17, fontWeight: FontWeight.w800)),
                if (isMixed) ...[
                  const SizedBox(height: 2),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('↑₹${CurrencyFormatter.format(incTotal)}',
                        style: const TextStyle(color: _incCol, fontSize: 11)),
                    const SizedBox(width: 6),
                    Text('↓₹${CurrencyFormatter.format(expTotal)}',
                        style: const TextStyle(color: _expCol, fontSize: 11)),
                  ]),
                ],
              ]),
            ],
          ),
        ),

        const Divider(color: Color(0xFF252830), height: 1),

        // ── Transaction list ─────────────────────────────────────────────────
        Flexible(
          child: ListView.separated(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 24),
            itemCount: transactions.length,
            separatorBuilder: (_, __) =>
                const Divider(color: Color(0xFF1E2128), height: 1, indent: 68),
            itemBuilder: (_, i) {
              final tx    = transactions[i];
              final isInc = tx.type == 'income';
              final txCol = isInc ? _incCol : _expCol;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: txCol.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isInc ? Icons.arrow_upward_rounded
                             : Icons.arrow_downward_rounded,
                      color: txCol, size: 17,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(tx.category, style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                      if (tx.description.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(tx.description,
                            style: const TextStyle(
                                color: _textSec, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        '${tx.creatorName}  ·  ${fmt.format(tx.createdAt)}',
                        style: const TextStyle(
                            color: Color(0xFF4A4F5C), fontSize: 11),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(
                      '${isInc ? '+' : '-'}₹${CurrencyFormatter.format(tx.amount)}',
                      style: TextStyle(
                          color: txCol,
                          fontSize: 14,
                          fontWeight: FontWeight.w700),
                    ),
                  ]),
                ]),
              );
            },
          ),
        ),
        SizedBox(height: MediaQuery.of(context).padding.bottom),
      ]),
    );
  }
}
