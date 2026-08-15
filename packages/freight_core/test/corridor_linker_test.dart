import 'package:freight_core/freight_core.dart';
import 'package:test/test.dart';

// Real coordinates: Kotka is a major Finnish cargo port; Oulu is 500 km north.
const kotka = Port(
  locode: 'FIKTK',
  name: 'Kotka',
  country: 'Finland',
  point: GeoPoint(latitude: 60.4664, longitude: 26.9458),
);
const oulu = Port(
  locode: 'FIOUL',
  name: 'Oulu',
  country: 'Finland',
  point: GeoPoint(latitude: 65.0121, longitude: 25.4651),
);
const rotterdam = Port(
  locode: 'NLRTM',
  name: 'Rotterdam',
  country: 'Netherlands',
  point: GeoPoint(latitude: 51.9244, longitude: 4.4777),
);

final now = DateTime.utc(2026, 8, 15, 12);

FreightTrain train({
  required int number,
  required String terminusName,
  required GeoPoint terminusLocation,
  GeoPoint? position,
}) {
  return FreightTrain(
    trainNumber: number,
    departureDate: '2026-08-15',
    operatorShortCode: 'vr',
    operatorName: 'VR-Yhtymä Oyj',
    trainTypeName: 'T',
    runningCurrently: true,
    position: position,
    speedKmh: 68,
    stops: <TimetableStop>[
      TimetableStop(
        stationName: 'Kouvola',
        stationShortCode: 'KV',
        type: StopType.departure,
        scheduledTime: now.subtract(const Duration(hours: 1)),
        actualTime: now.subtract(const Duration(hours: 1)),
        differenceInMinutes: 0,
      ),
      TimetableStop(
        stationName: terminusName,
        stationShortCode: 'TT',
        type: StopType.arrival,
        scheduledTime: now.add(const Duration(hours: 1)),
        stationLocation: terminusLocation,
      ),
    ],
  );
}

PortCall call(
  String locode, {
  required Duration inHours,
  bool arrived = false,
}) {
  return PortCall(
    portCallId: locode.hashCode + inHours.inHours,
    portToVisit: locode,
    vesselName: 'TEST VESSEL',
    cargoIntent: CargoIntent.discharging,
    visits: <PortAreaVisit>[
      PortAreaVisit(
        eta: now.add(inHours),
        ata: arrived ? now.add(inHours) : null,
      ),
    ],
  );
}

