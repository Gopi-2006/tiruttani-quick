import 'package:cloud_firestore/cloud_firestore.dart';

class BannerModel {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final String imageUrl;
  final String bannerType; // e.g. Offer Banner, Flash Sale, Festival Offer, etc.
  final String offerType; // e.g. Percentage Discount, Flat Discount, etc.
  final String discountType; // e.g. Percentage, Flat, BOGO, etc.
  final double discountValue;
  final String targetType; // e.g. Entire Store, Selected Products, etc.
  final List<String> targetIds;
  final int priority;
  final int displayOrder;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final bool countdownEnabled;
  final String actionType; // e.g. Open Product, Open Category, Open Brand, etc.
  final String actionTarget; // e.g. productId, categoryId, search query, external URL, etc.
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BannerModel({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.description = '',
    required this.imageUrl,
    required this.bannerType,
    required this.offerType,
    required this.discountType,
    required this.discountValue,
    required this.targetType,
    required this.targetIds,
    this.priority = 0,
    this.displayOrder = 0,
    required this.startDateTime,
    required this.endDateTime,
    this.countdownEnabled = false,
    required this.actionType,
    this.actionTarget = '',
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  bool get isCurrentlyActive {
    if (!isActive) return false;
    final now = DateTime.now();
    return now.isAfter(startDateTime) && now.isBefore(endDateTime);
  }

  factory BannerModel.fromFirestore(String id, Map<String, dynamic> data) {
    return BannerModel(
      id: id,
      title: data['title'] as String? ?? '',
      subtitle: data['subtitle'] as String? ?? '',
      description: data['description'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      bannerType: data['bannerType'] as String? ?? 'Custom Banner',
      offerType: data['offerType'] as String? ?? 'Percentage Discount',
      discountType: data['discountType'] as String? ?? 'Percentage',
      discountValue: (data['discountValue'] as num?)?.toDouble() ?? 0.0,
      targetType: data['targetType'] as String? ?? 'Entire Store',
      targetIds: List<String>.from(data['targetIds'] ?? []),
      priority: data['priority'] as int? ?? 0,
      displayOrder: data['displayOrder'] as int? ?? 0,
      startDateTime: _parseDateTime(data['startDateTime']) ?? DateTime.now(),
      endDateTime: _parseDateTime(data['endDateTime']) ?? DateTime.now().add(const Duration(days: 1)),
      countdownEnabled: data['countdownEnabled'] as bool? ?? false,
      actionType: data['actionType'] as String? ?? 'No Action',
      actionTarget: data['actionTarget'] as String? ?? '',
      isActive: data['isActive'] as bool? ?? true,
      createdAt: _parseDateTime(data['createdAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'subtitle': subtitle,
      'description': description,
      'imageUrl': imageUrl,
      'bannerType': bannerType,
      'offerType': offerType,
      'discountType': discountType,
      'discountValue': discountValue,
      'targetType': targetType,
      'targetIds': targetIds,
      'priority': priority,
      'displayOrder': displayOrder,
      'startDateTime': Timestamp.fromDate(startDateTime),
      'endDateTime': Timestamp.fromDate(endDateTime),
      'countdownEnabled': countdownEnabled,
      'actionType': actionType,
      'actionTarget': actionTarget,
      'isActive': isActive,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : FieldValue.serverTimestamp(),
    };
  }

  BannerModel copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? description,
    String? imageUrl,
    String? bannerType,
    String? offerType,
    String? discountType,
    double? discountValue,
    String? targetType,
    List<String>? targetIds,
    int? priority,
    int? displayOrder,
    DateTime? startDateTime,
    DateTime? endDateTime,
    bool? countdownEnabled,
    String? actionType,
    String? actionTarget,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BannerModel(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      bannerType: bannerType ?? this.bannerType,
      offerType: offerType ?? this.offerType,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      targetType: targetType ?? this.targetType,
      targetIds: targetIds ?? this.targetIds,
      priority: priority ?? this.priority,
      displayOrder: displayOrder ?? this.displayOrder,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
      countdownEnabled: countdownEnabled ?? this.countdownEnabled,
      actionType: actionType ?? this.actionType,
      actionTarget: actionTarget ?? this.actionTarget,
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
