import 'package:freight_core/freight_core.dart';
import 'package:test/test.dart';

// Helsinki Central and Tampere Central, the busiest corridor on the Finnish
// network. The real great-circle distance is about 161 km.
const helsinki = GeoPoint(latitude: 60.1719, longitude: 24.9414);
const tampere = GeoPoint(latitude: 61.4981, longitude: 23.7608);

void main() {
  group('haversineKm', () {
    test('returns the known Helsinki to Tampere distance', () {
      expect(haversineKm(helsinki, tampere), closeTo(161, 2));
    });

    test('is zero for a point against itself and is symmetric', () {
      expect(haversineKm(helsinki, helsinki), closeTo(0, 0.0001));
      expect(
        haversineKm(helsinki, tampere),
        closeTo(haversineKm(tampere, helsinki), 0.0001),
      );
    });
  });

  group('initialBearingDegrees', () {
    test('points north-north-west from Helsinki to Tampere', () {
      final bearing = initialBearingDegrees(helsinki, tampere);
      expect(bearing, closeTo(337, 1));
      expect(compassPoint(bearing), 'NNW');
    });

    test('resolves cardinal directions', () {
      const origin = GeoPoint(latitude: 0, longitude: 0);
      expect(
        initialBearingDegrees(
          origin,
          const GeoPoint(latitude: 10, longitude: 0),
        ),
        closeTo(0, 0.001),
      );
      expect(
        initialBearingDegrees(
          origin,
          const GeoPoint(latitude: 0, longitude: 10),
        ),
        closeTo(90, 0.001),
      );
    });
  });

  group('compassPoint', () {
    test('maps bearings to 16-point labels and wraps around 360', () {
      expect(compassPoint(0), 'N');
      expect(compassPoint(90), 'E');
      expect(compassPoint(202.5), 'SSW');
      expect(compassPoint(360), 'N');
      expect(compassPoint(-90), 'W');
    });
  });

  group('GeoPoint.fromLonLat', () {
    test('reads [longitude, latitude] in that order', () {
      // Straight from a live rail API response for train 3425.
      final point = GeoPoint.fromLonLat(<num>[24.103782, 61.555433]);
      expect(point, isNotNull);
      expect(point!.latitude, closeTo(61.555433, 1e-9));
      expect(point.longitude, closeTo(24.103782, 1e-9));
    });

    test('rejects malformed and out-of-range pairs', () {
      expect(GeoPoint.fromLonLat(null), isNull);
      expect(GeoPoint.fromLonLat(<num>[24.1]), isNull);
      expect(GeoPoint.fromLonLat('nope'), isNull);
      // Latitude beyond the poles means a corrupt record, not a real place.
      expect(GeoPoint.fromLonLat(<num>[24.1, 91]), isNull);
    });
  });

  test('knots and km/h convert both ways', () {
    expect(knotsToKmh(10), closeTo(18.52, 0.001));
    expect(kmhToKnots(18.52), closeTo(10, 0.001));
  });
}
