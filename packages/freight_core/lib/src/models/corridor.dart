import 'package:meta/meta.dart';

import 'freight_train.dart';
import 'port.dart';
import 'port_call.dart';
import 'vessel.dart';

/// A rail terminus paired with the seaport it feeds, plus everything currently
/// moving along that link.
///
/// This is the idea the whole app exists to show: Finnish freight arrives
/// inland by rail and leaves by sea, and the two halves are published by two
/// unrelated APIs that share no identifiers. Joining them is done here, in
/// plain Dart, with no framework involved.
@immutable
class FreightCorridor {
  const FreightCorridor({
    required this.port,
    required this.terminusName,
    required this.distanceKm,
    required this.bearingDegrees,
    required this.compassLabel,
    required this.inboundTrains,
    required this.vesselsAtPort,
    required this.upcomingCalls,
  });

  final Port port;

  /// The rail station whose position anchored this pairing.
  final String terminusName;

  final double distanceKm;
  final double bearingDegrees;
  final String compassLabel;

  final List<FreightTrain> inboundTrains;
  final List<VesselPosition> vesselsAtPort;
  final List<PortCall> upcomingCalls;

  /// How busy the link is right now. Used only for ordering, so the weights
  /// are a judgement call rather than a measurement: a port call is a firmer
  /// signal of cargo movement than a vessel merely being nearby.
  int get intensity =>
      inboundTrains.length * 3 +
      upcomingCalls.length * 2 +
      vesselsAtPort.length;

  bool get isActive => intensity > 0;

  int get cargoMovingCalls =>
      upcomingCalls.where((call) => call.cargoIntent.movesCargo).length;

  @override
  String toString() =>
      'FreightCorridor(${port.locode} <- $terminusName, intensity $intensity)';
}
