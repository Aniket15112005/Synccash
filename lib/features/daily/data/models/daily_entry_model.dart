// lib/features/daily/data/models/daily_entry_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:synccash/features/daily/domain/entities/daily_entry_entity.dart';

class DailyEntryModel extends DailyEntryEntity {
  DailyEntryModel({
    required super.entryId,
    required super.cashbookId,
    required super.createdBy,
    required super.creatorName,
    required super.createdAt,
    required super.amount,
    required super.type,
    required super.description,
    super.lastEditedBy,
  });

  factory DailyEntryModel.fromJson(
      Map<String, dynamic> json, String documentId) {
    return DailyEntryModel(
      entryId: documentId,
      cashbookId: json['cashbookId'] as String? ?? '',
      createdBy: json['createdBy'] as String? ?? '',
      creatorName: json['creatorName'] as String? ?? 'Partner',
      description: json['description'] as String? ?? '',
      type: json['type'] as String? ?? 'expense',
      amount: (json['amount'] ?? 0.0).toDouble(),
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      lastEditedBy: json['lastEditedBy'] as String?,
    );
  }

  factory DailyEntryModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    return DailyEntryModel.fromJson(doc.data()!, doc.id);
  }

  Map<String, dynamic> toJson() {
    return {
      'cashbookId': cashbookId,
      'createdBy': createdBy,
      'creatorName': creatorName.isEmpty ? 'Partner' : creatorName,
      'createdAt': Timestamp.fromDate(createdAt),
      'amount': amount,
      'type': type,
      'description': description,
      if (lastEditedBy != null) 'lastEditedBy': lastEditedBy,
    };
  }
}
