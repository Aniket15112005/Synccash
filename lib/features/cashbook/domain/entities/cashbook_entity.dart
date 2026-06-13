class CashbookEntity {
  final String id;
  final String inviteCode;
  final String ownerId;
  final String? participantId;
  final double totalBalance;
  final double totalIncome;
  final double totalExpense;

  /// UID of the iOS user in this cashbook.
  /// Written by FCMService when the iOS user saves their FCM token.
  /// Read by the Cloud Function to identify the notification receiver
  /// without needing an extra Firestore lookup.
  final String? iosReceiverId;

  /// Cached FCM tokens of the iOS user.
  /// Kept in sync by FCMService on token save/refresh/logout.
  /// The Cloud Function reads only the cashbook doc (1 read total)
  /// instead of 3 separate reads for sender + cashbook + receiver.
  final List<String> iosReceiverTokens;

  const CashbookEntity({
    required this.id,
    required this.inviteCode,
    required this.ownerId,
    this.participantId,
    required this.totalBalance,
    required this.totalIncome,
    required this.totalExpense,
    this.iosReceiverId,
    this.iosReceiverTokens = const [],
  });
}
