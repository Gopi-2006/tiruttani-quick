import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../core/constants/app_dimensions.dart';

const Color _greenColor = Color(0xFF00A86B);
const Color _redColor = Color(0xFFEF4444);

class ConnectivityListener extends StatefulWidget {
  final Widget child;

  const ConnectivityListener({
    super.key,
    required this.child,
  });

  @override
  State<ConnectivityListener> createState() => _ConnectivityListenerState();
}

class _ConnectivityListenerState extends State<ConnectivityListener> {
  Timer? _timer;
  bool _isOnline = true;
  bool _isFirstCheck = true;
  bool _checking = false;
  OverlayEntry? _activeEntry;
  GlobalKey<_ConnectivityPopupCardState>? _popupKey;

  @override
  void initState() {
    super.initState();
    _startConnectivityCheck();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _removeOverlay();
    super.dispose();
  }

  void _startConnectivityCheck() {
    // Run immediate check
    _checkConnection();
    // Schedule periodic checks every 5 seconds
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkConnection());
  }

  Future<void> _checkConnection() async {
    if (kIsWeb) {
      _updateStatus(true);
      return;
    }
    if (_checking) return;
    _checking = true;
    try {
      final result = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 3));
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      _updateStatus(online);
    } catch (_) {
      _updateStatus(false);
    } finally {
      _checking = false;
    }
  }

  void _updateStatus(bool online) {
    if (!mounted) return;

    if (_isFirstCheck) {
      _isOnline = online;
      _isFirstCheck = false;
      if (!_isOnline) {
        _showOfflineOverlay();
      }
      return;
    }

    if (online != _isOnline) {
      _isOnline = online;
      if (!_isOnline) {
        // Transitioned to offline
        _showOfflineOverlay();
      } else {
        // Transitioned to online
        _popupKey?.currentState?.transitionToOnline(() {
          _removeOverlay();
        });
      }
    }
  }

  void _showOfflineOverlay() {
    _removeOverlay();
    _popupKey = GlobalKey<_ConnectivityPopupCardState>();
    final overlayState = Overlay.of(context);
    _activeEntry = OverlayEntry(
      builder: (context) {
        return ConnectivityPopupCard(
          key: _popupKey,
          isOnlineInitially: false,
        );
      },
    );
    overlayState.insert(_activeEntry!);
  }

  void _removeOverlay() {
    if (_activeEntry != null) {
      try {
        _activeEntry!.remove();
      } catch (_) {}
      _activeEntry = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class ConnectivityPopupCard extends StatefulWidget {
  final bool isOnlineInitially;

  const ConnectivityPopupCard({
    super.key,
    required this.isOnlineInitially,
  });

  @override
  State<ConnectivityPopupCard> createState() => _ConnectivityPopupCardState();
}

class _ConnectivityPopupCardState extends State<ConnectivityPopupCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  bool _isOnline = false;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _isOnline = widget.isOnlineInitially;

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void transitionToOnline(VoidCallback onFinished) {
    if (!mounted || _isDismissing) return;
    setState(() {
      _isOnline = true;
    });

    // Wait for 2 seconds online feedback, then slide up and remove
    Future.delayed(const Duration(seconds: 2), () async {
      if (mounted) {
        setState(() {
          _isDismissing = true;
        });
        await _controller.reverse();
        onFinished();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top > 0 ? mediaQuery.padding.top : 16.0;

    final color = _isOnline ? _greenColor : _redColor;
    final icon = _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded;
    final title = _isOnline ? 'Back Online' : 'No Internet Connection';
    final subtitle = _isOnline
        ? 'Your internet connection was restored.'
        : 'Please check your network settings.';

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          top: topPadding + 8,
          left: 16,
          right: 16,
          child: SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: child,
            ),
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: AppDimensions.spacingMedium),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.9),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
