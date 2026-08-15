import 'package:freight_core/freight_core.dart';
import 'package:test/test.dart';

TimetableStop stop(String name, int? difference, {bool passed = true}) {
  return TimetableStop(
    stationName: name,
    stationShortCode: name
        .substring(0, name.length < 2 ? name.length : 2)
        .toUpperCase(),
    type: StopType.arrival,
    scheduledTime: DateTime.utc(2026, 8, 15, 12),
    actualTime: passed ? DateTime.utc(2026, 8, 15, 12) : null,
    differenceInMinutes: difference,
  );
}

void main() {
  group('classifyDelay', () {
    test('buckets signed minute differences at their boundaries', () {
      expect(classifyDelay(-6), DelayStatus.early);
      expect(classifyDelay(-3), DelayStatus.early);
      expect(classifyDelay(-2), DelayStatus.onTime);
      expect(classifyDelay(0), DelayStatus.onTime);
      expect(classifyDelay(2), DelayStatus.onTime);
      expect(classifyDelay(3), DelayStatus.minor);
      expect(classifyDelay(14), DelayStatus.minor);
      expect(classifyDelay(15), DelayStatus.major);
      expect(classifyDelay(120), DelayStatus.major);
    });

    test('treats an absent difference as unknown rather than on time', () {
      expect(classifyDelay(null), DelayStatus.unknown);
    });
  });

  group('worstDelayMinutes', () {
    test('picks the largest lateness across the timetable', () {
      final worst = worstDelayMinutes(<TimetableStop>[
        stop('Kouvola', 4),
        stop('Kotka', 21),
        stop('Lahti', 7),
      ]);
      expect(worst, 21);
    });

    test('ignores early running rather than treating it as recovery', () {
      expect(
        worstDelayMinutes(<TimetableStop>[stop('Oulu', -9), stop('Kemi', -2)]),
        isNull,
      );
    });

    test('returns null when nothing has been recorded', () {
      expect(worstDelayMinutes(const <TimetableStop>[]), isNull);
      expect(worstDelayMinutes(<TimetableStop>[stop('Turku', null)]), isNull);
    });
  });

  group('adherenceRatio', () {
    test('is the share of recorded stops within tolerance', () {
      final ratio = adherenceRatio(<TimetableStop>[
        stop('A', 0),
        stop('B', -4),
        stop('C', 1),
        stop('D', 30),
      ]);
      expect(ratio, closeTo(0.75, 1e-9));
    });

    test('returns null for an empty sample instead of zero', () {
      // "No data" and "nothing ran on time" must not look the same.
      expect(adherenceRatio(const <TimetableStop>[]), isNull);
      expect(adherenceRatio(<TimetableStop>[stop('A', null)]), isNull);
    });
  });

  group('estimateTravelTime', () {
    test('computes time from distance and speed', () {
      final duration = estimateTravelTime(distanceKm: 100, speedKmh: 80);
      expect(duration, isNotNull);
      expect(duration!.inMinutes, 75);
    });

    test('refuses to produce an ETA for a stationary train', () {
      // A parked freight train reports 0 km/h; an infinite ETA is not useful.
      expect(estimateTravelTime(distanceKm: 100, speedKmh: 0), isNull);
      expect(estimateTravelTime(distanceKm: 100, speedKmh: -5), isNull);
      expect(estimateTravelTime(distanceKm: 100, speedKmh: double.nan), isNull);
      expect(estimateTravelTime(distanceKm: -1, speedKmh: 80), isNull);
    });
  });

  group('formatDuration', () {
    test('formats compactly', () {
      expect(formatDuration(const Duration(hours: 2, minutes: 14)), '2h 14m');
      expect(formatDuration(const Duration(minutes: 45)), '45m');
      expect(formatDuration(const Duration(seconds: 20)), '<1m');
    });
  });
}
