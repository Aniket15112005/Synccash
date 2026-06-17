import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../sales/domain/entities/sale_bill_entity.dart';

class DeletedBillEntity {
  final String   billId;
  final String   cashbookId;
  final String   partyName;
  final String   billNumber;
  final double   billTotal;
  final DateTime billDate;
  final String?  billNote;
  final String   billStatus;
  final String   billCreatedBy;
  final String   billCreatedByName;
  final DateTime billCreatedAt;
  final DateTime deletedAt;
  final String?  deletedBy;

  const DeletedBillEntity({
    required this.billId,
    required this.cashbookId,
    required this.partyName,
    required this.billNumber,
    required this.billTotal,
    required this.billDate,
    this.billNote,
    required this.billStatus,
    required this.billCreatedBy,
    required this.billCreatedByName,
    required this.billCreatedAt,
    required this.deletedAt,
    this.deletedBy,
  });

  int get daysRemaining {
    final expiry = deletedAt.add(const Duration(days: 15));
    return expiry.difference(DateTime.now()).inDays.clamp(0, 15);
  }

  bool get isExpired => daysRemaining <= 0;

  factory DeletedBillEntity.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return DeletedBillEntity(
      billId:            doc.id,
      cashbookId:        d['cashbookId']        as String? ?? '',
      partyName:         d['partyName']          as String? ?? '',
      billNumber:        d['billNumber']         as String? ?? '',
      billTotal:         (d['billTotal'] as num?)?.toDouble() ?? 0.0,
      billDate:          (d['billDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      billNote:          d['billNote']           as String?,
      billStatus:        d['billStatus']         as String? ?? 'pending',
      billCreatedBy:     d['billCreatedBy']      as String? ?? '',
      billCreatedByName: d['billCreatedByName']  as String? ?? '',
      billCreatedAt:     (d['billCreatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      deletedAt:         (d['deletedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      deletedBy:         d['deletedBy']          as String?,
    );
  }

  /// Used when restoring back to the sale_bills collection.
  Map<String, dynamic> toRestoreMap() => {
    'saleBillId':        billId,
    'cashbookId':        cashbookId,
    'partyName':         partyName,
    'billNumber':        billNumber,
    'billTotal':         billTotal,
    'billDate':          Timestamp.fromDate(billDate),
    if (billNote != null) 'billNote': billNote,
    'billStatus':        billStatus,
    'billCreatedBy':     billCreatedBy,
    'billCreatedByName': billCreatedByName,
    'billCreatedAt':     Timestamp.fromDate(billCreatedAt),
  };

  /// Converts back to a [SaleBillEntity] for use in the UI after restore.
  SaleBillEntity toEntity() => SaleBillEntity(
    saleBillId:        billId,
    partyName:         partyName,
    billNumber:        billNumber,
    billTotal:         billTotal,
    billDate:          billDate,
    billNote:          billNote,
    billCreatedAt:     billCreatedAt,
    billCreatedBy:     billCreatedBy,
    billCreatedByName: billCreatedByName,
    billStatus:        billStatus,
  );
}
