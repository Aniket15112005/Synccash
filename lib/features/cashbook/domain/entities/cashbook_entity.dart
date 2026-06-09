class CashbookEntity {
  final String id;
  final String inviteCode;
  final String ownerId;
  final String? participantId;
  final double totalBalance;
  final double totalIncome;
  final double totalExpense;

  const CashbookEntity({
    required this.id,
    required this.inviteCode,
    required this.ownerId,
    this.participantId,
    required this.totalBalance,
    required this.totalIncome,
    required this.totalExpense,
  });
}