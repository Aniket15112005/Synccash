class SaleBillEntity {
  final String saleBillId;
  final String partyName;
  final String billNumber;
  final double billTotal;
  final DateTime billDate;
  final String? billNote;
  final DateTime billCreatedAt;
  final String billCreatedBy;
  final String billCreatedByName;
  final String billStatus;

  const SaleBillEntity({
    required this.saleBillId,
    required this.partyName,
    required this.billNumber,
    required this.billTotal,
    required this.billDate,
    this.billNote,
    required this.billCreatedAt,
    required this.billCreatedBy,
    required this.billCreatedByName,
    required this.billStatus,
  });

  bool get isSettled => billStatus == 'settled';
  bool get isPending => billStatus == 'pending';

  SaleBillEntity copyWith({
    String? saleBillId,
    String? partyName,
    String? billNumber,
    double? billTotal,
    DateTime? billDate,
    String? billNote,
    DateTime? billCreatedAt,
    String? billCreatedBy,
    String? billCreatedByName,
    String? billStatus,
  }) {
    return SaleBillEntity(
      saleBillId: saleBillId ?? this.saleBillId,
      partyName: partyName ?? this.partyName,
      billNumber: billNumber ?? this.billNumber,
      billTotal: billTotal ?? this.billTotal,
      billDate: billDate ?? this.billDate,
      billNote: billNote ?? this.billNote,
      billCreatedAt: billCreatedAt ?? this.billCreatedAt,
      billCreatedBy: billCreatedBy ?? this.billCreatedBy,
      billCreatedByName: billCreatedByName ?? this.billCreatedByName,
      billStatus: billStatus ?? this.billStatus,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaleBillEntity && other.saleBillId == saleBillId;

  @override
  int get hashCode => saleBillId.hashCode;
}
