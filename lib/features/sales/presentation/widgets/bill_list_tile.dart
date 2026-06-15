import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/sale_bill_entity.dart';

class BillListTile extends StatelessWidget {
  final SaleBillEntity bill;
  final double amountReceived;
  final VoidCallback onTap;

  const BillListTile({
    super.key,
    required this.bill,
    required this.amountReceived,
    required this.onTap,
  });

  static const _bg = Color(0xFF181B22);
  static const _border = Color(0xFF252830);
  static const _secondary = Color(0xFF7A8494);
  static const _green = Color(0xFF4DB87E);
  static const _amber = Color(0xFFE0A85C);
  static const _red = Color(0xFFE05C5C);

  @override
  Widget build(BuildContext context) {
    final remaining = bill.billTotal - amountReceived;
    final fmt = NumberFormat('#,##0.00');
    final dateStr = DateFormat('dd MMM yyyy').format(bill.billDate);

    Color pillColor;
    String pillLabel;

    if (remaining <= 0) {
      pillColor = _green;
      pillLabel = 'Settled';
    } else if (amountReceived > 0) {
      pillColor = _amber;
      pillLabel = '₹${fmt.format(remaining)} due';
    } else {
      pillColor = _amber;
      pillLabel = '₹${fmt.format(remaining)} due';
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bill.partyName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${bill.billNumber}  •  $dateStr',
                      style: const TextStyle(
                        color: _secondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${fmt.format(bill.billTotal)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: pillColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: pillColor.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      pillLabel,
                      style: TextStyle(
                        color: pillColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
