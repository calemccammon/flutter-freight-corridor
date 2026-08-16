import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freight_corridor/data/alerts_client.dart';
import 'package:freight_corridor/providers/alerts_sync.dart';
import 'package:freight_corridor/providers/settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> containerWith({
  required AlertsClient? client,
  Map<String, Object> prefs = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final preferences = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(preferences),
      alertsClientProvider.overrideWithValue(client),
    ],
  );
}

/// Records every rule POSTed so tests can assert on what was sent.
AlertsClient recordingClient(
  List<Map<String, Object?>> sent, {
  int status = 201,
}) {
  final mock = MockClient((http.Request request) async {
    if (request.method == 'POST') {
      sent.add(jsonDecode(request.body) as Map<String, Object?>);
      return http.Response(
        jsonEncode(<String, Object?>{'id': sent.length, 'kind': 'train'}),
        status,
      );
    }
    return http.Response(
      jsonEncode(<String, Object?>{'alerts': <Object?>[]}),
      200,
    );
  });
  return AlertsClient(
    baseUrl: 'https://alerts.test',
    token: 'a-device-token-long-enough',
    client: mock,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an unconfigured connection yields no client', () async {
    final container = await containerWith(client: null);
    addTearDown(container.dispose);
    expect(container.read(alertsClientProvider), isNull);
  });

  test('syncing without a connection reports rather than throwing', () async {
    final container = await containerWith(client: null);
    addTearDown(container.dispose);

    final outcome = await container
        .read(alertsSyncProvider.notifier)
        .syncWatchlist();
    expect(outcome.succeeded, isFalse);
    expect(outcome.error, contains('Set the service URL'));
  });

  test('sends the train number, dropping the local departure date', () async {
    // Local ids are number/date; the service watches the number on every day.
    final sent = <Map<String, Object?>>[];
    final container = await containerWith(
      client: recordingClient(sent),
      prefs: <String, Object>{
        'watchlist:trains': <String>['3001/2026-08-16'],
        'watchlist:alertMinutes': 20,
      },
    );
    addTearDown(container.dispose);

    final outcome = await container
        .read(alertsSyncProvider.notifier)
        .syncWatchlist();
    expect(outcome.succeeded, isTrue);
    expect(outcome.synced, 1);
    expect(sent.single['target'], '3001');
    expect(sent.single['threshold_minutes'], 20);
  });

  test('the same train on two dates is registered once', () async {
    // Two local pins for the same train collapse to one server-side rule.
    final sent = <Map<String, Object?>>[];
    final container = await containerWith(
      client: recordingClient(sent),
      prefs: <String, Object>{
        'watchlist:trains': <String>['3001/2026-08-16', '3001/2026-08-17'],
      },
    );
    addTearDown(container.dispose);

    final outcome = await container
        .read(alertsSyncProvider.notifier)
        .syncWatchlist();
    expect(outcome.synced, 1);
    expect(sent, hasLength(1));
  });

  test('watched vessels are counted, not silently dropped', () async {
    // The service is rail-only; a vanished vessel would look like a bug.
    final sent = <Map<String, Object?>>[];
    final container = await containerWith(
      client: recordingClient(sent),
      prefs: <String, Object>{
        'watchlist:trains': <String>['3001/2026-08-16'],
        'watchlist:vessels': <String>['230123456', '230999999'],
      },
    );
    addTearDown(container.dispose);

    final outcome = await container
        .read(alertsSyncProvider.notifier)
        .syncWatchlist();
    expect(outcome.skippedVessels, 2);
    expect(sent, hasLength(1));
  });

  test('a rejected rule surfaces the service message', () async {
    final sent = <Map<String, Object?>>[];
    final mock = MockClient((http.Request request) async {
      sent.add(<String, Object?>{});
      return http.Response(
        jsonEncode(<String, Object?>{
          'error': 'threshold must be at least 1 minute',
        }),
        400,
      );
    });
    final container = await containerWith(
      client: AlertsClient(
        baseUrl: 'https://alerts.test',
        token: 'a-device-token-long-enough',
        client: mock,
      ),
      prefs: <String, Object>{
        'watchlist:trains': <String>['3001/2026-08-16'],
      },
    );
    addTearDown(container.dispose);

    final outcome = await container
        .read(alertsSyncProvider.notifier)
        .syncWatchlist();
    expect(outcome.succeeded, isFalse);
    expect(outcome.error, contains('at least 1 minute'));
  });

  test('an empty watchlist syncs nothing and still succeeds', () async {
    final sent = <Map<String, Object?>>[];
    final container = await containerWith(client: recordingClient(sent));
    addTearDown(container.dispose);

    final outcome = await container
        .read(alertsSyncProvider.notifier)
        .syncWatchlist();
    expect(outcome.succeeded, isTrue);
    expect(outcome.synced, 0);
    expect(sent, isEmpty);
  });

  test('the connection round-trips through storage', () async {
    final container = await containerWith(client: null);
    addTearDown(container.dispose);

    await container
        .read(alertsConnectionProvider.notifier)
        .save(baseUrl: 'https://alerts.test/', token: '  a-token-value-here  ');

    final saved = container.read(alertsConnectionProvider);
    expect(
      saved.baseUrl,
      'https://alerts.test',
      reason: 'trailing slash trimmed',
    );
    expect(saved.token, 'a-token-value-here', reason: 'whitespace trimmed');
    expect(saved.isConfigured, isTrue);
  });

  test('disconnecting clears the stored credential', () async {
    final container = await containerWith(client: null);
    addTearDown(container.dispose);

    final controller = container.read(alertsConnectionProvider.notifier);
    await controller.save(
      baseUrl: 'https://alerts.test',
      token: 'a-token-value',
    );
    await controller.disconnect();

    expect(container.read(alertsConnectionProvider).isConfigured, isFalse);
  });
}
