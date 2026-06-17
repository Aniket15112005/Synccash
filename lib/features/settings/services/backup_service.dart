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

// ── Sale bill snapshot (for backup only) ─────────────────────────────────────

class SaleBillBackup {
  final String   saleBillId;
  final String   partyName;
  final String   billNumber;
  final double   billTotal;
  final DateTime billDate;
  final String?  billNote;
  final DateTime billCreatedAt;
  final String   billCreatedBy;
  final String   billCreatedByName;
  final String   billStatus;

  const SaleBillBackup({
    required this.saleBillId,
    required this.partyName,
    required this.billNumber,
    required this.billTotal,
    required this.billDate,
    this.billNote,
    required this.billCreatedAt,
    required this.billCreatedBy,
    required this.billCreatedByName,
    required this.billStatus,
  });

  Map<String, dynamic> toJson() => {
    'saleBillId':        saleBillId,
    'partyName':         partyName,
    'billNumber':        billNumber,
    'billTotal':         billTotal,
    'billDate':          billDate.toIso8601String(),
    'billNote':          billNote,
    'billCreatedAt':     billCreatedAt.toIso8601String(),
    'billCreatedBy':     billCreatedBy,
    'billCreatedByName': billCreatedByName,
    'billStatus':        billStatus,
  };

  factory SaleBillBackup.fromJson(Map<String, dynamic> j) => SaleBillBackup(
    saleBillId:        j['saleBillId']        as String?  ?? '',
    partyName:         j['partyName']          as String?  ?? '',
    billNumber:        j['billNumber']          as String?  ?? '',
    billTotal:         (j['billTotal']  as num?)?.toDouble() ?? 0.0,
    billDate:          DateTime.parse(j['billDate']      as String),
    billNote:          j['billNote']            as String?,
    billCreatedAt:     DateTime.parse(j['billCreatedAt'] as String),
    billCreatedBy:     j['billCreatedBy']      as String?  ?? '',
    billCreatedByName: j['billCreatedByName']  as String?  ?? '',
    billStatus:        j['billStatus']          as String?  ?? 'pending',
  );
}

// ── Party snapshot (for backup only) ─────────────────────────────────────────

class PartyBackup {
  final String partyId;
  final String partyName;
  final double openingBalance;
  final String description;
  final String place;

  const PartyBackup({
    required this.partyId,
    required this.partyName,
    required this.openingBalance,
    this.description = '',
    this.place = '',
  });

  Map<String, dynamic> toJson() => {
    'partyId':        partyId,
    'partyName':      partyName,
    'openingBalance': openingBalance,
    'description':    description,
    'place':          place,
  };

  factory PartyBackup.fromJson(Map<String, dynamic> j) => PartyBackup(
    partyId:        j['partyId']        as String? ?? '',
    partyName:      j['partyName']      as String? ?? '',
    openingBalance: (j['openingBalance'] as num?)?.toDouble() ?? 0.0,
    description:    j['description']    as String? ?? '',
    place:          j['place']          as String? ?? '',
  );
}

// ── Main backup envelope ──────────────────────────────────────────────────────

class SyncCashBackup {
  static const String currentVersion = '2.0.0';
  static const String fileExtension  = 'synccash';
  static const String mimeType       = 'application/octet-stream';

  final String version;
  final DateTime exportedAt;
  final String cashbookId;
  final String cashbookName;
  final List<TransactionEntity> transactions;
  final List<SaleBillBackup>    saleBills;
  final List<PartyBackup>       parties;

  const SyncCashBackup({
    required this.version,
    required this.exportedAt,
    required this.cashbookId,
    required this.cashbookName,
    required this.transactions,
    this.saleBills = const [],
    this.parties   = const [],
  });

  Map<String, dynamic> toJson() => {
    'version':          version,
    'exportedAt':       exportedAt.toIso8601String(),
    'cashbookId':       cashbookId,
    'cashbookName':     cashbookName,
    'transactionCount': transactions.length,
    'saleBillCount':    saleBills.length,
    'partyCount':       parties.length,
    'transactions': transactions.map((t) => {
      'transactionId': t.transactionId,
      'cashbookId':    t.cashbookId,
      'createdBy':     t.createdBy,
      'creatorName':   t.creatorName,
      'createdAt':     t.createdAt.toIso8601String(),
      'amount':        t.amount,
      'type':          t.type,
      'category':      t.category,
      'description':   t.description,
    }).toList(),
    'saleBills': saleBills.map((b) => b.toJson()).toList(),
    'parties':   parties.map((p) => p.toJson()).toList(),
  };

  factory SyncCashBackup.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as String? ?? '1.0.0';
    final parts = version.split('.').map(int.parse).toList();
    final majorVersion = parts.isNotEmpty ? parts[0] : 1;
    if (majorVersion > 2) {
      throw BackupVersionException(
          'This backup was created with a newer version of SyncCash '
          '($version). Please update the app to restore it.');
    }

    final txList = (json['transactions'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    // v1 backups have no saleBills / parties — default to empty lists
    final billList = (json['saleBills'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final partyList = (json['parties'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    return SyncCashBackup(
      version:      version,
      exportedAt:   DateTime.parse(json['exportedAt'] as String),
      cashbookId:   json['cashbookId'] as String,
      cashbookName: json['cashbookName'] as String? ?? 'Unknown',
      transactions: txList.map((t) => TransactionEntity(
        transactionId: t['transactionId'] as String,
        cashbookId:    t['cashbookId']    as String,
        createdBy:     t['createdBy']     as String,
        creatorName:   t['creatorName']   as String? ?? '',
        createdAt:     DateTime.parse(t['createdAt'] as String),
        amount:        (t['amount'] as num).toDouble(),
        type:          t['type']          as String,
        category:      t['category']      as String,
        description:   t['description']   as String? ?? '',
      )).toList(),
      saleBills: billList.map((b) => SaleBillBackup.fromJson(b)).toList(),
      parties:   partyList.map((p) => PartyBackup.fromJson(p)).toList(),
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

// ── Service ───────────────────────────────────────────────────────────────────

class BackupService {
  static final _fileDateFmt = DateFormat('yyyyMMdd_HHmmss');

  static Future<void> createBackup({
    required BuildContext            context,
    required CashbookEntity          cashbook,
    required List<TransactionEntity> transactions,
    List<SaleBillBackup>             saleBills = const [],
    List<PartyBackup>                parties   = const [],
  }) async {
    final backup = SyncCashBackup(
      version:      SyncCashBackup.currentVersion,
      exportedAt:   DateTime.now(),
      cashbookId:   cashbook.id,
      cashbookName: 'Cashbook ${cashbook.inviteCode}',
      transactions: transactions,
      saleBills:    saleBills,
      parties:      parties,
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
          text: 'SyncCash backup — ${transactions.length} transactions, '
                '${saleBills.length} bills, ${parties.length} parties',
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
          text: 'SyncCash backup — ${transactions.length} transactions, '
                '${saleBills.length} bills, ${parties.length} parties',
        ),
      );
    }
  }

  static Future<SyncCashBackup?> pickAndParseBackup(
      BuildContext context) async {
    FilePickerResult? result;

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
