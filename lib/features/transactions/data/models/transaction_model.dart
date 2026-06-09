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
  });

  /// Safely parse Firestore JSON maps into a clean Dart Entity Model object
  factory TransactionModel.fromJson(Map<String, dynamic> json, String documentId) {
    return TransactionModel(
      transactionId: documentId,
      cashbookId: json['cashbookId'] as String? ?? '',
      createdBy: json['createdBy'] as String? ?? '',
      // Safe defaults to protect against null accounts or missing values:
      creatorName: json['creatorName'] as String? ?? 'Partner',
      category: json['category'] as String? ?? 'General',
      description: json['description'] as String? ?? '',
      type: json['type'] as String? ?? 'OUTFLOW',
      // Convert integers to doubles safely to avoid runtime casting dropouts
      amount: (json['amount'] ?? 0.0).toDouble(),
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  /// Convert model fields cleanly to map structures for database transactions
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
    };
  }
}