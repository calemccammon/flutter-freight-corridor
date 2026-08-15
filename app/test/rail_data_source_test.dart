import 'package:ferry/ferry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freight_core/freight_core.dart';
import 'package:freight_corridor/data/rail_data_source.dart';
import 'package:gql_exec/gql_exec.dart' as gql;

/// A GraphQL response shaped exactly like the live rail API's, including the
/// `__typename` fields ferry adds to every selection set.
///
/// Driving a real ferry `Client` through a fake `Link` means the generated
/// built_value deserialisers actually run, so this test fails if the committed
/// schema, the .graphql document and the mapping code ever disagree — which a
/// hand-rolled mock of the data source could never catch.
const _cargoTrainsResponse = <String, dynamic>{
  'currentlyRunningTrains': <dynamic>[
    <String, dynamic>{
      '__typename': 'Train',
      'trainNumber': 3425,
      'departureDate': '2026-08-15',
      'runningCurrently': true,
      'operator': <String, dynamic>{
        '__typename': 'Operator',
        'shortCode': 'vr',
        'name': 'VR-Yhtymä Oyj',
      },
      'trainType': <String, dynamic>{'__typename': 'TrainType', 'name': 'T'},
      'trainLocations': <dynamic>[
        <String, dynamic>{
          '__typename': 'TrainLocation',
          'speed': 68,
          'timestamp': '2026-08-15T16:17:10.000Z',
          'location': <double>[24.103782, 61.555433],
        },
      ],
      'timeTableRows': <dynamic>[
        <String, dynamic>{
          '__typename': 'TimeTableRow',
          'type': 'DEPARTURE',
          'scheduledTime': '2026-08-15T15:57:00.000Z',
          'actualTime': '2026-08-15T15:50:45.000Z',
          'differenceInMinutes': -6,
          'cancelled': false,
          'station': <String, dynamic>{
            '__typename': 'Station',
            'name': 'Tampere Viinikka',
            'shortCode': 'TPEV',
            'location': <double>[23.7608, 61.4981],
          },
        },
        <String, dynamic>{
          '__typename': 'TimeTableRow',
          'type': 'ARRIVAL',
          'scheduledTime': '2026-08-15T17:30:00.000Z',
          'actualTime': null,
          'differenceInMinutes': 12,
          'cancelled': false,
          'station': <String, dynamic>{
            '__typename': 'Station',
            'name': 'Kotka Mussalo',
            'shortCode': 'KTMU',
            'location': <double>[26.9300, 60.5300],
          },
        },
      ],
    },
  ],
};

/// Returns a canned payload for any request, without touching the network.
class _FakeLink extends Link {
  _FakeLink(this.data, {this.errors});

  final Map<String, dynamic>? data;
  final List<gql.GraphQLError>? errors;

  @override
  Stream<gql.Response> request(
    gql.Request request, [
    NextLink? forward,
  ]) async* {
    yield gql.Response(
      data: data,
      errors: errors,
      response: const <String, dynamic>{},
    );
  }
}

RailDataSource _sourceReturning(
  Map<String, dynamic>? data, {
  List<gql.GraphQLError>? errors,
}) {
  return RailDataSource(
    Client(
      link: _FakeLink(data, errors: errors),
      cache: Cache(),
    ),
  );
}

