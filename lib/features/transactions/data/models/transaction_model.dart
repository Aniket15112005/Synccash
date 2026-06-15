import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';

class TransactionModel extends TransactionEntity {
  TransactionModel({
    required super.transactionId,
    required super.cashbookId,
    required super.createdBy,
    required super.creatorName,
    required super.createdAt,
    required super.amount,
    required super.type,
    required super.category,
    required super.description,
    super.linkedSaleBillId, // NEW — nullable, null for all existing docs
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json, String documentId) {
    return TransactionModel(
      transactionId: documentId,
      cashbookId: json['cashbookId'] as String? ?? '',
      createdBy: json['createdBy'] as String? ?? '',
      creatorName: json['creatorName'] as String? ?? 'Partner',
      category: json['category'] as String? ?? 'General',
      description: json['description'] as String? ?? '',
      type: json['type'] as String? ?? 'OUTFLOW',
      amount: (json['amount'] ?? 0.0).toDouble(),
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      linkedSaleBillId: json['linkedSaleBillId'] as String?, // NEW
    );
  }

  factory TransactionModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    return TransactionModel.fromJson(doc.data()!, doc.id);
  }

  Map<String, dynamic> toJson() {
    return {
      'transactionId': transactionId,
      'cashbookId': cashbookId,
      'createdBy': createdBy,
      'creatorName': creatorName.isEmpty ? 'Partner' : creatorName,
      'createdAt': Timestamp.fromDate(createdAt),
      'amount': amount,
      'type': type,
      'category': category.isEmpty ? 'General' : category,
      'description': description,
      // Only written when a bill is linked — keeps existing docs unchanged
      if (linkedSaleBillId != null) 'linkedSaleBillId': linkedSaleBillId,
    };
  }
}
