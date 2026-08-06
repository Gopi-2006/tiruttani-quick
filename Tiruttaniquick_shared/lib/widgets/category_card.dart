import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_dimensions.dart';

class CategoryCard extends StatelessWidget {
  final String title;
  final String categoryImage;
  final VoidCallback onTap;
  final double size;

  const CategoryCard({
    super.key,
    required this.title,
    required this.categoryImage,
    required this.onTap,
    this.size = AppDimensions.categoryImageSize,
  });

  @override
  Widget build(BuildContext context) {
    final isValidUrl = categoryImage.isNotEmpty &&
        (categoryImage.startsWith('http://') || categoryImage.startsWith('https://'));

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFC8E6C9), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: isValidUrl
                  ? CachedNetworkImage(
                      imageUrl: categoryImage,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      fadeInDuration: const Duration(milliseconds: 200),
                      placeholder: (context, url) => const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => const Center(
                        child: Icon(
                          Icons.shopping_bag_outlined,
                          color: AppColors.primary,
                          size: 26,
                        ),
                      ),
                    )
                  : const Center(
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        color: AppColors.primary,
                        size: 26,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: AppDimensions.spacingSmall),
          SizedBox(
            width: size + 16,
            height: 34,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: AppDimensions.fontSizeNormal,
                height: 1.2,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
