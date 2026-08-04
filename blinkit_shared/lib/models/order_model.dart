import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class OrderModel {
  final String id;
  final String orderNumber;
  final String customerId;
  final String deliveryAddressId;
  final double subtotal;
  final double deliveryFee;
  final double totalPrice;
  final String paymentMethod;
  final String paymentStatus;
  final String status;
  final int statusIndex;
  final DateTime? placedAt;
  final DateTime? confirmedAt;
  final DateTime? packedAt;
  final DateTime? outForDeliveryAt;
  final DateTime? deliveredAt;
  final DateTime? eta;
  final String notes;
  final String verificationCode;

  // Cancellation and Refund Fields
  final String? cancellationReason;
  final String? cancelledBy;
  final DateTime? cancelledAt;
  final String? refundStatus;

  const OrderModel({
    required this.id,
    required this.orderNumber,
    required this.customerId,
    required this.deliveryAddressId,
    required this.subtotal,
    required this.deliveryFee,
    required this.totalPrice,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.status,
    required this.statusIndex,
    this.placedAt,
    this.confirmedAt,
    this.packedAt,
    this.outForDeliveryAt,
    this.deliveredAt,
    this.eta,
    this.notes = '',
    required this.verificationCode,
    this.cancellationReason,
    this.cancelledBy,
    this.cancelledAt,
    this.refundStatus,
  });

  factory OrderModel.fromFirestore(String id, Map<String, dynamic> data) {
    return OrderModel(
      id: id,
      orderNumber: data['orderNumber']?.toString() ?? id,
      customerId: data['customerId']?.toString() ?? '',
      deliveryAddressId: data['deliveryAddressId']?.toString() ?? '',
      subtotal: _parseDouble(data['subtotal']),
      deliveryFee: _parseDouble(data['deliveryFee']),
      totalPrice: _parseDouble(data['totalPrice']),
      paymentMethod: data['paymentMethod']?.toString() ?? 'COD',
      paymentStatus: data['paymentStatus']?.toString() ?? 'Pending',
      status: _normalizeStatus(data['status']?.toString() ?? 'pending'),
      statusIndex: _parseInt(data['statusIndex'], defaultValue: 1),
      placedAt: _parseDateTime(data['placedAt']),
      confirmedAt: _parseDateTime(data['packedAt'] ?? data['confirmedAt']),
      packedAt: _parseDateTime(data['packedAt']),
      outForDeliveryAt: _parseDateTime(data['outForDeliveryAt']),
      deliveredAt: _parseDateTime(data['deliveredAt']),
      eta: _parseDateTime(data['eta']),
      notes: data['notes']?.toString() ?? '',
      verificationCode: data['verificationCode']?.toString() ?? '',
      cancellationReason: data['cancellationReason']?.toString(),
      cancelledBy: data['cancelledBy']?.toString(),
      cancelledAt: _parseDateTime(data['cancelledAt']),
      refundStatus: data['refundStatus']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'orderNumber': orderNumber,
      'customerId': customerId,
      'deliveryAddressId': deliveryAddressId,
      'subtotal': subtotal,
      'deliveryFee': deliveryFee,
      'totalPrice': totalPrice,
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus,
      'status': status,
      'statusIndex': statusIndex,
      'placedAt': placedAt ?? FieldValue.serverTimestamp(),
      'confirmedAt': confirmedAt,
      'packedAt': packedAt,
      'outForDeliveryAt': outForDeliveryAt,
      'deliveredAt': deliveredAt,
      'eta': eta != null ? Timestamp.fromDate(eta!) : null,
      'notes': notes,
      'verificationCode': verificationCode,
      'cancellationReason': cancellationReason,
      'cancelledBy': cancelledBy,
      'cancelledAt': cancelledAt,
      'refundStatus': refundStatus,
    };
  }

  String get formattedPlacedAt {
    if (placedAt == null) return '';
    return DateFormat('dd MMM, hh:mm a').format(placedAt!);
  }

  OrderModel copyWith({
    String? id,
    String? orderNumber,
    String? customerId,
    String? deliveryAddressId,
    double? subtotal,
    double? deliveryFee,
    double? totalPrice,
    String? paymentMethod,
    String? paymentStatus,
    String? status,
    int? statusIndex,
    DateTime? placedAt,
    DateTime? confirmedAt,
    DateTime? packedAt,
    DateTime? outForDeliveryAt,
    DateTime? deliveredAt,
    DateTime? eta,
    String? notes,
    String? verificationCode,
    String? cancellationReason,
    String? cancelledBy,
    DateTime? cancelledAt,
    String? refundStatus,
  }) {
    return OrderModel(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      customerId: customerId ?? this.customerId,
      deliveryAddressId: deliveryAddressId ?? this.deliveryAddressId,
      subtotal: subtotal ?? this.subtotal,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      totalPrice: totalPrice ?? this.totalPrice,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      status: status ?? this.status,
      statusIndex: statusIndex ?? this.statusIndex,
      placedAt: placedAt ?? this.placedAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      packedAt: packedAt ?? this.packedAt,
      outForDeliveryAt: outForDeliveryAt ?? this.outForDeliveryAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      eta: eta ?? this.eta,
      notes: notes ?? this.notes,
      verificationCode: verificationCode ?? this.verificationCode,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      refundStatus: refundStatus ?? this.refundStatus,
    );
  }
}

DateTime? _parseDateTime(dynamic val) {
  if (val == null) return null;
  if (val is Timestamp) return val.toDate();
  if (val is DateTime) return val;
  return null;
}

String _normalizeStatus(String raw) {
  final status = raw.toLowerCase().trim();
  if (status == 'placed') return 'pending';
  if (status == 'out for delivery') return 'out_for_delivery';
  return status;
}

double _parseDouble(dynamic val) {
  if (val == null) return 0.0;
  if (val is num) return val.toDouble();
  if (val is String) {
    return double.tryParse(val) ?? 0.0;
  }
  return 0.0;
}

int _parseInt(dynamic val, {int defaultValue = 0}) {
  if (val == null) return defaultValue;
  if (val is num) return val.toInt();
  if (val is String) {
    return int.tryParse(val) ?? defaultValue;
  }
  return defaultValue;
}
