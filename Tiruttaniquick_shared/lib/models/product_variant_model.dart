class ProductVariantModel {
  final String id;
  final String name; // e.g. "500 g", "1 kg"
  final String size; // e.g. "500", "1"
  final String unitType; // e.g. "g", "kg", "ml", "L", "Pieces", "Packets", "Boxes", "Custom"
  final double mrp;
  final double price; // Selling price
  final double purchasePrice;
  final double discount; // Discount percentage, e.g. 10 for 10%
  final int stockQuantity;
  final int lowStockThreshold;
  final String status; // "Available", "Out of Stock", "Disabled"
  final String barcode;
  final String sku;
  final String imageUrl;
  final String blurHash;

  // Transient promotion fields
  final String? appliedOfferId;
  final String? appliedOfferTitle;
  final DateTime? appliedOfferEndsAt;
  final bool? appliedOfferCountdownEnabled;
  final String? appliedOfferType;

  const ProductVariantModel({
    required this.id,
    required this.name,
    required this.size,
    required this.unitType,
    required this.mrp,
    required this.price,
    required this.purchasePrice,
    required this.discount,
    required this.stockQuantity,
    required this.lowStockThreshold,
    required this.status,
    required this.barcode,
    required this.sku,
    this.imageUrl = '',
    this.blurHash = '',
    this.appliedOfferId,
    this.appliedOfferTitle,
    this.appliedOfferEndsAt,
    this.appliedOfferCountdownEnabled,
    this.appliedOfferType,
  });

  bool get isOutOfStock => stockQuantity <= 0 || status == 'Out of Stock';
  bool get isLowStock => stockQuantity > 0 && stockQuantity <= lowStockThreshold;
  bool get isDisabled => status == 'Disabled';

  factory ProductVariantModel.fromMap(Map<String, dynamic> map) {
    final priceVal = (map['price'] as num?)?.toDouble() ?? (map['sellingPrice'] as num?)?.toDouble() ?? 0.0;
    final mrpVal = (map['mrp'] as num?)?.toDouble() ?? priceVal;
    
    // Auto-calculate discount if not set or zero
    double discountVal = (map['discount'] as num?)?.toDouble() ?? 0.0;
    if (discountVal == 0.0 && mrpVal > priceVal) {
      discountVal = (((mrpVal - priceVal) / mrpVal) * 100).roundToDouble();
    }

    return ProductVariantModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      size: map['size']?.toString() ?? '',
      unitType: map['unitType'] as String? ?? '',
      mrp: mrpVal,
      price: priceVal,
      purchasePrice: (map['purchasePrice'] as num?)?.toDouble() ?? 0.0,
      discount: discountVal,
      stockQuantity: map['stockQuantity'] as int? ?? 0,
      lowStockThreshold: map['lowStockThreshold'] as int? ?? 5,
      status: map['status'] as String? ?? 'Available',
      barcode: map['barcode'] as String? ?? '',
      sku: map['sku'] as String? ?? '',
      imageUrl: map['imageUrl'] as String? ?? '',
      blurHash: map['blurHash'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'size': size,
      'unitType': unitType,
      'mrp': mrp,
      'price': price,
      'sellingPrice': price,
      'purchasePrice': purchasePrice,
      'discount': discount,
      'stockQuantity': stockQuantity,
      'lowStockThreshold': lowStockThreshold,
      'status': status,
      'barcode': barcode,
      'sku': sku,
      'imageUrl': imageUrl,
      'blurHash': blurHash,
    };
  }

  ProductVariantModel copyWith({
    String? id,
    String? name,
    String? size,
    String? unitType,
    double? mrp,
    double? price,
    double? purchasePrice,
    double? discount,
    int? stockQuantity,
    int? lowStockThreshold,
    String? status,
    String? barcode,
    String? sku,
    String? imageUrl,
    String? blurHash,
    String? appliedOfferId,
    String? appliedOfferTitle,
    DateTime? appliedOfferEndsAt,
    bool? appliedOfferCountdownEnabled,
    String? appliedOfferType,
  }) {
    return ProductVariantModel(
      id: id ?? this.id,
      name: name ?? this.name,
      size: size ?? this.size,
      unitType: unitType ?? this.unitType,
      mrp: mrp ?? this.mrp,
      price: price ?? this.price,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      discount: discount ?? this.discount,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      status: status ?? this.status,
      barcode: barcode ?? this.barcode,
      sku: sku ?? this.sku,
      imageUrl: imageUrl ?? this.imageUrl,
      blurHash: blurHash ?? this.blurHash,
      appliedOfferId: appliedOfferId ?? this.appliedOfferId,
      appliedOfferTitle: appliedOfferTitle ?? this.appliedOfferTitle,
      appliedOfferEndsAt: appliedOfferEndsAt ?? this.appliedOfferEndsAt,
      appliedOfferCountdownEnabled: appliedOfferCountdownEnabled ?? this.appliedOfferCountdownEnabled,
      appliedOfferType: appliedOfferType ?? this.appliedOfferType,
    );
  }
}
