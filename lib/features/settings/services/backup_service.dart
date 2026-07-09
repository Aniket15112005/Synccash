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


// ── Purchase bill snapshot (for backup only) ─────────────────────────────────

class PurchaseBillBackup {
  final String   purchaseBillId;
  final String   clientName;
  final String   billNumber;
  final double   billAmount;
  final DateTime billDate;
  final String?  billNote;
  final DateTime billCreatedAt;
  final String   billCreatedBy;
  final String   billCreatedByName;
  final String   billStatus;

  const PurchaseBillBackup({
    required this.purchaseBillId,
    required this.clientName,
    required this.billNumber,
    required this.billAmount,
    required this.billDate,
    this.billNote,
    required this.billCreatedAt,
    required this.billCreatedBy,
    required this.billCreatedByName,
    required this.billStatus,
  });

  Map<String, dynamic> toJson() => {
    'purchaseBillId':    purchaseBillId,
    'clientName':        clientName,
    'billNumber':        billNumber,
    'billAmount':        billAmount,
    'billDate':          billDate.toIso8601String(),
    'billNote':          billNote,
    'billCreatedAt':     billCreatedAt.toIso8601String(),
    'billCreatedBy':     billCreatedBy,
    'billCreatedByName': billCreatedByName,
    'billStatus':        billStatus,
  };

  factory PurchaseBillBackup.fromJson(Map<String, dynamic> j) => PurchaseBillBackup(
    purchaseBillId:    j['purchaseBillId']    as String?  ?? '',
    clientName:        j['clientName']        as String?  ?? '',
    billNumber:        j['billNumber']        as String?  ?? '',
    billAmount:        (j['billAmount']  as num?)?.toDouble() ?? 0.0,
    billDate:          DateTime.parse(j['billDate']      as String),
    billNote:          j['billNote']          as String?,
    billCreatedAt:     DateTime.parse(j['billCreatedAt'] as String),
    billCreatedBy:     j['billCreatedBy']     as String?  ?? '',
    billCreatedByName: j['billCreatedByName'] as String?  ?? '',
    billStatus:        j['billStatus']        as String?  ?? 'pending',
  );
}

// ── Daily entry snapshot (for backup only) ────────────────────────────────────

class DailyEntryBackup {
  final String   entryId;
  final String   cashbookId;
  final String   createdBy;
  final String   creatorName;
  final DateTime createdAt;
  final double   amount;
  final String   type;
  final String   description;

  const DailyEntryBackup({
    required this.entryId,
    required this.cashbookId,
    required this.createdBy,
    required this.creatorName,
    required this.createdAt,
    required this.amount,
    required this.type,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
    'entryId':     entryId,
    'cashbookId':  cashbookId,
    'createdBy':   createdBy,
    'creatorName': creatorName,
    'createdAt':   createdAt.toIso8601String(),
    'amount':      amount,
    'type':        type,
    'description': description,
  };

  factory DailyEntryBackup.fromJson(Map<String, dynamic> j) => DailyEntryBackup(
    entryId:     j['entryId']     as String?  ?? '',
    cashbookId:  j['cashbookId']  as String?  ?? '',
    createdBy:   j['createdBy']   as String?  ?? '',
    creatorName: j['creatorName'] as String?  ?? '',
    createdAt:   DateTime.parse(j['createdAt'] as String),
    amount:      (j['amount'] as num?)?.toDouble() ?? 0.0,
    type:        j['type']        as String?  ?? 'expense',
    description: j['description'] as String?  ?? '',
  );
}

// ── Daily card transaction snapshot (for backup only) ─────────────────────────

class DailyCardTxBackup {
  final String   txId;
  final String   cardId;
  final String   createdBy;
  final String   creatorName;
  final DateTime createdAt;
  final double   amount;
  final String   type;
  final String   description;

  const DailyCardTxBackup({
    required this.txId,
    required this.cardId,
    required this.createdBy,
    required this.creatorName,
    required this.createdAt,
    required this.amount,
    required this.type,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
    'txId':        txId,
    'cardId':      cardId,
    'createdBy':   createdBy,
    'creatorName': creatorName,
    'createdAt':   createdAt.toIso8601String(),
    'amount':      amount,
    'type':        type,
    'description': description,
  };

  factory DailyCardTxBackup.fromJson(Map<String, dynamic> j) => DailyCardTxBackup(
    txId:        j['txId']        as String?  ?? '',
    cardId:      j['cardId']      as String?  ?? '',
    createdBy:   j['createdBy']   as String?  ?? '',
    creatorName: j['creatorName'] as String?  ?? '',
    createdAt:   DateTime.parse(j['createdAt'] as String),
    amount:      (j['amount'] as num?)?.toDouble() ?? 0.0,
    type:        j['type']        as String?  ?? 'expense',
    description: j['description'] as String?  ?? '',
  );
}

// ── Daily card snapshot (for backup only) ─────────────────────────────────────

class DailyCardBackup {
  final String                  cardId;
  final String                  cashbookId;
  final String                  name;
  final String?                 number;
  final String?                 bankName;
  final int                     colorIndex;
  final String                  createdBy;
  final String                  creatorName;
  final DateTime                createdAt;
  final List<DailyCardTxBackup> transactions;

