/// Domain models and business logic for freight rail and maritime cargo.
///
/// This package deliberately depends on nothing from Flutter. Every rule that
/// decides what the app *means* — what counts as a freight vessel, when a
/// train is late, which port a rail terminus feeds — lives here and is covered
/// by tests that run in milliseconds without a device or a network.
library;

export 'src/logic/ais_codes.dart';
export 'src/logic/corridor_linker.dart';
export 'src/logic/geo.dart';
export 'src/logic/geojson.dart';
export 'src/logic/schedule.dart';
export 'src/models/corridor.dart';
export 'src/models/freight_train.dart';
export 'src/models/geo_point.dart';
export 'src/models/port.dart';
export 'src/models/port_call.dart';
export 'src/models/vessel.dart';
