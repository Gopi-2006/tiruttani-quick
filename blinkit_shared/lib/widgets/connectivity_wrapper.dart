import 'dart:async';
import 'package:flutter/material.dart';
import '../services/connectivity_provider.dart';
import 'connectivity_dialog.dart';

class ConnectivityWrapper extends StatefulWidget {
  final Widget child;

  const ConnectivityWrapper({
    super.key,
    required this.child,
  });

  @override
  State<ConnectivityWrapper> createState() => _ConnectivityWrapperState();
}

class _ConnectivityWrapperState extends State<ConnectivityWrapper> {
  final ConnectivityProvider _provider = ConnectivityProvider.instance;
  StreamSubscription<bool>? _subscription;
  OverlayEntry? _dialogEntry;
  bool _dialogDismissedByUser = false;

  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_provider.isOnline) {
        _showOfflineDialog();
      }
    });

    _subscription = _provider.onConnectivityChanged.listen((isOnline) {
      if (isOnline) {
        _dismissOfflineDialog();
        _showRestoredSnackBar();
        _dialogDismissedByUser = false;
      } else {
        if (!_dialogDismissedByUser) {
          _showOfflineDialog();
        }
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _dismissOfflineDialog();
    super.dispose();
  }

  void _showOfflineDialog() {
    if (_dialogEntry != null) return;

    final overlayState = Overlay.of(context);
    _dialogEntry = OverlayEntry(
      builder: (context) {
        return ConnectivityDialog(
          onRetry: () {
            _provider.forceCheck();
          },
          onClose: () {
            setState(() {
              _dialogDismissedByUser = true;
            });
            _dismissOfflineDialog();
          },
        );
      },
    );
    overlayState.insert(_dialogEntry!);
  }

  void _dismissOfflineDialog() {
    if (_dialogEntry != null) {
      try {
        _dialogEntry!.remove();
      } catch (_) {}
      _dialogEntry = null;
    }
  }

  void _showRestoredSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.wifi_rounded, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Text('Internet connection restored.'),
          ],
        ),
        backgroundColor: const Color(0xFF00A86B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
