import 'package:flutter/material.dart';

/// A reusable widget that smoothly slides and fades its [child] (e.g. [NavigationBar] or bottom bar)
/// into or out of view based on [isVisible].
class ScrollHideBottomNav extends StatelessWidget {
  final bool isVisible;
  final Widget child;
  final Duration duration;
  final Curve curve;

  const ScrollHideBottomNav({
    super.key,
    required this.isVisible,
    required this.child,
    this.duration = const Duration(milliseconds: 250),
    this.curve = Curves.easeInOutCubic,
  });

  /// Evaluates a [ScrollNotification] and triggers [onVisibilityChanged] when scroll direction changes.
  ///
  /// - Non-vertical scroll events (e.g. horizontal carousels) are ignored.
  /// - At scroll position 0 or negative (top of page), visibility is always restored.
  /// - Scrolling down the page (content moves up, positive delta > [threshold]) hides the bar.
  /// - Scrolling up the page (content moves down, negative delta < -[threshold]) shows the bar.
  /// - Sub-threshold micro-scrolls and idle stops are ignored to prevent flickering.
  static bool handleScrollNotification({
    required ScrollNotification notification,
    required bool isCurrentlyVisible,
    required void Function(bool newVisibility) onVisibilityChanged,
    double threshold = 4.0,
  }) {
    // 1. Only react to vertical scrolls; ignore horizontal carousels/swipes
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    // 2. Always show at the top of the scrollable content
    if (notification.metrics.pixels <= 0) {
      if (!isCurrentlyVisible) {
        onVisibilityChanged(true);
      }
      return false;
    }

    // 3. Evaluate scroll delta on updates
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0.0;

      // Positive delta: User scrolling down the page (content moves up) -> Hide
      if (delta > threshold && isCurrentlyVisible) {
        onVisibilityChanged(false);
      }
      // Negative delta: User scrolling up the page (content moves down) -> Show
      else if (delta < -threshold && !isCurrentlyVisible) {
        onVisibilityChanged(true);
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: isVisible ? Offset.zero : const Offset(0, 1),
      duration: duration,
      curve: curve,
      child: AnimatedOpacity(
        opacity: isVisible ? 1.0 : 0.0,
        duration: duration,
        curve: curve,
        child: Wrap(
          children: [child],
        ),
      ),
    );
  }
}
