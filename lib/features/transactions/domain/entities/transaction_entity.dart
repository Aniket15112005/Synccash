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
    );
  }
}
