# Version pinning — read before writing code

This project targets **Flutter 3.47 / Dart 3.13**. Several things here differ from what most
tutorials and model priors assume:

- **Riverpod is 3.x, not 2.x.** `Ref` is non-generic (`Ref ref`, never `TrainsRef ref`), and
  `AsyncValue.valueOrNull` is gone — use `.value`. `Override` is exported from
  `package:flutter_riverpod/misc.dart`, not the main barrel.
- **Providers are hand-written on purpose.** `riverpod_generator ≥4.0.6` needs `analyzer ^13`;
  every published `ferry_generator` caps `analyzer <13`. They cannot co-resolve. Do not add
  `riverpod_generator` or `riverpod_lint` — pub will fail. Same for `custom_lint`, which pins
  `analyzer_plugin ^0.13` against `riverpod_lint`'s `^0.14`.
- **`build_runner` is held below 2.15.2** for the same reason (2.15.2+ requires `analyzer ≥13.3`).
- **Generated code is gitignored.** Run `dart run build_runner build` in `app/` after a clean
  checkout. `--delete-conflicting-outputs` was removed in build_runner 2.15 and now warns.
- **`ferry` pulls in `hive 2.2.3`**, which is unmaintained. It is dormant: the client uses the
  in-memory `Cache()` and never calls `Hive.init`. Do not add `ferry_hive_store`.

## Rules specific to this codebase

- `packages/freight_core` must never import Flutter. It is the reason the domain rules are
  testable in a second; keep it that way.
- Never import `dart:io` outside `digitraffic_headers_io.dart` — one stray import breaks the web
  build, and the web build is the live demo.
- Digitraffic returns **406** without `Accept-Encoding: gzip`. Set it on the VM only; it is a
  forbidden header in browsers, which send it themselves.
- Both APIs report coordinates as `[longitude, latitude]`. Use `GeoPoint.fromLonLat`.
- AIS `properties.timestamp` is a second-of-minute, not a time. Use `timestampExternal`.
