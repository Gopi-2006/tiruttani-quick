import 'dart:async';

class PaymentService {
  Future<bool> pay({
    required String method,
    required int amountPaise,
    required String orderId,
  }) async {
    final normalized = method.trim().toUpperCase();
    if (normalized == 'COD' || normalized == 'CASH ON DELIVERY') {
      return true;
    }

    if (normalized == 'UPI' || normalized == 'ONLINE' || normalized == 'PAY ONLINE') {
      // Online payment is orchestrated securely via server-side session after order reservation
      return true;
    }

    if (normalized == 'CARD') {
      throw Exception('Credit / Debit Card payments are coming soon.');
    }

    throw Exception('Unsupported payment method: $method');
  }
}
