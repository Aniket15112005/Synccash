// lib/features/purchases/data/models/purchase_bill_model.dart
//
// Mirrors lib/features/sales/data/models/sale_bill_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/purchase_bill_entity.dart';

class PurchaseBillModel extends PurchaseBillEntity {
  const PurchaseBillModel({
    required super.purchaseBillId,
    required super.clientName,
    required super.billNumber,
    required super.billAmount,
    required super.billDate,
    super.billNote,
    required super.billCreatedAt,
    required super.billCreatedBy,
    required super.billCreatedByName,
    required super.billStatus,
  });

  factory PurchaseBillModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PurchaseBillModel(
      purchaseBillId: data['purchaseBillId'] as String? ?? doc.id,
      clientName: data['clientName'] as String? ?? '',
      billNumber: data['billNumber'] as String? ?? '',
      billAmount: (data['billAmount'] as num?)?.toDouble() ?? 0.0,
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
      'purchaseBillId': purchaseBillId,
      'clientName': clientName,
      'billNumber': billNumber,
      'billAmount': billAmount,
      'billDate': Timestamp.fromDate(billDate),
      'billNote': billNote,
      'billCreatedAt': Timestamp.fromDate(billCreatedAt),
      'billCreatedBy': billCreatedBy,
      'billCreatedByName': billCreatedByName,
      'billStatus': billStatus,
    };
  }
}
