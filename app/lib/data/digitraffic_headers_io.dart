/// Identifies this client to Fintraffic, as their usage instructions request.
/// It also raises the per-IP rate limit above the anonymous allowance.
const String digitrafficUserAgent = 'calemccammon/flutter-freight-corridor';

/// Headers used on the VM (Android, desktop, tests).
///
/// `Accept-Encoding: gzip` is mandatory — Digitraffic answers `406` without
/// it. `dart:io` would set it anyway, but stating it makes the requirement
/// visible rather than an accident of the platform.
Map<String, String> digitrafficHeaders() => const <String, String>{
  'Digitraffic-User': digitrafficUserAgent,
  'Accept': 'application/json',
  'Accept-Encoding': 'gzip',
};
