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
  /// Sends an order status push notification to the customer associated with [customerId].
  Future<bool> sendOrderStatusNotification({
    required String orderId,
    required String status,
    required String customerId,
    String? orderNumber,
    String? deliveryOtp,
    String? deliveryPersonName,
    String? directToken,
  }) async {
    debugPrint('[FCM DIAGNOSTICS] sendOrderStatusNotification called: orderId=$orderId, status=$status, customerId=$customerId');
    if (orderId.isEmpty || status.isEmpty || customerId.isEmpty) {
      debugPrint('[FCM DIAGNOSTICS] Missing required parameters (orderId/status/customerId); skipping push.');
      return false;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('[FCM DIAGNOSTICS] No authenticated admin user found in FirebaseAuth; skipping push.');
        return false;
      }

      // 1. Fetch customer's active FCM device tokens with multiple fallback layers
      final tokens = await _getCustomerFcmTokens(
        customerId,
        orderId: orderId,
        directToken: directToken,
      );
      if (tokens.isEmpty) {
        debugPrint('[FCM DIAGNOSTICS] No registered FCM device tokens found in Firestore for customer: $customerId');
        return true;
      }

      final truncatedList = tokens.map((t) => t.length > 8 ? '...${t.substring(t.length - 8)}' : t).toList();
      debugPrint('[FCM DIAGNOSTICS] Retrieved ${tokens.length} token(s) for customer $customerId: $truncatedList');

      // 2. Get Admin's Firebase Auth ID Token for Bearer authentication
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        debugPrint('[FCM DIAGNOSTICS] Failed to obtain Firebase ID token for admin.');
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
        if (deliveryOtp != null && deliveryOtp.isNotEmpty) 'deliveryOtp': deliveryOtp,
        if (deliveryPersonName != null && deliveryPersonName.isNotEmpty) 'deliveryPersonName': deliveryPersonName,
      };

      debugPrint('[FCM DIAGNOSTICS] Dispatching request to Cloudflare Worker: $uri');
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
        // Parse the Worker response to confirm actual FCM delivery
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final delivered = (data['delivered'] as num?)?.toInt() ?? -1;
          final failed = (data['failed'] as num?)?.toInt() ?? 0;
          final invalidTokens = (data['invalidTokens'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

          if (invalidTokens.isNotEmpty) {
            await _pruneInvalidTokens(customerId, invalidTokens);
          }

          if (delivered == 0 && failed > 0) {
            // Worker reached FCM but every token was rejected (invalid/expired)
            debugPrint('[FCM DIAGNOSTICS] Worker returned delivered:0 failed:$failed for order $orderId — all tokens invalid or FCM rejected');
            return false;
          }

          if (delivered == 0 && failed == 0 && data.containsKey('delivered')) {
            // No tokens were provided (skipped by worker) — not a push failure, just nothing to send
            debugPrint('[FCM DIAGNOSTICS] Worker skipped dispatch (no tokens) for order $orderId');
            return true;
          }

          debugPrint('[FCM DIAGNOSTICS] Worker SUCCESS: delivered=$delivered failed=$failed for order $orderId ($status)');
          return true;
        } catch (_) {
          // If we can\'t parse the body, treat HTTP 2xx as success
          debugPrint('[FCM DIAGNOSTICS] Worker 2xx but could not parse body for order $orderId; treating as success');
          return true;
        }
      } else {
        debugPrint('[FCM DIAGNOSTICS] Cloudflare Worker returned HTTP ${response.statusCode}: ${response.body}');
        return false;
      }
    } catch (e, st) {
      debugPrint('[FCM DIAGNOSTICS] Failed to send push notification: $e\n$st');
      return false;
    }
  }

  /// Sends a direct test notification to a specific test token for diagnostic verification.
  Future<Map<String, dynamic>> testSendCustomerNotification({
    required String testToken,
    String? orderId,
  }) async {
    final truncated = testToken.length > 8 ? '...${testToken.substring(testToken.length - 8)}' : testToken;
    debugPrint('[FCM DIAGNOSTICS] testSendCustomerNotification called with token: $truncated');

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'No authenticated admin user'};
      }

      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        return {'success': false, 'error': 'Failed to get ID token'};
      }

      final uri = Uri.parse('$workerEndpoint/send-order-notification');
      final payload = {
        'orderId': orderId ?? 'TEST-ORDER-123',
        'orderNumber': 'TEST-123',
        'customerId': user.uid,
        'status': 'test',
        'tokens': [testToken],
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

      final Map<String, dynamic> body = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : {};

      return {
        'statusCode': response.statusCode,
        'success': response.statusCode >= 200 && response.statusCode < 300,
        'body': body,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Queries all registered FCM tokens for the given customer ID with multi-layer fallback.
  Future<List<String>> _getCustomerFcmTokens(
    String customerId, {
    String? orderId,
    String? directToken,
  }) async {
    final tokenSet = <String>{};

    // 0. Direct token if supplied
    if (directToken != null && directToken.trim().isNotEmpty) {
      tokenSet.add(directToken.trim());
    }

    try {
      // 1. Check order document for direct customerFcmToken stored at checkout
      if (orderId != null && orderId.isNotEmpty) {
        try {
          final orderDoc = await FirebaseFirestore.instance.collection('orders').doc(orderId).get();
          if (orderDoc.exists) {
            final orderData = orderDoc.data();
            final orderToken = orderData?['customerFcmToken'] as String?;
            if (orderToken != null && orderToken.trim().isNotEmpty) {
              tokenSet.add(orderToken.trim());
            }
          }
        } catch (_) {}
      }

      // 2. Query customer user document
      final cleanId = customerId.trim();
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(cleanId).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        if (data != null) {
          final primaryToken = data['fcmToken'] as String?;
          if (primaryToken != null && primaryToken.trim().isNotEmpty) {
            tokenSet.add(primaryToken.trim());
          }

          final arrayTokens = data['fcmTokens'];
          if (arrayTokens is List) {
            for (final t in arrayTokens) {
              if (t != null && t.toString().trim().isNotEmpty) {
                tokenSet.add(t.toString().trim());
              }
            }
          }
        }
      }

      // 3. Also query multi-device subcollection
      final subSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(cleanId)
          .collection('fcmTokens')
          .limit(10)
          .get();

      for (final doc in subSnap.docs) {
        final token = doc.data()['token'] as String? ?? doc.id;
        if (token.trim().isNotEmpty) {
          tokenSet.add(token.trim());
        }
      }

      // 4. Fallback search by uid field if docId query was empty
      if (tokenSet.isEmpty) {
        final querySnap = await FirebaseFirestore.instance
            .collection('users')
            .where('uid', isEqualTo: cleanId)
            .limit(1)
            .get();
        for (final doc in querySnap.docs) {
          final data = doc.data();
          final primaryToken = data['fcmToken'] as String?;
          if (primaryToken != null && primaryToken.trim().isNotEmpty) {
            tokenSet.add(primaryToken.trim());
          }
          final arrayTokens = data['fcmTokens'];
          if (arrayTokens is List) {
            for (final t in arrayTokens) {
              if (t != null && t.toString().trim().isNotEmpty) {
                tokenSet.add(t.toString().trim());
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[NotificationSenderService] Error querying customer FCM tokens: $e');
    }

    return tokenSet.toList();
  }

  /// Prunes invalid/unregistered tokens from the customer's Firestore profile.
  Future<void> _pruneInvalidTokens(String customerId, List<String> invalidTokens) async {
    if (invalidTokens.isEmpty) return;

    try {
      // 1. Remove from user document array
      await FirebaseFirestore.instance.collection('users').doc(customerId).set({
        'fcmTokens': FieldValue.arrayRemove(invalidTokens),
      }, SetOptions(merge: true));

      // 2. Remove from subcollection
      final batch = FirebaseFirestore.instance.batch();
      for (final token in invalidTokens) {
        final subDoc = FirebaseFirestore.instance
            .collection('users')
            .doc(customerId)
            .collection('fcmTokens')
            .doc(token);
        batch.delete(subDoc);
      }
      await batch.commit();
      debugPrint('[NotificationSenderService] Successfully pruned ${invalidTokens.length} invalid tokens for $customerId');
    } catch (e) {
      debugPrint('[NotificationSenderService] Error pruning invalid tokens: $e');
    }
  }

  /// Dispatches a high-priority push notification to all Admin devices when a customer places a new order.
  /// Uses the authenticated user's ID token and the Cloudflare Notification Worker.
  Future<bool> sendNewOrderNotificationToAdmins({
    required String orderId,
    required String orderNumber,
    required double totalAmount,
    String? customerName,
    String? customerId,
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
        'customerId': customerId ?? (user.uid),
        'status': 'pending',
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
