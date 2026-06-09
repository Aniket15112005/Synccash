class UserEntity {
  final String uid;
  final String email;
  final String displayName;
  final String? currentCashbookId;

  const UserEntity({
    required this.uid,
    required this.email,
    required this.displayName,
    this.currentCashbookId,
  });
}