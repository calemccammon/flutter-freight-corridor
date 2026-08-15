import 'package:meta/meta.dart';

/// A WGS-84 coordinate.
///
/// Both Digitraffic APIs report positions as `[longitude, latitude]` — the
/// reverse of how coordinates are usually spoken and written. Rather than
/// leave that trap scattered across every call site, it is encoded once in
/// [GeoPoint.fromLonLat] and tested.
@immutable
class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});

  /// Builds a point from the `[lon, lat]` pair used by the GeoJSON AIS feed
  /// and by the rail API's `location` fields.
  ///
  /// Returns `null` when the pair is malformed, because both feeds
  /// occasionally emit positionless records and one bad row should never take
  /// down a whole response.
  static GeoPoint? fromLonLat(Object? pair) {
    if (pair is! List || pair.length < 2) return null;
    final lon = _toDouble(pair[0]);
    final lat = _toDouble(pair[1]);
    if (lon == null || lat == null) return null;
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    return GeoPoint(latitude: lat, longitude: lon);
  }

  static double? _toDouble(Object? value) {
    if (value is num) {
      final result = value.toDouble();
      return result.isFinite ? result : null;
    }
    if (value is String) return double.tryParse(value);
    return null;
  }

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() {
    final ns = latitude >= 0 ? 'N' : 'S';
    final ew = longitude >= 0 ? 'E' : 'W';
    return '${latitude.abs().toStringAsFixed(4)}°$ns, '
        '${longitude.abs().toStringAsFixed(4)}°$ew';
  }
}
