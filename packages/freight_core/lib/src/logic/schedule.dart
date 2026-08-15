import '../models/freight_train.dart';

/// How far off timetable a movement is.
///
/// Finnish rail publishes `differenceInMinutes` as a signed integer where
/// negative means early. Freight runs to looser tolerances than passenger
/// services, so the thresholds here are deliberately wider than a commuter
/// app would use.
enum DelayStatus {
  early('Early'),
  onTime('On time'),
  minor('Minor delay'),
  major('Major delay'),
  unknown('Unknown');

  const DelayStatus(this.label);

  final String label;
}

/// Buckets a signed minute difference.
///
/// Boundaries: below -2 is [early]; -2..2 inclusive is [onTime]; 3..14 is
/// [minor]; 15 and above is [major]; null is [unknown].
DelayStatus classifyDelay(int? differenceInMinutes) {
  if (differenceInMinutes == null) return DelayStatus.unknown;
  if (differenceInMinutes < -2) return DelayStatus.early;
  if (differenceInMinutes <= 2) return DelayStatus.onTime;
  if (differenceInMinutes < 15) return DelayStatus.minor;
  return DelayStatus.major;
}

/// The largest positive delay across [stops], or `null` when nothing has a
/// recorded difference yet.
///
/// Only lateness counts: a train that made up time at one station has not
/// "recovered" a delay elsewhere for the purpose of flagging exceptions.
int? worstDelayMinutes(Iterable<TimetableStop> stops) {
  int? worst;
  for (final stop in stops) {
    final difference = stop.differenceInMinutes;
    if (difference == null || difference <= 0) continue;
    if (worst == null || difference > worst) worst = difference;
  }
  return worst;
}

/// Share of [stops] that were within tolerance, in the range 0..1.
///
/// Returns `null` for an empty sample rather than a misleading 0.0 or a
/// division by zero — "no data" and "nothing ran on time" are different claims.
double? adherenceRatio(Iterable<TimetableStop> stops) {
  var counted = 0;
  var withinTolerance = 0;
  for (final stop in stops) {
    if (stop.differenceInMinutes == null) continue;
    counted++;
    final status = classifyDelay(stop.differenceInMinutes);
    if (status == DelayStatus.early || status == DelayStatus.onTime) {
      withinTolerance++;
    }
  }
  if (counted == 0) return null;
  return withinTolerance / counted;
}

/// Time to cover [distanceKm] at [speedKmh].
///
/// Returns `null` for a stationary or nonsensical speed, which is the common
/// case: a parked freight train reports 0 km/h and must not produce an
/// infinite ETA.
Duration? estimateTravelTime({
  required double distanceKm,
  required double speedKmh,
}) {
  if (!distanceKm.isFinite || !speedKmh.isFinite) return null;
  if (distanceKm < 0 || speedKmh <= 0) return null;
  final seconds = (distanceKm / speedKmh) * 3600;
  if (!seconds.isFinite || seconds > Duration.secondsPerDay * 30) return null;
  return Duration(seconds: seconds.round());
}

/// Formats a duration compactly: `2h 14m`, `45m`, `<1m`.
String formatDuration(Duration duration) {
  if (duration.inMinutes < 1) return '<1m';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  return '${hours}h ${minutes}m';
}
