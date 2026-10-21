import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../services/startup_provider.dart';
import '../../../cart/presentation/cart_provider.dart';
import '../home_screen.dart';
import 'banner_shimmer.dart';

/// Promotional banner carousel for the home screen meeting the full UI/UX design spec.
/// - 16:9 Aspect Ratio with 16px margins and rounded corners
/// - 4s auto-scroll with 3s pause on user touch
/// - Subtle 0.98x press scale micro-interaction
/// - Bottom 40% dark gradient overlay ensuring >= 4.5:1 text contrast
/// - Bold headline, optional subtitle, and high-contrast CTA pill chip
/// - Shimmer loading skeleton and graceful branded error fallback
/// - Full accessibility semantics and analytics impression/click tracking
class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key});

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _autoScrollTimer;
  Timer? _resumeTimer;
  bool _isUserInteracting = false;
  int _bannerCount = 0;
  final Set<String> _recordedBannerViews = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    if (_bannerCount > 1 && !_isUserInteracting) {
      _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted || _isUserInteracting) return;
        _currentPage++;
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  void _onUserPointerDown() {
    _isUserInteracting = true;
    _autoScrollTimer?.cancel();
    _resumeTimer?.cancel();
  }

  void _onUserPointerUp() {
    _resumeTimer?.cancel();
    // Resume auto-scroll after 3 seconds of user inactivity
    _resumeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _isUserInteracting = false;
        _startAutoScroll();
      }
    });
  }

  void _recordViewIfNeeded(List<BannerModel> activeBanners, int index) {
    if (activeBanners.isEmpty) return;
    final banner = activeBanners[index % activeBanners.length];
    if (!_recordedBannerViews.contains(banner.id)) {
      _recordedBannerViews.add(banner.id);
      FirestoreService().recordBannerView(banner.id);
    }
  }

  void _syncBannerCount(List<BannerModel> activeBanners) {
    if (activeBanners.length != _bannerCount) {
      _bannerCount = activeBanners.length;
      _currentPage = _bannerCount > 1 ? _bannerCount * 500 : 0;
      _pageController.dispose();
      _pageController = PageController(initialPage: _currentPage);
      _startAutoScroll();
      if (activeBanners.isNotEmpty) {
        _recordViewIfNeeded(activeBanners, _currentPage);
      }
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _resumeTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startup = context.watch<StartupProvider>();

    // Initial Loading Shimmer State
    if (!startup.isInitialized && startup.banners.isEmpty) {
      return const BannerShimmerWidget();
    }

    // Expiry logic: Client-side safety filter
    final activeBanners = startup.banners.where((b) => b.isCurrentlyActive).toList();

    _syncBannerCount(activeBanners);

    // Empty state: completely hide the section if no active banners exist
    if (activeBanners.isEmpty) {
      return const SizedBox.shrink();
    }

    final int actualCount = activeBanners.length;
    final int virtualCount = actualCount > 1 ? actualCount * 1000 : 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Listener(
          onPointerDown: (_) => _onUserPointerDown(),
          onPointerUp: (_) => _onUserPointerUp(),
          onPointerCancel: (_) => _onUserPointerUp(),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingMedium,
              vertical: 6,
            ),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: PageView.builder(
                controller: _pageController,
                itemCount: virtualCount,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                  _recordViewIfNeeded(activeBanners, index);
                },
                itemBuilder: (context, index) {
                  final banner = activeBanners[index % actualCount];
                  return _BannerItemCard(
                    banner: banner,
                    onTap: () => _handleBannerTap(banner),
                  );
                },
              ),
            ),
          ),
        ),

        // Dot Page Indicators
        if (actualCount > 1) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(actualCount, (idx) {
              final isSelected = (_currentPage % actualCount) == idx;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isSelected ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
          const SizedBox(height: AppDimensions.spacingSmall),
        ],
      ],
    );
  }

  void _handleBannerTap(BannerModel banner) async {
    // 1. Analytics click tracking
    FirestoreService().recordBannerClick(banner.id);

    // 2. Conversion attribution in cart provider
    if (mounted) {
      context.read<CartProvider>().bannerIdClicked = banner.id;
    }

    // 3. Navigation routing
    final destination = banner.actionType;
    final target = banner.actionTarget;

    if (!mounted) return;

    switch (destination) {
      case 'Open Product':
        context.push('/product/$target');
        break;
      case 'Open Category':
        context.push('/products/$target?name=${Uri.encodeComponent(banner.title)}');
        break;
      case 'Open Brand':
        final searchProvider = context.read<HomeSearchProvider>();
        searchProvider.query = target;
        break;
      case 'Open Offer Page':
        context.push('/offer/${banner.id}?title=${Uri.encodeComponent(banner.title)}');
        break;
      case 'Open Collection':
      case 'Open Search':
        final searchProvider = context.read<HomeSearchProvider>();
        searchProvider.query = target;
        break;
      case 'External URL':
        final uri = Uri.tryParse(target);
        if (uri != null) {
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {}
        }
        break;
      default:
        break;
    }
  }
}

