import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:freight_corridor/data/alerts_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AlertsClient clientReturning(
  int status,
  Object? body, {
  void Function(http.Request)? onRequest,
  String baseUrl = 'https://alerts.example.com',
  String token = 'a-device-token-long-enough',
}) {
  final mock = MockClient((http.Request request) async {
    onRequest?.call(request);
    return http.Response(
      body is String ? body : jsonEncode(body),
      status,
      headers: <String, String>{'content-type': 'application/json'},
    );
  });
  return AlertsClient(baseUrl: baseUrl, token: token, client: mock);
}

void main() {
  group('base URL handling', () {
    test('strips trailing slashes so paths do not double up', () {
      expect(
        AlertsClient.normaliseBaseUrl('https://x.test/'),
        'https://x.test',
      );
      expect(
        AlertsClient.normaliseBaseUrl('  https://x.test///  '),
        'https://x.test',
      );
    });

    test('accepts a full http or https URL', () {
      expect(AlertsClient.validateBaseUrl('https://alerts.example.com'), isNull);
      expect(AlertsClient.validateBaseUrl('http://localhost:8080'), isNull);
    });

    test('rejects an empty, schemeless, or non-http URL', () {
      expect(AlertsClient.validateBaseUrl(''), isNotNull);
      expect(AlertsClient.validateBaseUrl('   '), isNotNull);
      expect(AlertsClient.validateBaseUrl('alerts.example.com'), isNotNull);
      expect(AlertsClient.validateBaseUrl('ftp://alerts.example.com'), isNotNull);
    });
  });

  group('token validation', () {
    test('rejects an empty token', () {
      expect(AlertsClient.validateToken(''), isNotNull);
    });

    test('rejects a truncated paste', () {
      expect(AlertsClient.validateToken('abc123'), isNotNull);
    });

    test('accepts a realistic token', () {
      expect(
        AlertsClient.validateToken('P1YUx3n2Qk5RtVwZaBcDeFgHiJkLmNoPqRsTuVwX'),
        isNull,
      );
    });
  });

  group('authentication', () {
    test('sends the device token as a bearer', () async {
      String? seen;
      final client = clientReturning(200, <String, Object?>{
        'login': 'cale',
      }, onRequest: (http.Request r) => seen = r.headers['Authorization']);

      await client.signedInAs();
      expect(seen, 'Bearer a-device-token-long-enough');
    });

    test('a 401 is reported as a fixable token problem', () async {
      final client = clientReturning(401, <String, Object?>{
        'error': 'session expired',
      });

      await expectLater(
        client.signedInAs(),
        throwsA(
          isA<AlertsException>()
              .having((AlertsException e) => e.isAuthFailure, 'isAuthFailure', isTrue)
              .having((AlertsException e) => e.message, 'message', contains('token')),
        ),
      );
    });

    test('a server error is not mistaken for an auth failure', () async {
      final client = clientReturning(500, <String, Object?>{'error': 'boom'});
      await expectLater(
        client.signedInAs(),
        throwsA(
          isA<AlertsException>().having(
            (AlertsException e) => e.isAuthFailure,
            'isAuthFailure',
            isFalse,
          ),
        ),
      );
    });
  });

  group('alerts', () {
    test('parses the feed', () async {
      final client = clientReturning(200, <String, Object?>{
        'alerts': <Object?>[
          <String, Object?>{
            'id': 5,
            'rule_id': 7,
            'train_number': 3001,
            'departure_date': '2026-08-16',
            'operator': 'vr',
            'delay_minutes': 22,
            'station': 'Tampere',
            'created_at': '2026-08-16T12:30:00Z',
          },
        ],
        'attribution': 'Fintraffic Digitraffic, CC BY 4.0',
      });

      final feed = await client.alerts();
      expect(feed.alerts, hasLength(1));
      expect(feed.alerts.single.trainNumber, 3001);
      expect(feed.alerts.single.delayMinutes, 22);
      expect(feed.alerts.single.station, 'Tampere');
    });

    test('carries the attribution through rather than dropping it', () async {
      // The data is CC BY 4.0; the licence has to travel with it.
      final client = clientReturning(200, <String, Object?>{
        'alerts': <Object?>[],
        'attribution': 'Fintraffic Digitraffic, CC BY 4.0',
      });

      final feed = await client.alerts();
      expect(feed.attribution, contains('CC BY 4.0'));
    });

    test('an empty feed is not an error', () async {
      final client = clientReturning(200, <String, Object?>{
        'alerts': <Object?>[],
      });
      expect((await client.alerts()).alerts, isEmpty);
    });

    test('decodes Finnish station names as UTF-8', () async {
      // http's `body` getter guesses Latin-1 when the charset is unstated, which
      // turns Riihimäki into mojibake. The client decodes bodyBytes explicitly.
      final mock = MockClient((http.Request request) async {
        final payload = jsonEncode(<String, Object?>{
          'alerts': <Object?>[
            <String, Object?>{
              'train_number': 1,
              'departure_date': '2026-08-16',
              'operator': 'vr',
              'delay_minutes': 5,
              'station': 'Riihimäki',
              'created_at': '2026-08-16T12:30:00Z',
            },
          ],
        });
        return http.Response.bytes(utf8.encode(payload), 200);
      });
      final client = AlertsClient(
        baseUrl: 'https://x.test',
        token: 'a-device-token-long-enough',
        client: mock,
      );

      final feed = await client.alerts();
      expect(feed.alerts.single.station, 'Riihimäki');
    });

    test('a malformed row does not take down the whole feed', () async {
      final client = clientReturning(200, <String, Object?>{
        'alerts': <Object?>[
          'not-an-object',
          <String, Object?>{
            'train_number': 3001,
            'departure_date': '2026-08-16',
            'operator': 'vr',
            'delay_minutes': 9,
            'station': 'Kouvola',
            'created_at': '2026-08-16T12:30:00Z',
          },
        ],
      });

      final feed = await client.alerts();
      expect(feed.alerts, hasLength(1));
      expect(feed.alerts.single.trainNumber, 3001);
    });
  });

  group('watching a train', () {
    test('sends the train number without the departure date', () async {
      // Locally a watch is keyed number/date; server-side it means "this train
      // on every day it runs".
      Map<String, Object?>? sent;
      final client = clientReturning(
        201,
        <String, Object?>{
          'id': 3,
          'kind': 'train',
          'target': '3001',
          'threshold_minutes': 15,
        },
        onRequest: (http.Request r) =>
            sent = jsonDecode(r.body) as Map<String, Object?>,
      );

      final rule = await client.watchTrain(3001, 15);
      expect(sent!['kind'], 'train');
      expect(sent!['target'], '3001');
      expect(sent!['threshold_minutes'], 15);
      expect(rule.id, 3);
    });

    test('surfaces the service error message verbatim', () async {
      // The server explains *why* a rule was refused; paraphrasing loses that.
      final client = clientReturning(400, <String, Object?>{
        'error': 'threshold must be at least 1 minute, got 0',
      });

      await expectLater(
        client.watchTrain(3001, 0),
        throwsA(
          isA<AlertsException>().having(
            (AlertsException e) => e.message,
            'message',
            contains('at least 1 minute'),
          ),
        ),
      );
    });
  });

  group('transport failures', () {
    test('an unreachable host names the URL that failed', () async {
      final mock = MockClient(
        (http.Request request) async => throw const SocketishFailure(),
      );
      final client = AlertsClient(
        baseUrl: 'https://down.example.com',
        token: 'a-device-token-long-enough',
        client: mock,
      );

      await expectLater(
        client.signedInAs(),
        throwsA(
          isA<AlertsException>().having(
            (AlertsException e) => e.message,
            'message',
            contains('down.example.com'),
          ),
        ),
      );
    });

    test('a non-JSON body is reported rather than throwing a parse error', () async {
      final client = clientReturning(200, '<html>gateway timeout</html>');
      await expectLater(client.alerts(), throwsA(isA<AlertsException>()));
    });
  });
}

/// Stands in for a transport-level failure without depending on dart:io, so
/// this test file still runs under the web test runner.
class SocketishFailure implements Exception {
  const SocketishFailure();
  @override
  String toString() => 'connection refused';
}
