/// Identifies this client to Fintraffic, as their usage instructions request.
const String digitrafficUserAgent = 'calemccammon/flutter-freight-corridor';

/// Headers used in the browser.
///
/// `Accept-Encoding` is deliberately absent. It is a forbidden header name, so
/// `XMLHttpRequest.setRequestHeader` ignores it and the console fills with
/// `Refused to set unsafe header` warnings. Browsers already send
/// `Accept-Encoding: gzip, deflate, br` on every request, which is what
/// satisfies Digitraffic's `406` check — verified against the live endpoint.
Map<String, String> digitrafficHeaders() => const <String, String>{
  'Digitraffic-User': digitrafficUserAgent,
  'Accept': 'application/json',
};
