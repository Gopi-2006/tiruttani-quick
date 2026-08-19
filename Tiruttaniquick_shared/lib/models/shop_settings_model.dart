import 'package:cloud_firestore/cloud_firestore.dart';

class ShopSettingsModel {
  final bool deliveryAvailable;
  final String deliveryUnavailableMessage;
  final DateTime? updatedAt;
  final String? updatedBy;

  const ShopSettingsModel({
    this.deliveryAvailable = true,
    this.deliveryUnavailableMessage = 'Our shop delivery is temporarily unavailable. Please try again later.',
    this.updatedAt,
    this.updatedBy,
  });

  factory ShopSettingsModel.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) {
      return const ShopSettingsModel();
    }
    return ShopSettingsModel(
      deliveryAvailable: data['deliveryAvailable'] as bool? ?? true,
      deliveryUnavailableMessage: data['deliveryUnavailableMessage'] as String? ??
          'Our shop delivery is temporarily unavailable. Please try again later.',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      updatedBy: data['updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'deliveryAvailable': deliveryAvailable,
      'deliveryUnavailableMessage': deliveryUnavailableMessage,
      'updatedAt': FieldValue.serverTimestamp(),
      if (updatedBy != null) 'updatedBy': updatedBy,
    };
  }

  ShopSettingsModel copyWith({
    bool? deliveryAvailable,
    String? deliveryUnavailableMessage,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return ShopSettingsModel(
      deliveryAvailable: deliveryAvailable ?? this.deliveryAvailable,
      deliveryUnavailableMessage: deliveryUnavailableMessage ?? this.deliveryUnavailableMessage,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}
