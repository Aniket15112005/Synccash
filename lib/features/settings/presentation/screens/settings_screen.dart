// lib/features/settings/presentation/screens/settings_screen.dart
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:synccash/features/purchases/presentation/purchase_routes.dart';
import 'package:synccash/features/purchases/presentation/screens/purchases_screen.dart';

import 'package:synccash/features/analytics/presentation/screens/analytics_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/app/theme/app_colors.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart'
    show currentCashbookIdProvider;
import 'package:synccash/features/cashbook/presentation/providers/cashbook_provider.dart';
import 'package:synccash/features/settings/services/backup_frequency_service.dart';
import 'package:synccash/features/settings/services/backup_service.dart';
import 'package:synccash/features/settings/services/export_service.dart';
import 'package:synccash/features/transactions/presentation/providers/transaction_provider.dart'
    show allTransactionsStreamProvider;
import 'package:intl/intl.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:flutter/foundation.dart';
import 'package:synccash/features/settings/presentation/screens/widgets/recycle_bin_sheet.dart';
import 'package:synccash/features/sales/presentation/sales_routes.dart';
import 'package:synccash/features/sales/presentation/screens/sales_screen.dart';
import 'package:synccash/features/sales/presentation/screens/billport_screen.dart';
import 'package:synccash/features/daily/presentation/screens/daily_screen.dart';

class SettingsSheet extends ConsumerStatefulWidget {
  const SettingsSheet({super.key});

  @override
  ConsumerState<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<SettingsSheet> {
  _SettingsPage _page = _SettingsPage.main;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
      child: switch (_page) {
  _SettingsPage.main =>
    _MainSheet(
      key: const ValueKey('main'),
      onNavigate: _navigate,
    ),
  _SettingsPage.export =>
    _ExportSheet(
      key: const ValueKey('export'),
      onBack: _back,
    ),
  _SettingsPage.import =>
    _ImportSheet(
      key: const ValueKey('import'),
      onBack: _back,
    ),
  _SettingsPage.backup =>
    _BackupSheet(
      key: const ValueKey('backup'),
      onBack: _back,
      onNavigate: _navigate,
    ),
  _SettingsPage.backupFrequency =>
    _BackupFrequencySheet(
      key: const ValueKey('backupFrequency'),
      onBack: () => setState(() => _page = _SettingsPage.backup),
    ),
  _SettingsPage.recycleBin =>
    RecycleBinSheet(
      key: const ValueKey('recycleBin'),
      onBack: _back,
    ),
},
    );
  }

  void _navigate(_SettingsPage page) {
    HapticFeedback.selectionClick();
    setState(() => _page = page);
  }

  void _back() {
    HapticFeedback.selectionClick();
    setState(() => _page = _SettingsPage.main);
  }
}

enum _SettingsPage { main, export, import, backup, backupFrequency, recycleBin  }

// ─────────────────────────────────────────────────────────────────────────────
//  Main settings page
// ─────────────────────────────────────────────────────────────────────────────

