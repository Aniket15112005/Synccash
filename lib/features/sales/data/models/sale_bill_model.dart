import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/sale_bill_entity.dart';

class SaleBillModel extends SaleBillEntity {
  const SaleBillModel({
    required super.saleBillId,
    required super.partyName,
    required super.billNumber,
    required super.billTotal,
    required super.billDate,
    super.billNote,
    required super.billCreatedAt,
    required super.billCreatedBy,
    required super.billCreatedByName,
    required super.billStatus,
  });

  factory SaleBillModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SaleBillModel(
      saleBillId: data['saleBillId'] as String? ?? doc.id,
      partyName: data['partyName'] as String? ?? '',
      billNumber: data['billNumber'] as String? ?? '',
      billTotal: (data['billTotal'] as num?)?.toDouble() ?? 0.0,
      billDate: (data['billDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      billNote: data['billNote'] as String?,
      billCreatedAt:
          (data['billCreatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      billCreatedBy: data['billCreatedBy'] as String? ?? '',
      billCreatedByName: data['billCreatedByName'] as String? ?? '',
      billStatus: data['billStatus'] as String? ?? 'pending',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'saleBillId': saleBillId,
      'partyName': partyName,
      'billNumber': billNumber,
      'billTotal': billTotal,
      'billDate': Timestamp.fromDate(billDate),
      'billNote': billNote,
      'billCreatedAt': Timestamp.fromDate(billCreatedAt),
      'billCreatedBy': billCreatedBy,
      'billCreatedByName': billCreatedByName,
      'billStatus': billStatus,
    };
  }
}
