import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:flutter/material.dart';

class TextStyles {
  static const TextStyle display = TextStyle(
    fontSize: AppDimensions.fontSizeDisplay,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle h1 = TextStyle(
    fontSize: AppDimensions.fontSizeH1,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: AppDimensions.fontSizeH2,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle title = TextStyle(
    fontSize: AppDimensions.fontSizeTitle,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const TextStyle header = TextStyle(
    fontSize: AppDimensions.fontSizeHeader,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle boldNormal = TextStyle(
    fontSize: AppDimensions.fontSizeNormal,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: AppDimensions.fontSizeBody,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: AppDimensions.fontSizeCaption,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const TextStyle price = TextStyle(
    fontSize: AppDimensions.fontSizePrice,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
  );

  static const TextStyle priceDark = TextStyle(
    fontSize: AppDimensions.fontSizePrice,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
  );

  static const TextStyle button = TextStyle(
    fontSize: AppDimensions.fontSizeNormal,
    fontWeight: FontWeight.w600,
    color: AppColors.white,
  );

  static const TextStyle muted = TextStyle(
    fontSize: AppDimensions.fontSizeMedium,
    color: AppColors.muted,
  );

  static const TextStyle mutedSmall = TextStyle(
    fontSize: AppDimensions.fontSizeSmall,
    color: AppColors.muted,
  );

  static const TextStyle error = TextStyle(
    fontSize: AppDimensions.fontSizeSmall,
    color: AppColors.error,
  );
}
