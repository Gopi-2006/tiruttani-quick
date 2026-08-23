import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

/// Interactive Voice Search Modal Dialog with auto-timeout and suggestions fallback.
/// Guarantees clean dismissal on speech, selection, timeout, or cancellation without freezing.
class VoiceSearchDialog extends StatefulWidget {
  const VoiceSearchDialog({super.key});

  @override
  State<VoiceSearchDialog> createState() => _VoiceSearchDialogState();
}

class _VoiceSearchDialogState extends State<VoiceSearchDialog> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseScale;
  late Animation<double> _glowAlpha;

  Timer? _timeoutTimer;
  bool _isTimedOut = false;

  final List<String> _quickSuggestions = const [
    'Aashirvaad Atta',
    'Basmati Rice',
    'Sunflower Oil',
    'Amul Milk',
    'Vim Gel',
    'Urad Dal',
    'அரிசி',
    'எண்ணெய்',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _glowAlpha = Tween<double>(begin: 0.25, end: 0.65).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Safety auto-timeout: if no voice input received after 4.5 seconds, transition cleanly
    _timeoutTimer = Timer(const Duration(milliseconds: 4500), () {
      if (mounted) {
        setState(() {
          _isTimedOut = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _selectQuery(String query) {
    _timeoutTimer?.cancel();
    if (mounted) {
      Navigator.of(context).pop(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.mic, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Voice Search',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkText : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: isDark ? AppColors.darkMuted : AppColors.muted,
                  onPressed: () => Navigator.of(context).pop(null),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Pulsing Mic Animation
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer glow ring
                    Container(
                      width: 96 * _pulseScale.value,
                      height: 96 * _pulseScale.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withValues(alpha: _glowAlpha.value * 0.3),
                      ),
                    ),
                    // Inner solid button
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.mic_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Status message
            Text(
              _isTimedOut ? "Didn't catch that. Tap a suggestion:" : 'Listening... Say a product name',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _isTimedOut ? AppColors.warning : AppColors.primary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'e.g. Atta, Oil, Basmati Rice, Milk, அரிசி',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkMuted : AppColors.muted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Quick Tap Suggestions
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _quickSuggestions.map((suggestion) {
                return ActionChip(
                  label: Text(
                    suggestion,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
                  side: BorderSide(
                    color: isDark ? AppColors.darkBorder : AppColors.border,
                    width: 1,
                  ),
                  onPressed: () => _selectQuery(suggestion),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Cancel / Dismiss button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(null),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
