import 'package:intl/intl.dart';

class CurrencyFormatter {
  static String format(num amount) {
    return NumberFormat('#,##,##0', 'en_IN').format(amount);
  }
}