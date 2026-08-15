import 'package:freight_core/freight_core.dart';

import 'marine_data_source.dart';
import 'rail_data_source.dart';

/// Where a piece of data came from, so the UI can be honest about it.
enum Freshness { live, cached }

/// A result plus its provenance.
class Sourced<T> {
  const Sourced(this.value, {this.freshness = Freshness.live, this.capturedAt});

  final T value;
  final Freshness freshness;

  /// When a cached value was captured. Null for live data.
  final DateTime? capturedAt;

  bool get isStale => freshness == Freshness.cached;
}

/// The single seam between the app and the outside world.
///
/// Two very different transports sit behind this class — GraphQL over ferry
/// for rail, REST over http for maritime — and neither leaks through it. Every
/// method returns `freight_core` types, so providers and widgets cannot tell
/// which screen is backed by GraphQL, and swapping either transport would
/// touch one file.
class FreightRepository {
  /// Uses Dart 3.12 private named parameters: callers write
  /// `FreightRepository(rail: ..., marine: ...)` while the fields stay
  /// private. The leading underscore is stripped at the call site, so there is
  /// no initializer list and no public field to keep in sync.
  FreightRepository({required this._rail, required this._marine});

  final RailDataSource _rail;
  final MarineDataSource _marine;

  /// Every cargo train currently running.
  Future<List<FreightTrain>> cargoTrains() =>
      _guard(() => _rail.cargoTrains(), 'cargo trains');

  Future<FreightTrain?> trainDetail({
    required int trainNumber,
    required String departureDate,
  }) => _guard(
    () => _rail.trainDetail(
      trainNumber: trainNumber,
      departureDate: departureDate,
    ),
    'train $trainNumber',
  );

  /// Freight vessels near a point, with their static details merged in.
  ///
  /// The AIS feed splits what a vessel *is* from where it *is*; joining them
  /// here means the UI never has to.
  Future<Sourced<List<TrackedVessel>>> freightVesselsNear({
    required GeoPoint centre,
    required double radiusKm,
  }) async {
    return _guard(() async {
      final positions = await _marine.vesselPositions(
        centre: centre,
        radiusKm: radiusKm,
      );
      final details = await _marine.vessels();

      final tracked = <TrackedVessel>[
        for (final position in positions)
          if (details[position.mmsi] case final Vessel vessel)
            if (vessel.isFreight)
              TrackedVessel(vessel: vessel, position: position),
      ];
      return _sourced(tracked);
    }, 'vessel positions');
  }

  Future<Sourced<List<PortCall>>> portCalls() =>
      _guard(() async => _sourced(await _marine.portCalls()), 'port calls');

  Future<Sourced<List<Port>>> ports() =>
      _guard(() async => _sourced(await _marine.ports()), 'ports');

  /// Roughly the centre of Finland, with a radius that reaches every coast.
  /// The corridor view is national, so it cannot be anchored on wherever the
  /// user happens to be looking on the map.
  static const _finlandCentre = GeoPoint(latitude: 64.5, longitude: 26.0);
  static const _finlandRadiusKm = 700.0;

  /// The multimodal view: rail termini paired with the seaports they feed.
  ///
  /// This is the only place the two feeds meet, and it does so by handing all
  /// four datasets to [linkCorridors] — pure logic in `freight_core` that has
  /// no idea any of this came off a network.
  Future<List<FreightCorridor>> corridors({
    DateTime? now,
    double pairingRadiusKm = 60,
  }) async {
    final trains = await cargoTrains();
    final allPorts = await ports();
    final calls = await portCalls();
    final vessels = await freightVesselsNear(
      centre: _finlandCentre,
      radiusKm: _finlandRadiusKm,
    );

    // The LOCODE directory lists every registered place, including inland
    // towns that no ship ever visits. Keeping only the codes that actually
    // appear in the port-call feed is a data-driven way to say "seaport",
    // and it stops a rail terminus being paired with a lakeside village.
    final servedLocodes = calls.value.map((call) => call.portToVisit).toSet();
    final seaports = allPorts.value
        .where((port) => servedLocodes.contains(port.locode))
        .toList(growable: false);

    return linkCorridors(
      trains: trains,
      ports: seaports,
      vesselPositions: vessels.value
          .map((tracked) => tracked.position)
          .toList(growable: false),
      portCalls: calls.value,
      now: now ?? DateTime.now().toUtc(),
      radiusKm: pairingRadiusKm,
    );
  }

  Sourced<T> _sourced<T>(T value) {
    final stale = _marine.staleSince;
    return Sourced(
      value,
      freshness: stale == null ? Freshness.live : Freshness.cached,
      capturedAt: stale,
    );
  }

  /// Collapses every transport-specific failure into one type, so callers
  /// handle a single exception rather than knowing about ferry and http.
  Future<T> _guard<T>(Future<T> Function() operation, String what) async {
    try {
      return await operation();
    } on MarineRequestException catch (error) {
      throw FreightException('Could not load $what', detail: error.message);
    } on RailRequestException catch (error) {
      throw FreightException('Could not load $what', detail: error.message);
    } on Object catch (error) {
      throw FreightException('Could not load $what', detail: error.toString());
    }
  }
}

/// A freight vessel with its latest position.
class TrackedVessel {
  const TrackedVessel({required this.vessel, required this.position});

  final Vessel vessel;
  final VesselPosition position;

  int get mmsi => vessel.mmsi;
}

/// The one error type the UI has to understand.
class FreightException implements Exception {
  const FreightException(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message ($detail)';
}
