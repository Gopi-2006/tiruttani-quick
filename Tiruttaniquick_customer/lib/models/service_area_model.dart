class ServiceAreaModel {
  final List<String> allowedPincodes;

  ServiceAreaModel({required this.allowedPincodes});

  factory ServiceAreaModel.fromMap(Map<String, dynamic> map) {
    final list = map['allowedPincodes'] as List<dynamic>? ?? [];
    return ServiceAreaModel(
      allowedPincodes: list.map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'allowedPincodes': allowedPincodes,
    };
  }
}
