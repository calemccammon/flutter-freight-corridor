/// Storage for last-known-good API payloads.
///
/// An interface rather than a concrete class so the data layer stays free of
/// Flutter: `shared_preferences` is a plugin and pulls in `dart:ui`, which
/// would stop the data sources from being exercised by a plain `dart run` or
/// a non-widget test. The Flutter-backed implementation lives in
/// `preferences_snapshot_store.dart` and is injected at startup.
abstract class SnapshotStore {
  /// The stored payload for [key], or null when nothing usable is held.
  Object? read(String key);

  /// When the payload for [key] was captured.
  DateTime? capturedAt(String key);

  Future<void> write(String key, Object? json);

  Future<void> clear(String key);
}

/// In-memory store used by tests and by the live smoke tool.
class InMemorySnapshotStore implements SnapshotStore {
  final Map<String, Object?> _payloads = <String, Object?>{};
  final Map<String, DateTime> _stamps = <String, DateTime>{};

  @override
  Object? read(String key) => _payloads[key];

  @override
  DateTime? capturedAt(String key) => _stamps[key];

  @override
  Future<void> write(String key, Object? json) async {
    _payloads[key] = json;
    _stamps[key] = DateTime.now().toUtc();
  }

  @override
  Future<void> clear(String key) async {
    _payloads.remove(key);
    _stamps.remove(key);
  }
}
