import 'dart:async';

class PaymentService {
  Future<bool> pay({
    required String method,
    required int amountPaise,
    required String orderId,
  }) async {
    if (method == 'UPI' || method == 'Card') {
      throw Exception('this service is not available for us');
    }

    String actualMethod = method;
    if (method == 'UPI') {
      actualMethod = 'Razorpay';
    } else if (method == 'Card') {
      actualMethod = 'Stripe';
    }

    if (actualMethod == 'COD') {
      return true;
    }
    else if (actualMethod == 'Razorpay'){
      await Future.delayed(const Duration(seconds: 2));
    }
    else if (actualMethod == 'PayPal'){
      await Future.delayed(const Duration(seconds: 2));
    }
    else if (actualMethod == 'Stripe'){
      await Future.delayed(const Duration(seconds: 2));
    }
    else {
      throw Exception('Unsupported payment method: $method');
    }
    return true;
  }
}
