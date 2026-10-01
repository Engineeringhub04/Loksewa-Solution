import 'dart:math' as math;

/// Shared chart math — port of `chartMath.ts` (pure functions only).
///
/// Owned by the analytics data layer; chart widgets import this rather than
/// re-implementing it.

/// Rounds [value] up to a "nice" axis ceiling (1 / 2 / 2.5 / 5 × 10^n).
double niceMax(double value) {
  if (!value.isFinite || value <= 0) return 1;
  final magnitude = math.pow(10, (math.log(value) / math.ln10).floor()).toDouble();
  final normalized = value / magnitude;
  final step = normalized <= 1
      ? 1.0
      : normalized <= 2
          ? 2.0
          : normalized <= 2.5
              ? 2.5
              : normalized <= 5
                  ? 5.0
                  : 10.0;
  return step * magnitude;
}

/// 1500 → "1.5k", 2000000 → "2M", 42 → "42".
String compactNumber(double value) {
  final safe = value.isFinite ? value : 0.0;
  final abs = safe.abs();
  if (abs >= 1000000) {
    return '${(safe / 1000000).toStringAsFixed(abs >= 10000000 ? 0 : 1)}M';
  }
  if (abs >= 1000) {
    return '${(safe / 1000).toStringAsFixed(abs >= 10000 ? 0 : 1)}k';
  }
  if (safe != safe.roundToDouble()) return safe.toStringAsFixed(1);
  return safe.toInt().toString();
}

/// Seconds → "2h 15m" / "45m" / "30s".
String formatDuration(double totalSeconds) {
  final safe = math.max(0, totalSeconds.round());
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m';
  return '${safe}s';
}
