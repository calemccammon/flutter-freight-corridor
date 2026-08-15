import 'package:meta/meta.dart';

import 'geo_point.dart';

/// A UN/LOCODE port location.
///
/// The directory covers the whole world, not just Finland, because port calls
/// reference previous and next ports anywhere. Some entries genuinely have no
/// coordinates, so [point] is nullable and such ports are skipped when pairing
/// against rail termini.
@immutable
class Port {
  const Port({
    required this.locode,
    required this.name,
    this.country,
    this.point,
  });

  final String locode;
  final String name;
  final String? country;
  final GeoPoint? point;

  /// Finnish LOCODEs begin `FI`. The corridor view only pairs rail with
  /// domestic seaports, since the rail network does not leave the country.
  bool get isFinnish => locode.toUpperCase().startsWith('FI');

  @override
  String toString() => '$name ($locode)';
}
