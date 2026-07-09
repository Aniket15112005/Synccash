// lib/features/daily/cards/domain/entities/daily_card_entity.dart
//
// Entity for the "Daily Cards" sub-feature — lives entirely inside the
// isolated Daily feature. Cards are stored in
// cashbooks/{cashbookId}/daily_cards and are never read by, written to, or
// mixed with /daily_entries, /transactions, or any other collection.

class DailyCardEntity {
  final String cardId;
  final String cashbookId;
  final String name;
  final String? number;
  final String? bankName;

  /// Index into the gradient palette used to render the card visually.
  /// Assigned once at creation so a card's colour stays stable over time.
  final int colorIndex;

  final String createdBy;
  final String creatorName;
  final DateTime createdAt;

  const DailyCardEntity({
    required this.cardId,
    required this.cashbookId,
    required this.name,
    this.number,
    this.bankName,
    required this.colorIndex,
    required this.createdBy,
    required this.creatorName,
    required this.createdAt,
  });

  DailyCardEntity copyWith({
    String? cardId,
    String? cashbookId,
    String? name,
    String? number,
    String? bankName,
    int? colorIndex,
    String? createdBy,
    String? creatorName,
    DateTime? createdAt,
  }) {
    return DailyCardEntity(
      cardId: cardId ?? this.cardId,
      cashbookId: cashbookId ?? this.cashbookId,
      name: name ?? this.name,
      number: number ?? this.number,
      bankName: bankName ?? this.bankName,
      colorIndex: colorIndex ?? this.colorIndex,
      createdBy: createdBy ?? this.createdBy,
      creatorName: creatorName ?? this.creatorName,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
