import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

/// Singleton manager for continuous repeating NEW ORDER alerts on Admin devices.
///
/// Ensures:
/// 1. Only 'new_order' notifications trigger repeating audio alerts.
/// 2. Controlled repeating interval (e.g. every 4 seconds) without tight loop battery drain.
/// 3. Immediate stoppage when the Admin acknowledges, views, or changes the order status.
/// 4. Duplicate protection: ignores duplicate FCM triggers for the same orderId.
/// 5. Multiple order support: maintains an active unacknowledged queue and continues alerting until all are cleared.
/// 6. Safety auto-cutoff after 5 minutes (75 ticks) to avoid draining battery on unattended devices.
class NewOrderAlertManager {
  static final NewOrderAlertManager instance = NewOrderAlertManager._();
  NewOrderAlertManager._();

  final Set<String> _activeOrderIds = <String>{};
  final Map<String, Map<String, dynamic>> _orderDetails = <String, Map<String, dynamic>>{};
  
  Timer? _repeatingTimer;
  bool _isPlaying = false;
  int _alertTickCount = 0;
  AudioPlayer? _audioPlayer;
  Uint8List? _cachedAudioBytes;

  /// Reactive notifier containing the list of active unacknowledged new orders.
  /// Used by foreground UI banners/overlays.
  final ValueNotifier<List<Map<String, dynamic>>> activeOrdersNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  /// Returns true if the repeating alert loop is currently ringing.
  bool get isAlertActive => _isPlaying && _activeOrderIds.isNotEmpty;

  /// Returns a set of all currently unacknowledged order IDs.
  Set<String> get activeOrderIds => Set<String>.unmodifiable(_activeOrderIds);

  /// Handle receipt of a new order notification.
  /// Deduplicates by [orderId] and starts the controlled repeating alert loop.
  void handleNewOrderReceived({
    required String orderId,
    String? orderNumber,
    double? totalAmount,
    String? customerName,
    String? customerId,
    Map<String, dynamic>? rawPayload,
  }) {
    if (orderId.trim().isEmpty) return;
    final normalizedId = orderId.trim();

    // 1. Duplicate Protection: If order is already in the active alert queue, ignore
    if (_activeOrderIds.contains(normalizedId)) {
      debugPrint('[NewOrderAlertManager] Duplicate new-order alert ignored for order: $normalizedId');
      return;
    }

    // 2. Add to active unacknowledged order queue
    _activeOrderIds.add(normalizedId);
    _orderDetails[normalizedId] = {
      'orderId': normalizedId,
      'orderNumber': orderNumber ?? (normalizedId.length > 8 ? normalizedId.substring(0, 8) : normalizedId),
      'totalAmount': totalAmount ?? 0.0,
      'customerName': customerName ?? 'Customer',
      'customerId': customerId ?? '',
      'receivedAt': DateTime.now(),
      'rawPayload': rawPayload ?? {},
    };

    _syncNotifier();
    debugPrint('[NewOrderAlertManager] New order alert registered: $normalizedId. Active queue: ${_activeOrderIds.length}');

    // 3. Start repeating audio loop if not already running
    if (!_isPlaying) {
      _startAlertLoop();
    }
  }

  /// Acknowledge and dismiss an individual order alert.
  /// Immediately stops repeating sound if no other unacknowledged orders remain.
  void acknowledgeOrder(String orderId) {
    if (orderId.trim().isEmpty) return;
    final normalizedId = orderId.trim();

    if (!_activeOrderIds.contains(normalizedId)) {
      // Force stop audio if no active orders remain
      if (_activeOrderIds.isEmpty) {
        _stopAlertLoop();
      }
      return;
    }

    _activeOrderIds.remove(normalizedId);
    _orderDetails.remove(normalizedId);
    _syncNotifier();

    debugPrint('[NewOrderAlertManager] Acknowledged order: $normalizedId. Remaining in queue: ${_activeOrderIds.length}');

    // If all new orders are acknowledged, stop sound immediately!
    if (_activeOrderIds.isEmpty) {
      _stopAlertLoop();
    }
  }

