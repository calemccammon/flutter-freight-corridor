import '../models/geo_point.dart';
import '../models/port.dart';
import '../models/vessel.dart';
import 'ais_codes.dart';

/// Parses the AIS `locations` FeatureCollection into position reports.
///
/// Two traps live in this payload and both are handled here rather than at the
/// call sites:
///
///  * `geometry.coordinates` is `[longitude, latitude]`.
///  * `properties.timestamp` is **not** a timestamp. It is the AIS
///    second-of-minute field (0-59). The real instant is `timestampExternal`,
///    in epoch milliseconds.
///
/// Malformed features are skipped rather than thrown on: a live feed of a
/// thousand vessels will always contain a few bad rows, and losing one vessel
/// is better than losing the map.
List<VesselPosition> parseVesselPositions(Object? json) {
  if (json is! Map) return const <VesselPosition>[];
  final features = json['features'];
  if (features is! List) return const <VesselPosition>[];

  final positions = <VesselPosition>[];
  for (final feature in features) {
    final position = _parseVesselFeature(feature);
    if (position != null) positions.add(position);
  }
  return positions;
}

VesselPosition? _parseVesselFeature(Object? feature) {
  if (feature is! Map) return null;

  final properties = feature['properties'];
  if (properties is! Map) return null;

  final mmsi = _asInt(properties['mmsi'] ?? feature['mmsi']);
  if (mmsi == null) return null;

  final geometry = feature['geometry'];
  if (geometry is! Map) return null;
  final point = GeoPoint.fromLonLat(geometry['coordinates']);
  if (point == null) return null;

  final millis = _asInt(properties['timestampExternal']);
  if (millis == null) return null;

  // AIS uses 102.3 knots and 360 degrees as "not available" sentinels.
  final rawSpeed = _asDouble(properties['sog']);
  final speed = (rawSpeed == null || rawSpeed >= 102.3) ? 0.0 : rawSpeed;
  final rawCourse = _asDouble(properties['cog']);
  final course = (rawCourse == null || rawCourse >= 360) ? 0.0 : rawCourse;

  final rawHeading = _asInt(properties['heading']);

  return VesselPosition(
    mmsi: mmsi,
    point: point,
    speedKnots: speed,
    courseDegrees: course,
    navigationStatus: navigationStatusFromCode(_asInt(properties['navStat'])),
    reportedAt: DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
    headingDegrees: (rawHeading == null || rawHeading > 359)
        ? null
        : rawHeading,
  );
}

/// Parses the `vessels` metadata array into [Vessel]s keyed by MMSI.
Map<int, Vessel> parseVessels(Object? json) {
  if (json is! List) return const <int, Vessel>{};

  final vessels = <int, Vessel>{};
  for (final entry in json) {
    if (entry is! Map) continue;
    final mmsi = _asInt(entry['mmsi']);
    if (mmsi == null) continue;

    final dimensions = vesselDimensions(
      referencePointA: _asDouble(entry['referencePointA']),
      referencePointB: _asDouble(entry['referencePointB']),
      referencePointC: _asDouble(entry['referencePointC']),
      referencePointD: _asDouble(entry['referencePointD']),
    );

    final name = (entry['name'] as Object?)?.toString().trim() ?? '';

    vessels[mmsi] = Vessel(
      mmsi: mmsi,
      name: name.isEmpty ? 'MMSI $mmsi' : name,
      shipTypeCode: _asInt(entry['shipType']) ?? 0,
      callSign: _emptyToNull(entry['callSign']),
      imo: _asInt(entry['imo']),
      destination: _emptyToNull(entry['destination']),
      draughtMetres: draughtMetresFromAis(_asDouble(entry['draught'])),
      lengthMetres: dimensions.lengthMetres,
      beamMetres: dimensions.beamMetres,
      eta: decodeAisEta(_asInt(entry['eta'])),
    );
  }
  return vessels;
}

/// Parses the `ssnLocations` FeatureCollection into the port directory.
///
/// Many entries carry `"geometry": null` — inland UN/LOCODE places that are
/// not seaports. Those are kept but left without a position, and the corridor
/// linker filters them out.
List<Port> parsePorts(Object? json) {
  if (json is! Map) return const <Port>[];
  final locations = json['ssnLocations'];
  if (locations is! Map) return const <Port>[];
  final features = locations['features'];
  if (features is! List) return const <Port>[];

  final ports = <Port>[];
  for (final feature in features) {
    if (feature is! Map) continue;
    final properties = feature['properties'];
    if (properties is! Map) continue;

    final locode = _emptyToNull(properties['locode'] ?? feature['locode']);
    if (locode == null) continue;

    final geometry = feature['geometry'];
    final point = geometry is Map
        ? GeoPoint.fromLonLat(geometry['coordinates'])
        : null;

    ports.add(
      Port(
        locode: locode,
        name: _emptyToNull(properties['locationName']) ?? locode,
        country: _emptyToNull(properties['country']),
        point: point,
      ),
    );
  }
  return ports;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.isFinite ? value.toInt() : null;
  if (value is String) return int.tryParse(value);
  return null;
}

double? _asDouble(Object? value) {
  if (value is num) return value.isFinite ? value.toDouble() : null;
  if (value is String) return double.tryParse(value);
  return null;
}

String? _emptyToNull(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
