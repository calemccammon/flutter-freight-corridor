import 'package:meta/meta.dart';

/// What a vessel is at the berth to do.
///
/// The API does not state this directly; it exposes three weakly-named flags
/// and leaves the interpretation to the caller. Deriving it once here — and
/// testing it — is the difference between a screen that shows `notLoading:
/// false` and one that shows "Loading".
enum CargoIntent {
  loading('Loading'),
  discharging('Discharging'),
  both('Loading & discharging'),
  ballast('In ballast'),
  unknown('Unknown');

  const CargoIntent(this.label);

  final String label;

  /// True when cargo actually moves across the quay, which is what makes a
  /// call interesting to a freight corridor.
  bool get movesCargo =>
      this == CargoIntent.loading ||
      this == CargoIntent.discharging ||
      this == CargoIntent.both;

  static CargoIntent from({
    bool? arrivalWithCargo,
    bool? notLoading,
    int? discharge,
  }) {
    final willDischarge = (discharge ?? 0) > 0 || (arrivalWithCargo ?? false);
    final willLoad = notLoading == false;

    if (willDischarge && willLoad) return CargoIntent.both;
    if (willDischarge) return CargoIntent.discharging;
    if (willLoad) return CargoIntent.loading;
    if (arrivalWithCargo == false && (notLoading ?? false)) {
      return CargoIntent.ballast;
    }
    return CargoIntent.unknown;
  }
}

/// Times and berth for one leg of a port visit.
@immutable
class PortAreaVisit {
  const PortAreaVisit({
    this.berthName,
    this.portAreaName,
    this.eta,
    this.ata,
    this.etd,
    this.atd,
    this.arrivalDraughtMetres,
  });

  final String? berthName;
  final String? portAreaName;

  /// Estimated and actual times of arrival and departure. The gap between
  /// [eta] and [ata] is the only real measure of schedule reliability the
  /// maritime feed offers.
  final DateTime? eta;
  final DateTime? ata;
  final DateTime? etd;
  final DateTime? atd;

  final double? arrivalDraughtMetres;

  /// Minutes late on arrival, negative when early. Null until the vessel has
  /// actually arrived and both times are known.
  int? get arrivalDelayMinutes {
    final estimated = eta;
    final actual = ata;
    if (estimated == null || actual == null) return null;
    return actual.difference(estimated).inMinutes;
  }

  bool get hasArrived => ata != null;
  bool get hasDeparted => atd != null;
}

/// A scheduled or completed vessel visit to a Finnish port.
@immutable
class PortCall {
  const PortCall({
    required this.portCallId,
    required this.portToVisit,
    required this.vesselName,
    required this.cargoIntent,
    required this.visits,
    this.mmsi,
    this.imoLloyds,
    this.prevPort,
    this.nextPort,
    this.vesselTypeCode,
    this.nationality,
    this.agentInfo,
  });

  final int portCallId;

  /// LOCODE of the port being visited.
  final String portToVisit;

  final String vesselName;
  final CargoIntent cargoIntent;
  final List<PortAreaVisit> visits;

  /// Shared with the AIS feed, so a port call can be matched to a live
  /// position. Not always present.
  final int? mmsi;

  final int? imoLloyds;
  final String? prevPort;
  final String? nextPort;
  final String? vesselTypeCode;
  final String? nationality;
  final String? agentInfo;

  /// A call can span several berths; the call as a whole starts at whichever
  /// of them comes first.
  DateTime? _earliest(DateTime? Function(PortAreaVisit visit) pick) {
    DateTime? earliest;
    for (final visit in visits) {
      final candidate = pick(visit);
      if (candidate == null) continue;
      if (earliest == null || candidate.isBefore(earliest)) {
        earliest = candidate;
      }
    }
    return earliest;
  }

  /// Earliest expected arrival across the call's berths.
  DateTime? get eta => _earliest((visit) => visit.eta);

  /// Earliest actual arrival, once the vessel is alongside.
  DateTime? get ata => _earliest((visit) => visit.ata);

  bool get hasArrived => visits.any((visit) => visit.hasArrived);

  int? get arrivalDelayMinutes {
    for (final visit in visits) {
      final delay = visit.arrivalDelayMinutes;
      if (delay != null) return delay;
    }
    return null;
  }

  /// True when the call is expected within [window] from [now] and has not
  /// happened yet — the definition of "inbound" used by the corridor view.
  bool isInboundWithin(Duration window, {required DateTime now}) {
    if (hasArrived) return false;
    final expected = eta;
    if (expected == null) return false;
    return expected.isAfter(now) && expected.difference(now) <= window;
  }

  @override
  String toString() => 'PortCall($portCallId, $vesselName -> $portToVisit)';
}
