class AddressModel {
  final String id;
  final String userId;
  final String label;
  final String fullAddress;
  final String landmark;
  final String city;
  final String state;
  final String pincode;
  final String phone;
  final bool isDefault;
  final double? latitude;
  final double? longitude;

  const AddressModel({
    required this.id,
    required this.userId,
    required this.label,
    required this.fullAddress,
    required this.landmark,
    required this.city,
    required this.state,
    required this.pincode,
    required this.phone,
    required this.isDefault,
    this.latitude,
    this.longitude,
  });

  factory AddressModel.fromFirestore(String id, Map<String, dynamic> data) {
    return AddressModel(
      id: id,
      userId: data['userId'] as String? ?? '',
      label: data['label'] as String? ?? 'Home',
      fullAddress: data['fullAddress'] as String? ?? '',
      landmark: data['landmark'] as String? ?? '',
      city: data['city'] as String? ?? 'Thiruttani',
      state: data['state'] as String? ?? 'Tamil Nadu',
      pincode: data['pincode'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      isDefault: data['isDefault'] as bool? ?? false,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'label': label,
      'fullAddress': fullAddress,
      'landmark': landmark,
      'city': city,
      'state': state,
      'pincode': pincode,
      'phone': phone,
      'isDefault': isDefault,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}
