import 'package:meta/meta.dart';

import '../logic/schedule.dart';
import 'geo_point.dart';

/// Whether a timetable row describes a train arriving at or leaving a station.
enum StopType { arrival, departure }

/// One scheduled call at a station.
@immutable
class TimetableStop {
  const TimetableStop({
    required this.stationName,
    required this.stationShortCode,
    required this.type,
    required this.scheduledTime,
    this.actualTime,
    this.differenceInMinutes,
    this.stationLocation,
    this.cancelled = false,
  });

  final String stationName;
  final String stationShortCode;
  final StopType type;
  final DateTime scheduledTime;
  final DateTime? actualTime;
  final int? differenceInMinutes;
  final GeoPoint? stationLocation;
  final bool cancelled;

  DelayStatus get delayStatus => classifyDelay(differenceInMinutes);

  /// True once the train has actually passed this point.
  bool get hasPassed => actualTime != null;

  @override
  String toString() => '$stationName (${type.name})';
}

/// A cargo train, assembled from the rail GraphQL API.
@immutable
class FreightTrain {
  const FreightTrain({
    required this.trainNumber,
    required this.departureDate,
    required this.operatorShortCode,
    required this.operatorName,
    required this.trainTypeName,
    required this.runningCurrently,
    required this.stops,
    this.position,
    this.speedKmh,
    this.positionReportedAt,
    this.composition,
  });

  final int trainNumber;

  /// The operating day. Two trains can share a number on different days, so
  /// this is part of the identity, not decoration.
  final String departureDate;

  final String operatorShortCode;
  final String operatorName;
  final String trainTypeName;
  final bool runningCurrently;
  final List<TimetableStop> stops;
  final GeoPoint? position;
  final double? speedKmh;
  final DateTime? positionReportedAt;
  final WagonComposition? composition;

  /// Stable identity across refreshes, used as a list key and a watchlist entry.
  String get id => '$trainNumber/$departureDate';

  bool get isMoving => (speedKmh ?? 0) > 0;

  /// The last station on the timetable — where the freight is headed, and the
  /// anchor for pairing this train with a seaport.
  TimetableStop? get terminus => stops.isEmpty ? null : stops.last;

  TimetableStop? get origin => stops.isEmpty ? null : stops.first;

  /// The next station the train has not yet reached.
  TimetableStop? get nextStop {
    for (final stop in stops) {
      if (!stop.hasPassed && !stop.cancelled) return stop;
    }
    return null;
  }

  int? get worstDelay => worstDelayMinutes(stops);

  DelayStatus get delayStatus => classifyDelay(worstDelay ?? 0);

  double? get adherence => adherenceRatio(stops);

  @override
  String toString() => 'FreightTrain($id, $operatorShortCode)';
}

/// One locomotive-and-wagons section of a train.
@immutable
class JourneySection {
  const JourneySection({
    required this.maximumSpeedKmh,
    required this.totalLengthMetres,
    required this.wagons,
    required this.locomotives,
  });

  final int maximumSpeedKmh;
  final int totalLengthMetres;
  final List<Wagon> wagons;
  final List<Locomotive> locomotives;
}

@immutable
class Wagon {
  const Wagon({
    required this.salesNumber,
    required this.lengthMetres,
    this.wagonType,
  });

  final int salesNumber;

  /// Reported in centimetres by the API; normalised to metres on the way in.
  final double lengthMetres;
  final String? wagonType;
}

@immutable
class Locomotive {
  const Locomotive({required this.locomotiveType, required this.powerType});

  final String locomotiveType;

  /// `S` for electric (sähkö), `D` for diesel.
  final String powerType;

  bool get isElectric => powerType.toUpperCase() == 'S';
}

/// The physical make-up of a train: how long, how heavy, hauled by what.
@immutable
class WagonComposition {
  const WagonComposition({required this.sections});

  final List<JourneySection> sections;

  int get wagonCount =>
      sections.fold(0, (sum, section) => sum + section.wagons.length);

  int get locomotiveCount =>
      sections.fold(0, (sum, section) => sum + section.locomotives.length);

  double get totalLengthMetres =>
      sections.fold(0, (sum, section) => sum + section.totalLengthMetres);

  /// Highest permitted speed across all sections. A train is limited by its
  /// slowest section, but the sections of one train normally agree.
  int? get maximumSpeedKmh {
    if (sections.isEmpty) return null;
    return sections
        .map((section) => section.maximumSpeedKmh)
        .reduce((a, b) => a < b ? a : b);
  }

  /// The most common wagon type, which is a decent proxy for what the train
  /// is carrying — timber, tank, or container flats.
  String? get dominantWagonType {
    final counts = <String, int>{};
    for (final section in sections) {
      for (final wagon in section.wagons) {
        final type = wagon.wagonType;
        if (type == null || type.isEmpty) continue;
        counts[type] = (counts[type] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    var best = counts.entries.first;
    for (final entry in counts.entries) {
      if (entry.value > best.value) best = entry;
    }
    return best.key;
  }

  bool get isElectricHauled => sections
      .expand((section) => section.locomotives)
      .any((locomotive) => locomotive.isElectric);
}
