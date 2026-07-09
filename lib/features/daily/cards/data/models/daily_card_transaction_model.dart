// lib/features/daily/cards/data/models/daily_card_transaction_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:synccash/features/daily/cards/domain/entities/daily_card_transaction_entity.dart';

class DailyCardTransactionModel extends DailyCardTransactionEntity {
  DailyCardTransactionModel({
    required super.txId,
    required super.cashbookId,
    required super.cardId,
    required super.createdBy,
    required super.creatorName,
    required super.createdAt,
    required super.amount,
    required super.type,
    required super.description,
    super.lastEditedBy,
  });

  factory DailyCardTransactionModel.fromJson(
      Map<String, dynamic> json, String documentId) {
    return DailyCardTransactionModel(
      txId: documentId,
      cashbookId: json['cashbookId'] as String? ?? '',
      cardId: json['cardId'] as String? ?? '',
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

  factory DailyCardTransactionModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    return DailyCardTransactionModel.fromJson(doc.data()!, doc.id);
  }

  Map<String, dynamic> toJson() {
    return {
      'cashbookId': cashbookId,
      'cardId': cardId,
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
