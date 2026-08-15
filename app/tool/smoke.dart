// Throwaway live smoke test: proves the data layer maps real responses.
// Not part of the app or the test suite.
import 'package:ferry/ferry.dart';
import 'package:freight_corridor/data/freight_repository.dart';
import 'package:freight_corridor/data/marine_data_source.dart';
import 'package:freight_corridor/data/rail_data_source.dart';
import 'package:freight_core/freight_core.dart';
import 'package:gql_http_link/gql_http_link.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final httpClient = http.Client();
  final link = HttpLink(
    'https://rata.digitraffic.fi/api/v2/graphql/graphql',
    defaultHeaders: const {
      'Digitraffic-User': 'calemccammon/flutter-freight-corridor',
      'Accept-Encoding': 'gzip',
    },
    httpClient: httpClient,
  );

  final repository = FreightRepository(
    rail: RailDataSource(Client(link: link, cache: Cache())),
    marine: MarineDataSource(httpClient),
  );

  final trains = await repository.cargoTrains();
  print('CARGO TRAINS: ${trains.length}');
  for (final train in trains.take(3)) {
    print(
      '  #${train.trainNumber} ${train.operatorShortCode} '
      '${train.speedKmh?.toStringAsFixed(0)}km/h  pos=${train.position} '
      'stops=${train.stops.length} terminus=${train.terminus?.stationName} '
      'termLoc=${train.terminus?.stationLocation} delay=${train.worstDelay}',
    );
  }

  const helsinki = GeoPoint(latitude: 60.1719, longitude: 24.9414);
  final vessels = await repository.freightVesselsNear(
    centre: helsinki,
    radiusKm: 100,
  );
  print('FREIGHT VESSELS within 100km: ${vessels.value.length}');
  for (final tracked in vessels.value.take(3)) {
    print(
      '  ${tracked.vessel.name} (${tracked.vessel.category.label}) '
      '${tracked.position.speedKnots}kn ${tracked.position.point} '
      'len=${tracked.vessel.lengthMetres}m',
    );
  }

  final calls = await repository.portCalls();
  print('PORT CALLS: ${calls.value.length}');
  for (final call in calls.value.take(3)) {
    print(
      '  ${call.vesselName} -> ${call.portToVisit} '
      '${call.cargoIntent.label} eta=${call.eta} delay=${call.arrivalDelayMinutes}',
    );
  }

  final ports = await repository.ports();
  final located = ports.value.where((p) => p.isFinnish && p.point != null);
  print(
    'PORTS: ${ports.value.length} (Finnish with coords: ${located.length})',
  );

  final corridors = await repository.corridors();
  print('CORRIDORS: ${corridors.length}');
  for (final corridor in corridors.take(5)) {
    print(
      '  ${corridor.port.name} <- ${corridor.terminusName} '
      '${corridor.distanceKm.toStringAsFixed(1)}km ${corridor.compassLabel} '
      'trains=${corridor.inboundTrains.length} '
      'vessels=${corridor.vesselsAtPort.length} '
      'calls=${corridor.upcomingCalls.length} intensity=${corridor.intensity}',
    );
  }

  httpClient.close();
}