  const DailyCardBackup({
    required this.cardId,
    required this.cashbookId,
    required this.name,
    this.number,
    this.bankName,
    required this.colorIndex,
    required this.createdBy,
    required this.creatorName,
    required this.createdAt,
    this.transactions = const [],
  });

  Map<String, dynamic> toJson() => {
    'cardId':       cardId,
    'cashbookId':   cashbookId,
    'name':         name,
    if (number   != null && number!.isNotEmpty)   'number':   number,
    if (bankName != null && bankName!.isNotEmpty) 'bankName': bankName,
    'colorIndex':   colorIndex,
    'createdBy':    createdBy,
    'creatorName':  creatorName,
    'createdAt':    createdAt.toIso8601String(),
    'transactions': transactions.map((t) => t.toJson()).toList(),
  };

  factory DailyCardBackup.fromJson(Map<String, dynamic> j) => DailyCardBackup(
    cardId:      j['cardId']      as String?  ?? '',
    cashbookId:  j['cashbookId']  as String?  ?? '',
    name:        j['name']        as String?  ?? 'Card',
    number:      j['number']      as String?,
    bankName:    j['bankName']    as String?,
    colorIndex:  (j['colorIndex'] as num?)?.toInt() ?? 0,
    createdBy:   j['createdBy']   as String?  ?? '',
    creatorName: j['creatorName'] as String?  ?? '',
    createdAt:   DateTime.parse(j['createdAt'] as String),
    transactions: (j['transactions'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map((t) => DailyCardTxBackup.fromJson(t))
        .toList(),
  );
}

// ── Main backup envelope ──────────────────────────────────────────────────────

class SyncCashBackup {
  static const String currentVersion = '3.0.0';
  static const String fileExtension  = 'synccash';
  static const String mimeType       = 'application/octet-stream';

  final String version;
  final DateTime exportedAt;
  final String cashbookId;
  final String cashbookName;
  final List<TransactionEntity>  transactions;
  final List<SaleBillBackup>     saleBills;
  final List<PartyBackup>        parties;
  final List<PurchaseBillBackup> purchaseBills;
  final List<DailyEntryBackup>   dailyEntries;
  final List<DailyCardBackup>    dailyCards;

  const SyncCashBackup({
    required this.version,
    required this.exportedAt,
    required this.cashbookId,
    required this.cashbookName,
    required this.transactions,
    this.saleBills     = const [],
    this.parties       = const [],
    this.purchaseBills = const [],
    this.dailyEntries  = const [],
    this.dailyCards    = const [],
  });

  Map<String, dynamic> toJson() => {
    'version':          version,
    'exportedAt':       exportedAt.toIso8601String(),
    'cashbookId':       cashbookId,
    'cashbookName':     cashbookName,
    'transactionCount':  transactions.length,
    'saleBillCount':     saleBills.length,
    'partyCount':        parties.length,
    'purchaseBillCount': purchaseBills.length,
    'dailyEntryCount':   dailyEntries.length,
    'dailyCardCount':    dailyCards.length,
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
    'saleBills':     saleBills.map((b) => b.toJson()).toList(),
    'parties':       parties.map((p) => p.toJson()).toList(),
    'purchaseBills': purchaseBills.map((b) => b.toJson()).toList(),
    'dailyEntries':  dailyEntries.map((e) => e.toJson()).toList(),
    'dailyCards':    dailyCards.map((c) => c.toJson()).toList(),
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
      saleBills:     billList.map((b) => SaleBillBackup.fromJson(b)).toList(),
      parties:       partyList.map((p) => PartyBackup.fromJson(p)).toList(),
      purchaseBills: (json['purchaseBills'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map((b) => PurchaseBillBackup.fromJson(b))
          .toList(),
      dailyEntries: (json['dailyEntries'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map((e) => DailyEntryBackup.fromJson(e))
          .toList(),
      dailyCards: (json['dailyCards'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map((card) => DailyCardBackup.fromJson(card))
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

// ── Service ───────────────────────────────────────────────────────────────────

class BackupService {
  static final _fileDateFmt = DateFormat('yyyyMMdd_HHmmss');

  static Future<void> createBackup({
    required BuildContext            context,
    required CashbookEntity          cashbook,
    required List<TransactionEntity> transactions,
    List<SaleBillBackup>             saleBills     = const [],
    List<PartyBackup>                parties       = const [],
    List<PurchaseBillBackup>         purchaseBills = const [],
    List<DailyEntryBackup>           dailyEntries  = const [],
    List<DailyCardBackup>            dailyCards    = const [],
  }) async {
    final backup = SyncCashBackup(
      version:      SyncCashBackup.currentVersion,
      exportedAt:   DateTime.now(),
      cashbookId:   cashbook.id,
      cashbookName: 'Cashbook ${cashbook.inviteCode}',
      transactions:  transactions,
      saleBills:     saleBills,
      parties:       parties,
      purchaseBills: purchaseBills,
      dailyEntries:  dailyEntries,
      dailyCards:    dailyCards,
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