class _MainSheet extends StatelessWidget {
  final void Function(_SettingsPage) onNavigate;
  const _MainSheet({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Settings',
      child: Column(
        children: [
          const _SectionLabel('DATA'),
          // Export, Import, Backup — iOS/PWA only (kIsWeb covers PWA + web)
          if (kIsWeb) ...[
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.upload_file_rounded,
              iconColor: const Color(0xFF3B82F6),
              title: 'Export',
              subtitle: 'Save as PDF or Excel spreadsheet',
              onTap: () => onNavigate(_SettingsPage.export),
              trailing: const _ChevronIcon(),
            ).animate().fadeIn(delay: 60.ms, duration: 220.ms).slideX(
                begin: 0.04, end: 0, curve: Curves.easeOut),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.download_rounded,
              iconColor: const Color(0xFF8B5CF6),
              title: 'Import',
              subtitle: 'Restore from a .synccash backup file',
              onTap: () => onNavigate(_SettingsPage.import),
              trailing: const _ChevronIcon(),
            ).animate().fadeIn(delay: 100.ms, duration: 220.ms).slideX(
                begin: 0.04, end: 0, curve: Curves.easeOut),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.cloud_done_rounded,
              iconColor: const Color(0xFF10B981),
              title: 'Backup',
              subtitle: 'Create a local backup of all transactions',
              onTap: () => onNavigate(_SettingsPage.backup),
              trailing: const _ChevronIcon(),
            ).animate().fadeIn(delay: 140.ms, duration: 220.ms).slideX(
                begin: 0.04, end: 0, curve: Curves.easeOut),
          ],
          // ─── Sales tile ─────────────────────────────────────────────
          const SizedBox(height: 8),
          _SettingsTile(
            icon: Icons.receipt_long_rounded,
            iconColor: const Color(0xFF5B8DEF),
            title: 'Sales',
            subtitle: 'Manage sale bills & client payments',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                salesRoute(const SalesScreen()),
              );
            },
            trailing: const _ChevronIcon(),
          ).animate().fadeIn(delay: 175.ms, duration: 220.ms).slideX(
              begin: 0.04, end: 0, curve: Curves.easeOut),
          // ─── Billport tile ──────────────────────────────────────────
          const SizedBox(height: 8),
          _SettingsTile(
            icon: Icons.import_export_rounded,
            iconColor: const Color(0xFFF59E0B),
            title: 'Billport',
            subtitle: 'Export bills of selected parties to PDF or Excel',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                salesRoute(const BillportScreen()),
              );
            },
            trailing: const _ChevronIcon(),
          ).animate().fadeIn(delay: 210.ms, duration: 220.ms).slideX(
              begin: 0.04, end: 0, curve: Curves.easeOut),
          // ─── end Billport tile ──────────────────────────────────────
          // ─── Purchases tile — iOS / PWA / Web only, hidden on Android ──
          if (kIsWeb || Platform.isIOS) ...[
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.shopping_cart_rounded,
              iconColor: const Color(0xFF10B981),
              title: 'Purchases',
              subtitle: 'Manage purchase bills & supplier payments',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  purchaseRoute(const PurchasesScreen()),
                );
              },
              trailing: const _ChevronIcon(),
            ).animate().fadeIn(delay: 225.ms, duration: 220.ms).slideX(
                begin: 0.04, end: 0, curve: Curves.easeOut),
          ],
          // ─── end Purchases tile ─────────────────────────────────────
          // ─── Daily tile — iOS / PWA / Web only, hidden on Android ───
          if (kIsWeb || Platform.isIOS) ...[
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.bolt_rounded,
              iconColor: const Color(0xFF8B5CF6),
              title: 'Daily',
              subtitle: 'Personal income & expense manager',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DailyScreen()),
                );
              },
              trailing: const _ChevronIcon(),
            ).animate().fadeIn(delay: 235.ms, duration: 220.ms).slideX(
                begin: 0.04, end: 0, curve: Curves.easeOut),
          ],
          // ─── end Daily tile ─────────────────────────────────────────
          if (kIsWeb) ...[
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.delete_sweep_rounded,
              iconColor: const Color(0xFFf87171),
              title: 'Recycle Bin',
              subtitle: 'Restore or permanently remove deleted entries',
              onTap: () => onNavigate(_SettingsPage.recycleBin),
              trailing: const _ChevronIcon(),
            ).animate().fadeIn(delay: 245.ms, duration: 220.ms).slideX(
                begin: 0.04, end: 0, curve: Curves.easeOut),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.analytics_rounded,
              iconColor: const Color(0xFF5B8DEF),
              title: 'Analytics',
              subtitle: 'Spending insights, trends & category breakdown',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AnalyticsScreen(),
                  ),
                );
              },
              trailing: const _ChevronIcon(),
            ).animate().fadeIn(delay: 280.ms, duration: 220.ms).slideX(
                begin: 0.04, end: 0, curve: Curves.easeOut),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Export page
// ─────────────────────────────────────────────────────────────────────────────

