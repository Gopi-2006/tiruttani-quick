import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import '../../../services/startup_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Staged Animations
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;

  late Animation<double> _pinProgress;
  late Animation<double> _pinBounceY;

  late Animation<double> _lightningProgress;
  late Animation<double> _lightningGlow;

  late Animation<double> _linesProgress;

  late Animation<double> _bagProgress;

  late Animation<double> _textOpacity;
  late Animation<Offset> _textOffset;

  late Animation<double> _poweredByOpacity;

  late Animation<double> _exitScale;
  late Animation<double> _exitOpacity;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 2300),
      vsync: this,
    );

    // Sequence timelines based on 2300ms total duration
    
    // T = 0.0s to 0.5s -> Logo Entrance (Scale & Fade)
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.22, curve: Curves.easeOut),
      ),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.22, curve: Curves.easeIn),
      ),
    );

    // T = 0.3s to 0.8s -> Location Pin Drops (Fade & Bounce)
    _pinProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.13, 0.35, curve: Curves.easeIn),
      ),
    );
    _pinBounceY = Tween<double>(begin: -150.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.13, 0.35, curve: Curves.bounceOut),
      ),
    );

    // T = 0.6s to 1.1s -> Lightning Slide & Glow
    _lightningProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.26, 0.48, curve: Curves.easeOut),
      ),
    );
    _lightningGlow = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 50),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.39, 0.48, curve: Curves.easeInOut),
      ),
    );

    // T = 0.9s to 1.2s -> Speed Lines slide left-to-right
    _linesProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.39, 0.52, curve: Curves.easeOut),
      ),
    );

    // T = 1.1s to 1.5s -> Shopping Bag sketch draw
    _bagProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.48, 0.65, curve: Curves.easeInOut),
      ),
    );

    // T = 1.3s to 1.8s -> Brand Text Fade & Slide
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.57, 0.78, curve: Curves.easeIn),
      ),
    );
    _textOffset = Tween<Offset>(
      begin: const Offset(0.0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.57, 0.78, curve: Curves.easeOutQuad),
      ),
    );

    // T = 1.8s to 2.3s -> Powered by text fade-in
    _poweredByOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.78, 1.0, curve: Curves.easeIn),
      ),
    );

    // T = 2.1s to 2.3s -> Exit animation (Scale down slightly to 98% and fade out)
    _exitScale = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.91, 1.0, curve: Curves.easeInOut),
      ),
    );
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.91, 1.0, curve: Curves.easeOut),
      ),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animationCompleted = true;
        _checkNavigation();
      }
    });

    _controller.forward();

    // Start background loading of all startup data concurrently during the splash animation
    startupProvider.runInitialization(context);
    startupProvider.addListener(_onStartupChange);
  }

  bool _animationCompleted = false;

  void _onStartupChange() {
    if (startupProvider.isInitialized) {
      _checkNavigation();
    }
  }

  void _checkNavigation() {
    if (_animationCompleted && startupProvider.isInitialized) {
      if (!mounted) return;
      context.go(AppRoutes.home);
    }
  }

  @override
  void dispose() {
    startupProvider.removeListener(_onStartupChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFFAFAFA),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Center Logo and Brand Name
            Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Opacity(
                    opacity: _exitOpacity.value,
                    child: Transform.scale(
                      scale: _exitScale.value,
                      child: Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Vector Animation Cluster
                              SizedBox(
                                width: 180,
                                height: 180,
                                child: CustomPaint(
                                  painter: LogoPainter(
                                    pinProgress: _pinProgress.value,
                                    pinBounceY: _pinBounceY.value,
                                    lightningProgress: _lightningProgress.value,
                                    lightningGlow: _lightningGlow.value,
                                    linesProgress: _linesProgress.value,
                                    bagProgress: _bagProgress.value,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Typography
                              FadeTransition(
                                opacity: _textOpacity,
                                child: SlideTransition(
                                  position: _textOffset,
                                  child: Column(
                                    children: [
                                      const Text(
                                        'TIRUTTANI',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 30,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF16A34A),
                                          letterSpacing: 2,
                                          height: 1.0,
                                        ),
                                      ),
                                      const Text(
                                        'QUICK',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 38,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF16A34A),
                                          letterSpacing: 3,
                                          height: 1.1,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Grocery Delivery',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF16A34A).withValues(alpha: 0.8),
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Bottom "Powered By" text
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40.0),
                child: FadeTransition(
                  opacity: _poweredByOpacity,
                  child: const Text(
                    'Powered by Ranuka Store',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF757575),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LogoPainter extends CustomPainter {
  final double pinProgress;
  final double pinBounceY;
  final double lightningProgress;
  final double lightningGlow;
  final double linesProgress;
  final double bagProgress;

  LogoPainter({
    required this.pinProgress,
    required this.pinBounceY,
    required this.lightningProgress,
    required this.lightningGlow,
    required this.linesProgress,
    required this.bagProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Relative coordinate space is 200x200
    final double scaleX = size.width / 200;
    final double scaleY = size.height / 200;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    final orangeStrokePaint = Paint()
      ..color = const Color(0xFFF97316)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 1. Draw Shopping Bag outline (sketched)
    if (bagProgress > 0) {
      final bagPath = Path()
        ..moveTo(35, 150)
        ..lineTo(42, 115)
        ..quadraticBezierTo(43, 110, 52, 110)
        ..lineTo(52, 95)
        ..cubicTo(52, 78, 82, 78, 82, 95)
        ..lineTo(82, 110)
        ..quadraticBezierTo(91, 110, 92, 115)
        ..lineTo(98, 150)
        ..quadraticBezierTo(99, 155, 90, 155)
        ..lineTo(40, 155)
        ..quadraticBezierTo(34, 155, 35, 150);

      final sketchedPath = Path();
      for (final metric in bagPath.computeMetrics()) {
        sketchedPath.addPath(
          metric.extractPath(0.0, metric.length * bagProgress),
          Offset.zero,
        );
      }
      canvas.drawPath(sketchedPath, orangeStrokePaint);
    }

    // 2. Draw Location Pin (drops with bounce)
    if (pinProgress > 0) {
      canvas.save();
      canvas.translate(0, pinBounceY);

      final pinPath = Path()
        ..moveTo(100, 110)
        ..cubicTo(80, 93, 75, 83, 75, 70)
        ..arcToPoint(const Offset(125, 70), radius: const Radius.circular(25), clockwise: true)
        ..cubicTo(125, 83, 120, 93, 100, 110)
        ..close();

      final cutoutPath = Path()
        ..addOval(Rect.fromCircle(center: const Offset(100, 70), radius: 8));

      final finalPinPath = Path.combine(PathOperation.difference, pinPath, cutoutPath);

      final pinPaint = Paint()
        ..color = const Color(0xFF16A34A).withValues(alpha: pinProgress)
        ..style = PaintingStyle.fill;

      canvas.drawPath(finalPinPath, pinPaint);
      canvas.restore();
    }

    // 3. Draw Lightning Bolt (slides and glows)
    if (lightningProgress > 0) {
      canvas.save();
      final double slideOffset = 40 * (1.0 - lightningProgress);
      canvas.translate(slideOffset, -slideOffset);

      final lightningPath = Path()
        ..moveTo(118, 38)
        ..lineTo(95, 88)
        ..lineTo(108, 88)
        ..lineTo(86, 138)
        ..lineTo(105, 100)
        ..lineTo(96, 100)
        ..close();

      // Orange Glow
      if (lightningGlow > 0) {
        final glowPaint = Paint()
          ..color = const Color(0xFFFF9800).withValues(alpha: lightningGlow * 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
          ..style = PaintingStyle.fill;
        canvas.drawPath(lightningPath, glowPaint);
      }

      // White outline border for overlay separation
      final borderPaint = Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: lightningProgress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(lightningPath, borderPaint);

      // Filled lightning shape
      final lPaint = Paint()
        ..color = const Color(0xFFF97316).withValues(alpha: lightningProgress)
        ..style = PaintingStyle.fill;
      canvas.drawPath(lightningPath, lPaint);

      canvas.restore();
    }

    // 4. Draw Speed Lines (fade and slide left to right)
    if (linesProgress > 0) {
      final linesPaint = Paint()
        ..color = const Color(0xFF16A34A).withValues(alpha: linesProgress)
        ..style = PaintingStyle.fill;

      // Top Speed Line
      final topPath = Path()
        ..moveTo(105, 120)
        ..lineTo(105 + 30 * linesProgress, 118.5)
        ..lineTo(105 + 30 * linesProgress, 121.5)
        ..close();
      canvas.drawPath(topPath, linesPaint);

      // Middle Speed Line
      final midPath = Path()
        ..moveTo(107, 126)
        ..lineTo(107 + 25 * linesProgress, 124.5)
        ..lineTo(107 + 25 * linesProgress, 127.5)
        ..close();
      canvas.drawPath(midPath, linesPaint);

      // Bottom Speed Line
      final botPath = Path()
        ..moveTo(109, 132)
        ..lineTo(109 + 20 * linesProgress, 130.5)
        ..lineTo(109 + 20 * linesProgress, 133.5)
        ..close();
      canvas.drawPath(botPath, linesPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LogoPainter oldDelegate) {
    return oldDelegate.pinProgress != pinProgress ||
        oldDelegate.pinBounceY != pinBounceY ||
        oldDelegate.lightningProgress != lightningProgress ||
        oldDelegate.lightningGlow != lightningGlow ||
        oldDelegate.linesProgress != linesProgress ||
        oldDelegate.bagProgress != bagProgress;
  }
}
