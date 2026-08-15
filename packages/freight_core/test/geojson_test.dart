import 'package:freight_core/freight_core.dart';
import 'package:test/test.dart';

void main() {
  group('parseVesselPositions', () {
    // Shaped exactly like a live /api/ais/v1/locations response.
    final feed = <String, Object?>{
      'type': 'FeatureCollection',
      'features': <Object?>[
        <String, Object?>{
          'mmsi': 230108610,
          'type': 'Feature',
          'geometry': <String, Object?>{
            'type': 'Point',
            'coordinates': <num>[24.95591, 60.167298],
          },
          'properties': <String, Object?>{
            'mmsi': 230108610,
            'sog': 12.4,
            'cog': 15.3,
            'navStat': 0,
            'heading': 356,
            'timestamp': 53,
            'timestampExternal': 1786810612872,
          },
        },
      ],
    };

    test('reads coordinates as [longitude, latitude]', () {
      final positions = parseVesselPositions(feed);
      expect(positions, hasLength(1));
      expect(positions.single.point.latitude, closeTo(60.167298, 1e-9));
      expect(positions.single.point.longitude, closeTo(24.95591, 1e-9));
    });

    test('uses timestampExternal, not the AIS second-of-minute field', () {
      // `timestamp: 53` is the 53rd second of the minute, not a time. Reading
      // it as one would place every vessel in January 1970.
      final position = parseVesselPositions(feed).single;
      expect(
        position.reportedAt,
        DateTime.fromMillisecondsSinceEpoch(1786810612872, isUtc: true),
      );
      expect(position.reportedAt.year, 2026);
    });

    test('normalises the not-available sentinels for speed and course', () {
      final sentinel = <String, Object?>{
        'features': <Object?>[
          <String, Object?>{
            'geometry': <String, Object?>{
              'coordinates': <num>[25.0, 60.0],
            },
            'properties': <String, Object?>{
              'mmsi': 1,
              'sog': 102.3,
              'cog': 360.0,
              'heading': 511,
              'timestampExternal': 1786810612872,
            },
          },
        ],
      };
      final position = parseVesselPositions(sentinel).single;
      expect(position.speedKnots, 0);
      expect(position.courseDegrees, 0);
      expect(position.headingDegrees, isNull);
      expect(position.isUnderWay, isFalse);
    });

    test('skips malformed features instead of throwing', () {
      final messy = <String, Object?>{
        'features': <Object?>[
          <String, Object?>{
            'properties': <String, Object?>{'mmsi': 1},
          }, // no geometry
          <String, Object?>{
            'geometry': <String, Object?>{'coordinates': null},
            'properties': <String, Object?>{'mmsi': 2, 'timestampExternal': 1},
          },
          <String, Object?>{
            'geometry': <String, Object?>{
              'coordinates': <num>[25.0, 60.0],
            },
            'properties': <String, Object?>{'timestampExternal': 1}, // no mmsi
          },
          'not a feature at all',
          ...feed['features']! as List<Object?>, // one good row
        ],
      };
      final positions = parseVesselPositions(messy);
      expect(positions, hasLength(1));
      expect(positions.single.mmsi, 230108610);
    });

    test('returns empty for structurally wrong input', () {
      expect(parseVesselPositions(null), isEmpty);
      expect(parseVesselPositions(<String, Object?>{}), isEmpty);
      expect(parseVesselPositions('nope'), isEmpty);
    });
  });

  group('parseVessels', () {
    test('builds vessels keyed by MMSI with derived dimensions', () {
      final vessels = parseVessels(<Object?>[
        <String, Object?>{
          'mmsi': 566453000,
          'name': 'EAGLE SAN ANTONIO',
          'callSign': '9V9330',
          'imo': 959482200,
          'shipType': 80,
          'destination': 'PLGDN',
          'draught': 147,
          'referencePointA': 227,
          'referencePointB': 47,
          'referencePointC': 28,
          'referencePointD': 21,
        },
      ]);

      final vessel = vessels[566453000]!;
      expect(vessel.name, 'EAGLE SAN ANTONIO');
      expect(vessel.category, ShipCategory.tanker);
      expect(vessel.isFreight, isTrue);
      expect(vessel.lengthMetres, 274);
      expect(vessel.beamMetres, 49);
      expect(vessel.draughtMetres, closeTo(14.7, 1e-9));
    });

    test('falls back to an MMSI label when the name is blank', () {
      final vessels = parseVessels(<Object?>[
        <String, Object?>{'mmsi': 12345, 'name': '   ', 'shipType': 70},
      ]);
      expect(vessels[12345]!.name, 'MMSI 12345');
    });
  });

  group('parsePorts', () {
    final payload = <String, Object?>{
      'ssnLocations': <String, Object?>{
        'features': <Object?>[
          <String, Object?>{
            'locode': 'FIKTK',
            'geometry': <String, Object?>{
              'coordinates': <num>[26.9458, 60.4664],
            },
            'properties': <String, Object?>{
              'locode': 'FIKTK',
              'locationName': 'Kotka',
              'country': 'Finland',
            },
          },
          <String, Object?>{
            'locode': 'DEHEN',
            'geometry': null, // inland LOCODE, no coordinates
            'properties': <String, Object?>{
              'locode': 'DEHEN',
              'locationName': 'Heilbronn',
              'country': 'Germany',
            },
          },
        ],
      },
    };

    test('parses ports and tolerates null geometry', () {
      final ports = parsePorts(payload);
      expect(ports, hasLength(2));

      final kotka = ports.firstWhere((port) => port.locode == 'FIKTK');
      expect(kotka.name, 'Kotka');
      expect(kotka.point!.latitude, closeTo(60.4664, 1e-9));
      expect(kotka.isFinnish, isTrue);

      final heilbronn = ports.firstWhere((port) => port.locode == 'DEHEN');
      expect(heilbronn.point, isNull);
      expect(heilbronn.isFinnish, isFalse);
    });
  });
}
