import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freight_core/freight_core.dart';
import 'package:intl/intl.dart';

import '../providers/freight_providers.dart';
import '../widgets/async_value_view.dart';
import '../widgets/common.dart';
import '../widgets/page_body.dart';

/// One train: what it is made of, and how it is running against timetable.
class TrainDetailScreen extends ConsumerWidget {
  const TrainDetailScreen({required this.trainId, super.key});

  /// `trainNumber/departureDate`, matching [FreightTrain.id].
  final String trainId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final train = ref.watch(trainDetailProvider(trainId));

    return Scaffold(
      appBar: AppBar(title: Text('Train ${trainId.split('/').first}')),
      body: PageBody(
        child: AsyncValueView<FreightTrain?>(
          value: train,
          onRetry: () => ref.invalidate(trainDetailProvider(trainId)),
          isEmpty: (value) => value == null,
          emptyTitle: 'Train not found',
          emptyMessage: 'It may have completed its run.',
          data: (value) => _Detail(train: value!),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.train});

  final FreightTrain train;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateFormat.Hm();
    final composition = train.composition;
    final adherence = train.adherence;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: StatCard(
                label: 'Operator',
                value: train.operatorShortCode.toUpperCase(),
                detail: train.operatorName,
                icon: Icons.business,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: 'Schedule kept',
                value: adherence == null
                    ? '—'
                    : '${(adherence * 100).round()}%',
                detail: '${train.stops.length} stops',
                icon: Icons.schedule,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Route', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        train.origin?.stationName ?? 'Unknown origin',
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: theme.colorScheme.outline,
                    ),
                    Expanded(
                      child: Text(
                        train.terminus?.stationName ?? 'Unknown destination',
                        style: theme.textTheme.titleSmall,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    Chip(
                      avatar: Icon(
                        train.isMoving ? Icons.speed : Icons.pause,
                        size: 16,
                      ),
                      label: Text(
                        train.isMoving
                            ? '${train.speedKmh!.round()} km/h'
                            : 'Stationary',
                      ),
                    ),
                    if (train.nextStop case final TimetableStop next)
                      Chip(
                        avatar: const Icon(Icons.place_outlined, size: 16),
                        label: Text('Next: ${next.stationName}'),
                      ),
                    Chip(
                      avatar: const Icon(Icons.today_outlined, size: 16),
                      label: Text(train.departureDate),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Composition', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        if (composition == null)
          // Not a bug, and worth saying so rather than showing nothing:
          // Digitraffic publishes wagon composition for passenger services,
          // where seat and carriage detail matters to travellers. Freight
          // trains return an empty list — verified across every cargo train
          // running at the time of writing.
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(
                Icons.info_outline,
                color: theme.colorScheme.outline,
              ),
              title: const Text('No composition published'),
              subtitle: const Text(
                'Digitraffic publishes wagon composition for passenger '
                'services only; freight trains return none.',
              ),
            ),
          )
        else ...<Widget>[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CompositionBar(composition: composition),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      if (composition.maximumSpeedKmh != null)
                        Chip(
                          label: Text(
                            'Max ${composition.maximumSpeedKmh} km/h',
                          ),
                        ),
                      if (composition.dominantWagonType != null)
                        Chip(
                          label: Text(
                            'Mostly ${composition.dominantWagonType}',
                          ),
                        ),
                      Chip(
                        label: Text(
                          composition.isElectricHauled
                              ? 'Electric haulage'
                              : 'Diesel haulage',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text('Timetable', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        // Already-fetched data, so a plain column beats a nested scroll view.
        ...train.stops.map(
          (stop) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              stop.type == StopType.departure
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              size: 16,
              color: theme.colorScheme.outline,
            ),
            title: Text(stop.stationName),
            // Stations appear twice — once arriving, once departing — so the
            // direction has to be spelled out, not left to an arrow glyph.
            subtitle: Text(
              '${stop.type == StopType.departure ? 'Departure' : 'Arrival'} · '
              '${time.format(stop.scheduledTime.toLocal())} scheduled'
              '${stop.actualTime != null ? ' · ${time.format(stop.actualTime!.toLocal())} actual' : ''}',
            ),
            trailing: DelayChip(
              status: stop.delayStatus,
              minutes: stop.differenceInMinutes,
            ),
          ),
        ),
      ],
    );
  }
}
