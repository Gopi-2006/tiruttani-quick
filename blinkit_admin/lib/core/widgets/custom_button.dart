import 'package:blinkit_shared/blinkit_shared.dart';
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
      borderRadius: BorderRadius.circular(AppDimensions.borderRadiusNormal),
    );

    if (outline) {
      if (icon != null) {
        return OutlinedButton.icon(
          onPressed: loading ? null : onPressed,
          icon: loading
              ? const SizedBox(
                  height: AppDimensions.iconSizeSmall,
                  width: AppDimensions.iconSizeSmall,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon),
          label: Text(text),
          style: OutlinedButton.styleFrom(shape: shape),
        );
      }
      return OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(shape: shape),
        child: loading
            ? const SizedBox(
                height: AppDimensions.iconSizeSmall,
                width: AppDimensions.iconSizeSmall,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(text),
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
            : Icon(icon),
        label: Text(text),
        style: ElevatedButton.styleFrom(shape: shape),
      );
    }

    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(shape: shape),
      child: loading
          ? const SizedBox(
              height: AppDimensions.iconSizeSmall,
              width: AppDimensions.iconSizeSmall,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
            )
          : Text(text),
    );
  }
}