void main() {
  group('linkCorridors', () {
    test('pairs a rail terminus with the nearest port inside the radius', () {
      // A station 8 km from Kotka harbour.
      final corridors = linkCorridors(
        trains: <FreightTrain>[
          train(
            number: 3425,
            terminusName: 'Kotkan satama',
            terminusLocation: const GeoPoint(
              latitude: 60.5300,
              longitude: 26.9300,
            ),
            position: const GeoPoint(latitude: 60.8, longitude: 26.9),
          ),
        ],
        ports: <Port>[kotka, oulu, rotterdam],
        vesselPositions: const <VesselPosition>[],
        portCalls: const <PortCall>[],
        now: now,
      );

      expect(corridors, hasLength(1));
      expect(corridors.single.port.locode, 'FIKTK');
      expect(corridors.single.terminusName, 'Kotkan satama');
      expect(corridors.single.distanceKm, lessThan(20));
      // The train sits north of the port, so it approaches heading south.
      expect(corridors.single.compassLabel, anyOf('S', 'SSW', 'SSE'));
    });

    test('excludes a terminus with no port inside the radius', () {
      final corridors = linkCorridors(
        trains: <FreightTrain>[
          train(
            number: 1,
            terminusName: 'Pieksämäki',
            terminusLocation: const GeoPoint(
              latitude: 62.3000,
              longitude: 27.1500,
            ),
          ),
        ],
        ports: <Port>[kotka, oulu],
        vesselPositions: const <VesselPosition>[],
        portCalls: const <PortCall>[],
        now: now,
        radiusKm: 50,
      );
      expect(corridors, isEmpty);
    });

    test(
      'ignores foreign ports even when they are the nearest located one',
      () {
        // Rail never leaves the country, so a Dutch port must never anchor a
        // Finnish corridor.
        final corridors = linkCorridors(
          trains: <FreightTrain>[
            train(
              number: 2,
              terminusName: 'Near Rotterdam',
              terminusLocation: const GeoPoint(
                latitude: 51.93,
                longitude: 4.48,
              ),
            ),
          ],
          ports: <Port>[rotterdam],
          vesselPositions: const <VesselPosition>[],
          portCalls: const <PortCall>[],
          now: now,
        );
        expect(corridors, isEmpty);
      },
    );

    test('attaches nearby vessels and only genuinely inbound port calls', () {
      final corridors = linkCorridors(
        trains: <FreightTrain>[
          train(
            number: 3,
            terminusName: 'Kotkan satama',
            terminusLocation: const GeoPoint(
              latitude: 60.5300,
              longitude: 26.9300,
            ),
          ),
        ],
        ports: <Port>[kotka],
        vesselPositions: <VesselPosition>[
          VesselPosition(
            mmsi: 1,
            point: const GeoPoint(
              latitude: 60.47,
              longitude: 26.95,
            ), // at Kotka
            speedKnots: 0,
            courseDegrees: 0,
            navigationStatus: NavigationStatus.moored,
            reportedAt: now,
          ),
          VesselPosition(
            mmsi: 2,
            point: const GeoPoint(latitude: 59.44, longitude: 24.75), // Tallinn
            speedKnots: 12,
            courseDegrees: 0,
            navigationStatus: NavigationStatus.underWayUsingEngine,
            reportedAt: now,
          ),
        ],
        portCalls: <PortCall>[
          call('FIKTK', inHours: const Duration(hours: 6)), // inbound
          call('FIKTK', inHours: const Duration(hours: 40)), // beyond window
          call(
            'FIKTK',
            inHours: const Duration(hours: 2),
            arrived: true,
          ), // already in
          call('FIOUL', inHours: const Duration(hours: 3)), // different port
        ],
        now: now,
      );

      final corridor = corridors.single;
      expect(corridor.vesselsAtPort.map((v) => v.mmsi), <int>[1]);
      expect(corridor.upcomingCalls, hasLength(1));
      expect(corridor.cargoMovingCalls, 1);
    });

    test('orders corridors by how much is moving through them', () {
      final corridors = linkCorridors(
        trains: <FreightTrain>[
          train(
            number: 10,
            terminusName: 'Oulun satama',
            terminusLocation: const GeoPoint(
              latitude: 65.0121,
              longitude: 25.4651,
            ),
          ),
          train(
            number: 11,
            terminusName: 'Kotkan satama',
            terminusLocation: const GeoPoint(
              latitude: 60.5300,
              longitude: 26.9300,
            ),
          ),
          train(
            number: 12,
            terminusName: 'Kotkan satama',
            terminusLocation: const GeoPoint(
              latitude: 60.5300,
              longitude: 26.9300,
            ),
          ),
        ],
        ports: <Port>[kotka, oulu],
        vesselPositions: const <VesselPosition>[],
        portCalls: const <PortCall>[],
        now: now,
      );

      expect(corridors.map((c) => c.port.locode), <String>['FIKTK', 'FIOUL']);
      expect(corridors.first.inboundTrains, hasLength(2));
      expect(corridors.first.intensity, greaterThan(corridors.last.intensity));
    });

    test('returns nothing when no port has coordinates', () {
      final corridors = linkCorridors(
        trains: <FreightTrain>[
          train(
            number: 4,
            terminusName: 'Kotkan satama',
            terminusLocation: const GeoPoint(latitude: 60.53, longitude: 26.93),
          ),
        ],
        ports: const <Port>[Port(locode: 'FIXXX', name: 'Unknown')],
        vesselPositions: const <VesselPosition>[],
        portCalls: const <PortCall>[],
        now: now,
      );
      expect(corridors, isEmpty);
    });
  });

  group('CargoIntent', () {
    test('derives intent from the three weakly-named API flags', () {
      expect(
        CargoIntent.from(
          arrivalWithCargo: true,
          notLoading: true,
          discharge: 1,
        ),
        CargoIntent.discharging,
      );
      expect(
        CargoIntent.from(arrivalWithCargo: false, notLoading: false),
        CargoIntent.loading,
      );
      expect(
        CargoIntent.from(
          arrivalWithCargo: true,
          notLoading: false,
          discharge: 1,
        ),
        CargoIntent.both,
      );
      expect(
        CargoIntent.from(arrivalWithCargo: false, notLoading: true),
        CargoIntent.ballast,
      );
      expect(CargoIntent.from(), CargoIntent.unknown);
    });

    test('knows which intents actually move cargo across the quay', () {
      expect(CargoIntent.both.movesCargo, isTrue);
      expect(CargoIntent.ballast.movesCargo, isFalse);
      expect(CargoIntent.unknown.movesCargo, isFalse);
    });
  });

  group('PortCall timing', () {
    test(
      'computes arrival delay only once the vessel has actually arrived',
      () {
        final late = PortCall(
          portCallId: 1,
          portToVisit: 'FIKTK',
          vesselName: 'X',
          cargoIntent: CargoIntent.discharging,
          visits: <PortAreaVisit>[
            PortAreaVisit(eta: now, ata: now.add(const Duration(minutes: 35))),
          ],
        );
        expect(late.arrivalDelayMinutes, 35);
        expect(late.hasArrived, isTrue);
        expect(
          late.isInboundWithin(const Duration(hours: 24), now: now),
          isFalse,
        );

        final pending = PortCall(
          portCallId: 2,
          portToVisit: 'FIKTK',
          vesselName: 'Y',
          cargoIntent: CargoIntent.loading,
          visits: <PortAreaVisit>[
            PortAreaVisit(eta: now.add(const Duration(hours: 3))),
          ],
        );
        expect(pending.arrivalDelayMinutes, isNull);
        expect(
          pending.isInboundWithin(const Duration(hours: 24), now: now),
          isTrue,
        );
      },
    );
  });

  group('WagonComposition', () {
    test('aggregates wagons, length and dominant type across sections', () {
      const composition = WagonComposition(
        sections: <JourneySection>[
          JourneySection(
            maximumSpeedKmh: 100,
            totalLengthMetres: 220,
            locomotives: <Locomotive>[
              Locomotive(locomotiveType: 'Sr2', powerType: 'S'),
            ],
            wagons: <Wagon>[
              Wagon(salesNumber: 1, lengthMetres: 20, wagonType: 'Sim'),
              Wagon(salesNumber: 2, lengthMetres: 20, wagonType: 'Sim'),
              Wagon(salesNumber: 3, lengthMetres: 20, wagonType: 'Hkbi'),
            ],
          ),
          JourneySection(
            maximumSpeedKmh: 80,
            totalLengthMetres: 100,
            locomotives: <Locomotive>[],
            wagons: <Wagon>[
              Wagon(salesNumber: 4, lengthMetres: 20, wagonType: 'Sim'),
            ],
          ),
        ],
      );

      expect(composition.wagonCount, 4);
      expect(composition.locomotiveCount, 1);
      expect(composition.totalLengthMetres, 320);
      expect(composition.dominantWagonType, 'Sim');
      // A train is limited by its slowest section.
      expect(composition.maximumSpeedKmh, 80);
      expect(composition.isElectricHauled, isTrue);
    });

    test('handles an empty composition without dividing by zero', () {
      const empty = WagonComposition(sections: <JourneySection>[]);
      expect(empty.wagonCount, 0);
      expect(empty.maximumSpeedKmh, isNull);
      expect(empty.dominantWagonType, isNull);
    });
  });
}
