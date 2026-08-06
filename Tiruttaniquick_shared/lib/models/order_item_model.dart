class OrderItemModel {
  final String id;
  final String orderId;
  final String productId;
  final String productName;
  final double unitPrice;
  final int quantity;
  final String variantId;
  final String variantName;
  final String selectedWeight;
  final double purchasePrice;

  const OrderItemModel({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    this.variantId = '',
    this.variantName = '',
    this.selectedWeight = '',
    this.purchasePrice = 0.0,
  });

  factory OrderItemModel.fromFirestore(String id, Map<String, dynamic> data) {
    return OrderItemModel(
      id: id,
      orderId: data['orderId'] as String? ?? '',
      productId: data['productId'] as String? ?? '',
      productName: data['productName'] as String? ?? '',
      unitPrice: (data['unitPrice'] as num?)?.toDouble() ?? 0,
      quantity: data['quantity'] as int? ?? 0,
      variantId: data['variantId'] as String? ?? '',
      variantName: data['variantName'] as String? ?? '',
      selectedWeight: data['selectedWeight'] as String? ?? '',
      purchasePrice: (data['purchasePrice'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'orderId': orderId,
      'productId': productId,
      'productName': productName,
      'unitPrice': unitPrice,
      'quantity': quantity,
      'variantId': variantId,
      'variantName': variantName,
      'selectedWeight': selectedWeight,
      'purchasePrice': purchasePrice,
    };
  }

  double get subtotal => quantity * unitPrice;
}
