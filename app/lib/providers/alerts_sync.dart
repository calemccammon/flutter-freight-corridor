import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/alerts_client.dart';
import 'settings.dart';
import 'watchlist.dart';

/// Connection details for the companion alerts service.
///
/// Stored beside the rest of the app's preferences rather than in a secure
/// keystore. The token is a bearer credential, so that is a real trade-off and
/// worth naming: it buys zero extra plugins, and the blast radius is one user's
/// watch rules on one service that grants no access to their GitHub account.
/// A production app holding anything of value would use `flutter_secure_storage`.
@immutable
class AlertsConnection {
  const AlertsConnection({this.baseUrl = '', this.token = ''});

  final String baseUrl;
  final String token;

  bool get isConfigured => baseUrl.isNotEmpty && token.isNotEmpty;

  AlertsConnection copyWith({String? baseUrl, String? token}) =>
      AlertsConnection(
        baseUrl: baseUrl ?? this.baseUrl,
        token: token ?? this.token,
      );
}

class AlertsConnectionController extends Notifier<AlertsConnection> {
  static const _baseUrlKey = 'alerts:baseUrl';
  static const _tokenKey = 'alerts:token';

  @override
  AlertsConnection build() {
    final preferences = ref.read(sharedPreferencesProvider);
    return AlertsConnection(
      baseUrl: preferences.getString(_baseUrlKey) ?? '',
      token: preferences.getString(_tokenKey) ?? '',
    );
  }

  Future<void> save({required String baseUrl, required String token}) async {
    final normalised = AlertsClient.normaliseBaseUrl(baseUrl);
    state = AlertsConnection(baseUrl: normalised, token: token.trim());
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.setString(_baseUrlKey, normalised);
    await preferences.setString(_tokenKey, token.trim());
  }

  Future<void> disconnect() async {
    state = const AlertsConnection();
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.remove(_baseUrlKey);
    await preferences.remove(_tokenKey);
  }
}

final alertsConnectionProvider =
    NotifierProvider<AlertsConnectionController, AlertsConnection>(
      AlertsConnectionController.new,
    );

/// Builds a client from the stored connection, or null when not configured.
///
/// Exposed as a provider so tests can override it with a client backed by a
/// mock transport.
final alertsClientProvider = Provider<AlertsClient?>((Ref ref) {
  final connection = ref.watch(alertsConnectionProvider);
  if (!connection.isConfigured) return null;
  return AlertsClient(baseUrl: connection.baseUrl, token: connection.token);
});

/// What a sync attempt produced, in a form the UI can render directly.
@immutable
class SyncOutcome {
  const SyncOutcome({
    required this.synced,
    required this.skippedVessels,
    this.error,
  });

  const SyncOutcome.failed(String message)
    : synced = 0,
      skippedVessels = 0,
      error = message;

  final int synced;

  /// Watched vessels are counted but not sent: the service is rail-only, and
  /// silently dropping them would look like a bug.
  final int skippedVessels;
  final String? error;

  bool get succeeded => error == null;
}

/// Pushes the local watchlist to the service and reads alerts back.
class AlertsSyncController extends AsyncNotifier<AlertFeed?> {
  @override
  Future<AlertFeed?> build() async {
    final client = ref.watch(alertsClientProvider);
    if (client == null) return null;
    return client.alerts();
  }

  /// Confirms the stored URL and token work, returning the signed-in login.
  Future<String> testConnection() async {
    final client = ref.read(alertsClientProvider);
    if (client == null) {
      throw const AlertsException('Set the service URL and token first');
    }
    return client.signedInAs();
  }

  /// Registers every watched train with the service.
  ///
  /// Creating a rule is idempotent server-side — an identical rule returns the
  /// existing one — so syncing twice is safe and this does not need to diff
  /// against what is already there.
  Future<SyncOutcome> syncWatchlist() async {
    final client = ref.read(alertsClientProvider);
    if (client == null) {
      return const SyncOutcome.failed('Set the service URL and token first');
    }

    final watchlist = ref.read(watchlistProvider);
    final trainNumbers = watchlist.trainIds
        .map(_trainNumberFrom)
        .whereType<int>()
        .toSet();

    var synced = 0;
    try {
      for (final number in trainNumbers) {
        await client.watchTrain(number, watchlist.alertMinutes);
        synced++;
      }
    } on AlertsException catch (error) {
      return SyncOutcome.failed(error.message);
    }

    // Refresh the feed so the UI reflects the rules just registered.
    ref.invalidateSelf();
    return SyncOutcome(
      synced: synced,
      skippedVessels: watchlist.vesselMmsis.length,
    );
  }

  /// Local ids are `trainNumber/departureDate`; the service watches the number.
  static int? _trainNumberFrom(String id) {
    final head = id.split('/').first;
    return int.tryParse(head);
  }
}

final alertsSyncProvider =
    AsyncNotifierProvider<AlertsSyncController, AlertFeed?>(
      AlertsSyncController.new,
    );
