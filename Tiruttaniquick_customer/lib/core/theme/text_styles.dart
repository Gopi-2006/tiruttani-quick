import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:flutter/material.dart';

class TextStyles {
  static const TextStyle title = TextStyle(
    fontSize: AppDimensions.fontSizeTitle,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle header = TextStyle(
    fontSize: AppDimensions.fontSizeHeader,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle boldNormal = TextStyle(
    fontSize: AppDimensions.fontSizeNormal,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle body = TextStyle(
    fontSize: AppDimensions.fontSizeMedium,
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
