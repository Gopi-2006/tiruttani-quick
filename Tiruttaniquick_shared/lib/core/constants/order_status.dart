class OrderStatuses {
  static const pending = 'pending';
  static const confirmed = 'confirmed';
  static const packed = 'packed';
  static const outForDelivery = 'out_for_delivery';
  static const delivered = 'delivered';
  static const cancelled = 'cancelled';

  static int index(String status) {
    return switch (status) {
      pending => 1,
      confirmed => 2,
      packed => 3,
      outForDelivery => 4,
      delivered => 5,
      cancelled => 6,
      _ => 0,
    };
  }

  static List<String> customerSteps = const [
    pending,
    confirmed,
    packed,
    outForDelivery,
    delivered,
  ];

  static List<String> allStatuses = const [
    pending,
    confirmed,
    packed,
    outForDelivery,
    delivered,
    cancelled,
  ];
}
