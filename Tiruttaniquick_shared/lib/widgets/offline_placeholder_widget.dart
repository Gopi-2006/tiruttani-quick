import 'package:flutter/material.dart';
import '../core/constants/app_dimensions.dart';
import '../services/connectivity_provider.dart';

class OfflinePlaceholderWidget extends StatefulWidget {
  final VoidCallback? onRetrySuccess;

  const OfflinePlaceholderWidget({
    super.key,
    this.onRetrySuccess,
  });

  @override
  State<OfflinePlaceholderWidget> createState() => _OfflinePlaceholderWidgetState();
}

class _OfflinePlaceholderWidgetState extends State<OfflinePlaceholderWidget> {
  bool _isLoading = false;

  Future<void> _handleRetry() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    final isOnline = await ConnectivityProvider.instance.forceCheck();

    await Future.delayed(const Duration(milliseconds: 1000));
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      if (isOnline) {
        widget.onRetrySuccess?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.paddingLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.withValues(alpha: 0.1),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 72,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Internet Connection',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "You are currently offline. Please check your network and try again.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              onPressed: _handleRetry,
              icon: _isLoading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