void main() {
  group('RailDataSource', () {
    test('maps a GraphQL response onto FreightTrain models', () async {
      final trains = await _sourceReturning(_cargoTrainsResponse).cargoTrains();

      expect(trains, hasLength(1));
      final train = trains.single;
      expect(train.trainNumber, 3425);
      expect(train.operatorShortCode, 'vr');
      expect(train.operatorName, 'VR-Yhtymä Oyj');
      expect(train.speedKmh, 68);
      expect(train.isMoving, isTrue);
      expect(train.id, '3425/2026-08-15');
    });

    test(
      'reads train and station positions as [longitude, latitude]',
      () async {
        final train = (await _sourceReturning(
          _cargoTrainsResponse,
        ).cargoTrains()).single;

        // The API sends [24.103782, 61.555433]; latitude is the second element.
        expect(train.position!.latitude, closeTo(61.555433, 1e-9));
        expect(train.position!.longitude, closeTo(24.103782, 1e-9));

        expect(train.terminus!.stationName, 'Kotka Mussalo');
        expect(train.terminus!.stationLocation!.latitude, closeTo(60.53, 1e-9));
      },
    );

    test('carries timetable rows, delay status and stop direction', () async {
      final train = (await _sourceReturning(
        _cargoTrainsResponse,
      ).cargoTrains()).single;

      expect(train.stops, hasLength(2));
      expect(train.origin!.type, StopType.departure);
      expect(train.origin!.delayStatus, DelayStatus.early);
      expect(train.origin!.hasPassed, isTrue);

      // The arrival has not happened yet, so it is the next stop.
      expect(train.nextStop!.stationName, 'Kotka Mussalo');
      expect(train.worstDelay, 12);
      expect(train.delayStatus, DelayStatus.minor);
    });

    test(
      'returns an empty list rather than throwing on a null payload',
      () async {
        final trains = await _sourceReturning(const <String, dynamic>{
          'currentlyRunningTrains': <dynamic>[],
        }).cargoTrains();
        expect(trains, isEmpty);
      },
    );

    test('maps a train detail response including wagon composition', () async {
      final source = _sourceReturning(_trainDetailResponse);
      final train = await source.trainDetail(
        trainNumber: 3425,
        departureDate: '2026-08-15',
      );

      expect(train, isNotNull);
      final composition = train!.composition!;
      expect(composition.wagonCount, 3);
      expect(composition.locomotiveCount, 1);
      expect(composition.dominantWagonType, 'Sim');
      expect(composition.isElectricHauled, isTrue);
      // Wagon length arrives in centimetres and is normalised to metres.
      expect(composition.sections.single.wagons.first.lengthMetres, 20.5);
    });

    test('returns null when no train matches', () async {
      final train = await _sourceReturning(const <String, dynamic>{
        'train': <dynamic>[],
      }).trainDetail(trainNumber: 1, departureDate: '2026-08-15');
      expect(train, isNull);
    });
  });
}

const _trainDetailResponse = <String, dynamic>{
  'train': <dynamic>[
    <String, dynamic>{
      '__typename': 'Train',
      'trainNumber': 3425,
      'departureDate': '2026-08-15',
      'runningCurrently': true,
      'operator': <String, dynamic>{
        '__typename': 'Operator',
        'shortCode': 'vr',
        'name': 'VR-Yhtymä Oyj',
      },
      'trainType': <String, dynamic>{'__typename': 'TrainType', 'name': 'T'},
      'trainLocations': <dynamic>[],
      'timeTableRows': <dynamic>[],
      'compositions': <dynamic>[
        <String, dynamic>{
          '__typename': 'Composition',
          'journeySections': <dynamic>[
            <String, dynamic>{
              '__typename': 'JourneySection',
              'maximumSpeed': 100,
              'totalLength': 220,
              'wagons': <dynamic>[
                <String, dynamic>{
                  '__typename': 'Wagon',
                  'salesNumber': 1,
                  'length': 2050,
                  'wagonType': 'Sim',
                },
                <String, dynamic>{
                  '__typename': 'Wagon',
                  'salesNumber': 2,
                  'length': 2050,
                  'wagonType': 'Sim',
                },
                <String, dynamic>{
                  '__typename': 'Wagon',
                  'salesNumber': 3,
                  'length': 2050,
                  'wagonType': 'Hkbi',
                },
              ],
              'locomotives': <dynamic>[
                <String, dynamic>{
                  '__typename': 'Locomotive',
                  'locomotiveType': 'Sr2',
                  'powerTypeAbbreviation': 'S',
                },
              ],
            },
          ],
        },
      ],
    },
  ],
};
