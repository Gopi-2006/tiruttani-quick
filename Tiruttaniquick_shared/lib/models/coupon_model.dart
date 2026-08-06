import 'package:cloud_firestore/cloud_firestore.dart';

class CouponModel {
  final String id;
  final String code; // Coupon code, e.g. "TIRUTTANI20"
  final String title;
  final String description;
  final String discountType; // e.g. Percentage, Flat
  final double discountValue;
  final double minOrderValue;
  final double maxDiscount;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CouponModel({
    required this.id,
    required this.code,
    required this.title,
    this.description = '',
    required this.discountType,
    required this.discountValue,
    this.minOrderValue = 0.0,
    this.maxDiscount = 9999.0,
    required this.startDateTime,
    required this.endDateTime,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  bool get isCurrentlyActive {
    if (!isActive) return false;
    final now = DateTime.now();
    return now.isAfter(startDateTime) && now.isBefore(endDateTime);
  }

  factory CouponModel.fromFirestore(String id, Map<String, dynamic> data) {
    return CouponModel(
      id: id,
      code: data['code'] as String? ?? '',
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      discountType: data['discountType'] as String? ?? 'Percentage',
      discountValue: (data['discountValue'] as num?)?.toDouble() ?? 0.0,
      minOrderValue: (data['minOrderValue'] as num?)?.toDouble() ?? 0.0,
      maxDiscount: (data['maxDiscount'] as num?)?.toDouble() ?? 9999.0,
      startDateTime: _parseDateTime(data['startDateTime']) ?? DateTime.now(),
      endDateTime: _parseDateTime(data['endDateTime']) ?? DateTime.now().add(const Duration(days: 7)),
      isActive: data['isActive'] as bool? ?? true,
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'title': title,
      'description': description,
      'discountType': discountType,
      'discountValue': discountValue,
      'minOrderValue': minOrderValue,
      'maxDiscount': maxDiscount,
      'startDateTime': Timestamp.fromDate(startDateTime),
      'endDateTime': Timestamp.fromDate(endDateTime),
      'isActive': isActive,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : FieldValue.serverTimestamp(),
    };
  }

  CouponModel copyWith({
    String? id,
    String? code,
    String? title,
    String? description,
    String? discountType,
    double? discountValue,
    double? minOrderValue,
    double? maxDiscount,
    DateTime? startDateTime,
    DateTime? endDateTime,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CouponModel(
      id: id ?? this.id,
      code: code ?? this.code,
      title: title ?? this.title,
      description: description ?? this.description,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      minOrderValue: minOrderValue ?? this.minOrderValue,
      maxDiscount: maxDiscount ?? this.maxDiscount,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _parseDateTime(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    return null;
  }
}
