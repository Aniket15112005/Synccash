// lib/features/daily/cards/presentation/screens/daily_cards_screen.dart
//
// "Choose a Card" screen — stacked/swipeable card chooser, opened from a
// button on the Daily dashboard. Tapping a card opens its detail screen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/daily/cards/domain/entities/daily_card_entity.dart';
import 'package:synccash/features/daily/cards/presentation/providers/daily_card_provider.dart';
import 'package:synccash/features/daily/cards/presentation/screens/daily_card_detail_screen.dart';
import 'package:synccash/features/daily/cards/presentation/widgets/daily_card_add_sheet.dart';
import 'package:synccash/features/daily/cards/presentation/widgets/daily_credit_card_widget.dart';

const _kAccent = Color(0xFF8B5CF6);
const _kBg = Color(0xFFE8E7E4);
const _kText = Color(0xFF1C1C1A);
const _kTextSub = Color(0xFF8A8882);
const _kCard = Color(0xFFF5F4F1);
const _kCardBorder = Color(0xFFF0EFED);

class DailyCardsScreen extends ConsumerStatefulWidget {
  const DailyCardsScreen({super.key});

  @override
  ConsumerState<DailyCardsScreen> createState() => _DailyCardsScreenState();
}

class _DailyCardsScreenState extends ConsumerState<DailyCardsScreen> {
  final PageController _pageController =
      PageController(viewportFraction: 0.78);
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      setState(() => _page = _pageController.page ?? 0);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cashbookId = ref.watch(currentCashbookIdProvider);

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: _kText),
        title: const Text('Choose a Card',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: _kText,
                letterSpacing: -0.3)),
        actions: [
          if (cashbookId != null)
            IconButton(
              icon: const Icon(Icons.add_rounded, color: _kAccent),
              onPressed: () {
                HapticFeedback.lightImpact();
                showAddDailyCardSheet(context, ref);
              },
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: cashbookId == null
          ? const Center(
              child: Text('No active cashbook',
                  style: TextStyle(color: _kTextSub)),
            )
          : Consumer(
              builder: (context, ref, _) {
                final asyncCards =
                    ref.watch(dailyCardsStreamProvider(cashbookId));
                return asyncCards.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(color: _kAccent)),
                  error: (e, _) => Center(
                    child: Text('Error: $e',
                        style: const TextStyle(color: _kTextSub)),
                  ),
                  data: (cards) {
                    if (cards.isEmpty) {
                      return _EmptyState(cashbookId: cashbookId);
                    }
                    return _CardsCarousel(
                      cards: cards,
                      pageController: _pageController,
                      page: _page,
                      cashbookId: cashbookId,
                    );
                  },
                );
              },
            ),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  final String cashbookId;
  const _EmptyState({required this.cashbookId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _kCard,
                shape: BoxShape.circle,
                border: Border.all(color: _kCardBorder),
              ),
              child: const Icon(Icons.credit_card_rounded,
                  color: _kAccent, size: 30),
            ),
            const SizedBox(height: 18),
            const Text('No cards yet',
                style: TextStyle(
                    color: _kText,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Add a card to start tracking its own\nincome, expenses and history.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kTextSub, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () => showAddDailyCardSheet(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add your first card'),
              style: FilledButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardsCarousel extends StatelessWidget {
  final List<DailyCardEntity> cards;
  final PageController pageController;
  final double page;
  final String cashbookId;
  const _CardsCarousel({
    required this.cards,
    required this.pageController,
    required this.page,
    required this.cashbookId,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        SizedBox(
          height: 300,
          child: PageView.builder(
            controller: pageController,
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final card = cards[index];
              final delta = (page - index).abs().clamp(0.0, 1.0);
              final scale = 1 - (delta * 0.14);
              final opacity = 1 - (delta * 0.35);

              return Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 24),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                DailyCardDetailScreen(card: card),
                          ),
                        );
                      },
                      child: DailyCreditCardWidget(
                        name: card.name,
                        number: card.number,
                        bankName: card.bankName,
                        colorIndex: card.colorIndex,
                        expanded: true,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(cards.length, (i) {
            final active = i == page.round();
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active
                    ? _kAccent
                    : _kTextSub.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
        const SizedBox(height: 18),
        Text('Tap a card to open it',
            style: TextStyle(color: _kTextSub.withValues(alpha: 0.8))),
      ],
    );
  }
}
