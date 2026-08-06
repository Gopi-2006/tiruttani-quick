import 'package:flutter/foundation.dart';

/// Performance Logger to measure and output execution timing for critical app operations.
class AuthPerformanceLogger {
  /// Starts a new stopwatch for a named operation.
  static Stopwatch start(String label) {
    final stopwatch = Stopwatch()..start();
    debugPrint('[Auth Performance Log] STARTED: "$label"');
    return stopwatch;
  }

  /// Stops the stopwatch and logs the total elapsed milliseconds.
  static double stopAndLog(Stopwatch stopwatch, String label) {
    stopwatch.stop();
    final elapsedMs = stopwatch.elapsedMicroseconds / 1000.0;
    debugPrint(
      '[Auth Performance Log] COMPLETED: "$label" in ${elapsedMs.toStringAsFixed(2)} ms (${stopwatch.elapsedMilliseconds} ms)',
    );
    return elapsedMs;
  }

  /// Convenience method to log an action with an async callback and return its result.
  static Future<T> trace<T>(String label, Future<T> Function() action) async {
    final stopwatch = start(label);
    try {
      final result = await action();
      stopAndLog(stopwatch, label);
      return result;
    } catch (e) {
      stopwatch.stop();
      debugPrint(
        '[Auth Performance Log] FAILED: "$label" after ${stopwatch.elapsedMilliseconds} ms with error: $e',
      );
      rethrow;
    }
  }
}
