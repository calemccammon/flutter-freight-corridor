/// What a vessel is for, derived from its AIS ship-type code.
///
/// Only [cargo] and [tanker] count as freight, which is how a general AIS feed
/// carrying ~1,400 vessels is narrowed to the ~600 that this app is about.
enum ShipCategory {
  cargo('Cargo'),
  tanker('Tanker'),
  passenger('Passenger'),
  fishing('Fishing'),
  highSpeed('High-speed craft'),
  service('Service'),
  other('Other'),
  unknown('Unknown');

  const ShipCategory(this.label);

  final String label;

  bool get isFreight =>
      this == ShipCategory.cargo || this == ShipCategory.tanker;
}

/// Maps an ITU-R M.1371 ship-type code to a [ShipCategory].
///
/// The codes are banded by first digit: 3x special craft, 4x high-speed,
/// 6x passenger, 7x cargo, 8x tanker, 9x other. Codes outside 0-99 are not
/// valid AIS values and resolve to [ShipCategory.unknown].
ShipCategory shipCategoryFromCode(int? code) {
  if (code == null || code < 0 || code > 99) return ShipCategory.unknown;
  if (code == 0) return ShipCategory.unknown;
  if (code == 30) return ShipCategory.fishing;
  if (code >= 31 && code <= 39) return ShipCategory.service;
  if (code >= 40 && code <= 49) return ShipCategory.highSpeed;
  if (code >= 50 && code <= 59) return ShipCategory.service;
  if (code >= 60 && code <= 69) return ShipCategory.passenger;
  if (code >= 70 && code <= 79) return ShipCategory.cargo;
  if (code >= 80 && code <= 89) return ShipCategory.tanker;
  if (code >= 90 && code <= 99) return ShipCategory.other;
  return ShipCategory.unknown;
}

/// AIS navigational status, which distinguishes a vessel working a berth from
/// one under way — the difference between "at the port" and "heading there".
enum NavigationStatus {
  underWayUsingEngine('Under way'),
  atAnchor('At anchor'),
  notUnderCommand('Not under command'),
  restrictedManoeuvrability('Restricted manoeuvrability'),
  constrainedByDraught('Constrained by draught'),
  moored('Moored'),
  aground('Aground'),
  engagedInFishing('Fishing'),
  underWaySailing('Under sail'),
  unknown('Unknown');

  const NavigationStatus(this.label);

  final String label;

  /// True when the vessel is stationary at a berth or anchorage.
  bool get isStationary =>
      this == NavigationStatus.moored ||
      this == NavigationStatus.atAnchor ||
      this == NavigationStatus.aground;
}

NavigationStatus navigationStatusFromCode(int? code) {
  switch (code) {
    case 0:
      return NavigationStatus.underWayUsingEngine;
    case 1:
      return NavigationStatus.atAnchor;
    case 2:
      return NavigationStatus.notUnderCommand;
    case 3:
      return NavigationStatus.restrictedManoeuvrability;
    case 4:
      return NavigationStatus.constrainedByDraught;
    case 5:
      return NavigationStatus.moored;
    case 6:
      return NavigationStatus.aground;
    case 7:
      return NavigationStatus.engagedInFishing;
    case 8:
      return NavigationStatus.underWaySailing;
    default:
      return NavigationStatus.unknown;
  }
}

/// Decodes the bit-packed AIS ETA field.
///
/// AIS squeezes an arrival time into 20 bits with no year: month (4 bits),
/// day (5), hour (5), minute (6). Transmitters send sentinel values (month 0,
/// day 0, hour 24, minute 60) to mean "not available", and plenty of vessels
/// send garbage, so every component is range-checked.
///
/// [reference] supplies the missing year and defaults to "now"; an ETA more
/// than six months behind the reference is assumed to belong to next year,
/// which is what makes December-to-January voyages decode sensibly.
DateTime? decodeAisEta(int? packed, {DateTime? reference}) {
  if (packed == null || packed < 0) return null;

  final minute = packed & 0x3F;
  final hour = (packed >> 6) & 0x1F;
  final day = (packed >> 11) & 0x1F;
  final month = (packed >> 16) & 0x0F;

  if (month < 1 || month > 12) return null;
  if (day < 1 || day > 31) return null;
  if (hour > 23 || minute > 59) return null;

  final now = reference ?? DateTime.now().toUtc();
  var candidate = DateTime.utc(now.year, month, day, hour, minute);

  // Reject values that rolled over, e.g. 31 February.
  if (candidate.month != month || candidate.day != day) return null;

  if (now.difference(candidate) > const Duration(days: 183)) {
    candidate = DateTime.utc(now.year + 1, month, day, hour, minute);
  }
  return candidate;
}
