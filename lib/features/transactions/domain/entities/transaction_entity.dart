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
}