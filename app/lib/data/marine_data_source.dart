import 'dart:convert';

import 'package:freight_core/freight_core.dart';
import 'package:http/http.dart' as http;

import 'digitraffic_headers.dart';
import 'snapshot_store.dart';

/// Reads live vessel positions, vessel metadata and port calls from the
/// Digitraffic marine REST APIs.
///
/// The maritime half of the app is plain REST while the rail half is GraphQL.
/// Both end up as `freight_core` models, which is what lets one repository
/// serve both without the UI knowing the difference.
class MarineDataSource {
  MarineDataSource(this._client, {Uri? baseUrl, this._cache})
    : _baseUrl = baseUrl ?? Uri.parse('https://meri.digitraffic.fi');

  final http.Client _client;
  final Uri _baseUrl;
  final SnapshotStore? _cache;

  /// When the most recent successful read came from disk rather than the
  /// network, this is when it was captured. Null means the data is live.
  DateTime? staleSince;

  /// AIS positions within [radiusKm] of a point.
  Future<List<VesselPosition>> vesselPositions({
    required GeoPoint centre,
    required double radiusKm,
  }) async {
    final json = await _getJson(
      '/api/ais/v1/locations',
      query: <String, String>{
        'latitude': centre.latitude.toStringAsFixed(5),
        'longitude': centre.longitude.toStringAsFixed(5),
        'radius': radiusKm.round().toString(),
      },
    );
    return parseVesselPositions(json);
  }

  /// Static vessel details, keyed by MMSI. Changes rarely, so callers cache it.
  Future<Map<int, Vessel>> vessels() async {
    final json = await _getJson('/api/ais/v1/vessels');
    return parseVessels(json);
  }

  /// The Finnish seaports, with coordinates.
  ///
  /// The endpoint returns the entire worldwide UN/LOCODE directory — about
  /// 18,600 entries and several megabytes — of which roughly 170 are Finnish
  /// places that actually have coordinates. Downloading that on every cold
  /// start is what made the corridor view slow, but caching the raw payload
  /// would put megabytes into `localStorage` on the web.
  ///
  /// So the response is trimmed to the entries this app can use *before* it is
  /// cached, and the trimmed copy is what later loads read. Same parser either
  /// way — only the size changes.
  Future<List<Port>> ports() async {
    const cacheKey = '/api/port-call/v1/ports#fi';

    final cached = _cache?.read(cacheKey);
    if (cached != null) return parsePorts(cached);

    final json = await _getJson('/api/port-call/v1/ports', useCache: false);
    final trimmed = _finnishSeaports(json);
    await _cache?.write(cacheKey, trimmed);
    return parsePorts(trimmed);
  }

  /// Rebuilds the ports payload keeping only Finnish entries that have
  /// coordinates, preserving the shape [parsePorts] expects.
  static Map<String, Object?> _finnishSeaports(Object? json) {
    final features = <Object?>[];

    final locations = json is Map ? json['ssnLocations'] : null;
    final all = locations is Map ? locations['features'] : null;

    if (all is List) {
      for (final feature in all) {
        if (feature is! Map) continue;
        // Entries without coordinates are inland places no ship visits, and
        // the corridor linker would discard them anyway.
        if (feature['geometry'] is! Map) continue;

        final properties = feature['properties'];
        final locode =
            (properties is Map ? properties['locode'] : null) ??
            feature['locode'];
        if (locode is! String || !locode.toUpperCase().startsWith('FI')) {
          continue;
        }
        features.add(feature);
      }
    }

    return <String, Object?>{
      'ssnLocations': <String, Object?>{'features': features},
    };
  }

  /// Scheduled and completed vessel visits to Finnish ports.
  Future<List<PortCall>> portCalls() async {
    final json = await _getJson('/api/port-call/v1/port-calls');
    if (json is! Map) return const <PortCall>[];
    final calls = json['portCalls'];
    if (calls is! List) return const <PortCall>[];

    return calls
        .map(_portCallFrom)
        .whereType<PortCall>()
        .toList(growable: false);
  }

  PortCall? _portCallFrom(Object? entry) {
    if (entry is! Map) return null;
    final id = entry['portCallId'];
    final port = entry['portToVisit'];
    if (id is! int || port is! String) return null;

    final details = entry['portAreaDetails'];
    final visits = <PortAreaVisit>[
      if (details is List)
        for (final detail in details)
          if (detail is Map)
            PortAreaVisit(
              berthName: _text(detail['berthName']),
              portAreaName: _text(detail['portAreaName']),
              eta: _time(detail['eta']),
              ata: _time(detail['ata']),
              etd: _time(detail['etd']),
              atd: _time(detail['atd']),
              arrivalDraughtMetres: _positiveDouble(detail['arrivalDraught']),
            ),
    ];

    return PortCall(
      portCallId: id,
      portToVisit: port,
      vesselName: _text(entry['vesselName']) ?? 'Unknown vessel',
      // The API exposes three loosely-named booleans; freight_core turns them
      // into a single intent that the UI can actually display.
      cargoIntent: CargoIntent.from(
        arrivalWithCargo: entry['arrivalWithCargo'] as bool?,
        notLoading: entry['notLoading'] as bool?,
        discharge: entry['discharge'] as int?,
      ),
      visits: visits,
      mmsi: entry['mmsi'] as int?,
      imoLloyds: entry['imoLloyds'] as int?,
      prevPort: _text(entry['prevPort']),
      nextPort: _text(entry['nextPort']),
      vesselTypeCode: _text(entry['vesselTypeCode']),
      nationality: _text(entry['nationality']),
      agentInfo: _text(entry['agentInfo']),
    );
  }

  /// Network first, falling back to the last good snapshot.
  ///
  /// A ferry crossing does not stop being interesting because the phone lost
  /// signal, so a failed fetch shows yesterday's answer with a "cached" marker
  /// rather than an error screen. Only a miss on both paths is a real failure.
  Future<Object?> _getJson(
    String path, {
    Map<String, String>? query,
    bool useCache = true,
  }) async {
    final uri = _baseUrl.replace(path: path, queryParameters: query);
    final store = useCache ? _cache : null;

    try {
      final response = await _client.get(uri, headers: digitrafficHeaders());
      if (response.statusCode != 200) {
        throw MarineRequestException(
          'Digitraffic answered ${response.statusCode} for $path',
        );
      }

      // Finnish place names are UTF-8; decoding the bytes explicitly avoids
      // the Latin-1 fallback that turns "Järvensivu" into mojibake.
      // `allowMalformed` keeps one bad byte from discarding a whole response
      // of otherwise good vessels.
      final json = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      staleSince = null;
      await store?.write(path, json);
      return json;
    } on Object catch (error) {
      final cached = store?.read(path);
      if (cached != null) {
        staleSince = store?.capturedAt(path);
        return cached;
      }
      if (error is MarineRequestException) rethrow;
      throw MarineRequestException('Could not reach $path: $error');
    }
  }

  static String? _text(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static DateTime? _time(Object? value) {
    final text = _text(value);
    if (text == null) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  static double? _positiveDouble(Object? value) {
    if (value is! num) return null;
    final result = value.toDouble();
    return result > 0 ? result : null;
  }
}

/// Raised when a marine REST call fails or answers with a non-200.
class MarineRequestException implements Exception {
  const MarineRequestException(this.message);

  final String message;

  @override
  String toString() => 'MarineRequestException: $message';
}
