// lib/features/bills/data/models/custom_bill_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

// ── Bill Item ─────────────────────────────────────────────────────────────────

class BillItem {
  final String name;
  final String hsnSac;
  final String size;
  final double qty;
  final double rate;

  const BillItem({
    required this.name,
    this.hsnSac = '',
    required this.size,
    required this.qty,
    required this.rate,
  });

  double get amount => qty * rate;

  BillItem copyWith({
    String? name,
    String? hsnSac,
    String? size,
    double? qty,
    double? rate,
  }) =>
      BillItem(
        name:   name   ?? this.name,
        hsnSac: hsnSac ?? this.hsnSac,
        size:   size   ?? this.size,
        qty:    qty    ?? this.qty,
        rate:   rate   ?? this.rate,
      );

  Map<String, dynamic> toMap() => {
        'name':   name,
        'hsnSac': hsnSac,
        'size':   size,
        'qty':    qty,
        'rate':   rate,
      };

  static BillItem fromMap(Map<String, dynamic> m) => BillItem(
        name:   m['name']   as String? ?? '',
        hsnSac: m['hsnSac'] as String? ?? '',
        size:   m['size']   as String? ?? '',
        qty:    (m['qty']  as num?)?.toDouble() ?? 0,
        rate:   (m['rate'] as num?)?.toDouble() ?? 0,
      );
}

// ── Custom Bill Model ─────────────────────────────────────────────────────────

class CustomBillModel {
  final String billId;
  final String billNumber;
  final DateTime billDate;
  final String businessName;
  final String businessAddress;
  final String clientName;
  final String clientAddress;
  final List<BillItem> items;
  final double taxRate;
  final double subtotal;
  final double taxAmount;
  final double grandTotal;
  final double receivedAmount;
  final String? pdfUrl;
  final DateTime createdAt;
  final String createdBy;
  final String createdByName;

  const CustomBillModel({
    required this.billId,
    required this.billNumber,
    required this.billDate,
    required this.businessName,
    required this.businessAddress,
    required this.clientName,
    required this.clientAddress,
    required this.items,
    required this.taxRate,
    required this.subtotal,
    required this.taxAmount,
    required this.grandTotal,
    this.receivedAmount = 0.0,
    this.pdfUrl,
    required this.createdAt,
    required this.createdBy,
    required this.createdByName,
  });

  Map<String, dynamic> toFirestore() => {
        'billId':          billId,
        'billNumber':      billNumber,
        'billDate':        Timestamp.fromDate(billDate),
        'businessName':    businessName,
        'businessAddress': businessAddress,
        'clientName':      clientName,
        'clientAddress':   clientAddress,
        'items':           items.map((e) => e.toMap()).toList(),
        'taxRate':         taxRate,
        'subtotal':        subtotal,
        'taxAmount':       taxAmount,
        'grandTotal':      grandTotal,
        'receivedAmount':  receivedAmount,
        'pdfUrl':          pdfUrl,
        'createdAt':       FieldValue.serverTimestamp(),
        'createdBy':       createdBy,
        'createdByName':   createdByName,
      };

  static CustomBillModel fromFirestore(DocumentSnapshot doc) {
    final d        = doc.data() as Map<String, dynamic>? ?? {};
    final rawItems = d['items'] as List? ?? [];
    final items = rawItems
        .whereType<Map<String, dynamic>>()
        .map(BillItem.fromMap)
        .toList();
    return CustomBillModel(
      billId:          d['billId']          as String?  ?? doc.id,
      billNumber:      d['billNumber']      as String?  ?? '',
      billDate:        (d['billDate']        as Timestamp?)?.toDate() ?? DateTime.now(),
      businessName:    d['businessName']    as String?  ?? '',
      businessAddress: d['businessAddress'] as String?  ?? '',
      clientName:      d['clientName']      as String?  ?? '',
      clientAddress:   d['clientAddress']   as String?  ?? '',
      items:           items,
      taxRate:         (d['taxRate']    as num?)?.toDouble() ?? 0,
      subtotal:        (d['subtotal']   as num?)?.toDouble() ?? 0,
      taxAmount:       (d['taxAmount']  as num?)?.toDouble() ?? 0,
      grandTotal:      (d['grandTotal'] as num?)?.toDouble() ?? 0,
      receivedAmount:  (d['receivedAmount'] as num?)?.toDouble() ?? 0,
      pdfUrl:          d['pdfUrl']          as String?,
      createdAt:       (d['createdAt']  as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy:       d['createdBy']       as String?  ?? '',
      createdByName:   d['createdByName']   as String?  ?? '',
    );
  }
}
