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
    super.linkedSaleBillId, // nullable, null for all existing docs
    super.linkedPurchaseBillId, // NEW — nullable, null for all existing docs
    super.paymentAttachmentUrl,
    super.paymentAttachmentName,
    super.paymentAttachmentType,
    super.paymentReceiptUrl,
    super.paymentReceiptName,
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
      linkedSaleBillId: json['linkedSaleBillId'] as String?,
      linkedPurchaseBillId: json['linkedPurchaseBillId'] as String?, // NEW
      paymentAttachmentUrl: json['paymentAttachmentUrl'] as String?,
      paymentAttachmentName: json['paymentAttachmentName'] as String?,
      paymentAttachmentType: json['paymentAttachmentType'] as String?,
      paymentReceiptUrl: json['paymentReceiptUrl'] as String?,
      paymentReceiptName: json['paymentReceiptName'] as String?,
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
      if (linkedPurchaseBillId != null) 'linkedPurchaseBillId': linkedPurchaseBillId,
      if (paymentAttachmentUrl != null)
        'paymentAttachmentUrl': paymentAttachmentUrl,
      if (paymentAttachmentName != null)
        'paymentAttachmentName': paymentAttachmentName,
      if (paymentAttachmentType != null)
        'paymentAttachmentType': paymentAttachmentType,
      if (paymentReceiptUrl != null) 'paymentReceiptUrl': paymentReceiptUrl,
      if (paymentReceiptName != null) 'paymentReceiptName': paymentReceiptName,
    };
  }
}
