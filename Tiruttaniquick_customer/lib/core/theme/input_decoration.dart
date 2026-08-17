import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:flutter/material.dart';

class AppInputDecoration {
  static InputDecorationTheme get theme {
    return InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface, // #F7F7F7
      hintStyle: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: AppDimensions.fontSizeNormal,
      ),
      labelStyle: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: AppDimensions.fontSizeNormal,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingMedium,
        vertical: 14.0,
      ),
    );
  }
}
