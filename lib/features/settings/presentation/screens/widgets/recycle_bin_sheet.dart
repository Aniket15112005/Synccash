
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:synccash/core/utils/currency_formatter.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import 'package:synccash/features/transactions/data/services/recycle_bin_service.dart';
import 'package:synccash/features/transactions/domain/entities/deleted_bill_entity.dart';
import 'package:synccash/features/transactions/domain/entities/deleted_transaction_entity.dart';
import 'package:synccash/features/transactions/presentation/providers/recycle_bin_provider.dart';

final _dateFmt = DateFormat('dd MMM yyyy');

class RecycleBinSheet extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  const RecycleBinSheet({super.key, required this.onBack});

  @override
  ConsumerState<RecycleBinSheet> createState() => _RecycleBinSheetState();
}

class _RecycleBinSheetState extends ConsumerState<RecycleBinSheet> {
  bool _selectMode = false;
  final Set<String> _selected = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Clean up any expired items when the user opens the recycle bin
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cashbookId = ref.read(currentCashbookIdProvider);
      if (cashbookId != null) {
        RecycleBinService.cleanupExpired(cashbookId);
        RecycleBinService.cleanupExpiredBills(cashbookId);
      }
    });
  }

  void _toggleSelectMode(List<DeletedTransactionEntity> items) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) {
        _selected.clear();
      } else {
        // Select all by default when entering select mode
        _selected.addAll(items.map((tx) => tx.transactionId));
      }
    });
  }

  void _toggleItem(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _restoreAll(
      List<DeletedTransactionEntity> all) async {
    final targets =
        all.where((tx) => _selected.contains(tx.transactionId)).toList();
    if (targets.isEmpty) return;
    setState(() => _busy = true);
    try {
      await RecycleBinService.restoreAll(targets);
      if (mounted) {
        setState(() {
          _selectMode = false;
          _selected.clear();
          _busy = false;
        });
        _snack('${targets.length} entries restored', isError: false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('Restore failed: $e', isError: true);
      }
    }
  }

  Future<void> _deleteAll(
      List<DeletedTransactionEntity> all) async {
    final targets =
        all.where((tx) => _selected.contains(tx.transactionId)).toList();
    if (targets.isEmpty) return;

    final confirmed = await _confirmBulkDelete(targets.length);
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await RecycleBinService.deleteAll(targets);
      if (mounted) {
        setState(() {
          _selectMode = false;
          _selected.clear();
          _busy = false;
        });
        _snack('${targets.length} entries permanently deleted', isError: false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('Delete failed: $e', isError: true);
      }
    }
  }

  Future<bool> _confirmBulkDelete(int count) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: const Color(0xFF161922),
            title: Text(
              'Delete $count ${count == 1 ? 'entry' : 'entries'}?',
              style: const TextStyle(
                color: Color(0xFFe5e7eb),
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            content: const Text(
              'These entries will be permanently deleted and cannot be recovered.',
              style: TextStyle(
                  color: Color(0xFF9ca3af), fontSize: 14, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel',
                    style: TextStyle(color: Color(0xFF6b7280))),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3d1f1f),
                  foregroundColor: const Color(0xFFf87171),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete All',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showItemActions(DeletedTransactionEntity tx) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => _ItemActionSheet(
        tx: tx,
        onRestore: () async {
          Navigator.pop(sheetCtx);
          try {
            await RecycleBinService.restore(tx);
            if (mounted) _snack('Entry restored', isError: false);
          } catch (e) {
            if (mounted) _snack('Restore failed: $e', isError: true);
          }
        },
        onDelete: () async {
          Navigator.pop(sheetCtx);
          final confirmed = await _confirmBulkDelete(1);
          if (!confirmed || !mounted) return;
          try {
            await RecycleBinService.permanentDelete(tx);
            if (mounted) _snack('Entry permanently deleted', isError: false);
          } catch (e) {
            if (mounted) _snack('Delete failed: $e', isError: true);
          }
        },
      ),
    );
  }

  void _showBillActions(DeletedBillEntity bill) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => _BillActionSheet(
        bill: bill,
        onRestore: () async {
          Navigator.pop(sheetCtx);
          try {
            await RecycleBinService.restoreBill(bill);
            if (mounted) _snack('Bill restored', isError: false);
          } catch (e) {
            if (mounted) _snack('Restore failed: \$e', isError: true);
          }
        },
        onDelete: () async {
          Navigator.pop(sheetCtx);
          final confirmed = await _confirmBulkDelete(1);
          if (!confirmed || !mounted) return;
          try {
            await RecycleBinService.permanentDeleteBill(bill);
            if (mounted) _snack('Bill permanently deleted', isError: false);
          } catch (e) {
            if (mounted) _snack('Delete failed: \$e', isError: true);
          }
        },
      ),
    );
  }

  void _snack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
          isError ? const Color(0xFFef4444) : const Color(0xFF10b981),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cashbookId = ref.watch(currentCashbookIdProvider);

    if (cashbookId == null) {
      return const SizedBox.shrink();
    }

    final asyncTx    = ref.watch(deletedTransactionsProvider(cashbookId));
    final asyncBills = ref.watch(deletedBillsProvider(cashbookId));

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0F14),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ───────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 36,
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFF374151),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
            child: Row(
              children: [
                GestureDetector(
                  onTap: widget.onBack,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.arrow_back_ios_rounded,
                        size: 16, color: Color(0xFF6B7280)),
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Recycle Bin',
                  style: TextStyle(
                    color: Color(0xFFD1D9E6),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                // Select All — only applies to transaction entries
                asyncTx.when(
                  data: (items) => items.isEmpty
                      ? const SizedBox.shrink()
                      : GestureDetector(
                          onTap: () => _toggleSelectMode(items),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: _selectMode
                                  ? const Color(0xFF1F2937)
                                  : const Color(0xFF161922),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _selectMode
                                    ? const Color(0xFF374151)
                                    : const Color(0xFF1F2937),
                              ),
                            ),
                            child: Text(
                              _selectMode ? 'Cancel' : 'Select All',
                              style: TextStyle(
                                color: _selectMode
                                    ? const Color(0xFF9CA3AF)
                                    : const Color(0xFF3B82F6),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),

          // ── 15-day info banner ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111318),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1F2937)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                    size: 14, color: Color(0xFF6B7280)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Deleted entries are kept for 15 days then removed permanently.',
                    style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        height: 1.4),
                  ),
                ),
              ]),
            ),
          ),

          const SizedBox(height: 12),

          // ── List ──────────────────────────────────────────────────────────
          Builder(builder: (context) {
            // Show spinner only while the primary (transactions) stream is loading.
            // Bills stream loads independently; asyncBills.value ?? [] already handles
            // the not-yet-loaded / error case so the UI is never permanently blocked.
            if (asyncTx.isLoading) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: Color(0xFF374151))),
              );
            }
            if (asyncTx.hasError) {
              return Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                    child: Text('Error: ${asyncTx.error}',
                        style: const TextStyle(color: Color(0xFF6B7280)))),
              );
            }

            final txItems   = asyncTx.value   ?? [];
            final billItems = asyncBills.value ?? [];
            final bothEmpty = txItems.isEmpty && billItems.isEmpty;

            if (bothEmpty) {
              return const Padding(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 40),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.delete_sweep_outlined,
                          size: 40, color: Color(0xFF1F2937)),
                      SizedBox(height: 12),
                      Text(
                        'Recycle bin is empty',
                        style: TextStyle(
                            color: Color(0xFF4B5563),
                            fontSize: 15,
                            fontWeight: FontWeight.w500),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Deleted entries will appear here for 15 days.',
                        style: TextStyle(
                            color: Color(0xFF374151), fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            final showSectionLabels =
                billItems.isNotEmpty && txItems.isNotEmpty;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // ── Bills section ───────────────────────────────────
                        if (billItems.isNotEmpty) ...[
                          if (showSectionLabels)
                            const Padding(
                              padding: EdgeInsets.only(top: 4, bottom: 8),
                              child: Text(
                                'BILLS',
                                style: TextStyle(
                                  color: Color(0xFF4B5563),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ...billItems.asMap().entries.map((e) {
                            final bill = e.value;
                            return Padding(
                              padding: EdgeInsets.only(
                                  bottom: e.key < billItems.length - 1 ? 6 : 0),
                              child: _DeletedBillItem(
                                bill: bill,
                                onTap: () => _showBillActions(bill),
                              ),
                            );
                          }),
                          if (txItems.isNotEmpty)
                            const SizedBox(height: 12),
                        ],

                        // ── Entries section ─────────────────────────────────
                        if (txItems.isNotEmpty) ...[
                          if (showSectionLabels)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                'ENTRIES',
                                style: TextStyle(
                                  color: Color(0xFF4B5563),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ...txItems.asMap().entries.map((e) {
                            final tx         = e.value;
                            final isSelected = _selected.contains(tx.transactionId);
                            return Padding(
                              padding: EdgeInsets.only(
                                  bottom: e.key < txItems.length - 1 ? 6 : 0),
                              child: _DeletedItem(
                                tx:         tx,
                                selectMode: _selectMode,
                                isSelected: isSelected,
                                onTap: _selectMode
                                    ? () => _toggleItem(tx.transactionId)
                                    : () => _showItemActions(tx),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),

                // ── Bulk action bar (transactions only) ──────────────────
                if (_selectMode && txItems.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Row(children: [
                      Expanded(
                        child: _BulkButton(
                          label: 'Restore (${_selected.length})',
                          icon: Icons.restore_rounded,
                          color: const Color(0xFF10B981),
                          disabled: _selected.isEmpty || _busy,
                          onTap: () => _restoreAll(txItems),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _BulkButton(
                          label: 'Delete (${_selected.length})',
                          icon: Icons.delete_forever_rounded,
                          color: const Color(0xFFef4444),
                          disabled: _selected.isEmpty || _busy,
                          onTap: () => _deleteAll(txItems),
                        ),
                      ),
                    ]),
                  ),
                ],
              ],
            );
          }),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }
}

// ─── Individual deleted item tile ─────────────────────────────────────────────

class _DeletedItem extends StatelessWidget {
  final DeletedTransactionEntity tx;
  final bool selectMode;
  final bool isSelected;
  final VoidCallback onTap;

  const _DeletedItem({
    required this.tx,
    required this.selectMode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = tx.type.toLowerCase() == 'income';
    final title =
        tx.description.isEmpty ? tx.category : tx.description;
    final daysLeft = tx.daysRemaining;
    final urgent = daysLeft <= 3;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF1A2030)
              : const Color(0xFF111318),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF3B82F6).withValues(alpha: 0.4)
                : const Color(0xFF1F2937),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          if (selectMode) ...[
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? const Color(0xFF3B82F6)
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFF374151),
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      size: 12, color: Colors.white)
                  : null,
            ),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _MiniTag(tx.category.toUpperCase()),
                  const SizedBox(width: 5),
                  _MiniTag(tx.creatorName.toUpperCase()),
                ]),
                const SizedBox(height: 5),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFD1D9E6),
                  ),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  Text(
                    _dateFmt.format(tx.createdAt),
                    style: const TextStyle(
                        fontSize: 11.5, color: Color(0xFF4B5563)),
                  ),
                  const Text('  ·  ',
                      style: TextStyle(
                          fontSize: 11.5, color: Color(0xFF374151))),
                  Text(
                    daysLeft == 0
                        ? 'Expires today'
                        : '$daysLeft day${daysLeft == 1 ? '' : 's'} left',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: urgent
                          ? const Color(0xFFf87171)
                          : const Color(0xFF4B5563),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${isIncome ? '+' : '−'}₹${CurrencyFormatter.format(tx.amount)}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              letterSpacing: -0.3,
              color: isIncome
                  ? const Color(0xF0E1EBF8)
                  : const Color(0xCCA0AEBE),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Mini tag ──────────────────────────────────────────────────────────────────

class _MiniTag extends StatelessWidget {
  const _MiniTag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: Color(0x997A8A9E),
        ),
      ),
    );
  }
}

