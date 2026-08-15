import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freight_core/freight_core.dart';
import 'package:intl/intl.dart';

import '../providers/freight_providers.dart';
import '../widgets/async_value_view.dart';
import '../widgets/page_body.dart';

/// The point of the app: rail termini paired with the seaports they feed.
///
/// Nothing on this screen comes from a single API. Trains arrive over GraphQL,
/// vessels and port calls over REST, and the pairing is computed by
/// `linkCorridors` in the pure-Dart core package.
class CorridorsScreen extends ConsumerWidget {
  const CorridorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final corridors = ref.watch(corridorsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Corridors'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(corridorsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: PageBody(
        child: AsyncValueView<List<FreightCorridor>>(
          value: corridors,
          onRetry: () => ref.invalidate(corridorsProvider),
          emptyTitle: 'No active corridors',
          emptyMessage:
              'No cargo train is currently heading for a seaport. This is '
              'normal outside working hours.',
          data: (list) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(corridorsProvider);
              await ref.read(corridorsProvider.future);
            },
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, index) =>
                  _CorridorTile(corridor: list[index]),
            ),
          ),
        ),
      ),
    );
  }
}

class _CorridorTile extends StatelessWidget {
  const _CorridorTile({required this.corridor});

  final FreightCorridor corridor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateFormat.Hm();

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        // ExpansionTile wraps its children in an Align that defaults to
        // centre, so without this the body floats in the middle of a wide
        // window instead of lining up with the title.
        expandedAlignment: Alignment.centerLeft,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        childrenPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            corridor.intensity.toString(),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(corridor.port.name),
        subtitle: Text(
          '${corridor.terminusName} · '
          '${corridor.distanceKm.toStringAsFixed(1)} km '
          '${corridor.compassLabel}',
        ),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    Chip(
                      avatar: const Icon(Icons.train, size: 16),
                      label: Text('${corridor.inboundTrains.length} inbound'),
                    ),
                    Chip(
                      avatar: const Icon(Icons.directions_boat, size: 16),
                      label: Text('${corridor.vesselsAtPort.length} vessels'),
                    ),
                    Chip(
                      avatar: const Icon(Icons.anchor, size: 16),
                      label: Text(
                        '${corridor.upcomingCalls.length} '
                        'call${corridor.upcomingCalls.length == 1 ? '' : 's'}',
                      ),
                    ),
                  ],
                ),
                if (corridor.inboundTrains.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text('Inbound trains', style: theme.textTheme.labelLarge),
                  ...corridor.inboundTrains.map(
                    (train) => Text(
                      '· ${train.trainNumber} '
                      '(${train.operatorShortCode.toUpperCase()})'
                      '${train.isMoving ? ' — ${train.speedKmh!.round()} km/h' : ' — stationary'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
                if (corridor.upcomingCalls.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    'Expected within 24 h',
                    style: theme.textTheme.labelLarge,
                  ),
                  ...corridor.upcomingCalls.map(
                    (call) => Text(
                      '· ${call.vesselName} — ${call.cargoIntent.label}'
                      '${call.eta != null ? ' at ${time.format(call.eta!.toLocal())}' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
