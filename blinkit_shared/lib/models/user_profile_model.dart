import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfileModel {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String role;
  final String? fcmToken;
  final DateTime? createdAt;

  const UserProfileModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    required this.role,
    this.fcmToken,
    this.createdAt,
  });

  factory UserProfileModel.fromFirestore(String id, Map<String, dynamic> data) {
    return UserProfileModel(
      id: id,
      name: data['name'] as String? ?? 'Customer',
      phone: data['phone'] as String? ?? '',
      email: data['email'] as String?,
      role: data['role'] as String? ?? 'Customer',
      fcmToken: data['fcmToken'] as String?,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : (data['createdAt'] is DateTime ? data['createdAt'] as DateTime : null),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
      'fcmToken': fcmToken,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    };
  }
}
