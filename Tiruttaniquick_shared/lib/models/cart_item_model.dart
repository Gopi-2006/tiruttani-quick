class CartItemModel {
  final String id;
  final String userId;
  final String productId;
  final int quantity;
  final double unitPrice;
  final String variantId;
  final String variantName;
  final String selectedWeight;

  const CartItemModel({
    required this.id,
    required this.userId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.variantId = '',
    this.variantName = '',
    this.selectedWeight = '',
  });

  factory CartItemModel.fromFirestore(String id, Map<String, dynamic> data) {
    return CartItemModel(
      id: id,
      userId: data['userId'] as String? ?? '',
      productId: data['productId'] as String? ?? '',
      quantity: data['quantity'] as int? ?? 0,
      unitPrice: (data['unitPrice'] as num?)?.toDouble() ?? 0,
      variantId: data['variantId'] as String? ?? '',
      variantName: data['variantName'] as String? ?? '',
      selectedWeight: data['selectedWeight'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'productId': productId,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'variantId': variantId,
      'variantName': variantName,
      'selectedWeight': selectedWeight,
    };
  }

  double get subtotal => quantity * unitPrice;
}
