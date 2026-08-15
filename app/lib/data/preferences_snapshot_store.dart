import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'snapshot_store.dart';

/// [SnapshotStore] backed by `shared_preferences`.
///
/// Deliberately not a database. These are a few hundred rows that go stale
/// within a minute, with nothing to query or join, so a relational store would
/// buy a schema, generated DAOs, a migration story and — on the web — a
/// `sqlite3.wasm` payload to ship and load, all for data thrown away on the
/// next refresh. `shared_preferences` uses `localStorage` in the browser and
/// platform preferences on Android, with no extra assets either way.
class PreferencesSnapshotStore implements SnapshotStore {
  PreferencesSnapshotStore(this._preferences);

  final SharedPreferences _preferences;

  static const _payloadPrefix = 'cache:';
  static const _stampSuffix = ':at';

  @override
  Object? read(String key) {
    final raw = _preferences.getString('$_payloadPrefix$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      // Written by an older build and no longer parseable. Drop it rather
      // than letting a stale format break every launch from here on.
      unawaited(clear(key));
      return null;
    }
  }

  @override
  DateTime? capturedAt(String key) {
    final raw = _preferences.getString('$_payloadPrefix$key$_stampSuffix');
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  @override
  Future<void> write(String key, Object? json) async {
    await _preferences.setString('$_payloadPrefix$key', jsonEncode(json));
    await _preferences.setString(
      '$_payloadPrefix$key$_stampSuffix',
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> clear(String key) async {
    await _preferences.remove('$_payloadPrefix$key');
    await _preferences.remove('$_payloadPrefix$key$_stampSuffix');
  }
}
