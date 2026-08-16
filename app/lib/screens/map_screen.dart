import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freight_core/freight_core.dart' as core;
import 'package:latlong2/latlong.dart';

import '../data/freight_repository.dart';
import '../providers/freight_providers.dart';
import '../providers/settings.dart';
import '../widgets/async_value_view.dart';

/// Live freight vessels and cargo trains on one map.
class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  /// Markers are capped because CanvasKit drops frames well before the data
  /// does. Nearest-first keeps the cap meaningful rather than arbitrary.
  static const _maxVesselMarkers = 150;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vessels = ref.watch(liveVesselsProvider);
    final trains = ref.watch(cargoTrainsProvider);
    final homePort = ref.watch(settingsProvider.select((s) => s.homePort));

    return Scaffold(
      appBar: AppBar(title: Text('Map · ${homePort.label}')),
      body: AsyncValueView<Sourced<List<TrackedVessel>>>(
        value: vessels,
        onRetry: () => ref.invalidate(liveVesselsProvider),
        isEmpty: (sourced) => sourced.value.isEmpty,
        emptyTitle: 'No freight vessels in range',
        emptyMessage: 'Try widening the search radius in Settings.',
        data: (sourced) => Column(
          children: <Widget>[
            if (sourced.isStale && sourced.capturedAt != null)
              StaleBanner(capturedAt: sourced.capturedAt!),
            Expanded(
              child: _Map(
                centre: homePort.point,
                vessels: sourced.value.take(_maxVesselMarkers).toList(),
                trains: trains.value ?? const <core.FreightTrain>[],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Map extends StatelessWidget {
  const _Map({
    required this.centre,
    required this.vessels,
    required this.trains,
  });

  final core.GeoPoint centre;
  final List<TrackedVessel> vessels;
  final List<core.FreightTrain> trains;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Stack(
      children: <Widget>[
        FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(centre.latitude, centre.longitude),
            initialZoom: 7,
            // Rotation adds nothing here and costs a repaint on every drag.
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: <Widget>[
            TileLayer(
              // CARTO rather than raw OpenStreetMap tiles: OSM's usage policy
              // requires an identifying User-Agent, which a browser will not
              // let the app set, so the web build could never comply. CARTO
              // serves CORS-enabled tiles and has a dark variant that follows
              // the app theme.
              urlTemplate: isDark
                  ? 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                  : 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
              retinaMode: RetinaMode.isHighDensity(context),
              userAgentPackageName: 'com.calemccammon.freight_corridor',
            ),
            MarkerLayer(
              markers: <Marker>[
                for (final train in trains)
                  if (train.position != null)
                    Marker(
                      point: LatLng(
                        train.position!.latitude,
                        train.position!.longitude,
                      ),
                      width: 22,
                      height: 22,
                      child: _Dot(
                        icon: Icons.train,
                        colour: theme.colorScheme.primary,
                      ),
                    ),
                for (final tracked in vessels)
                  Marker(
                    point: LatLng(
                      tracked.position.point.latitude,
                      tracked.position.point.longitude,
                    ),
                    width: 22,
                    height: 22,
                    child: Tooltip(
                      message:
                          '${tracked.vessel.name}\n'
                          '${tracked.vessel.category.label} · '
                          '${tracked.position.navigationStatus.label}',
                      child: _Dot(
                        icon: Icons.directions_boat,
                        colour:
                            tracked.vessel.category == core.ShipCategory.tanker
                            ? theme.colorScheme.error
                            : theme.colorScheme.tertiary,
                      ),
                    ),
                  ),
              ],
            ),
            // Two different things need crediting here, and only the basemap
            // was. The tiles are OpenStreetMap via CARTO; the trains and
            // vessels drawn on top are Fintraffic's open data under CC BY 4.0,
            // which requires the licence to be indicated wherever the data is
            // shown -- not only in the repository README that no user reads.
            const RichAttributionWidget(
              attributions: <SourceAttribution>[
                TextSourceAttribution('OpenStreetMap contributors'),
                TextSourceAttribution('CARTO'),
                TextSourceAttribution(
                  'Traffic data: Fintraffic Digitraffic, CC BY 4.0',
                ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 12,
          top: 12,
          child: _Legend(
            trains: trains.where((t) => t.position != null).length,
            vessels: vessels.length,
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.icon, required this.colour});

  final IconData icon;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colour,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Icon(icon, size: 12, color: Colors.white),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.trains, required this.vessels});

  final int trains;
  final int vessels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          '$trains trains · $vessels vessels',
          style: theme.textTheme.labelMedium,
        ),
      ),
    );
  }
}
