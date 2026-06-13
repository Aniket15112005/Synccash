import 'package:cloud_firestore/cloud_firestore.dart';

class DeletedTransactionEntity {
  final String transactionId;
  final String cashbookId;
  final String createdBy;
  final String creatorName;
  final DateTime createdAt;
  final double amount;
  final String type;
  final String category;
  final String description;
  final String? lastEditedBy;
  final DateTime deletedAt;
  final String? deletedBy;

  const DeletedTransactionEntity({
    required this.transactionId,
    required this.cashbookId,
    required this.createdBy,
    required this.creatorName,
    required this.createdAt,
    required this.amount,
    required this.type,
    required this.category,
    required this.description,
    this.lastEditedBy,
    required this.deletedAt,
    this.deletedBy,
  });

  int get daysRemaining {
    final expiry = deletedAt.add(const Duration(days: 15));
    return expiry.difference(DateTime.now()).inDays.clamp(0, 15);
  }

  bool get isExpired => daysRemaining <= 0;

  factory DeletedTransactionEntity.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return DeletedTransactionEntity(
      transactionId: doc.id,
      cashbookId:    d['cashbookId']   as String? ?? '',
      createdBy:     d['createdBy']    as String? ?? '',
      creatorName:   d['creatorName']  as String? ?? '',
      createdAt:     (d['createdAt']   as Timestamp?)?.toDate() ?? DateTime.now(),
      amount:        (d['amount'] as num?)?.toDouble() ?? 0.0,
      type:          d['type']         as String? ?? '',
      category:      d['category']     as String? ?? '',
      description:   d['description']  as String? ?? '',
      lastEditedBy:  d['lastEditedBy'] as String?,
      deletedAt:     (d['deletedAt']   as Timestamp?)?.toDate() ?? DateTime.now(),
      deletedBy:     d['deletedBy']    as String?,
    );
  }

  /// Used when restoring back to the transactions collection.
  Map<String, dynamic> toRestoreMap() => {
    'cashbookId':   cashbookId,
    'createdBy':    createdBy,
    'creatorName':  creatorName,
    'createdAt':    Timestamp.fromDate(createdAt),
    'amount':       amount,
    'type':         type,
    'category':     category,
    'description':  description,
    if (lastEditedBy != null) 'lastEditedBy': lastEditedBy,
  };
}