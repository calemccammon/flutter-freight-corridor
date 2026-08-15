import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freight_core/freight_core.dart';
import 'package:go_router/go_router.dart';

import '../providers/freight_providers.dart';
import '../widgets/async_value_view.dart';
import '../widgets/common.dart';
import '../widgets/page_body.dart';

/// The national picture in four numbers, plus whatever is running late.
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trains = ref.watch(cargoTrainsProvider);
    final vessels = ref.watch(freightVesselsProvider);
    final calls = ref.watch(portCallsProvider);
    final onTime = ref.watch(onTimeShareProvider);
    final delayed = ref.watch(delayedTrainsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Freight Corridor'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref
                ..invalidate(cargoTrainsProvider)
                ..invalidate(freightVesselsProvider)
                ..invalidate(portCallsProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: PageBody(
        child: RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(cargoTrainsProvider)
              ..invalidate(freightVesselsProvider)
              ..invalidate(portCallsProvider);
            await ref.read(cargoTrainsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              // Two columns on a phone, four on a wide web window.
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth > 700 ? 4 : 2;
                  // Derive the ratio from the actual tile width so the cards
                  // stay the same height whether there are two columns on a
                  // phone or four across a desktop browser window.
                  final spacing = 12.0 * (columns - 1);
                  final tileWidth = (constraints.maxWidth - spacing) / columns;
                  return GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: tileWidth / 116,
                    children: <Widget>[
                      StatCard(
                        label: 'Cargo trains running',
                        icon: Icons.train,
                        value: trains.value?.length.toString() ?? '—',
                        detail: 'across Finland',
                      ),
                      StatCard(
                        label: 'On time',
                        icon: Icons.schedule,
                        value: onTime == null
                            ? '—'
                            : '${(onTime * 100).round()}%',
                        detail: 'within 3 min',
                      ),
                      StatCard(
                        label: 'Freight vessels',
                        icon: Icons.directions_boat,
                        value: vessels.value?.value.length.toString() ?? '—',
                        detail: 'near your home port',
                      ),
                      StatCard(
                        label: 'Port calls',
                        icon: Icons.anchor,
                        value: calls.value?.value.length.toString() ?? '—',
                        detail: 'scheduled and current',
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Running late',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 260,
                child: AsyncValueView<List<FreightTrain>>(
                  value: delayed,
                  onRetry: () => ref.invalidate(cargoTrainsProvider),
                  emptyTitle: 'Everything is on time',
                  emptyMessage:
                      'No cargo train is more than three minutes behind '
                      'schedule right now.',
                  data: (late) => ListView.builder(
                    itemCount: late.length,
                    itemBuilder: (context, index) {
                      final train = late[index];
                      return ListTile(
                        leading: const Icon(Icons.train_outlined),
                        title: Text(
                          'Train ${train.trainNumber} · '
                          '${train.operatorShortCode.toUpperCase()}',
                        ),
                        subtitle: Text(
                          train.terminus?.stationName ?? 'Destination unknown',
                        ),
                        trailing: DelayChip(
                          status: train.delayStatus,
                          minutes: train.worstDelay,
                        ),
                        onTap: () => context.go('/rail/${train.id}'),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
