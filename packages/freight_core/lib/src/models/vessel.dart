import 'package:meta/meta.dart';

import '../logic/ais_codes.dart';
import 'geo_point.dart';

/// Static information a vessel broadcasts about itself.
@immutable
class Vessel {
  const Vessel({
    required this.mmsi,
    required this.name,
    required this.shipTypeCode,
    this.callSign,
    this.imo,
    this.destination,
    this.draughtMetres,
    this.lengthMetres,
    this.beamMetres,
    this.eta,
  });

  /// Maritime Mobile Service Identity — the vessel's radio identity, and the
  /// only key shared between the AIS feed and the port-call feed.
  final int mmsi;
  final String name;
  final int shipTypeCode;
  final String? callSign;
  final int? imo;

  /// Free-text and operator-entered, so it is often a LOCODE, often a port
  /// name, and sometimes nonsense. Treated as a hint, never as a join key.
  final String? destination;

  final double? draughtMetres;
  final double? lengthMetres;
  final double? beamMetres;
  final DateTime? eta;

  ShipCategory get category => shipCategoryFromCode(shipTypeCode);

  bool get isFreight => category.isFreight;

  @override
  String toString() => 'Vessel($mmsi, $name, ${category.label})';
}

/// A single AIS position report.
@immutable
class VesselPosition {
  const VesselPosition({
    required this.mmsi,
    required this.point,
    required this.speedKnots,
    required this.courseDegrees,
    required this.navigationStatus,
    required this.reportedAt,
    this.headingDegrees,
  });

  final int mmsi;
  final GeoPoint point;

  /// Speed over ground. AIS encodes 102.3 to mean "not available".
  final double speedKnots;

  /// Course over ground.
  final double courseDegrees;

  final NavigationStatus navigationStatus;
  final DateTime reportedAt;
  final int? headingDegrees;

  bool get isUnderWay => speedKnots > 0.5;

  @override
  String toString() => 'VesselPosition($mmsi @ $point)';
}

/// Vessel dimensions come as four AIS "reference point" distances measured
/// from the transponder to bow (A), stern (B), port (C) and starboard (D).
/// Length and beam are the sums, not any single value — a detail that is easy
/// to get wrong and worth isolating.
({double? lengthMetres, double? beamMetres}) vesselDimensions({
  num? referencePointA,
  num? referencePointB,
  num? referencePointC,
  num? referencePointD,
}) {
  double? sum(num? first, num? second) {
    if (first == null || second == null) return null;
    final total = first.toDouble() + second.toDouble();
    return total > 0 ? total : null;
  }

  return (
    lengthMetres: sum(referencePointA, referencePointB),
    beamMetres: sum(referencePointC, referencePointD),
  );
}

/// AIS reports draught in decimetres. 0 means "not reported".
double? draughtMetresFromAis(num? raw) {
  if (raw == null) return null;
  final metres = raw.toDouble() / 10;
  return metres > 0 ? metres : null;
}
