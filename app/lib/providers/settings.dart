import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freight_core/freight_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ports the map can be centred on. Kept short and hand-picked: these are the
/// Finnish ports that actually handle meaningful freight volumes.
enum HomePort {
  helsinki('Helsinki', GeoPoint(latitude: 60.1719, longitude: 24.9414)),
  kotka('Kotka', GeoPoint(latitude: 60.4664, longitude: 26.9458)),
  turku('Turku', GeoPoint(latitude: 60.4363, longitude: 22.2094)),
  kokkola('Kokkola', GeoPoint(latitude: 63.8486, longitude: 23.0206)),
  oulu('Oulu', GeoPoint(latitude: 65.0121, longitude: 25.4651));

  const HomePort(this.label, this.point);

  final String label;
  final GeoPoint point;
}

@immutable
class Settings {
  const Settings({
    this.homePort = HomePort.helsinki,
    this.radiusKm = 80,
    this.pollSeconds = 20,
    this.themeMode = ThemeMode.system,
  });

  final HomePort homePort;

  /// How far from [homePort] to look for vessels.
  final double radiusKm;

  /// How often live positions refresh. Digitraffic allows 60 requests a
  /// minute; at 20 seconds with one request in flight we use three.
  final int pollSeconds;

  final ThemeMode themeMode;

  Settings copyWith({
    HomePort? homePort,
    double? radiusKm,
    int? pollSeconds,
    ThemeMode? themeMode,
  }) => Settings(
    homePort: homePort ?? this.homePort,
    radiusKm: radiusKm ?? this.radiusKm,
    pollSeconds: pollSeconds ?? this.pollSeconds,
    themeMode: themeMode ?? this.themeMode,
  );
}

/// Holds user settings and writes each change straight through to storage.
///
/// Data providers watch slices of this with `select`, so moving the radius
/// slider invalidates only what depends on the radius and the affected screens
/// refetch on their own.
class SettingsController extends Notifier<Settings> {
  static const _homePortKey = 'settings:homePort';
  static const _radiusKey = 'settings:radiusKm';
  static const _pollKey = 'settings:pollSeconds';
  static const _themeKey = 'settings:themeMode';

  SharedPreferences get _preferences => ref.read(sharedPreferencesProvider);

  @override
  Settings build() {
    final preferences = _preferences;

    return Settings(
      homePort: HomePort.values.firstWhere(
        (port) => port.name == preferences.getString(_homePortKey),
        orElse: () => HomePort.helsinki,
      ),
      radiusKm: preferences.getDouble(_radiusKey) ?? 80,
      pollSeconds: preferences.getInt(_pollKey) ?? 20,
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == preferences.getString(_themeKey),
        orElse: () => ThemeMode.system,
      ),
    );
  }

  Future<void> setHomePort(HomePort port) async {
    state = state.copyWith(homePort: port);
    await _preferences.setString(_homePortKey, port.name);
  }

  Future<void> setRadiusKm(double radiusKm) async {
    state = state.copyWith(radiusKm: radiusKm);
    await _preferences.setDouble(_radiusKey, radiusKm);
  }

  Future<void> setPollSeconds(int seconds) async {
    state = state.copyWith(pollSeconds: seconds);
    await _preferences.setInt(_pollKey, seconds);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _preferences.setString(_themeKey, mode.name);
  }
}

final settingsProvider = NotifierProvider<SettingsController, Settings>(
  SettingsController.new,
);

/// Overridden in `main()` once the real instance has loaded. Throwing here
/// means a missing override fails loudly at startup rather than silently
/// producing an app that never persists anything.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);
