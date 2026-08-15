import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:freight_core/freight_core.dart';
import 'package:freight_corridor/data/marine_data_source.dart';
import 'package:freight_corridor/data/snapshot_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Shaped like a real /api/ais/v1/locations response.
const _locations = <String, Object?>{
  'type': 'FeatureCollection',
  'features': <Object?>[
    <String, Object?>{
      'mmsi': 230108610,
      'geometry': <String, Object?>{
        'type': 'Point',
        'coordinates': <num>[24.95591, 60.167298],
      },
      'properties': <String, Object?>{
        'mmsi': 230108610,
        'sog': 12.4,
        'cog': 15.3,
        'navStat': 0,
        'timestamp': 53,
        'timestampExternal': 1786810612872,
      },
    },
  ],
};

const _portCalls = <String, Object?>{
  'portCalls': <Object?>[
    <String, Object?>{
      'portCallId': 3319468,
      'portToVisit': 'FIKTK',
      'prevPort': 'SEGRH',
      'vesselName': 'Eckerö',
      'mmsi': 230108610,
      'arrivalWithCargo': true,
      'notLoading': false,
      'discharge': 1,
      'portAreaDetails': <Object?>[
        <String, Object?>{
          'berthName': 'Mussalo',
          'eta': '2026-08-15T10:00:00.000Z',
          'ata': '2026-08-15T10:35:00.000Z',
          'arrivalDraught': 7.4,
        },
      ],
    },
  ],
};

void main() {
  group('MarineDataSource', () {
    test('sends the Digitraffic-User header and the radius query', () async {
      Uri? seen;
      Map<String, String>? headers;

      final source = MarineDataSource(
        MockClient((request) async {
          seen = request.url;
          headers = request.headers;
          return http.Response(jsonEncode(_locations), 200);
        }),
      );

      await source.vesselPositions(
        centre: const GeoPoint(latitude: 60.1719, longitude: 24.9414),
        radiusKm: 25,
      );

      expect(headers!['Digitraffic-User'], isNotEmpty);
      expect(seen!.path, '/api/ais/v1/locations');
      expect(seen!.queryParameters['radius'], '25');
      expect(seen!.queryParameters['latitude'], '60.17190');
    });

    test('parses AIS positions into core models', () async {
      final source = MarineDataSource(
        MockClient((_) async => http.Response(jsonEncode(_locations), 200)),
      );

      final positions = await source.vesselPositions(
        centre: const GeoPoint(latitude: 60, longitude: 24),
        radiusKm: 10,
      );

      expect(positions, hasLength(1));
      expect(positions.single.mmsi, 230108610);
      expect(positions.single.point.latitude, closeTo(60.167298, 1e-9));
      expect(positions.single.reportedAt.year, 2026);
    });

    test('derives cargo intent and berth times from a port call', () async {
      // Sent as bytes: `http.Response(String, ...)` would encode the body as
      // Latin-1, which is exactly the mojibake this data source guards against.
      final source = MarineDataSource(
        MockClient(
          (_) async =>
              http.Response.bytes(utf8.encode(jsonEncode(_portCalls)), 200),
        ),
      );

      final calls = await source.portCalls();
      final call = calls.single;

      expect(call.vesselName, 'Eckerö'); // UTF-8 survived the round trip
      expect(call.cargoIntent, CargoIntent.both);
      expect(call.arrivalDelayMinutes, 35);
      expect(call.visits.single.berthName, 'Mussalo');
    });

    test('decodes UTF-8 rather than falling back to Latin-1', () async {
      final source = MarineDataSource(
        MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(jsonEncode(_portCalls)),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      );

      final calls = await source.portCalls();
      expect(calls.single.vesselName, 'Eckerö');
    });

    test('falls back to the cached snapshot when the network fails', () async {
      final store = InMemorySnapshotStore();
      var shouldFail = false;

      final source = MarineDataSource(
        MockClient((_) async {
          if (shouldFail) throw const SocketFailure();
          return http.Response(jsonEncode(_locations), 200);
        }),
        cache: store,
      );

      // Warm the cache from a good response.
      final live = await source.vesselPositions(
        centre: const GeoPoint(latitude: 60, longitude: 24),
        radiusKm: 10,
      );
      expect(live, hasLength(1));
      expect(source.staleSince, isNull);

      shouldFail = true;
      final cached = await source.vesselPositions(
        centre: const GeoPoint(latitude: 60, longitude: 24),
        radiusKm: 10,
      );

      expect(cached, hasLength(1), reason: 'served from the snapshot store');
      expect(source.staleSince, isNotNull, reason: 'and marked as stale');
    });

    test('throws when the network fails and nothing is cached', () async {
      final source = MarineDataSource(
        MockClient((_) async => throw const SocketFailure()),
        cache: InMemorySnapshotStore(),
      );

      expect(() => source.portCalls(), throwsA(isA<MarineRequestException>()));
    });

    test('treats a non-200 as a failure', () async {
      final source = MarineDataSource(
        MockClient((_) async => http.Response('nope', 503)),
      );

      expect(
        () => source.portCalls(),
        throwsA(
          isA<MarineRequestException>().having(
            (error) => error.message,
            'message',
            contains('503'),
          ),
        ),
      );
    });
  });
}

/// Stands in for a dropped connection.
class SocketFailure implements Exception {
  const SocketFailure();
}
