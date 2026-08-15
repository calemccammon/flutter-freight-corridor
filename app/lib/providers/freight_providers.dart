import 'package:ferry/ferry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freight_core/freight_core.dart';
import 'package:gql_http_link/gql_http_link.dart';
import 'package:http/http.dart' as http;

import '../data/digitraffic_headers.dart';
import '../data/freight_repository.dart';
import '../data/marine_data_source.dart';
import '../data/preferences_snapshot_store.dart';
import '../data/rail_data_source.dart';
import '../data/snapshot_store.dart';
import 'settings.dart';

const _railEndpoint = 'https://rata.digitraffic.fi/api/v2/graphql/graphql';

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final snapshotStoreProvider = Provider<SnapshotStore>(
  (ref) => PreferencesSnapshotStore(ref.watch(sharedPreferencesProvider)),
);

/// ferry's GraphQL client. An in-memory cache is deliberate: adding
/// `ferry_hive_store` would pull in an unmaintained dependency for no benefit,
/// since every query here is network-first anyway.
final ferryClientProvider = Provider<Client>((ref) {
  final link = HttpLink(
    _railEndpoint,
    defaultHeaders: digitrafficHeaders(),
    httpClient: ref.watch(httpClientProvider),
  );
  return Client(link: link, cache: Cache());
});

/// The seam every test overrides.
final freightRepositoryProvider = Provider<FreightRepository>((ref) {
  return FreightRepository(
    rail: RailDataSource(ref.watch(ferryClientProvider)),
    marine: MarineDataSource(
      ref.watch(httpClientProvider),
      cache: ref.watch(snapshotStoreProvider),
    ),
  );
});

/// Every cargo train currently running on the Finnish network.
final cargoTrainsProvider = FutureProvider<List<FreightTrain>>((ref) {
  return ref.watch(freightRepositoryProvider).cargoTrains();
});

/// One train with its wagon composition. Keyed by the train's compound id so
/// two trains sharing a number on different days stay distinct.
final trainDetailProvider = FutureProvider.family<FreightTrain?, String>((
  ref,
  id,
) {
  final parts = id.split('/');
  return ref
      .watch(freightRepositoryProvider)
      .trainDetail(
        trainNumber: int.parse(parts.first),
        departureDate: parts.last,
      );
});

/// Freight vessels around the chosen home port.
///
/// Watching only the two settings it needs means changing the theme does not
/// refetch, but moving the radius slider does.
final freightVesselsProvider = FutureProvider<Sourced<List<TrackedVessel>>>((
  ref,
) {
  final port = ref.watch(settingsProvider.select((s) => s.homePort));
  final radius = ref.watch(settingsProvider.select((s) => s.radiusKm));

  return ref
      .watch(freightRepositoryProvider)
      .freightVesselsNear(centre: port.point, radiusKm: radius);
});

/// Live vessel positions, re-fetched on a timer.
///
/// A `Stream` rather than a `Future` because this is the one genuinely
/// continuous thing in the app. Polling is used instead of Digitraffic's MQTT
/// feed: at a 20-second interval this costs three requests a minute against an
/// allowance of sixty, and a failed poll simply retries where a dropped
/// websocket would need reconnect and backoff handling.
final liveVesselsProvider = StreamProvider<Sourced<List<TrackedVessel>>>((
  ref,
) async* {
  final port = ref.watch(settingsProvider.select((s) => s.homePort));
  final radius = ref.watch(settingsProvider.select((s) => s.radiusKm));
  final period = Duration(
    seconds: ref.watch(settingsProvider.select((s) => s.pollSeconds)),
  );
  final repository = ref.watch(freightRepositoryProvider);

  var cancelled = false;
  ref.onDispose(() => cancelled = true);

  while (!cancelled) {
    yield await repository.freightVesselsNear(
      centre: port.point,
      radiusKm: radius,
    );
    await Future<void>.delayed(period);
  }
});

final portCallsProvider = FutureProvider<Sourced<List<PortCall>>>((ref) {
  return ref.watch(freightRepositoryProvider).portCalls();
});

/// The multimodal view. Composed from four upstream calls, but the joining
/// itself is pure logic in `freight_core`.
final corridorsProvider = FutureProvider<List<FreightCorridor>>((ref) {
  return ref.watch(freightRepositoryProvider).corridors();
});

/// Only the delayed trains, derived without another network call.
final delayedTrainsProvider = Provider<AsyncValue<List<FreightTrain>>>((ref) {
  return ref
      .watch(cargoTrainsProvider)
      .whenData(
        (trains) =>
            trains.where((train) => (train.worstDelay ?? 0) >= 3).toList()
              ..sort(
                (a, b) => (b.worstDelay ?? 0).compareTo(a.worstDelay ?? 0),
              ),
      );
});

/// Share of running cargo trains that are within tolerance at every recorded
/// stop. Null while loading or when nothing is running.
final onTimeShareProvider = Provider<double?>((ref) {
  final trains = ref.watch(cargoTrainsProvider).value;
  if (trains == null || trains.isEmpty) return null;

  final onTime = trains.where((train) => (train.worstDelay ?? 0) < 3).length;
  return onTime / trains.length;
});

/// Free-text filter for the rail list.
final railFilterProvider = NotifierProvider<RailFilter, String>(RailFilter.new);

class RailFilter extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

/// Trains matching the current filter, sorted worst-delay first.
final filteredTrainsProvider = Provider<AsyncValue<List<FreightTrain>>>((ref) {
  final query = ref.watch(railFilterProvider).trim().toLowerCase();

  return ref.watch(cargoTrainsProvider).whenData((trains) {
    final matches = query.isEmpty
        ? <FreightTrain>[...trains]
        : trains.where((train) {
            final terminus = train.terminus?.stationName.toLowerCase() ?? '';
            return train.trainNumber.toString().contains(query) ||
                train.operatorShortCode.toLowerCase().contains(query) ||
                terminus.contains(query);
          }).toList();

    matches.sort((a, b) => (b.worstDelay ?? 0).compareTo(a.worstDelay ?? 0));
    return matches;
  });
});
