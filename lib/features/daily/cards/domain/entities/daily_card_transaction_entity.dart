// lib/features/daily/cards/domain/entities/daily_card_transaction_entity.dart
//
// A transaction that belongs to exactly one Daily Card. Stored in
// cashbooks/{cashbookId}/daily_cards/{cardId}/transactions — a subcollection
// scoped to that single card, so adding/editing/deleting an entry here can
// never affect another card, the main Daily list, or /transactions.

class DailyCardTransactionEntity {
  final String txId;
  final String cashbookId;
  final String cardId;
  final String createdBy;
  final String creatorName;
  final DateTime createdAt;
  final double amount;
  final String type; // income | expense
  final String description;
  final String? lastEditedBy;

  const DailyCardTransactionEntity({
    required this.txId,
    required this.cashbookId,
    required this.cardId,
    required this.createdBy,
    required this.creatorName,
    required this.createdAt,
    required this.amount,
    required this.type,
    required this.description,
    this.lastEditedBy,
  });

  DailyCardTransactionEntity copyWith({
    String? txId,
    String? cashbookId,
    String? cardId,
    String? createdBy,
    String? creatorName,
    DateTime? createdAt,
    double? amount,
    String? type,
    String? description,
    String? lastEditedBy,
  }) {
    return DailyCardTransactionEntity(
      txId: txId ?? this.txId,
      cashbookId: cashbookId ?? this.cashbookId,
      cardId: cardId ?? this.cardId,
      createdBy: createdBy ?? this.createdBy,
      creatorName: creatorName ?? this.creatorName,
      createdAt: createdAt ?? this.createdAt,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      description: description ?? this.description,
      lastEditedBy: lastEditedBy ?? this.lastEditedBy,
    );
  }
}
