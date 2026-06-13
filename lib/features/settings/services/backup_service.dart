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

class BackupService {
  static final _fileDateFmt = DateFormat('yyyyMMdd_HHmmss');

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
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes,
                name:     fileName,
                mimeType: SyncCashBackup.mimeType)
          ],
          subject: fileName,
          text: 'SyncCash backup — ${transactions.length} transactions',
        ),
      );
    } else {
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: SyncCashBackup.mimeType)],
          subject: fileName,
          text: 'SyncCash backup — ${transactions.length} transactions',
        ),
      );
    }
  }

  static Future<SyncCashBackup?> pickAndParseBackup(
      BuildContext context) async {
    FilePickerResult? result;

    // FIX: Use FileType.any on ALL platforms (web, iOS, Android).
    // FileType.custom causes a dark/greyed-out picker on Android because
    // the system file manager doesn't recognise .synccash as a known MIME type.
    // We validate the extension ourselves after the user picks.
    try {
      result = await FilePicker.platform.pickFiles(
        type:        FileType.any,
        withData:    true,
        dialogTitle: 'Select SyncCash Backup File',
      );
    } catch (_) {
      result = null;
    }

    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.first;

    final pickedName = picked.name.toLowerCase();
    if (!pickedName.endsWith('.${SyncCashBackup.fileExtension}') &&
        !pickedName.endsWith('.json')) {
      throw BackupValidationException(
          'Wrong file type selected. Please pick a file ending in '
          '.${SyncCashBackup.fileExtension}');
    }

    Uint8List? bytes = picked.bytes;

    if ((bytes == null || bytes.isEmpty) && !kIsWeb && picked.path != null) {
      try {
        bytes = await File(picked.path!).readAsBytes();
      } catch (_) {}
    }

    if (bytes == null || bytes.isEmpty) {
      throw BackupValidationException(
          'Could not read the selected file.\n\n'
          'On iPhone: open the Files app, locate the backup, then try again. '
          'Make sure the file has fully downloaded from iCloud first.');
    }

    String raw;
    try {
      raw = utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      throw BackupValidationException(
          'The file could not be read — it may be corrupted or not a valid '
          'SyncCash backup.');
    }

    Map<String, dynamic> jsonMap;
    try {
      jsonMap = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw BackupValidationException(
          'Invalid backup file. The selected file is not a valid SyncCash backup.');
    }

    for (final key in ['version', 'exportedAt', 'cashbookId', 'transactions']) {
      if (!jsonMap.containsKey(key)) {
        throw BackupValidationException(
            'Invalid backup — missing "$key" field. '
            'Make sure you selected the correct .${SyncCashBackup.fileExtension} file.');
      }
    }

    return SyncCashBackup.fromJson(jsonMap);
  }
}