class _ExportSheet extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  const _ExportSheet({super.key, required this.onBack});

  @override
  ConsumerState<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<_ExportSheet> {
  bool _busy = false;
  String? _activeFormat;
  _DataFilter _filter = _DataFilter.all;
  _TypeFilter _typeFilter = _TypeFilter.all;

  Future<void> _doExport(String format) async {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = true;
      _activeFormat = format;
    });

    try {
      final cashbookId = ref.read(currentCashbookIdProvider);
      if (cashbookId == null) throw Exception('No active cashbook found.');

      final cashbook = ref.read(cashbookStreamProvider).asData?.value;
      if (cashbook == null) throw Exception('Could not load cashbook data.');

      final allTx =
          ref.read(allTransactionsStreamProvider(cashbookId)).asData?.value ?? [];
      final startDate = _filter.startDate;
      final dateFiltered = startDate == null
          ? allTx
          : allTx.where((tx) => !tx.createdAt.isBefore(startDate)).toList();
      final transactions = _typeFilter.apply(dateFiltered);

      if (transactions.isEmpty) {
        if (mounted) {
          _showSnack('No transactions to export for the selected range.', isError: true);
        }
        return;
      }

      if (!mounted) return;
      if (format == 'pdf') {
        await ExportService.exportToPdf(
          context: context,
          transactions: transactions,
          cashbookName: 'Cashbook ${cashbook.inviteCode}',
        );
      } else {
        await ExportService.exportToExcel(
          context: context,
          transactions: transactions,
          cashbookName: 'Cashbook ${cashbook.inviteCode}',
        );
      }

      if (mounted) {
        _showSnack(
          '${format.toUpperCase()} exported — choose a location in the share sheet.',
        );
      }
    } catch (e) {
      if (mounted) _showSnack('Export failed: $e', isError: true);
    } finally {
      if (mounted) setState(() { _busy = false; _activeFormat = null; });
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.expense : AppColors.income,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Export',
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _InfoBanner(
            icon: Icons.info_outline_rounded,
            text:
                'Your transactions will be exported and the share sheet will open so you can save to Downloads, Google Drive, or any other location.',
          ),
          const SizedBox(height: 20),
          const _SectionLabel('DATE RANGE'),
          const SizedBox(height: 8),
          _FilterChips(
            active: _filter,
            onSelect: (f) => setState(() => _filter = f),
          ),
          const SizedBox(height: 12),
          const _SectionLabel('TYPE'),
          const SizedBox(height: 8),
          _TypeFilterChips(
            active: _typeFilter,
            onSelect: (f) => setState(() => _typeFilter = f),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('FORMAT'),
          const SizedBox(height: 8),
          _ExportFormatTile(
            icon: Icons.picture_as_pdf_rounded,
            iconColor: const Color(0xFFEF4444),
            title: 'PDF Document',
            subtitle: 'Formatted table — great for printing or sharing',
            loading: _busy && _activeFormat == 'pdf',
            disabled: _busy,
            onTap: () => _doExport('pdf'),
          ).animate().fadeIn(delay: 60.ms, duration: 220.ms),
          const SizedBox(height: 8),
          _ExportFormatTile(
            icon: Icons.table_chart_rounded,
            iconColor: const Color(0xFF22C55E),
            title: 'Excel Spreadsheet',
            subtitle: 'Two sheets: all transactions + summary',
            loading: _busy && _activeFormat == 'excel',
            disabled: _busy,
            onTap: () => _doExport('excel'),
          ).animate().fadeIn(delay: 100.ms, duration: 220.ms),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Import page
// ─────────────────────────────────────────────────────────────────────────────

class _ImportSheet extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  const _ImportSheet({super.key, required this.onBack});

  @override
  ConsumerState<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<_ImportSheet> {
  bool _busy = false;

  Future<void> _doImport() async {
    if (_busy) return;
    HapticFeedback.mediumImpact();

    final confirmed = await _confirmImport(context);
    if (!mounted) return;
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      final backup = await BackupService.pickAndParseBackup(context);
      if (backup == null) return;

      if (!mounted) return;
      final proceed = await _showImportPreview(context, backup);
      if (!proceed) return;

      final cashbookId = ref.read(currentCashbookIdProvider);
      if (cashbookId == null) throw Exception('No active cashbook.');

      final db = FirebaseFirestore.instance;

      // ── 1. Restore transactions ──────────────────────────────────────
      var txImported = 0;
      for (final tx in backup.transactions) {
        await db
            .collection('cashbooks')
            .doc(cashbookId)
            .collection('transactions')
            .doc(tx.transactionId)
            .set({
          'transactionId': tx.transactionId,
          'cashbookId':    cashbookId,
          'createdBy':     tx.createdBy,
          'creatorName':   tx.creatorName,
          'createdAt':     Timestamp.fromDate(tx.createdAt),
          'amount':        tx.amount,
          'type':          tx.type,
          'category':      tx.category,
          'description':   tx.description,
          'isImport':      true,
        });
        txImported++;
      }

      // ── 2. Restore sale bills ────────────────────────────────────────
      var billsImported = 0;
      for (final bill in backup.saleBills) {
        if (bill.saleBillId.isEmpty) continue;
        await db
            .collection('cashbooks')
            .doc(cashbookId)
            .collection('sale_bills')
            .doc(bill.saleBillId)
            .set({
          'saleBillId':        bill.saleBillId,
          'partyName':         bill.partyName,
          'billNumber':        bill.billNumber,
          'billTotal':         bill.billTotal,
          'billDate':          Timestamp.fromDate(bill.billDate),
          'billNote':          bill.billNote,
          'billCreatedAt':     Timestamp.fromDate(bill.billCreatedAt),
          'billCreatedBy':     bill.billCreatedBy,
          'billCreatedByName': bill.billCreatedByName,
          'billStatus':        bill.billStatus,
          'isImport':          true,
        });
        billsImported++;
      }

      // ── 3. Restore parties (merge so existing newer data is kept) ────
      var partiesImported = 0;
      for (final party in backup.parties) {
        if (party.partyId.isEmpty) continue;
        await db
            .collection('cashbooks')
            .doc(cashbookId)
            .collection('parties')
            .doc(party.partyId)
            .set({
          'partyName':      party.partyName,
          'openingBalance': party.openingBalance,
          'description':    party.description,
          'place':          party.place,
          'updatedAt':      FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        partiesImported++;
      }

      if (mounted) {
        Navigator.pop(context);
        final parts = <String>[
          '$txImported transaction${txImported == 1 ? '' : 's'}',
          if (billsImported > 0)
            '$billsImported bill${billsImported == 1 ? '' : 's'}',
          if (partiesImported > 0)
            '$partiesImported part${partiesImported == 1 ? 'y' : 'ies'}',
        ];
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✓ Imported ${parts.join(', ')} successfully.'),
          backgroundColor: AppColors.income,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ));
      }
    } on BackupValidationException catch (e) {
      if (mounted) _showError(e.message);
    } on BackupVersionException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.expense,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
  }

  Future<bool> _confirmImport(BuildContext ctx) async {
    return await showDialog<bool>(
          context: ctx,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF161922),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('Import Backup',
                style: TextStyle(
                    color: Color(0xFFE5E7EB), fontWeight: FontWeight.w700)),
            content: const Text(
              'This will ADD transactions, sale bills, and parties from the backup '
              'file to your current cashbook. Existing data will not be removed.',
              style: TextStyle(color: Color(0xFF9CA3AF), height: 1.5),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel',
                      style: TextStyle(color: Color(0xFF6B7280)))),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Choose File'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _showImportPreview(
      BuildContext ctx, SyncCashBackup backup) async {
    final fmt = DateFormat('dd MMM yyyy, hh:mm a');
    return await showDialog<bool>(
          context: ctx,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF161922),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('Confirm Import',
                style: TextStyle(
                    color: Color(0xFFE5E7EB), fontWeight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _previewRow('From cashbook', backup.cashbookName),
                _previewRow('Backed up', fmt.format(backup.exportedAt)),
                _previewRow('Transactions', '${backup.transactions.length}'),
                _previewRow('Sale bills', '${backup.saleBills.length}'),
                _previewRow('Parties', '${backup.parties.length}'),
                const SizedBox(height: 12),
                const Text(
                  'All data above will be added to your current cashbook.',
                  style: TextStyle(
                      color: Color(0xFF6B7280), fontSize: 12, height: 1.5),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel',
                      style: TextStyle(color: Color(0xFF6B7280)))),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Import Now'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _previewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ',
              style: const TextStyle(
                  color: Color(0xFF6B7280), fontSize: 13)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Color(0xFFD1D5DB),
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Import',
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _InfoBanner(
            icon: Icons.warning_amber_rounded,
            text:
                'Import adds transactions, sale bills, and parties from a .synccash '
                'backup file to your current cashbook. Existing data is NOT deleted.',
            color: Color(0xFFF59E0B),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('BACKUP FILE'),
          const SizedBox(height: 8),
          _ActionTileButton(
            icon: Icons.folder_open_rounded,
            iconColor: const Color(0xFF8B5CF6),
            title: 'Choose Backup File',
            subtitle: 'Select a .synccash file from your device',
            loading: _busy,
            onTap: _doImport,
          ).animate().fadeIn(delay: 60.ms, duration: 220.ms),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Backup page
// ─────────────────────────────────────────────────────────────────────────────

class _BackupSheet extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  final void Function(_SettingsPage) onNavigate;
  const _BackupSheet({
    super.key,
    required this.onBack,
    required this.onNavigate,
  });

  @override
  ConsumerState<_BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends ConsumerState<_BackupSheet> {
  bool _busy = false;
  String _frequencyLabel = 'Never';
  _DataFilter _filter = _DataFilter.all;
  _TypeFilter _typeFilter = _TypeFilter.all;

  @override
  void initState() {
    super.initState();
    _loadFrequency();
    _checkAutoBackup();
  }

  Future<void> _loadFrequency() async {
    final freq = await BackupFrequencyService.getFrequency();
    if (mounted) setState(() => _frequencyLabel = freq.label);
  }

  Future<void> _checkAutoBackup() async {
    final due = await BackupFrequencyService.isBackupDue();
    if (!due || !mounted) return;
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) _doBackup(auto: true);
  }

  Future<void> _doBackup({bool auto = false}) async {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);

    try {
      final cashbookId = ref.read(currentCashbookIdProvider);
      if (cashbookId == null) throw Exception('No active cashbook.');

      final cashbook = ref.read(cashbookStreamProvider).asData?.value;
      if (cashbook == null) throw Exception('Could not load cashbook data.');

      // ── Transactions (with date + type filters) ──────────────────────
      final allTx =
          ref.read(allTransactionsStreamProvider(cashbookId)).asData?.value ?? [];
      final startDate = _filter.startDate;
      final dateFiltered = startDate == null
          ? allTx
          : allTx.where((tx) => !tx.createdAt.isBefore(startDate)).toList();
      final transactions = _typeFilter.apply(dateFiltered);

      // ── Sale bills (always full — date filter doesn't apply to bills) ─
      final db = FirebaseFirestore.instance;
      final billsSnap = await db
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('sale_bills')
          .get();
      final saleBills = billsSnap.docs.map((doc) {
        final d = doc.data();
        return SaleBillBackup(
          saleBillId:        d['saleBillId']        as String?  ?? doc.id,
          partyName:         d['partyName']          as String?  ?? '',
          billNumber:        d['billNumber']          as String?  ?? '',
          billTotal:         (d['billTotal']  as num?)?.toDouble() ?? 0.0,
          billDate:          (d['billDate']   as Timestamp?)?.toDate() ??
                             DateTime.now(),
          billNote:          d['billNote']            as String?,
          billCreatedAt:     (d['billCreatedAt'] as Timestamp?)?.toDate() ??
                             DateTime.now(),
          billCreatedBy:     d['billCreatedBy']      as String?  ?? '',
          billCreatedByName: d['billCreatedByName']  as String?  ?? '',
          billStatus:        d['billStatus']          as String?  ?? 'pending',
        );
      }).toList();

      // ── Parties (always full) ─────────────────────────────────────────
      final partiesSnap = await db
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('parties')
          .get();
      final parties = partiesSnap.docs.map((doc) {
        final d = doc.data();
        return PartyBackup(
          partyId:        doc.id,
          partyName:      d['partyName']      as String? ?? '',
          openingBalance: (d['openingBalance'] as num?)?.toDouble() ?? 0.0,
          description:    d['description']    as String? ?? '',
          place:          d['place']          as String? ?? '',
        );
      }).toList();

      await BackupService.createBackup(
        context:      context,
        cashbook:     cashbook,
        transactions: transactions,
        saleBills:    saleBills,
        parties:      parties,
      );

      await BackupFrequencyService.recordBackup();

      if (mounted) {
        final parts = <String>[
          '${transactions.length} transaction${transactions.length == 1 ? '' : 's'}',
          '${saleBills.length} bill${saleBills.length == 1 ? '' : 's'}',
          '${parties.length} part${parties.length == 1 ? 'y' : 'ies'}',
        ];
        final msg = auto
            ? 'Auto-backup created — ${parts.join(', ')} saved.'
            : 'Backup created — ${parts.join(', ')} saved.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.income,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Backup failed: $e'),
          backgroundColor: AppColors.expense,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cashbookId = ref.watch(currentCashbookIdProvider);
    final allTx = cashbookId == null
        ? <TransactionEntity>[]
        : (ref.watch(allTransactionsStreamProvider(cashbookId)).asData?.value ?? []);
    final startDate = _filter.startDate;
    final dateFiltered = startDate == null
        ? allTx
        : allTx.where((tx) => !tx.createdAt.isBefore(startDate)).toList();
    final count = _typeFilter.apply(dateFiltered).length;

    return _SheetScaffold(
      title: 'Backup',
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _InfoBanner(
            icon: Icons.shield_outlined,
            text:
                'Creates a .synccash backup of your transactions, sale bills, and '
                'party opening balances. Use the date range to filter transactions only.',
            color: Color(0xFF10B981),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('DATE RANGE'),
          const SizedBox(height: 8),
          _FilterChips(
            active: _filter,
            onSelect: (f) => setState(() => _filter = f),
          ),
          const SizedBox(height: 12),
          const _SectionLabel('TYPE'),
          const SizedBox(height: 8),
          _TypeFilterChips(
            active: _typeFilter,
            onSelect: (f) => setState(() => _typeFilter = f),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('CURRENT DATA'),
          const SizedBox(height: 8),
          _StatTile(
            icon: Icons.receipt_long_rounded,
            label: 'Transactions to back up',
            value: '$count',
          ).animate().fadeIn(delay: 60.ms, duration: 220.ms),
          const SizedBox(height: 8),
          if (cashbookId != null) ...[
            _SaleBillsStatTile(cashbookId: cashbookId)
                .animate()
                .fadeIn(delay: 80.ms, duration: 220.ms),
            const SizedBox(height: 8),
            _PartiesStatTile(cashbookId: cashbookId)
                .animate()
                .fadeIn(delay: 100.ms, duration: 220.ms),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          const _SectionLabel('ACTION'),
          const SizedBox(height: 8),
          _ActionTileButton(
            icon: Icons.cloud_upload_rounded,
            iconColor: const Color(0xFF10B981),
            title: 'Create Backup Now',
            subtitle: 'Saves a .synccash file — open share sheet to save it',
            loading: _busy,
            onTap: _doBackup,
          ).animate().fadeIn(delay: 120.ms, duration: 220.ms),
          const SizedBox(height: 16),
          const _SectionLabel('SCHEDULE'),
          const SizedBox(height: 8),
          _SettingsTile(
            icon: Icons.schedule_rounded,
            iconColor: const Color(0xFF6366F1),
            title: 'Backup Frequency',
            subtitle: _frequencyLabel,
            onTap: () => widget.onNavigate(_SettingsPage.backupFrequency),
            trailing: const _ChevronIcon(),
          ).animate().fadeIn(delay: 140.ms, duration: 220.ms).slideX(
              begin: 0.04, end: 0, curve: Curves.easeOut),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Live stat tiles for backup page ──────────────────────────────────────────

class _SaleBillsStatTile extends StatelessWidget {
  final String cashbookId;
  const _SaleBillsStatTile({required this.cashbookId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('sale_bills')
          .snapshots()
          .map((s) => s.size),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return _StatTile(
          icon: Icons.receipt_rounded,
          label: 'Sale bills (always full backup)',
          value: '$count',
        );
      },
    );
  }
}

class _PartiesStatTile extends StatelessWidget {
  final String cashbookId;
  const _PartiesStatTile({required this.cashbookId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('parties')
          .snapshots()
          .map((s) => s.size),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return _StatTile(
          icon: Icons.people_rounded,
          label: 'Parties / opening balances (always full backup)',
          value: '$count',
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Backup Frequency page
// ─────────────────────────────────────────────────────────────────────────────

class _BackupFrequencySheet extends StatefulWidget {
  final VoidCallback onBack;
  const _BackupFrequencySheet({super.key, required this.onBack});

  @override
  State<_BackupFrequencySheet> createState() => _BackupFrequencySheetState();
}

class _BackupFrequencySheetState extends State<_BackupFrequencySheet> {
  BackupFrequency _selected = BackupFrequency.never;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    BackupFrequencyService.getFrequency().then((freq) {
      if (mounted) setState(() { _selected = freq; _loading = false; });
    });
  }

  Future<void> _select(BackupFrequency freq) async {
    HapticFeedback.selectionClick();
    setState(() => _selected = freq);
    await BackupFrequencyService.setFrequency(freq);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Backup frequency set to "${freq.label}"'),
        backgroundColor: const Color(0xFF6366F1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Backup Frequency',
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _InfoBanner(
            icon: Icons.info_outline_rounded,
            text:
                'When a frequency is set, a backup will be triggered automatically '
                'the next time you open the Backup screen after the interval has passed. '
                'Set to Never to only back up manually.',
            color: Color(0xFF6366F1),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('FREQUENCY'),
          const SizedBox(height: 8),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            ...BackupFrequency.values.map((freq) {
              final isSelected = _selected == freq;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _FrequencyOptionTile(
                  freq: freq,
                  selected: isSelected,
                  onTap: () => _select(freq),
                ).animate().fadeIn(
                    delay: Duration(
                        milliseconds:
                            60 + BackupFrequency.values.indexOf(freq) * 40),
                    duration: 220.ms),
              );
            }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _FrequencyOptionTile extends StatelessWidget {
  final BackupFrequency freq;
  final bool selected;
  final VoidCallback onTap;

  const _FrequencyOptionTile({
    required this.freq,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF6366F1);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.07),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? accent : const Color(0xFF4B5563),
                  width: 2,
                ),
                color: selected ? accent : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    freq.label,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFFF0F1F3)
                          : const Color(0xFFD1D5DB),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    freq.subtitle,
                    style: TextStyle(
                      color: selected
                          ? accent.withValues(alpha: 0.7)
                          : const Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared sheet scaffold
// ─────────────────────────────────────────────────────────────────────────────

class _SheetScaffold extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget child;

  const _SheetScaffold({
    required this.title,
    this.onBack,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0C0E12),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              children: [
                if (onBack != null) ...[
                  GestureDetector(
                    onTap: onBack,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 0.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 14,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFF0F1F3),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: child,
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reusable sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF4B5563),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InfoBanner({
    required this.icon,
    required this.text,
    this.color = const Color(0xFF3B82F6),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color.withValues(alpha: 0.8), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color.withValues(alpha: 0.85),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return _TileBase(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _ExportFormatTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;

  const _ExportFormatTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.loading,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _TileBase(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      loading: loading,
      disabled: disabled,
      onTap: onTap,
      trailing: loading
          ? null
          : Icon(Icons.arrow_forward_ios_rounded,
              size: 13, color: Colors.white.withValues(alpha: 0.25)),
    );
  }
}

class _ActionTileButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool loading;
  final VoidCallback onTap;

  const _ActionTileButton({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _TileBase(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      loading: loading,
      onTap: onTap,
      trailing: loading
          ? null
          : Icon(Icons.arrow_forward_ios_rounded,
              size: 13, color: Colors.white.withValues(alpha: 0.25)),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon,
                color: const Color(0xFF10B981), size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 13,
                )),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFF0F1F3),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TileBase extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;
  final Widget? trailing;

  const _TileBase({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.loading = false,
    this.disabled = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        opacity: disabled && !loading ? 0.4 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFF0F1F3),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: iconColor,
                  ),
                )
              else if (trailing != null)
                trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _ChevronIcon extends StatelessWidget {
  const _ChevronIcon();

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.arrow_forward_ios_rounded,
      size: 13,
      color: Colors.white.withValues(alpha: 0.25),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Date-range filter — shared by Backup and Export pages
// ─────────────────────────────────────────────────────────────────────────────

// ignore_for_file: unused_element

enum _DataFilter {
  today,
  week,
  month,
  year,
  all;

  String get label {
    switch (this) {
      case _DataFilter.today: return 'Today';
      case _DataFilter.week:  return 'This Week';
      case _DataFilter.month: return 'This Month';
      case _DataFilter.year:  return 'This Year';
      case _DataFilter.all:   return 'All Time';
    }
  }

  DateTime? get startDate {
    final now = DateTime.now();
    switch (this) {
      case _DataFilter.today:
        return DateTime(now.year, now.month, now.day);
      case _DataFilter.week:
        return DateTime(now.year, now.month, now.day - (now.weekday - 1));
      case _DataFilter.month:
        return DateTime(now.year, now.month, 1);
      case _DataFilter.year:
        return DateTime(now.year, 1, 1);
      case _DataFilter.all:
        return null;
    }
  }
}

class _FilterChips extends StatelessWidget {
  final _DataFilter active;
  final ValueChanged<_DataFilter> onSelect;
  const _FilterChips({required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _DataFilter.values.map((f) {
          final on = f == active;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onSelect(f);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: on
                      ? const Color(0xFF3B82F6)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: on
                        ? const Color(0xFF3B82F6)
                        : Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: Text(
                  f.label,
                  style: TextStyle(
                    color: on ? Colors.white : const Color(0xFF9CA3AF),
                    fontSize: 13,
                    fontWeight:
                        on ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Type filter — shared by Backup & Export
// ─────────────────────────────────────────────────────────────────────────────

enum _TypeFilter {
  all,
  income,
  expense,
  retail,
  wholesale;

  String get label {
    switch (this) {
      case _TypeFilter.all:       return 'All';
      case _TypeFilter.income:    return 'Income';
      case _TypeFilter.expense:   return 'Expense';
      case _TypeFilter.retail:    return 'Retail';
      case _TypeFilter.wholesale: return 'Wholesale';
    }
  }

  List<TransactionEntity> apply(List<TransactionEntity> txs) {
    switch (this) {
      case _TypeFilter.all:
        return txs;
      case _TypeFilter.income:
        return txs.where((tx) => tx.type.toLowerCase() == 'income').toList();
      case _TypeFilter.expense:
        return txs.where((tx) => tx.type.toLowerCase() != 'income').toList();
      case _TypeFilter.retail:
        return txs
            .where((tx) => tx.category.toLowerCase().contains('retail'))
            .toList();
      case _TypeFilter.wholesale:
        return txs
            .where((tx) => tx.category.toLowerCase().contains('wholesale'))
            .toList();
    }
  }
}

class _TypeFilterChips extends StatelessWidget {
  final _TypeFilter active;
  final ValueChanged<_TypeFilter> onSelect;
  const _TypeFilterChips({required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _TypeFilter.values.map((f) {
          final on = f == active;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onSelect(f);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: on
                      ? const Color(0xFF8B5CF6)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: on
                        ? const Color(0xFF8B5CF6)
                        : Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: Text(
                  f.label,
                  style: TextStyle(
                    color: on ? Colors.white : const Color(0xFF9CA3AF),
                    fontSize: 13,
                    fontWeight:
                        on ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