// ─── Item action sheet ────────────────────────────────────────────────────────

class _ItemActionSheet extends StatelessWidget {
  final DeletedTransactionEntity tx;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _ItemActionSheet({
    required this.tx,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = tx.type.toLowerCase() == 'income';
    final title =
        tx.description.isEmpty ? tx.category : tx.description;

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
          width: 32, height: 3,
          decoration: BoxDecoration(
            color: const Color(0xFF374151),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Entry preview card
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0C0E12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1F2937)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MiniTag(tx.category.toUpperCase()),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFD1D9E6),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${tx.creatorName}  ·  ${_dateFmt.format(tx.createdAt)}',
                      style: const TextStyle(
                          color: Color(0xFF6B7280), fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${isIncome ? '+' : '−'}₹${CurrencyFormatter.format(tx.amount)}',
                style: TextStyle(
                  fontSize: 17,
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
        // Restore
        _SheetRow(
          icon: Icons.restore_rounded,
          label: 'Restore',
          color: const Color(0xFF10B981),
          onTap: onRestore,
        ),
        Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: const Color(0xFF1F2937)),
        // Delete permanently
        _SheetRow(
          icon: Icons.delete_forever_rounded,
          label: 'Delete Permanently',
          color: const Color(0xFFf87171),
          onTap: onDelete,
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _SheetRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SheetRow(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, size: 18, color: color.withValues(alpha: 0.8)),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: color)),
        ]),
      ),
    );
  }
}

