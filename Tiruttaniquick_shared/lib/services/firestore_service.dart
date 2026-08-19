import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_roles.dart';
import '../core/constants/order_status.dart';
import '../models/address_model.dart';
import '../models/cart_item_model.dart';
import '../models/category_model.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import '../models/banner_model.dart';
import '../models/offer_model.dart';
import '../models/flash_sale_model.dart';
import '../models/coupon_model.dart';
import '../models/shop_settings_model.dart';
import 'product_search_engine.dart';

class FirestoreService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  FirestoreService() {
    try {
      _db.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (_) {
      // Ignore if settings were already configured elsewhere
    }
  }

  Stream<List<CategoryModel>> categoriesStream() {
    return _db
        .collection('categories')
        .orderBy('sortOrder')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => CategoryModel.fromFirestore(doc.id, doc.data()))
          .toList();
    });
  }

  /// Fetches product list once without real-time stream subscription.
  Future<List<ProductModel>> fetchProducts({
    bool includeInactive = false,
    int limit = 200,
  }) async {
    Query<Map<String, dynamic>> query = _db.collection('products');
    if (!includeInactive) {
      query = query.where('isActive', isEqualTo: true);
    }

    final snapshot = await query.limit(limit).get();
    final products = snapshot.docs
        .map((doc) => ProductModel.fromFirestore(doc.id, doc.data()))
        .toList();

    products.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return products;
  }

  Stream<List<ProductModel>> productsStream({
    String? categoryId,
    String? searchQuery,
    bool includeInactive = false,
    int limit = 100,
  }) {
    final normalizedQuery = searchQuery?.trim() ?? '';

    Query<Map<String, dynamic>> query = _db.collection('products');
    if (!includeInactive) {
      query = query.where('isActive', isEqualTo: true);
    }
    if (categoryId != null && categoryId.isNotEmpty) {
      query = query.where('categoryId', isEqualTo: categoryId);
    }

    return query
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final products = snapshot.docs
          .map((doc) => ProductModel.fromFirestore(doc.id, doc.data()))
          .toList();

      final filtered = ProductSearchEngine.filterProducts(
        products: products,
        rawQuery: normalizedQuery,
      );

      final resultList = List<ProductModel>.from(filtered);
      resultList.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return resultList;
    });
  }

  Stream<List<ProductModel>> featuredProductsStream({int limit = 12}) {
    return _db
        .collection('products')
        .where('isActive', isEqualTo: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => ProductModel.fromFirestore(doc.id, doc.data()))
          .toList();
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return list;
    });
  }

  Stream<List<Map<String, dynamic>>> promotionsStream() {
    return _db
        .collection('promotions')
        .snapshots()
        .map((snapshot) {
      final promotions = snapshot.docs
          .map((doc) => doc.data())
          .where((promotion) => promotion['isActive'] == true)
          .toList();
      promotions.sort((a, b) {
        final orderA = a['sortOrder'] as int? ?? 999;
        final orderB = b['sortOrder'] as int? ?? 999;
        return orderA.compareTo(orderB);
      });
      return promotions;
    });
  }

  Stream<List<CartItemModel>> cartItemsStream(String userId) {
    return _db
        .collection('cart_items')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CartItemModel.fromFirestore(doc.id, doc.data()))
            .toList());
  }

  Stream<List<AddressModel>> addressesStream(String userId) {
    return _db
        .collection('addresses')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final addresses = snapshot.docs
          .map((doc) => AddressModel.fromFirestore(doc.id, doc.data()))
          .toList();
      addresses.sort((a, b) {
        final aDefault = a.isDefault ? 1 : 0;
        final bDefault = b.isDefault ? 1 : 0;
        return bDefault.compareTo(aDefault);
      });
      return addresses;
    });
  }

  Stream<List<OrderModel>> userOrdersStream(String userId, {int limit = 50}) {
    return _db
        .collection('orders')
        .where('customerId', isEqualTo: userId)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final orders = snapshot.docs
          .map((doc) => OrderModel.fromFirestore(doc.id, doc.data()))
          .toList();
      orders.sort((a, b) {
        final aTime = a.placedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.placedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      return orders;
    });
  }

  Stream<List<OrderModel>> adminOrdersStream({int limit = 200}) {
    return _db
        .collection('orders')
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final orders = snapshot.docs
          .map((doc) => OrderModel.fromFirestore(doc.id, doc.data()))
          .toList();
      orders.sort((a, b) {
        final aTime = a.placedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.placedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      return orders;
    });
  }

  Stream<List<Map<String, dynamic>>> adminsStream() {
    return _db
        .collection('users')
        .where('role', isEqualTo: AppRoles.admin)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
  }

  Future<List<Map<String, dynamic>>> getAdmins() async {
    final snapshot = await _db.collection('users').where('role', isEqualTo: AppRoles.admin).get();
    return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  Future<void> createNotification({
    required String userId,
    required String title,
    required String body,
    String? orderId,
  }) async {
    await _db.collection('notifications').add({
      'userId': userId,
      'title': title,
      'body': body,
      'orderId': orderId,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<Map<String, dynamic>>> notificationsStream(String userId, {int limit = 30}) {
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      list.sort((a, b) {
        final aTime = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      return list;
    });
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    await _db.collection('notifications').doc(notificationId).update({
      'isRead': true,
    });
  }

  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
    Map<String, dynamic> extra = const {},
  }) async {
    await _db.collection('orders').doc(orderId).update({
      'status': status,
      'statusIndex': OrderStatuses.index(status),
      ...extra,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addProduct(ProductModel product) async {
    await _db.collection('products').add(product.toMap());
  }

  Future<void> updateProduct(ProductModel product) async {
    await _db.collection('products').doc(product.id).update(product.toMap());
  }

  Future<void> deleteProduct(String productId) async {
    await _db.collection('products').doc(productId).delete();
  }

  Future<void> toggleProductActive(String productId, bool isActive) async {
    await _db.collection('products').doc(productId).update({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<ProductModel> productStream(String productId) {
    return _db.collection('products').doc(productId).snapshots().map((doc) {
      return ProductModel.fromFirestore(doc.id, doc.data() ?? {});
    });
  }

  Future<void> cancelOrder({
    required String orderId,
    required String customerId,
    required String reason,
    required String cancelledBy,
  }) async {
    final orderRef = _db.collection('orders').doc(orderId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(orderRef);
      if (!snapshot.exists) {
        throw Exception('Order does not exist');
      }

      final data = snapshot.data() as Map<String, dynamic>;
      final dbCustomerId = data['customerId'] as String?;
      final currentStatus = data['status'] as String? ?? '';

      // Security check: Only the customer who placed the order can cancel it (if cancelled by customer)
      if (cancelledBy == 'Customer' && dbCustomerId != customerId) {
        throw Exception('Unauthorized to cancel this order');
      }

      // Validate order status: Allow cancellation only before 'out_for_delivery'
      if (currentStatus == OrderStatuses.outForDelivery ||
          currentStatus == OrderStatuses.delivered ||
          currentStatus == OrderStatuses.cancelled) {
        throw Exception('Order cannot be cancelled in its current status: $currentStatus');
      }

      final paymentMethod = data['paymentMethod'] as String? ?? 'COD';
      final isOnlinePayment = paymentMethod != 'COD';

      final Map<String, dynamic> updates = {
        'status': OrderStatuses.cancelled,
        'statusIndex': OrderStatuses.index(OrderStatuses.cancelled),
        'cancellationReason': reason,
        'cancelledBy': cancelledBy,
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (isOnlinePayment) {
        updates['refundStatus'] = 'Refund Pending';
      }

      transaction.update(orderRef, updates);
    });
  }

  Future<void> updateRefundStatus({
    required String orderId,
    required String refundStatus,
  }) async {
    await _db.collection('orders').doc(orderId).update({
      'refundStatus': refundStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// ⚠️ DANGEROUS — ADMIN DEV TOOL ONLY. Deletes ALL orders and their sub-collections.
  /// Only accessible to admin users. Think twice before calling this.
  Future<void> deleteAllOrders() async {
    final querySnapshot = await _db.collection('orders').get();
    for (final doc in querySnapshot.docs) {
      final itemsSnapshot = await doc.reference.collection('order_items').get();
      for (final itemDoc in itemsSnapshot.docs) {
        await itemDoc.reference.delete();
      }
      await doc.reference.delete();
    }
  }

  /// ⚠️ DANGEROUS — ADMIN DEV TOOL ONLY. Deletes ALL products from Firestore.
  /// Only accessible to admin users. Think twice before calling this.
  Future<void> deleteAllProducts() async {
    final querySnapshot = await _db.collection('products').get();
    for (final doc in querySnapshot.docs) {
      await doc.reference.delete();
    }
  }

  // -------------------------------------------------------------
  // PROMOTION BANNERS
  // -------------------------------------------------------------
  Stream<List<BannerModel>> bannersStream({bool includeInactive = false}) {
    return _db
        .collection('banners')
        .orderBy('displayOrder')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => BannerModel.fromFirestore(doc.id, doc.data()))
          .where((banner) => includeInactive || banner.isActive)
          .toList();
    });
  }

  Future<void> addBanner(BannerModel banner) async {
    await _db.collection('banners').add(banner.toMap());
  }

  Future<void> updateBanner(BannerModel banner) async {
    await _db.collection('banners').doc(banner.id).update(banner.toMap());
  }

  Future<void> deleteBanner(String bannerId) async {
    await _db.collection('banners').doc(bannerId).delete();
  }

  Future<void> toggleBannerActive(String bannerId, bool isActive) async {
    await _db.collection('banners').doc(bannerId).update({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateBannersOrder(List<BannerModel> banners) async {
    final batch = _db.batch();
    for (int i = 0; i < banners.length; i++) {
      final banner = banners[i];
      final docRef = _db.collection('banners').doc(banner.id);
      batch.update(docRef, {
        'displayOrder': i,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  // -------------------------------------------------------------
  // OFFERS
  // -------------------------------------------------------------
  Stream<List<OfferModel>> offersStream({bool includeInactive = false}) {
    return _db.collection('offers').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => OfferModel.fromFirestore(doc.id, doc.data()))
          .where((offer) => includeInactive || offer.isActive)
          .toList();
    });
  }

  Future<void> addOffer(OfferModel offer) async {
    await _db.collection('offers').add(offer.toMap());
  }

  Future<void> updateOffer(OfferModel offer) async {
    await _db.collection('offers').doc(offer.id).update(offer.toMap());
  }

  Future<void> deleteOffer(String offerId) async {
    await _db.collection('offers').doc(offerId).delete();
  }

  Future<void> toggleOfferActive(String offerId, bool isActive) async {
    await _db.collection('offers').doc(offerId).update({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // -------------------------------------------------------------
  // FLASH SALES
  // -------------------------------------------------------------
  Stream<List<FlashSaleModel>> flashSalesStream({bool includeInactive = false}) {
    return _db.collection('flash_sales').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => FlashSaleModel.fromFirestore(doc.id, doc.data()))
          .where((sale) => includeInactive || sale.isActive)
          .toList();
    });
  }

  Future<void> addFlashSale(FlashSaleModel sale) async {
    await _db.collection('flash_sales').add(sale.toMap());
  }

  Future<void> updateFlashSale(FlashSaleModel sale) async {
    await _db.collection('flash_sales').doc(sale.id).update(sale.toMap());
  }

  Future<void> deleteFlashSale(String saleId) async {
    await _db.collection('flash_sales').doc(saleId).delete();
  }

  Future<void> toggleFlashSaleActive(String saleId, bool isActive) async {
    await _db.collection('flash_sales').doc(saleId).update({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // -------------------------------------------------------------
  // COUPONS
  // -------------------------------------------------------------
  Stream<List<CouponModel>> couponsStream({bool includeInactive = false}) {
    return _db.collection('coupons').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => CouponModel.fromFirestore(doc.id, doc.data()))
          .where((coupon) => includeInactive || coupon.isActive)
          .toList();
    });
  }

  Future<void> addCoupon(CouponModel coupon) async {
    await _db.collection('coupons').add(coupon.toMap());
  }

  Future<void> updateCoupon(CouponModel coupon) async {
    await _db.collection('coupons').doc(coupon.id).update(coupon.toMap());
  }

  Future<void> deleteCoupon(String couponId) async {
    await _db.collection('coupons').doc(couponId).delete();
  }

  Future<void> toggleCouponActive(String couponId, bool isActive) async {
    await _db.collection('coupons').doc(couponId).update({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // -------------------------------------------------------------
  // BANNER ANALYTICS
  // -------------------------------------------------------------
  Future<void> recordBannerView(String bannerId) async {
    final docRef = _db.collection('banner_analytics').doc(bannerId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) {
        transaction.set(docRef, {
          'views': 1,
          'clicks': 0,
          'conversions': 0,
          'productsSold': 0,
          'revenue': 0.0,
          'discountGiven': 0.0,
        });
      } else {
        transaction.update(docRef, {
          'views': FieldValue.increment(1),
        });
      }
    });
  }

  Future<void> recordBannerClick(String bannerId) async {
    final docRef = _db.collection('banner_analytics').doc(bannerId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) {
        transaction.set(docRef, {
          'views': 0,
          'clicks': 1,
          'conversions': 0,
          'productsSold': 0,
          'revenue': 0.0,
          'discountGiven': 0.0,
        });
      } else {
        transaction.update(docRef, {
          'clicks': FieldValue.increment(1),
        });
      }
    });
  }

  Future<void> recordBannerConversion(
    String bannerId, {
    required int productsSold,
    required double revenue,
    required double discountGiven,
  }) async {
    final docRef = _db.collection('banner_analytics').doc(bannerId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) {
        transaction.set(docRef, {
          'views': 0,
          'clicks': 0,
          'conversions': 1,
          'productsSold': productsSold,
          'revenue': revenue,
          'discountGiven': discountGiven,
        });
      } else {
        transaction.update(docRef, {
          'conversions': FieldValue.increment(1),
          'productsSold': FieldValue.increment(productsSold),
          'revenue': FieldValue.increment(revenue),
          'discountGiven': FieldValue.increment(discountGiven),
        });
      }
    });
  }

  Stream<Map<String, dynamic>> bannerAnalyticsStream(String bannerId) {
    return _db
        .collection('banner_analytics')
        .doc(bannerId)
        .snapshots()
        .map((doc) => {'id': doc.id, ...doc.data() ?? {}});
  }

  Stream<List<Map<String, dynamic>>> allBannerAnalyticsStream() {
    return _db.collection('banner_analytics').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    });
  }

  /// Real-time stream of central shop settings (delivery availability, messages)
  Stream<ShopSettingsModel> shopSettingsStream() {
    return _db.collection('shop_settings').doc('config').snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        return const ShopSettingsModel();
      }
      return ShopSettingsModel.fromFirestore(snap.data());
    });
  }

  /// Fresh direct fetch of central shop settings (used for checkout verification)
  Future<ShopSettingsModel> getShopSettings() async {
    try {
      final snap = await _db
          .collection('shop_settings')
          .doc('config')
          .get()
          .timeout(const Duration(seconds: 5));
      if (!snap.exists || snap.data() == null) {
        return const ShopSettingsModel();
      }
      return ShopSettingsModel.fromFirestore(snap.data());
    } catch (_) {
      rethrow;
    }
  }

  /// Admin method to toggle delivery availability and set optional custom closed message
  Future<void> updateDeliveryAvailability({
    required bool deliveryAvailable,
    String? unavailableMessage,
    required String adminUid,
  }) async {
    await _db.collection('shop_settings').doc('config').set({
      'deliveryAvailable': deliveryAvailable,
      if (unavailableMessage != null && unavailableMessage.isNotEmpty)
        'deliveryUnavailableMessage': unavailableMessage,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminUid,
    }, SetOptions(merge: true));
  }
}
