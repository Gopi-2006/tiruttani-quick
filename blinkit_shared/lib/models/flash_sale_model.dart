import 'package:cloud_firestore/cloud_firestore.dart';

class FlashSaleModel {
  final String id;
  final String title;
  final String description;
  final String discountType; // e.g. Percentage, Flat
  final double discountValue;
  final String targetType; // e.g. Selected Products, Selected Categories, etc.
  final List<String> targetIds;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FlashSaleModel({
    required this.id,
    required this.title,
    this.description = '',
    required this.discountType,
    required this.discountValue,
    required this.targetType,
    required this.targetIds,
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

  factory FlashSaleModel.fromFirestore(String id, Map<String, dynamic> data) {
    return FlashSaleModel(
      id: id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      discountType: data['discountType'] as String? ?? 'Percentage',
      discountValue: (data['discountValue'] as num?)?.toDouble() ?? 0.0,
      targetType: data['targetType'] as String? ?? 'Selected Products',
      targetIds: List<String>.from(data['targetIds'] ?? []),
      startDateTime: _parseDateTime(data['startDateTime']) ?? DateTime.now(),
      endDateTime: _parseDateTime(data['endDateTime']) ?? DateTime.now().add(const Duration(hours: 2)),
      isActive: data['isActive'] as bool? ?? true,
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'discountType': discountType,
      'discountValue': discountValue,
      'targetType': targetType,
      'targetIds': targetIds,
      'startDateTime': Timestamp.fromDate(startDateTime),
      'endDateTime': Timestamp.fromDate(endDateTime),
      'isActive': isActive,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : FieldValue.serverTimestamp(),
    };
  }

  FlashSaleModel copyWith({
    String? id,
    String? title,
    String? description,
    String? discountType,
    double? discountValue,
    String? targetType,
    List<String>? targetIds,
    DateTime? startDateTime,
    DateTime? endDateTime,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FlashSaleModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      targetType: targetType ?? this.targetType,
      targetIds: targetIds ?? this.targetIds,
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