// ─── Bulk action button ───────────────────────────────────────────────────────

class _BulkButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool disabled;
  final VoidCallback onTap;

  const _BulkButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        opacity: disabled ? 0.4 : 1.0,
        duration: const Duration(milliseconds: 160),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ─── Individual deleted bill tile ─────────────────────────────────────────────

class _DeletedBillItem extends StatelessWidget {
  final DeletedBillEntity bill;
  final VoidCallback onTap;

  const _DeletedBillItem({
    required this.bill,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fmt      = NumberFormat('#,##,##0.##');
    final daysLeft = bill.daysRemaining;
    final urgent   = daysLeft <= 3;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF111318),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1F2937)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _MiniTag('BILL'),
                  const SizedBox(width: 5),
                  _MiniTag(bill.partyName.toUpperCase()),
                ]),
                const SizedBox(height: 5),
                Text(
                  '${bill.billNumber}  ·  ${bill.partyName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFD1D9E6),
                  ),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  Text(
                    _dateFmt.format(bill.billDate),
                    style: const TextStyle(
                        fontSize: 11.5, color: Color(0xFF4B5563)),
                  ),
                  const Text('  ·  ',
                      style: TextStyle(
                          fontSize: 11.5, color: Color(0xFF374151))),
                  Text(
                    daysLeft == 0
                        ? 'Expires today'
                        : '\$daysLeft day\${daysLeft == 1 ? "" : "s"} left',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: urgent
                          ? const Color(0xFFf87171)
                          : const Color(0xFF4B5563),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '₹\${fmt.format(bill.billTotal)}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              letterSpacing: -0.3,
              color: Color(0xFFF1F2F5),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Bill action sheet ────────────────────────────────────────────────────────

class _BillActionSheet extends StatelessWidget {
  final DeletedBillEntity bill;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _BillActionSheet({
    required this.bill,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##,##0.##');

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
          width: 32, height: 3,
          decoration: BoxDecoration(
            color: const Color(0xFF374151),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Bill preview card
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0C0E12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1F2937)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MiniTag('BILL'),
                    const SizedBox(height: 6),
                    Text(
                      '\${bill.billNumber}  ·  \${bill.partyName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFD1D9E6),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _dateFmt.format(bill.billDate),
                      style: const TextStyle(
                          color: Color(0xFF6B7280), fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '₹\${fmt.format(bill.billTotal)}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                  letterSpacing: -0.5,
                  color: Color(0xFFF1F2F5),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        // Restore
        _SheetRow(
          icon: Icons.restore_rounded,
          label: 'Restore',
          color: const Color(0xFF10B981),
          onTap: onRestore,
        ),
        Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: const Color(0xFF1F2937)),
        // Delete permanently
        _SheetRow(
          icon: Icons.delete_forever_rounded,
          label: 'Delete Permanently',
          color: const Color(0xFFf87171),
          onTap: onDelete,
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}
