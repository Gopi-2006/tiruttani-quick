class OrderStatuses {
  // Canonical Statuses
  static const orderPlaced = 'ORDER_PLACED';
  static const accepted = 'ACCEPTED';
  static const packing = 'PACKING';
  static const outForDelivery = 'OUT_FOR_DELIVERY';
  static const delivered = 'DELIVERED';
  static const cancelled = 'CANCELLED';

  // Legacy mappings for backward compatibility
  static const pending = orderPlaced;
  static const confirmed = accepted;
  static const packed = packing;

  /// Normalizes any status string (legacy, lowercase, or whitespace) to the canonical status
  static String normalize(String? raw) {
    if (raw == null || raw.trim().isEmpty) return orderPlaced;
    final s = raw.trim().toUpperCase().replaceAll(' ', '_').replaceAll('-', '_');
    if (s == 'PENDING' || s == 'PLACED' || s == 'ORDER_PLACED') return orderPlaced;
    if (s == 'CONFIRMED' || s == 'ACCEPT' || s == 'ACCEPTED') return accepted;
    if (s == 'PACK' || s == 'PACKED' || s == 'PACKING') return packing;
    if (s == 'OUT_FOR_DELIVERY' || s == 'OUTFORDELIVERY' || s == 'ON_THE_WAY') return outForDelivery;
    if (s == 'DELIVER' || s == 'DELIVERED') return delivered;
    if (s == 'CANCEL' || s == 'CANCELLED' || s == 'CANCELED') return cancelled;
    return s;
  }

  /// Maps canonical or raw status to a clean human-readable label
  static String display(String? status) {
    final norm = normalize(status);
    return switch (norm) {
      orderPlaced => 'Order Placed',
      accepted => 'Accepted',
      packing => 'Packing',
      outForDelivery => 'Out for Delivery',
      delivered => 'Delivered',
      cancelled => 'Cancelled',
      _ => status ?? '',
    };
  }

  static int index(String? status) {
    final norm = normalize(status);
    return switch (norm) {
      orderPlaced => 1,
      accepted => 2,
      packing => 3,
      outForDelivery => 4,
      delivered => 5,
      cancelled => 6,
      _ => 0,
    };
  }

  static List<String> customerSteps = const [
    orderPlaced,
    accepted,
    packing,
    outForDelivery,
    delivered,
  ];

  static List<String> allStatuses = const [
    orderPlaced,
    accepted,
    packing,
    outForDelivery,
    delivered,
    cancelled,
  ];
}
