class TransactionEntity {
  final String transactionId;
  final String cashbookId;
  final String createdBy;
  final String creatorName;
  final DateTime createdAt;
  final double amount;
  final String type; // income | expense
  final String category;
  final String description;

  /// Tracks which user last edited this transaction.
  /// Written client-side on every edit so the Cloud Function can identify
  /// the editor in a single write (no separate Firestore update needed).
  final String? lastEditedBy;

  /// Links this transaction to a sale bill in sale_bills sub-collection.
  /// Null for all existing transactions — fully backward compatible.
  final String? linkedSaleBillId;

  /// Links this transaction to a purchase bill in purchase_bills
  /// sub-collection. Null for all existing/non-purchase transactions —
  /// fully backward compatible.
  final String? linkedPurchaseBillId;

  /// Optional documents saved against this individual purchase payment.
  /// These are transaction-level fields because one bill can have many
  /// separate payments.
  final String? paymentAttachmentUrl;
  final String? paymentAttachmentName;
  final String? paymentAttachmentType;
  final String? paymentReceiptUrl;
  final String? paymentReceiptName;

  const TransactionEntity({
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
    this.linkedSaleBillId,
    this.linkedPurchaseBillId,
    this.paymentAttachmentUrl,
    this.paymentAttachmentName,
    this.paymentAttachmentType,
    this.paymentReceiptUrl,
    this.paymentReceiptName,
  });

  TransactionEntity copyWith({
    String? transactionId,
    String? cashbookId,
    String? createdBy,
    String? creatorName,
    DateTime? createdAt,
    double? amount,
    String? type,
    String? category,
    String? description,
    String? lastEditedBy,
    String? linkedSaleBillId,
    String? linkedPurchaseBillId,
    String? paymentAttachmentUrl,
    String? paymentAttachmentName,
    String? paymentAttachmentType,
    String? paymentReceiptUrl,
    String? paymentReceiptName,
  }) {
    return TransactionEntity(
      transactionId: transactionId ?? this.transactionId,
      cashbookId:    cashbookId    ?? this.cashbookId,
      createdBy:     createdBy     ?? this.createdBy,
      creatorName:   creatorName   ?? this.creatorName,
      createdAt:     createdAt     ?? this.createdAt,
      amount:        amount        ?? this.amount,
      type:          type          ?? this.type,
      category:      category      ?? this.category,
      description:   description   ?? this.description,
      lastEditedBy:  lastEditedBy  ?? this.lastEditedBy,
      linkedSaleBillId: linkedSaleBillId ?? this.linkedSaleBillId,
      linkedPurchaseBillId: linkedPurchaseBillId ?? this.linkedPurchaseBillId,
      paymentAttachmentUrl: paymentAttachmentUrl ?? this.paymentAttachmentUrl,
      paymentAttachmentName: paymentAttachmentName ?? this.paymentAttachmentName,
      paymentAttachmentType: paymentAttachmentType ?? this.paymentAttachmentType,
      paymentReceiptUrl: paymentReceiptUrl ?? this.paymentReceiptUrl,
      paymentReceiptName: paymentReceiptName ?? this.paymentReceiptName,
    );
  }
}
