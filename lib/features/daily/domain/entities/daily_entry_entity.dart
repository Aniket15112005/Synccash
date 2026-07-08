// lib/features/daily/domain/entities/daily_entry_entity.dart
//
// Entity for the "Daily" feature — a fully isolated, personal income/expense
// tracker that lives in its own Firestore subcollection
// (cashbooks/{cashbookId}/daily_entries) and is never read by, written to,
// or mixed with the main app's `transactions` collection or any of its
// providers/screens.

class DailyEntryEntity {
  final String entryId;
  final String cashbookId;
  final String createdBy;
  final String creatorName;
  final DateTime createdAt;
  final double amount;
  final String type; // income | expense
  final String description;

  /// Tracks which user last edited this entry (mirrors the pattern used by
  /// TransactionEntity.lastEditedBy). Null until the entry is edited.
  final String? lastEditedBy;

  const DailyEntryEntity({
    required this.entryId,
    required this.cashbookId,
    required this.createdBy,
    required this.creatorName,
    required this.createdAt,
    required this.amount,
    required this.type,
    required this.description,
    this.lastEditedBy,
  });

  DailyEntryEntity copyWith({
    String? entryId,
    String? cashbookId,
    String? createdBy,
    String? creatorName,
    DateTime? createdAt,
    double? amount,
    String? type,
    String? description,
    String? lastEditedBy,
  }) {
    return DailyEntryEntity(
      entryId: entryId ?? this.entryId,
      cashbookId: cashbookId ?? this.cashbookId,
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
