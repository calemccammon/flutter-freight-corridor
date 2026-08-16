import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;


/// Client for the companion [freight-alerts](https://github.com/calemccammon/freight-alerts)
/// service.
///
/// The watchlist in this app is device-local: reinstall the app and it is gone,
/// and nothing watches your trains while the app is closed. That service is the
/// other half — it holds the rules server-side and polls on a schedule. This
/// client is the bridge.
///
/// It authenticates with a device token rather than a session cookie. Cookie
/// jars and OAuth redirects assume a browser; a bearer token is what a native
/// client can actually carry. The token is minted once from the web UI and
/// pasted in here.
///
/// A failure talking to the alerts service, carrying a message worth showing.
@immutable
class AlertsException implements Exception {
  const AlertsException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// True when the token is missing, wrong, or expired — the one failure the
  /// user can actually fix, so the UI distinguishes it from a server problem.
  bool get isAuthFailure => statusCode == 401;

  @override
  String toString() => message;
}

/// An alert the service has already recorded, as opposed to a delay this app
/// happens to be looking at right now.
@immutable
class RemoteAlert {
  const RemoteAlert({
    required this.trainNumber,
    required this.departureDate,
    required this.operator,
    required this.delayMinutes,
    required this.station,
    required this.createdAt,
  });

  final int trainNumber;
  final String departureDate;
  final String operator;
  final int delayMinutes;
  final String station;
  final DateTime createdAt;

  static RemoteAlert fromJson(Map<String, Object?> json) => RemoteAlert(
    trainNumber: (json['train_number'] as num?)?.toInt() ?? 0,
    departureDate: json['departure_date'] as String? ?? '',
    operator: json['operator'] as String? ?? '',
    delayMinutes: (json['delay_minutes'] as num?)?.toInt() ?? 0,
    station: json['station'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// The alert feed plus the attribution the service returns alongside it.
///
/// Carried through rather than discarded: the underlying data is CC BY 4.0, and
/// the licence travels with it.
@immutable
class AlertFeed {
  const AlertFeed({required this.alerts, required this.attribution});

  final List<RemoteAlert> alerts;
  final String attribution;
}

/// A watch rule as the server holds it.
@immutable
class RemoteRule {
  const RemoteRule({
    required this.id,
    required this.kind,
    required this.target,
    required this.thresholdMinutes,
  });

  final int id;
  final String kind;
  final String target;
  final int thresholdMinutes;

  static RemoteRule fromJson(Map<String, Object?> json) => RemoteRule(
    id: (json['id'] as num?)?.toInt() ?? 0,
    kind: json['kind'] as String? ?? '',
    target: json['target'] as String? ?? '',
    thresholdMinutes: (json['threshold_minutes'] as num?)?.toInt() ?? 0,
  );
}

class AlertsClient {
  AlertsClient({
    required String baseUrl,
    required this.token,
    http.Client? client,
  }) : baseUrl = normaliseBaseUrl(baseUrl),
       _client = client ?? http.Client();

  final String baseUrl;
  final String token;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 15);

  /// Trims the trailing slash so paths can be appended without doubling it,
  /// which is the single most common thing to get wrong in a pasted URL.
  static String normaliseBaseUrl(String raw) {
    var value = raw.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// Validates a user-entered base URL, returning an error message or null.
  /// Kept beside the client rather than in the widget so it is testable alone.
  static String? validateBaseUrl(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return 'Enter the service URL';
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Must be a full URL, e.g. https://alerts.example.com';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Must be http or https';
    }
    return null;
  }

  static String? validateToken(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return 'Paste the device token';
    // Tokens are 32 random bytes in base64url; anything much shorter is a
    // truncated paste rather than a real token.
    if (text.length < 20) return 'That looks too short to be a device token';
    return null;
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> get _headers => <String, String>{
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
  };

  /// Confirms the URL and token work, returning the signed-in login.
  ///
  /// Exists so the settings screen can say "connected as cale" instead of
  /// leaving the user to discover a typo on their next sync.
  Future<String> signedInAs() async {
    final body = await _get('/api/me');
    return body['login'] as String? ?? 'unknown';
  }

  Future<AlertFeed> alerts({int limit = 50}) async {
    final body = await _get('/api/alerts', <String, String>{
      'limit': '$limit',
    });
    final raw = (body['alerts'] as List<Object?>? ?? <Object?>[]);
    return AlertFeed(
      alerts: raw
          .whereType<Map<String, Object?>>()
          .map(RemoteAlert.fromJson)
          .toList(growable: false),
      attribution: body['attribution'] as String? ?? '',
    );
  }

  Future<List<RemoteRule>> rules() async {
    final body = await _get('/api/rules');
    final raw = (body['rules'] as List<Object?>? ?? <Object?>[]);
    return raw
        .whereType<Map<String, Object?>>()
        .map(RemoteRule.fromJson)
        .toList(growable: false);
  }

  /// Registers a watch on one train number.
  ///
  /// The server keys train rules on the number alone, not the compound
  /// `number/date` this app uses locally — watching a train means watching it on
  /// every day it runs, not just the instance currently on screen.
  Future<RemoteRule> watchTrain(int trainNumber, int thresholdMinutes) async {
    final body = await _post('/api/rules', <String, Object?>{
      'kind': 'train',
      'target': '$trainNumber',
      'threshold_minutes': thresholdMinutes,
    });
    return RemoteRule.fromJson(body);
  }

  Future<Map<String, Object?>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    try {
      final response = await _client
          .get(_uri(path, query), headers: _headers)
          .timeout(_timeout);
      return _decode(response);
    } on AlertsException {
      rethrow;
    } catch (error) {
      throw AlertsException('Could not reach $baseUrl — $error');
    }
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> payload,
  ) async {
    try {
      final response = await _client
          .post(
            _uri(path),
            headers: <String, String>{
              ..._headers,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      return _decode(response);
    } on AlertsException {
      rethrow;
    } catch (error) {
      throw AlertsException('Could not reach $baseUrl — $error');
    }
  }

  Map<String, Object?> _decode(http.Response response) {
    if (response.statusCode == 401) {
      throw const AlertsException(
        'The device token was rejected. Mint a new one and paste it again.',
        statusCode: 401,
      );
    }
    if (response.statusCode >= 400) {
      // The service reports failures as {"error": "..."}, which is worth
      // surfacing verbatim: it explains *why* a rule was refused.
      String detail = 'HTTP ${response.statusCode}';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['error'] is String) {
          detail = body['error'] as String;
        }
      } catch (_) {
        // Body was not the JSON shape we expect; the status is all we have.
      }
      throw AlertsException(detail, statusCode: response.statusCode);
    }
    if (response.body.isEmpty) return <String, Object?>{};
    // Decoded explicitly as UTF-8: Finnish station names arrive with umlauts,
    // and http's `body` getter guesses Latin-1 when the charset is unstated.
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, Object?>) {
      throw const AlertsException('The service returned an unexpected response');
    }
    return decoded;
  }

  void close() => _client.close();
}
