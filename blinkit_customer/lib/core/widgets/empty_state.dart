import 'package:blinkit_shared/blinkit_shared.dart';
import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;

  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: AppDimensions.emptyStateIconSize, color: AppColors.muted),
          const SizedBox(height: AppDimensions.spacingNormal),
          Text(
            message,
            style: const TextStyle(
              fontSize: AppDimensions.fontSizeLarge,
              color: AppColors.muted,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
