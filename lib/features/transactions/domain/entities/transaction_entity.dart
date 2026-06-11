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
  }) {
    return TransactionEntity(
      transactionId: transactionId ?? this.transactionId,
      cashbookId: cashbookId ?? this.cashbookId,
      createdBy: createdBy ?? this.createdBy,
      creatorName: creatorName ?? this.creatorName,
      createdAt: createdAt ?? this.createdAt,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      category: category ?? this.category,
      description: description ?? this.description,
    );
  }
}