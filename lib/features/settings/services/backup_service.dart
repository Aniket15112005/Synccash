// lib/features/settings/services/backup_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:synccash/features/cashbook/domain/entities/cashbook_entity.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';

// ── Backup file model ─────────────────────────────────────────────────────────

class SyncCashBackup {
  static const String currentVersion = '1.0.0';
  static const String fileExtension  = 'synccash';
  static const String mimeType       = 'application/octet-stream';

  final String version;
  final DateTime exportedAt;
  final String cashbookId;
  final String cashbookName;
  final List<TransactionEntity> transactions;

  const SyncCashBackup({
    required this.version,
    required this.exportedAt,
    required this.cashbookId,
    required this.cashbookName,
    required this.transactions,
  });

  Map<String, dynamic> toJson() => {
        'version':          version,
        'exportedAt':       exportedAt.toIso8601String(),
        'cashbookId':       cashbookId,
        'cashbookName':     cashbookName,
        'transactionCount': transactions.length,
        'transactions': transactions
            .map((t) => {
                  'transactionId': t.transactionId,
                  'cashbookId':    t.cashbookId,
                  'createdBy':     t.createdBy,
                  'creatorName':   t.creatorName,
                  'createdAt':     t.createdAt.toIso8601String(),
                  'amount':        t.amount,
                  'type':          t.type,
                  'category':      t.category,
                  'description':   t.description,
                })
            .toList(),
      };

  factory SyncCashBackup.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as String? ?? '1.0.0';
    final parts = version.split('.').map(int.parse).toList();
    final majorVersion = parts.isNotEmpty ? parts[0] : 1;
    if (majorVersion > 1) {
      throw BackupVersionException(
          'This backup was created with a newer version of SyncCash '
          '($version). Please update the app to restore it.');
    }

    final txList = (json['transactions'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    return SyncCashBackup(
      version:      version,
      exportedAt:   DateTime.parse(json['exportedAt'] as String),
      cashbookId:   json['cashbookId'] as String,
      cashbookName: json['cashbookName'] as String? ?? 'Unknown',
      transactions: txList
          .map((t) => TransactionEntity(
                transactionId: t['transactionId'] as String,
                cashbookId:    t['cashbookId']    as String,
                createdBy:     t['createdBy']     as String,
                creatorName:   t['creatorName']   as String? ?? '',
                createdAt:     DateTime.parse(t['createdAt'] as String),
                amount:        (t['amount'] as num).toDouble(),
                type:          t['type']          as String,
                category:      t['category']      as String,
                description:   t['description']   as String? ?? '',
              ))
          .toList(),
    );
  }
}

class BackupVersionException implements Exception {
  final String message;
  BackupVersionException(this.message);
  @override
  String toString() => message;
}

class BackupValidationException implements Exception {
  final String message;
  BackupValidationException(this.message);
  @override
  String toString() => message;
}

// ── Backup service ────────────────────────────────────────────────────────────

class BackupService {
  static final _fileDateFmt = DateFormat('yyyyMMdd_HHmmss');

  // ── Create & share backup ─────────────────────────────────────────────────

  static Future<void> createBackup({
    required BuildContext context,
    required CashbookEntity cashbook,
    required List<TransactionEntity> transactions,
  }) async {
    final backup = SyncCashBackup(
      version:      SyncCashBackup.currentVersion,
      exportedAt:   DateTime.now(),
      cashbookId:   cashbook.id,
      cashbookName: 'Cashbook ${cashbook.inviteCode}',
      transactions: transactions,
    );

    final json   = const JsonEncoder.withIndent('  ').convert(backup.toJson());
    final bytes  = Uint8List.fromList(utf8.encode(json));
    final fileName =
        'SyncCash_Backup_${_fileDateFmt.format(backup.exportedAt)}'
        '.${SyncCashBackup.fileExtension}';

    if (kIsWeb) {
      // Web / iOS PWA: use in-memory XFile — no path_provider needed
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes,
                name:     fileName,
                mimeType: SyncCashBackup.mimeType)
          ],
          subject: fileName,
          text:
              'SyncCash backup — ${transactions.length} transactions',
        ),
      );
    } else {
      // Android / iOS native: write to temp file then share
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: SyncCashBackup.mimeType)],
          subject: fileName,
          text:
              'SyncCash backup — ${transactions.length} transactions',
        ),
      );
    }
  }

  // ── Pick & parse backup file ──────────────────────────────────────────────

  static Future<SyncCashBackup?> pickAndParseBackup(
      BuildContext context) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type:              FileType.custom,
        allowedExtensions: [SyncCashBackup.fileExtension, 'json'],
        withData:          true,
        dialogTitle:       'Select SyncCash Backup File',
      );
    } catch (_) {
      // Fallback: no extension filter (some platforms don't support it)
      result = await FilePicker.platform.pickFiles(withData: true);
    }

    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.first;
    final bytes  = picked.bytes;

    if (bytes == null || bytes.isEmpty) {
      throw BackupValidationException(
          'Could not read the selected file. Please try again.');
    }

    final raw = utf8.decode(bytes);
    Map<String, dynamic> jsonMap;
    try {
      jsonMap = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw BackupValidationException(
          'Invalid backup file. The file is not a valid SyncCash backup.');
    }

    for (final key in [
      'version', 'exportedAt', 'cashbookId', 'transactions'
    ]) {
      if (!jsonMap.containsKey(key)) {
        throw BackupValidationException(
            'Invalid backup file — missing "$key" field. '
            'Make sure you selected a SyncCash backup file.');
      }
    }

    return SyncCashBackup.fromJson(jsonMap);
  }
}