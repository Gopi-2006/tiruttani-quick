import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service responsible for dispatching order status push notifications
/// to customer devices via the Cloudflare Notification Worker (FCM HTTP v1).
class NotificationSenderService {
  NotificationSenderService._();
  static final NotificationSenderService instance = NotificationSenderService._();

  /// Default Cloudflare Worker URL.
  String workerEndpoint = 'https://tiruttani-quick-notification-worker.tirttani-quick.workers.dev';

  /// Sets or updates the active Cloudflare Worker endpoint URL.
  void setWorkerEndpoint(String url) {
    if (url.isNotEmpty) {
      workerEndpoint = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    }
  }

  /// Sends an order status push notification to the customer associated with [customerId].
  ///
  /// This method:
  /// 1. Queries the customer's active FCM registration token(s) from Firestore.
  /// 2. Retrieves the current Admin's Firebase Auth ID token for secure authorization.
  /// 3. Dispatches the notification payload to the Cloudflare Worker.
  /// 4. Handles invalid/expired tokens by pruning them from Firestore.
  ///
  /// Returns `true` if dispatch succeeded or if skipped gracefully. Never throws.
  Future<bool> sendOrderStatusNotification({
    required String orderId,
    required String status,
    required String customerId,
    String? orderNumber,
  }) async {
    if (orderId.isEmpty || status.isEmpty || customerId.isEmpty) {
      debugPrint('[NotificationSenderService] Missing required parameters; skipping push.');
      return false;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('[NotificationSenderService] No authenticated admin user; skipping push.');
        return false;
      }

      // 1. Fetch customer's active FCM device tokens from Firestore
      final tokens = await _getCustomerFcmTokens(customerId);
      if (tokens.isEmpty) {
        debugPrint('[NotificationSenderService] No FCM device tokens found for customer: $customerId');
        return true;
      }

      // 2. Get Admin's Firebase Auth ID Token for Bearer authentication
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        debugPrint('[NotificationSenderService] Failed to obtain Firebase ID token for admin.');
        return false;
      }

      // 3. Make authenticated request to Cloudflare Worker
      final uri = Uri.parse('$workerEndpoint/send-order-notification');
      final payload = {
        'orderId': orderId,
        'orderNumber': orderNumber ?? (orderId.length > 8 ? orderId.substring(0, 8) : orderId),
        'customerId': customerId,
        'status': status,
        'tokens': tokens,
      };

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('[NotificationSenderService] Push notification sent successfully for order $orderId ($status)');
        
        // Check for any invalid tokens returned to clean up
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final invalidTokens = (data['invalidTokens'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
          if (invalidTokens.isNotEmpty) {
            await _pruneInvalidTokens(customerId, invalidTokens);
          }
        } catch (_) {}

        return true;
      } else {
        debugPrint('[NotificationSenderService] Worker returned HTTP ${response.statusCode}: ${response.body}');
        return false;
      }
    } catch (e, st) {
      debugPrint('[NotificationSenderService] Failed to send push notification: $e\n$st');
      return false;
    }
  }

  /// Queries all registered FCM tokens for the given customer ID.
  Future<List<String>> _getCustomerFcmTokens(String customerId) async {
    final tokenSet = <String>{};

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(customerId).get();
      if (userDoc.exists) {
        final primaryToken = userDoc.data()?['fcmToken'] as String?;
        if (primaryToken != null && primaryToken.trim().isNotEmpty) {
          tokenSet.add(primaryToken.trim());
        }
      }

      // Also query multi-device subcollection
      final subSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(customerId)
          .collection('fcmTokens')
          .limit(10)
          .get();

      for (final doc in subSnap.docs) {
        final token = doc.data()['token'] as String? ?? doc.id;
        if (token.trim().isNotEmpty) {
          tokenSet.add(token.trim());
        }
      }
    } catch (e) {
      debugPrint('[NotificationSenderService] Error querying customer FCM tokens: $e');
    }

    return tokenSet.toList();
  }

  /// Prunes invalid/unregistered tokens from the customer's Firestore profile.
  Future<void> _pruneInvalidTokens(String customerId, List<String> invalidTokens) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final token in invalidTokens) {
      final subDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(customerId)
          .collection('fcmTokens')
          .doc(token);
      batch.delete(subDoc);
    }
    await batch.commit().catchError((e) {
      debugPrint('[NotificationSenderService] Error pruning invalid tokens: $e');
    });
  }

  /// Dispatches a high-priority push notification to all Admin devices when a customer places a new order.
  /// Uses the authenticated user's ID token and the Cloudflare Notification Worker.
  Future<bool> sendNewOrderNotificationToAdmins({
    required String orderId,
    required String orderNumber,
    required double totalAmount,
    String? customerName,
  }) async {
    if (orderId.isEmpty) {
      debugPrint('[NotificationSenderService] Missing orderId; skipping new order push.');
      return false;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('[NotificationSenderService] No authenticated user; skipping new order push.');
        return false;
      }

      // 1. Fetch all admin FCM device tokens from Firestore
      final adminTokens = await _getAllAdminFcmTokens();
      if (adminTokens.isEmpty) {
        debugPrint('[NotificationSenderService] No admin FCM device tokens found; skipping push.');
        return true;
      }

      // 2. Get caller's Firebase Auth ID Token for Bearer authentication
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        debugPrint('[NotificationSenderService] Failed to obtain Firebase ID token for new order push.');
        return false;
      }

      // 3. Make authenticated request to Cloudflare Worker
      final uri = Uri.parse('$workerEndpoint/send-admin-new-order-notification');
      final payload = {
        'orderId': orderId,
        'orderNumber': orderNumber,
        'totalAmount': totalAmount,
        'customerName': customerName ?? 'Customer',
        'tokens': adminTokens,
      };

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('[NotificationSenderService] [NEW ORDER NOTIFICATION] orderId = $orderId, adminTokenCount = ${adminTokens.length}, workerStatus = ${response.statusCode}');
        return true;
      } else {
        debugPrint('[NotificationSenderService] Worker returned HTTP ${response.statusCode} for new order: ${response.body}');
        return false;
      }
    } catch (e, st) {
      debugPrint('[NotificationSenderService] Failed to dispatch new order push: $e\n$st');
      return false;
    }
  }

  /// Queries all registered FCM tokens for all Admin accounts in Firestore.
  Future<List<String>> _getAllAdminFcmTokens() async {
    final tokenSet = <String>{};

    try {
      final adminDocs = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'Admin')
          .get();

      for (final doc in adminDocs.docs) {
        final data = doc.data();
        final primaryToken = data['fcmToken'] as String?;
        if (primaryToken != null && primaryToken.trim().isNotEmpty) {
          tokenSet.add(primaryToken.trim());
        }

        try {
          final subSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(doc.id)
              .collection('fcmTokens')
              .limit(10)
              .get();

          for (final subDoc in subSnap.docs) {
            final token = subDoc.data()['token'] as String? ?? subDoc.id;
            if (token.trim().isNotEmpty) {
              tokenSet.add(token.trim());
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[NotificationSenderService] Error querying admin FCM tokens: $e');
    }

    return tokenSet.toList();
  }
}
