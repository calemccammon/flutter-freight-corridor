import 'package:flutter_test/flutter_test.dart';
import 'package:freight_core/freight_core.dart';
import 'package:freight_corridor/data/freight_repository.dart';
import 'package:freight_corridor/data/marine_data_source.dart';
import 'package:freight_corridor/data/rail_data_source.dart';
import 'package:mocktail/mocktail.dart';

class _MockRail extends Mock implements RailDataSource {}

class _MockMarine extends Mock implements MarineDataSource {}

final _now = DateTime.utc(2026, 8, 15, 12);

FreightTrain _trainTo(String station, GeoPoint location) => FreightTrain(
  trainNumber: 3425,
  departureDate: '2026-08-15',
  operatorShortCode: 'vr',
  operatorName: 'VR-Yhtymä Oyj',
  trainTypeName: 'T',
  runningCurrently: true,
  position: const GeoPoint(latitude: 60.9, longitude: 26.9),
  speedKmh: 68,
  stops: <TimetableStop>[
    TimetableStop(
      stationName: station,
      stationShortCode: 'KTMU',
      type: StopType.arrival,
      scheduledTime: _now.add(const Duration(hours: 1)),
      stationLocation: location,
    ),
  ],
);

void main() {
  late _MockRail rail;
  late _MockMarine marine;
  late FreightRepository repository;

  // mocktail needs a concrete instance before `any(named: 'centre')` can
  // stand in for a non-nullable GeoPoint.
  setUpAll(() {
    registerFallbackValue(const GeoPoint(latitude: 0, longitude: 0));
  });

  setUp(() {
    rail = _MockRail();
    marine = _MockMarine();
    repository = FreightRepository(rail: rail, marine: marine);
    when(() => marine.staleSince).thenReturn(null);
  });

  group('error handling', () {
    test('collapses a rail transport failure into FreightException', () async {
      when(rail.cargoTrains)
          .thenThrow(const RailRequestException('Validation error'));

      await expectLater(
        repository.cargoTrains(),
        throwsA(
          isA<FreightException>()
              .having((e) => e.message, 'message', contains('cargo trains'))
              .having((e) => e.detail, 'detail', contains('Validation error')),
        ),
      );
    });

    test(
      'collapses a marine transport failure into FreightException',
      () async {
        when(
          marine.portCalls,
        ).thenThrow(const MarineRequestException('Digitraffic answered 503'));

        // The UI handles one exception type; it never learns that one half of
        // the app speaks GraphQL and the other speaks REST.
        await expectLater(
          repository.portCalls(),
          throwsA(isA<FreightException>()),
        );
      },
    );
  });

  group('freightVesselsNear', () {
    test('joins positions to vessel details and drops non-freight', () async {
      when(
        () => marine.vesselPositions(
          centre: any(named: 'centre'),
          radiusKm: any(named: 'radiusKm'),
        ),
      ).thenAnswer(
        (_) async => <VesselPosition>[
          _position(1),
          _position(2),
          _position(3), // no matching detail record
        ],
      );
      when(marine.vessels).thenAnswer(
        (_) async => <int, Vessel>{
          1: const Vessel(mmsi: 1, name: 'CARGO ONE', shipTypeCode: 70),
          2: const Vessel(mmsi: 2, name: 'FERRY', shipTypeCode: 60),
        },
      );

      final result = await repository.freightVesselsNear(
        centre: const GeoPoint(latitude: 60, longitude: 24),
        radiusKm: 50,
      );

      expect(result.value.map((tracked) => tracked.mmsi), <int>[1]);
      expect(result.freshness, Freshness.live);
      expect(result.isStale, isFalse);
    });

    test('reports cached data as stale with its capture time', () async {
      final captured = _now.subtract(const Duration(minutes: 4));
      when(() => marine.staleSince).thenReturn(captured);
      when(
        () => marine.vesselPositions(
          centre: any(named: 'centre'),
          radiusKm: any(named: 'radiusKm'),
        ),
      ).thenAnswer((_) async => <VesselPosition>[_position(1)]);
      when(marine.vessels).thenAnswer(
        (_) async => <int, Vessel>{
          1: const Vessel(mmsi: 1, name: 'CARGO ONE', shipTypeCode: 70),
        },
      );

      final result = await repository.freightVesselsNear(
        centre: const GeoPoint(latitude: 60, longitude: 24),
        radiusKm: 50,
      );

      expect(result.isStale, isTrue);
      expect(result.capturedAt, captured);
    });
  });

  group('corridors', () {
    test('pairs rail with sea and ignores LOCODEs no ship visits', () async {
      const kotka = GeoPoint(latitude: 60.4664, longitude: 26.9458);

      when(rail.cargoTrains).thenAnswer(
        (_) async => <FreightTrain>[
          _trainTo(
            'Kotka Mussalo',
            const GeoPoint(latitude: 60.53, longitude: 26.93),
          ),
        ],
      );
      when(marine.ports).thenAnswer(
        (_) async => const <Port>[
          Port(locode: 'FIKTK', name: 'Kotka', point: kotka),
          // A lakeside town that happens to sit near the same terminus but
          // receives no vessels at all.
          Port(
            locode: 'FILAK',
            name: 'Lakeside',
            point: GeoPoint(latitude: 60.54, longitude: 26.94),
          ),
        ],
      );
      when(marine.portCalls).thenAnswer(
        (_) async => <PortCall>[
          PortCall(
            portCallId: 1,
            portToVisit: 'FIKTK',
            vesselName: 'CARGO ONE',
            cargoIntent: CargoIntent.discharging,
            visits: <PortAreaVisit>[
              PortAreaVisit(eta: _now.add(const Duration(hours: 5))),
            ],
          ),
        ],
      );
      when(
        () => marine.vesselPositions(
          centre: any(named: 'centre'),
          radiusKm: any(named: 'radiusKm'),
        ),
      ).thenAnswer((_) async => const <VesselPosition>[]);
      when(marine.vessels).thenAnswer((_) async => const <int, Vessel>{});

      final corridors = await repository.corridors(now: _now);

      expect(corridors, hasLength(1));
      expect(corridors.single.port.locode, 'FIKTK');
      expect(corridors.single.terminusName, 'Kotka Mussalo');
      expect(corridors.single.upcomingCalls, hasLength(1));
    });
  });
}

VesselPosition _position(int mmsi) => VesselPosition(
  mmsi: mmsi,
  point: const GeoPoint(latitude: 60.1, longitude: 24.9),
  speedKnots: 8,
  courseDegrees: 90,
  navigationStatus: NavigationStatus.underWayUsingEngine,
  reportedAt: _now,
);