  /// Dismisses all pending new order alerts and immediately silences the alert loop.
  void acknowledgeAll() {
    _activeOrderIds.clear();
    _orderDetails.clear();
    _syncNotifier();
    _stopAlertLoop();
    debugPrint('[NewOrderAlertManager] All new order alerts acknowledged and silenced.');
  }

  /// Alias for acknowledgeOrder
  void stopAlert(String orderId) => acknowledgeOrder(orderId);

  /// Check whether an alert is currently active for a given orderId.
  bool isOrderAlertActive(String orderId) => _activeOrderIds.contains(orderId.trim());

  /// Starts the controlled repeating audio timer (every 4 seconds)
  void _startAlertLoop() {
    _isPlaying = true;
    _alertTickCount = 0;

    // Play immediately on first trigger
    _playChime();

    _repeatingTimer?.cancel();
    _repeatingTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_activeOrderIds.isEmpty) {
        _stopAlertLoop();
        return;
      }

      _alertTickCount++;
      // Safety auto-cutoff after 5 minutes (75 ticks * 4s = 300s) to prevent battery drain on unattended devices
      if (_alertTickCount >= 75) {
        debugPrint('[NewOrderAlertManager] 5-minute safety threshold reached. Silencing repeating alert loop.');
        _stopAlertLoop();
        return;
      }

      _playChime();
    });
  }

  /// Stops the repeating audio timer and silences all audio immediately
  void _stopAlertLoop() {
    _repeatingTimer?.cancel();
    _repeatingTimer = null;
    _isPlaying = false;
    _alertTickCount = 0;

    try {
      _audioPlayer?.stop();
    } catch (e) {
      debugPrint('[NewOrderAlertManager] Error stopping AudioPlayer: $e');
    }

    try {
      FlutterRingtonePlayer().stop();
    } catch (e) {
      debugPrint('[NewOrderAlertManager] Error stopping FlutterRingtonePlayer: $e');
    }
  }

  /// Plays a single alert chime cycle using order_received.mp3
  Future<void> _playChime() async {
    try {
      _audioPlayer ??= AudioPlayer();
      await _audioPlayer!.setVolume(1.0);
      await _audioPlayer!.setReleaseMode(ReleaseMode.stop);

      // Preload audio bytes from asset if not cached
      if (_cachedAudioBytes == null) {
        try {
          final ByteData data = await rootBundle.load('assets/sounds/order_received.mp3');
          _cachedAudioBytes = data.buffer.asUint8List();
        } catch (_) {
          try {
            final ByteData data = await rootBundle.load('assets/order_received.mp3');
            _cachedAudioBytes = data.buffer.asUint8List();
          } catch (_) {}
        }
      }

      if (_cachedAudioBytes != null && _cachedAudioBytes!.isNotEmpty) {
        await _audioPlayer!.stop();
        await _audioPlayer!.play(BytesSource(_cachedAudioBytes!), volume: 1.0);
        return;
      }

      // Fallback: AssetSource
      await _audioPlayer!.stop();
      await _audioPlayer!.play(
        AssetSource('sounds/order_received.mp3'),
        volume: 1.0,
      );
    } catch (e) {
      debugPrint('[NewOrderAlertManager] AudioPlayer playback error, using fallback: $e');
      try {
        FlutterRingtonePlayer().play(
          fromAsset: 'assets/sounds/order_received.mp3',
          android: AndroidSounds.notification,
          ios: IosSounds.glass,
          looping: false,
          volume: 1.0,
          asAlarm: true,
        );
      } catch (e2) {
        debugPrint('[NewOrderAlertManager] All audio playback attempts failed: $e2');
      }
    }
  }

  void _syncNotifier() {
    activeOrdersNotifier.value = _activeOrderIds.map((id) => _orderDetails[id] ?? {'orderId': id}).toList();
  }

  /// Visible for testing: resets state
  @visibleForTesting
  void resetForTesting() {
    _repeatingTimer?.cancel();
    _repeatingTimer = null;
    _isPlaying = false;
    _alertTickCount = 0;
    _activeOrderIds.clear();
    _orderDetails.clear();
    activeOrdersNotifier.value = [];
    try {
      _audioPlayer?.stop();
    } catch (_) {}
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {}
  }
}
