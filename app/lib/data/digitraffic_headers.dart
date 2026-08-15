/// Digitraffic asks every client to identify itself, and rejects any request
/// that does not accept gzip with `406 Not Acceptable`.
///
/// Supplying `Accept-Encoding` is correct on the VM and *wrong* in a browser:
/// it is a forbidden header name, so the browser sets it itself and logs a
/// `Refused to set unsafe header` warning if we try. The conditional export
/// below picks the right set at compile time — the one place in this app where
/// the two platforms genuinely differ.
library;

export 'digitraffic_headers_io.dart'
    if (dart.library.js_interop) 'digitraffic_headers_web.dart';
