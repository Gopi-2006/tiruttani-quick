import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool loading;
  final bool outline;
  final IconData? icon;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.loading = false,
    this.outline = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
    );

    if (outline) {
      if (icon != null) {
        return OutlinedButton.icon(
          onPressed: loading ? null : onPressed,
          icon: loading
              ? const SizedBox(
                  height: AppDimensions.iconSizeSmall,
                  width: AppDimensions.iconSizeSmall,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                )
              : Icon(icon, size: 18),
          label: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppDimensions.fontSizeNormal),
          ),
          style: OutlinedButton.styleFrom(
            shape: shape,
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        );
      }
      return OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          shape: shape,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        child: loading
            ? const SizedBox(
                height: AppDimensions.iconSizeSmall,
                width: AppDimensions.iconSizeSmall,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              )
            : Text(
                text,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppDimensions.fontSizeNormal),
              ),
      );
    }

    if (icon != null) {
      return ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                height: AppDimensions.iconSizeSmall,
                width: AppDimensions.iconSizeSmall,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
              )
            : Icon(icon, size: 18),
        label: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppDimensions.fontSizeNormal, color: AppColors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 0,
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      );
    }

    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        elevation: 0,
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      child: loading
          ? const SizedBox(
              height: AppDimensions.iconSizeSmall,
              width: AppDimensions.iconSizeSmall,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
            )
          : Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppDimensions.fontSizeNormal, color: AppColors.white),
            ),
    );
  }
}