/// Single Banner Item Card with Press Micro-Animation and Content Layout
class _BannerItemCard extends StatefulWidget {
  final BannerModel banner;
  final VoidCallback onTap;

  const _BannerItemCard({
    required this.banner,
    required this.onTap,
  });

  @override
  State<_BannerItemCard> createState() => _BannerItemCardState();
}

class _BannerItemCardState extends State<_BannerItemCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final banner = widget.banner;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final String accessibilityLabel = [
      if (banner.title.isNotEmpty) banner.title,
      if (banner.subtitle.isNotEmpty) banner.subtitle,
      if (banner.bannerType.isNotEmpty) banner.bannerType,
      'Promotional offer. Double tap to view.',
    ].join('. ');

    return Semantics(
      label: accessibilityLabel,
      button: true,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeInOut,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
            child: Material(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              child: InkWell(
                onTap: widget.onTap,
                onHighlightChanged: (highlighted) {
                  setState(() => _isPressed = highlighted);
                },
                splashColor: Colors.white.withValues(alpha: 0.2),
                highlightColor: Colors.white.withValues(alpha: 0.1),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background Lifestyle / Product Image
                    CachedNetworkImage(
                      imageUrl: banner.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: isDark ? const Color(0xFF262626) : Colors.grey.shade100,
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => _buildBrandedFallback(context, banner),
                    ),

                    // Subtle dark gradient overlay (bottom 45%) for 4.5:1 text contrast
                    if (banner.title.isNotEmpty || banner.subtitle.isNotEmpty)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 90,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.78),
                                Colors.black.withValues(alpha: 0.40),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Headline + Subtext + CTA Chip
                    if (banner.title.isNotEmpty || banner.subtitle.isNotEmpty)
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 12,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    banner.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      height: 1.2,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black54,
                                          blurRadius: 4,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (banner.subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      banner.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        shadows: const [
                                          Shadow(
                                            color: Colors.black54,
                                            blurRadius: 3,
                                            offset: Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // CTA Pill Chip
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Shop Now',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  SizedBox(width: 3),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 13,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Countdown Timer Badge (if enabled)
                    if (banner.countdownEnabled)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: BannerCountdownWidget(endDateTime: banner.endDateTime),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Soft branded placeholder card when image fails to load
  Widget _buildBrandedFallback(BuildContext context, BannerModel banner) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE86C00),
            Color(0xFFF5A623),
          ],
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Ranuka Store Special Offer',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (banner.title.isNotEmpty)
            Text(
              banner.title,
              maxLines: 2,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          if (banner.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              banner.subtitle,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class BannerCountdownWidget extends StatefulWidget {
  final DateTime endDateTime;
  const BannerCountdownWidget({super.key, required this.endDateTime});

  @override
  State<BannerCountdownWidget> createState() => _BannerCountdownWidgetState();
}

class _BannerCountdownWidgetState extends State<BannerCountdownWidget> {
  late Timer _timer;
  late Duration _timeLeft;

  @override
  void initState() {
    super.initState();
    _calculateTimeLeft();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _calculateTimeLeft();
        });
      }
    });
  }

  void _calculateTimeLeft() {
    _timeLeft = widget.endDateTime.difference(DateTime.now());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_timeLeft.isNegative) {
      return const SizedBox.shrink();
    }

    final hours = _timeLeft.inHours.toString().padLeft(2, '0');
    final minutes = (_timeLeft.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (_timeLeft.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, color: Colors.orangeAccent, size: 13),
          const SizedBox(width: 4),
          Text(
            'Ends in $hours:$minutes:$seconds',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier',
            ),
          ),
        ],
      ),
    );
  }
}

