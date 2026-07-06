// lib/features/purchases/domain/entities/purchase_bill_entity.dart
//
// Mirrors SaleBillEntity (see lib/features/sales/domain/entities/sale_bill_entity.dart)
// but represents a single purchase bill owed to a purchase client (supplier).

class PurchaseBillEntity {
  final String purchaseBillId;
  final String clientName;
  final String billNumber;
  final double billAmount;
  final DateTime billDate;

  /// Free-text note — used for "description / type of goods".
  final String? billNote;

  final DateTime billCreatedAt;
  final String billCreatedBy;
  final String billCreatedByName;

  /// 'pending' | 'partial' | 'paid'
  final String billStatus;

  const PurchaseBillEntity({
    required this.purchaseBillId,
    required this.clientName,
    required this.billNumber,
    required this.billAmount,
    required this.billDate,
    this.billNote,
    required this.billCreatedAt,
    required this.billCreatedBy,
    required this.billCreatedByName,
    required this.billStatus,
  });

  PurchaseBillEntity copyWith({
    String? purchaseBillId,
    String? clientName,
    String? billNumber,
    double? billAmount,
    DateTime? billDate,
    String? billNote,
    DateTime? billCreatedAt,
    String? billCreatedBy,
    String? billCreatedByName,
    String? billStatus,
  }) {
    return PurchaseBillEntity(
      purchaseBillId: purchaseBillId ?? this.purchaseBillId,
      clientName: clientName ?? this.clientName,
      billNumber: billNumber ?? this.billNumber,
      billAmount: billAmount ?? this.billAmount,
      billDate: billDate ?? this.billDate,
      billNote: billNote ?? this.billNote,
      billCreatedAt: billCreatedAt ?? this.billCreatedAt,
      billCreatedBy: billCreatedBy ?? this.billCreatedBy,
      billCreatedByName: billCreatedByName ?? this.billCreatedByName,
      billStatus: billStatus ?? this.billStatus,
    );
  }
}
