import 'dart:async';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import 'notification_popup_card.dart';

class InAppNotificationListener extends StatefulWidget {
  final Widget child;
  final String? currentUserId;
  final Function(String? orderId) onTapNotification;
  final VoidCallback? onPlaySound;

  const InAppNotificationListener({
    super.key,
    required this.child,
    this.currentUserId,
    required this.onTapNotification,
    this.onPlaySound,
  });

  @override
  State<InAppNotificationListener> createState() => _InAppNotificationListenerState();
}

class _InAppNotificationListenerState extends State<InAppNotificationListener> {
  final FirestoreService _firestoreService = FirestoreService();
  StreamSubscription? _subscription;
  final Set<String> _processedNotificationIds = {};
  OverlayEntry? _activeEntry;

  @override
  void initState() {
    super.initState();
    _setupStream();
  }

  @override
  void didUpdateWidget(covariant InAppNotificationListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUserId != widget.currentUserId) {
      _setupStream();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (_activeEntry != null) {
      try {
        _activeEntry!.remove();
      } catch (_) {}
      _activeEntry = null;
    }
    super.dispose();
  }

  void _setupStream() {
    _subscription?.cancel();
    _subscription = null;

    final userId = widget.currentUserId;
    if (userId == null) {
      _processedNotificationIds.clear();
      if (_activeEntry != null) {
        try {
          _activeEntry!.remove();
        } catch (_) {}
        _activeEntry = null;
      }
      return;
    }

    bool isFirstLoad = true;

    _subscription = _firestoreService.notificationsStream(userId).listen((notifications) {
      if (isFirstLoad) {
        // Populate the set with existing notifications to avoid popping up old notifications
        for (final n in notifications) {
          final id = n['id'] as String?;
          if (id != null) {
            _processedNotificationIds.add(id);
          }
        }
        isFirstLoad = false;
        return;
      }

      for (final n in notifications) {
        final id = n['id'] as String?;
        final isRead = n['isRead'] as bool? ?? false;
        final title = n['title'] as String? ?? 'Notification';
        final body = n['body'] as String? ?? '';
        final orderId = n['orderId'] as String?;

        if (id != null && !_processedNotificationIds.contains(id)) {
          _processedNotificationIds.add(id);
          if (!isRead) {
            // Trigger sound and popup!
            widget.onPlaySound?.call();
            _showNotificationPopup(id, title, body, orderId);
          }
        }
      }
    });
  }

  Future<void> _showNotificationPopup(
    String id,
    String title,
    String body,
    String? orderId,
  ) async {
    // Mark as read in Firestore to prevent repeat triggers
    await _firestoreService.markNotificationAsRead(id);

    if (mounted) {
      _showOverlay(title, body, orderId);
    }
  }

  void _showOverlay(String title, String body, String? orderId) {
    if (_activeEntry != null) {
      try {
        _activeEntry!.remove();
      } catch (_) {}
      _activeEntry = null;
    }

    final overlayState = Overlay.of(context);

    _activeEntry = OverlayEntry(
      builder: (context) {
        return NotificationPopupCard(
          title: title,
          body: body,
          orderId: orderId,
          onTap: () {
            widget.onTapNotification(orderId);
          },
          onDismissed: () {
            if (_activeEntry != null) {
              try {
                _activeEntry!.remove();
              } catch (_) {}
              _activeEntry = null;
            }
          },
        );
      },
    );

    overlayState.insert(_activeEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
