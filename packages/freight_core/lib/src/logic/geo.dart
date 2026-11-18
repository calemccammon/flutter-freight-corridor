import 'dart:math' as math;

import '../models/geo_point.dart';

const double _earthRadiusKm = 6371.0088;

double _toRadians(double degrees) => degrees * math.pi / 180;

double _toDegrees(double radians) => radians * 180 / math.pi;

/// Great-circle distance between two points, in kilometres.
///
/// Used to pair a rail terminus with its nearest seaport and to decide which
/// vessels count as "serving" a port.
double haversineKm(GeoPoint from, GeoPoint to) {
  final dLat = _toRadians(to.latitude - from.latitude);
  final dLon = _toRadians(to.longitude - from.longitude);
  final lat1 = _toRadians(from.latitude);
  final lat2 = _toRadians(to.latitude);

  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.pow(math.sin(dLon / 2), 2) * math.cos(lat1) * math.cos(lat2);
  return 2 * _earthRadiusKm * math.asin(math.min(1, math.sqrt(a)));
}

/// Initial bearing from [from] to [to], normalised to 0-360 degrees.
double initialBearingDegrees(GeoPoint from, GeoPoint to) {
  final lat1 = _toRadians(from.latitude);
  final lat2 = _toRadians(to.latitude);
  final dLon = _toRadians(to.longitude - from.longitude);

  final y = math.sin(dLon) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  return (_toDegrees(math.atan2(y, x)) + 360) % 360;
}

/// Circular mean of [bearings], normalised to 0-360 degrees.
///
/// Bearings wrap at north, so an arithmetic mean is wrong: 350 and 10 would
/// average to 180, due south, when both point within ten degrees of north.
/// Each bearing is treated as a unit vector and the vectors are summed.
/// Returns 0 for an empty input.
double meanBearingDegrees(Iterable<double> bearings) {
  var sumSin = 0.0;
  var sumCos = 0.0;
  var count = 0;
  for (final bearing in bearings) {
    final radians = _toRadians(bearing);
    sumSin += math.sin(radians);
    sumCos += math.cos(radians);
    count++;
  }
  if (count == 0) return 0;
  return (_toDegrees(math.atan2(sumSin, sumCos)) + 360) % 360;
}

const List<String> _compassPoints = <String>[
  'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', //
  'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
];

/// Converts a bearing to a 16-point compass label, e.g. `212` -> `SSW`.
String compassPoint(double bearingDegrees) {
  final normalised = (bearingDegrees % 360 + 360) % 360;
  final index = ((normalised / 22.5) + 0.5).floor() % 16;
  return _compassPoints[index];
}

/// AIS reports speed over ground in knots; the rail API uses km/h. Everything
/// downstream of the data layer speaks km/h so the two modes stay comparable.
double knotsToKmh(double knots) => knots * 1.852;

double kmhToKnots(double kmh) => kmh / 1.852;
