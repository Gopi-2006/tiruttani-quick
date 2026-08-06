import 'package:intl/intl.dart';

class Formatters {
  static String formatCurrency(double amount) {
    return '₹${amount.toStringAsFixed(0)}';
  }

  static String formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    return DateFormat('dd MMM, hh:mm a').format(dateTime);
  }
}
