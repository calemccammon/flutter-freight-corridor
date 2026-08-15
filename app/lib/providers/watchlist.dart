import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freight_core/freight_core.dart';

import '../data/freight_repository.dart';
import 'freight_providers.dart';
import 'settings.dart';

/// Trains and vessels the user has pinned, plus the lateness at which a
/// watched train is worth flagging.
@immutable
class Watchlist {
  const Watchlist({
    this.trainIds = const <String>{},
    this.vesselMmsis = const <int>{},
    this.alertMinutes = defaultAlertMinutes,
  });

  /// Fifteen minutes matches [DelayStatus.major], so the default alert lines
  /// up with what the rest of the app already calls a serious delay.
  static const int defaultAlertMinutes = 15;
  static const int minAlertMinutes = 1;
  static const int maxAlertMinutes = 240;

  /// Compound `trainNumber/departureDate` ids, matching [FreightTrain.id].
  final Set<String> trainIds;
  final Set<int> vesselMmsis;
  final int alertMinutes;

  bool watchesTrain(String id) => trainIds.contains(id);

  bool watchesVessel(int mmsi) => vesselMmsis.contains(mmsi);

  int get length => trainIds.length + vesselMmsis.length;

  bool get isEmpty => length == 0;

  Watchlist copyWith({
    Set<String>? trainIds,
    Set<int>? vesselMmsis,
    int? alertMinutes,
  }) => Watchlist(
    trainIds: trainIds ?? this.trainIds,
    vesselMmsis: vesselMmsis ?? this.vesselMmsis,
    alertMinutes: alertMinutes ?? this.alertMinutes,
  );

  /// Validates a user-entered threshold, returning an error message or null.
  /// Kept here rather than in the widget so the rule is testable on its own.
  static String? validateAlertMinutes(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return 'Enter a number of minutes';
    final value = int.tryParse(text);
    if (value == null) return 'Whole minutes only';
    if (value < minAlertMinutes) return 'Must be at least $minAlertMinutes';
    if (value > maxAlertMinutes) return 'Must be $maxAlertMinutes or less';
    return null;
  }
}

class WatchlistController extends Notifier<Watchlist> {
  static const _trainsKey = 'watchlist:trains';
  static const _vesselsKey = 'watchlist:vessels';
  static const _alertKey = 'watchlist:alertMinutes';

  @override
  Watchlist build() {
    final preferences = ref.read(sharedPreferencesProvider);
    return Watchlist(
      trainIds:
          preferences.getStringList(_trainsKey)?.toSet() ?? const <String>{},
      vesselMmsis:
          preferences
              .getStringList(_vesselsKey)
              ?.map(int.tryParse)
              .whereType<int>()
              .toSet() ??
          const <int>{},
      alertMinutes:
          preferences.getInt(_alertKey) ?? Watchlist.defaultAlertMinutes,
    );
  }

  Future<void> toggleTrain(String id) async {
    final next = <String>{...state.trainIds};
    if (!next.remove(id)) next.add(id);
    state = state.copyWith(trainIds: next);
    await ref
        .read(sharedPreferencesProvider)
        .setStringList(_trainsKey, next.toList());
  }

  Future<void> toggleVessel(int mmsi) async {
    final next = <int>{...state.vesselMmsis};
    if (!next.remove(mmsi)) next.add(mmsi);
    state = state.copyWith(vesselMmsis: next);
    await ref
        .read(sharedPreferencesProvider)
        .setStringList(
          _vesselsKey,
          next.map((value) => value.toString()).toList(),
        );
  }

  Future<void> setAlertMinutes(int minutes) async {
    final clamped = minutes.clamp(
      Watchlist.minAlertMinutes,
      Watchlist.maxAlertMinutes,
    );
    state = state.copyWith(alertMinutes: clamped);
    await ref.read(sharedPreferencesProvider).setInt(_alertKey, clamped);
  }

  Future<void> clear() async {
    state = state.copyWith(
      trainIds: const <String>{},
      vesselMmsis: const <int>{},
    );
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.setStringList(_trainsKey, const <String>[]);
    await preferences.setStringList(_vesselsKey, const <String>[]);
  }
}

final watchlistProvider = NotifierProvider<WatchlistController, Watchlist>(
  WatchlistController.new,
);

/// The pinned trains, resolved against the live feed.
///
/// A watched train that has finished its run simply disappears from the feed,
/// so this is a filter over live data rather than a stored copy — the pin is
/// an id, never a snapshot that can go stale.
final watchedTrainsProvider = Provider<AsyncValue<List<FreightTrain>>>((ref) {
  final watched = ref.watch(watchlistProvider).trainIds;

  return ref
      .watch(cargoTrainsProvider)
      .whenData(
        (trains) => trains.where((train) => watched.contains(train.id)).toList()
          ..sort((a, b) => (b.worstDelay ?? 0).compareTo(a.worstDelay ?? 0)),
      );
});

final watchedVesselsProvider = Provider<AsyncValue<List<TrackedVessel>>>((ref) {
  final watched = ref.watch(watchlistProvider).vesselMmsis;

  return ref
      .watch(freightVesselsProvider)
      .whenData(
        (sourced) => sourced.value
            .where((tracked) => watched.contains(tracked.mmsi))
            .toList(),
      );
});

/// Watched trains currently later than the user's threshold.
final watchlistAlertsProvider = Provider<List<FreightTrain>>((ref) {
  final threshold = ref.watch(
    watchlistProvider.select((list) => list.alertMinutes),
  );

  return ref
          .watch(watchedTrainsProvider)
          .value
          ?.where((train) => (train.worstDelay ?? 0) >= threshold)
          .toList(growable: false) ??
      const <FreightTrain>[];
});
