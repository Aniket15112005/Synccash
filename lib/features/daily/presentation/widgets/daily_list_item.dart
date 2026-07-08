// lib/features/daily/presentation/widgets/daily_list_item.dart
//
// Simplified row widget for Daily entries — adapted from
// transaction_list_item.dart but with no category tag, no bill number,
// and no party-picker/edit-sheet complexity (Daily entries have no category
// and no bill linking).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/daily/domain/entities/daily_entry_entity.dart';
import 'package:synccash/features/daily/presentation/providers/daily_provider.dart';

const _kDailyAccent = Color(0xFF8B5CF6);

final _timeFmt = DateFormat('hh:mm a');
final _dateFmt = DateFormat('dd MMM yyyy');

class DailyListItem extends ConsumerWidget {
  final DailyEntryEntity entry;
  final String? currentUserId;
  final bool showTimeline;
  final bool isLastInGroup;

  const DailyListItem({
    super.key,
    required this.entry,
    this.currentUserId,
    this.showTimeline = false,
    this.isLastInGroup = false,
  });

  void _showActions(BuildContext context, WidgetRef ref) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => _DailyActionSheet(
        entry: entry,
        onDelete: () {
          Navigator.pop(sheetCtx);
          _confirmDelete(context, ref);
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF161922),
        title: const Text('Delete this entry?',
            style: TextStyle(
                color: Color(0xFFe5e7eb),
                fontWeight: FontWeight.w700,
                fontSize: 17)),
        content: Text(
          '₹${entry.amount.toStringAsFixed(0)} ${entry.type} entry will be '
          'permanently removed from Daily.',
          style: const TextStyle(
              color: Color(0xFF9ca3af), fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6b7280))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3d1f1f),
              foregroundColor: const Color(0xFFf87171),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref.read(dailyRepositoryProvider).deleteEntry(entry);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete: $e')),
                  );
                }
              }
            },
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIncome = entry.type.toLowerCase() == 'income';
    final isMe = entry.createdBy == currentUserId;
    final title = entry.description.isEmpty ? 'Daily entry' : entry.description;
    final timeStr = _timeFmt.format(entry.createdAt);
    final amountStr =
        '${isIncome ? '+' : '−'}₹${CurrencyFormatter.format(entry.amount)}';

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => _showActions(context, ref),
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showTimeline)
              SizedBox(
                width: 28,
                child: Column(children: [
                  const SizedBox(height: 18),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isIncome
                          ? _kDailyAccent.withValues(alpha: 0.75)
                          : const Color(0x70828FA0),
                      border: Border.all(
                        color: isIncome
                            ? _kDailyAccent.withValues(alpha: 0.35)
                            : const Color(0x3C828FA0),
                        width: 1,
                      ),
                    ),
                  ),
                  if (!isLastInGroup)
                    Expanded(
                      child: Container(
                        width: 1,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        color: const Color(0x0DFFFFFF),
                      ),
                    ),
                ]),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: showTimeline ? 4 : 0,
                  top: 10,
                  bottom: isLastInGroup ? 0 : 2,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            _DailyTag(
                              label: isIncome ? 'INCOME' : 'EXPENSE',
                              color: isIncome
                                  ? const Color(0xFF5CB87A)
                                  : const Color(0xFFD96C6C),
                            ),
                            const SizedBox(width: 5),
                            _DailyTag(
                              label: entry.creatorName.toUpperCase(),
                              highlight: isMe,
                            ),
                          ]),
                          const SizedBox(height: 5),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                              color: isIncome
                                  ? const Color(0xEDD7E1EE)
                                  : const Color(0xD0A5B0C0),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_dateFmt.format(entry.createdAt)}  ·  $timeStr',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        amountStr,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                          letterSpacing: -0.3,
                          color: isIncome
                              ? const Color(0xF0E1EBF8)
                              : const Color(0xCCA0AEBE),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyTag extends StatelessWidget {
  const _DailyTag({required this.label, this.highlight = false, this.color});
  final String label;
  final bool highlight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bg = color != null
        ? color!.withValues(alpha: 0.14)
        : (highlight ? const Color(0x2A8B5CF6) : const Color(0x1AFFFFFF));
    final fg = color ?? (highlight ? _kDailyAccent : const Color(0x997A8A9E));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.2,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: fg,
        ),
      ),
    );
  }
}

class _DailyActionSheet extends StatelessWidget {
  const _DailyActionSheet({required this.entry, required this.onDelete});
  final DailyEntryEntity entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isIncome = entry.type.toLowerCase() == 'income';
    final title = entry.description.isEmpty ? 'Daily entry' : entry.description;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF161922),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 32,
          height: 3,
          decoration: BoxDecoration(
            color: const Color(0xFF374151),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0C0E12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1F2937)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFD1D9E6),
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${entry.creatorName}  ·  ${_dateFmt.format(entry.createdAt)}',
                      style:
                          const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '${isIncome ? '+' : '−'}₹${CurrencyFormatter.format(entry.amount)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                  letterSpacing: -0.5,
                  color: isIncome
                      ? const Color(0xF0E1EBF8)
                      : const Color(0xCCA0AEBE),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onDelete();
          },
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFf87171)),
              SizedBox(width: 12),
              Text('Delete',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFf87171))),
            ]),
          ),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}
