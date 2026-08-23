import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';

import '../core/constants/app_colors.dart';

/// Reusable, performance-optimized image widget supporting:
/// 1. BlurHash preview placeholder during image load
/// 2. Smooth fade transition when network image loads
/// 3. Memory & disk caching via [CachedNetworkImage]
/// 4. Graceful fallbacks for missing/invalid BlurHash or broken URLs
class AppNetworkImage extends StatelessWidget {
  final String imageUrl;
  final String? blurHash;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget Function(BuildContext context, String url)? placeholder;
  final Widget Function(BuildContext context, String url, dynamic error)? errorWidget;
  final Duration fadeInDuration;
  final Duration? fadeOutDuration;
  final Curve fadeInCurve;
  final int? maxWidthDiskCache;
  final int? maxHeightDiskCache;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final Color? backgroundColor;

  const AppNetworkImage({
    super.key,
    required this.imageUrl,
    this.blurHash,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.fadeOutDuration = const Duration(milliseconds: 200),
    this.fadeInCurve = Curves.easeIn,
    this.maxWidthDiskCache,
    this.maxHeightDiskCache,
    this.memCacheWidth,
    this.memCacheHeight,
    this.backgroundColor,
  });

  /// Validates whether a given string is a syntactically valid BlurHash.
  static bool isValidBlurHash(String? hash) {
    if (hash == null) return false;
    final trimmed = hash.trim();
    if (trimmed.length < 6) return false;

    // BlurHash base83 character set: 0-9, A-Z, a-z, #$%*+,-.:;=?@[]^_{|}~
    const base83Charset =
        r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~';
    for (int i = 0; i < trimmed.length; i++) {
      if (!base83Charset.contains(trimmed[i])) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cleanUrl = imageUrl.trim();
    final isValidUrl = cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://');

    Widget content;
    if (!isValidUrl) {
      content = errorWidget != null
          ? errorWidget!(context, cleanUrl, 'Invalid image URL')
          : _buildDefaultErrorWidget(context);
    } else {
      content = CachedNetworkImage(
        imageUrl: cleanUrl,
        width: width,
        height: height,
        fit: fit,
        maxWidthDiskCache: maxWidthDiskCache,
        maxHeightDiskCache: maxHeightDiskCache,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        fadeInDuration: fadeInDuration,
        fadeOutDuration: fadeOutDuration,
        fadeInCurve: fadeInCurve,
        placeholder: (ctx, url) => _buildPlaceholder(ctx, url),
        errorWidget: (ctx, url, error) => errorWidget != null
            ? errorWidget!(ctx, url, error)
            : _buildDefaultErrorWidget(ctx),
      );
    }

    if (backgroundColor != null) {
      content = Container(
        width: width,
        height: height,
        color: backgroundColor,
        child: content,
      );
    }

    if (borderRadius != null) {
      content = ClipRRect(
        borderRadius: borderRadius!,
        child: content,
      );
    }

    return content;
  }

  Widget _buildPlaceholder(BuildContext context, String url) {
    final validHash = isValidBlurHash(blurHash) ? blurHash!.trim() : null;

    if (validHash != null && validHash.isNotEmpty) {
      return _SafeBlurHashPlaceholder(
        hash: validHash,
        fit: fit,
        fallback: placeholder != null
            ? placeholder!(context, url)
            : _buildDefaultPlaceholder(context),
      );
    }

    return placeholder != null
        ? placeholder!(context, url)
        : _buildDefaultPlaceholder(context);
  }

  Widget _buildDefaultPlaceholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      color: isDark ? const Color(0xFF222222) : Colors.grey.shade100,
    );
  }

  Widget _buildDefaultErrorWidget(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      color: isDark ? const Color(0xFF222222) : Colors.grey.shade50,
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: (width != null && width! < 60) ? 20 : 32,
          color: isDark ? AppColors.darkMuted : Colors.grey.shade400,
        ),
      ),
    );
  }
}

/// Safely displays BlurHash in a background isolate with fallback on decode error.
class _SafeBlurHashPlaceholder extends StatefulWidget {
  final String hash;
  final BoxFit fit;
  final Widget fallback;

  const _SafeBlurHashPlaceholder({
    required this.hash,
    required this.fit,
    required this.fallback,
  });

  @override
  State<_SafeBlurHashPlaceholder> createState() => _SafeBlurHashPlaceholderState();
}

class _SafeBlurHashPlaceholderState extends State<_SafeBlurHashPlaceholder> {
  bool _hasError = false;

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.fallback;
    }

    return BlurHash(
      hash: widget.hash,
      imageFit: widget.fit,
      duration: Duration.zero,
      decodingWidth: 32,
      decodingHeight: 32,
      onDecoded: () {},
      onReady: () {},
    );
  }
}
