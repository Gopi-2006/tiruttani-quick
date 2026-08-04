import 'package:cloud_firestore/cloud_firestore.dart';

class OfferModel {
  final String id;
  final String title;
  final String description;
  final String offerType; // e.g. Percentage Discount, Flat Discount, etc.
  final String discountType; // e.g. Percentage, Flat, BOGO, etc.
  final double discountValue;
  final String targetType; // e.g. Entire Store, Selected Products, Selected Categories, etc.
  final List<String> targetIds;
  final int priority;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final bool countdownEnabled;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const OfferModel({
    required this.id,
    required this.title,
    this.description = '',
    required this.offerType,
    required this.discountType,
    required this.discountValue,
    required this.targetType,
    required this.targetIds,
    this.priority = 0,
    required this.startDateTime,
    required this.endDateTime,
    this.countdownEnabled = false,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  bool get isCurrentlyActive {
    if (!isActive) return false;
    final now = DateTime.now();
    return now.isAfter(startDateTime) && now.isBefore(endDateTime);
  }

  factory OfferModel.fromFirestore(String id, Map<String, dynamic> data) {
    return OfferModel(
      id: id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      offerType: data['offerType'] as String? ?? 'Percentage Discount',
      discountType: data['discountType'] as String? ?? 'Percentage',
      discountValue: (data['discountValue'] as num?)?.toDouble() ?? 0.0,
      targetType: data['targetType'] as String? ?? 'Entire Store',
      targetIds: List<String>.from(data['targetIds'] ?? []),
      priority: data['priority'] as int? ?? 0,
      startDateTime: _parseDateTime(data['startDateTime']) ?? DateTime.now(),
      endDateTime: _parseDateTime(data['endDateTime']) ?? DateTime.now().add(const Duration(days: 1)),
      countdownEnabled: data['countdownEnabled'] as bool? ?? false,
      isActive: data['isActive'] as bool? ?? true,
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'offerType': offerType,
      'discountType': discountType,
      'discountValue': discountValue,
      'targetType': targetType,
      'targetIds': targetIds,
      'priority': priority,
      'startDateTime': Timestamp.fromDate(startDateTime),
      'endDateTime': Timestamp.fromDate(endDateTime),
      'countdownEnabled': countdownEnabled,
      'isActive': isActive,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : FieldValue.serverTimestamp(),
    };
  }

  OfferModel copyWith({
    String? id,
    String? title,
    String? description,
    String? offerType,
    String? discountType,
    double? discountValue,
    String? targetType,
    List<String>? targetIds,
    int? priority,
    DateTime? startDateTime,
    DateTime? endDateTime,
    bool? countdownEnabled,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OfferModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      offerType: offerType ?? this.offerType,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      targetType: targetType ?? this.targetType,
      targetIds: targetIds ?? this.targetIds,
      priority: priority ?? this.priority,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
      countdownEnabled: countdownEnabled ?? this.countdownEnabled,
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
