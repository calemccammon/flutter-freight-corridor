import '../models/corridor.dart';
import '../models/freight_train.dart';
import '../models/geo_point.dart';
import '../models/port.dart';
import '../models/port_call.dart';
import '../models/vessel.dart';
import 'geo.dart';

/// Joins live rail and maritime data into [FreightCorridor]s.
///
/// The two feeds share no identifier — the rail API knows nothing about ships
/// and the maritime API knows nothing about trains — so the join is
/// geographic: a train's final station is matched to the nearest seaport
/// within [radiusKm], and everything happening at that port is attached.
///
/// Kept as a free function over plain data so it can be exercised without a
/// network, a widget tree, or a clock.
List<FreightCorridor> linkCorridors({
  required List<FreightTrain> trains,
  required List<Port> ports,
  required List<VesselPosition> vesselPositions,
  required List<PortCall> portCalls,
  required DateTime now,
  double radiusKm = 60,
  Duration callWindow = const Duration(hours: 24),
}) {
  final locatedPorts = ports
      .where((port) => port.point != null && port.isFinnish)
      .toList(growable: false);
  if (locatedPorts.isEmpty) return const <FreightCorridor>[];

  // Group trains by the nearest port to their terminus.
  final trainsByLocode = <String, List<FreightTrain>>{};
  final anchorByLocode = <String, ({String terminus, double distance})>{};

  for (final train in trains) {
    final terminus = train.terminus;
    final location = terminus?.stationLocation;
    if (terminus == null || location == null) continue;

    final nearest = _nearestPort(location, locatedPorts, radiusKm);
    if (nearest == null) continue;

    trainsByLocode
        .putIfAbsent(nearest.port.locode, () => <FreightTrain>[])
        .add(train);

    // Remember the closest terminus so the corridor is labelled by the
    // station that actually sits nearest the quay.
    final existing = anchorByLocode[nearest.port.locode];
    if (existing == null || nearest.distanceKm < existing.distance) {
      anchorByLocode[nearest.port.locode] = (
        terminus: terminus.stationName,
        distance: nearest.distanceKm,
      );
    }
  }

  final corridors = <FreightCorridor>[];

  for (final entry in trainsByLocode.entries) {
    final port = locatedPorts.firstWhere((p) => p.locode == entry.key);
    final portPoint = port.point!;
    final anchor = anchorByLocode[entry.key]!;

    final vesselsAtPort = vesselPositions
        .where((position) => haversineKm(position.point, portPoint) <= radiusKm)
        .toList(growable: false);

    final upcomingCalls = portCalls
        .where((call) => call.portToVisit == port.locode)
        .where((call) => call.isInboundWithin(callWindow, now: now))
        .toList(growable: false);

    final trainsHere = entry.value;
    final bearing = _averageBearingToPort(trainsHere, portPoint);

    corridors.add(
      FreightCorridor(
        port: port,
        terminusName: anchor.terminus,
        distanceKm: anchor.distance,
        bearingDegrees: bearing,
        compassLabel: compassPoint(bearing),
        inboundTrains: trainsHere,
        vesselsAtPort: vesselsAtPort,
        upcomingCalls: upcomingCalls,
      ),
    );
  }

  corridors.sort((a, b) {
    final byIntensity = b.intensity.compareTo(a.intensity);
    if (byIntensity != 0) return byIntensity;
    return a.port.name.compareTo(b.port.name);
  });
  return corridors;
}

({Port port, double distanceKm})? _nearestPort(
  GeoPoint from,
  List<Port> ports,
  double radiusKm,
) {
  Port? best;
  var bestDistance = double.infinity;

  for (final port in ports) {
    final distance = haversineKm(from, port.point!);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = port;
    }
  }

  if (best == null || bestDistance > radiusKm) return null;
  return (port: best, distanceKm: bestDistance);
}

/// Bearing from the trains' current positions towards the port, so the UI can
/// say "approaching from the NNE". Falls back to 0 when nothing has a fix.
double _averageBearingToPort(List<FreightTrain> trains, GeoPoint portPoint) {
  final bearings = <double>[
    for (final train in trains)
      if (train.position != null)
        initialBearingDegrees(train.position!, portPoint),
  ];
  if (bearings.isEmpty) return 0;
  return bearings.reduce((a, b) => a + b) / bearings.length;
}
