import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freight_core/freight_core.dart';
import 'package:go_router/go_router.dart';

import '../providers/freight_providers.dart';
import '../widgets/async_value_view.dart';
import '../widgets/common.dart';

/// Every cargo train currently running, worst delay first.
class RailScreen extends ConsumerWidget {
  const RailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trains = ref.watch(filteredTrainsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cargo rail'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SearchBar(
              hintText: 'Train number, operator or destination',
              leading: const Icon(Icons.search),
              onChanged: (value) =>
                  ref.read(railFilterProvider.notifier).set(value),
            ),
          ),
        ),
      ),
      body: AsyncValueView<List<FreightTrain>>(
        value: trains,
        onRetry: () => ref.invalidate(cargoTrainsProvider),
        emptyTitle: 'No cargo trains match',
        emptyMessage:
            'Finnish freight rail is quiet at some hours — try clearing the '
            'search, or check back shortly.',
        data: (list) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(cargoTrainsProvider);
            await ref.read(cargoTrainsProvider.future);
          },
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) => _TrainTile(train: list[index]),
          ),
        ),
      ),
    );
  }
}

class _TrainTile extends StatelessWidget {
  const _TrainTile({required this.train});

  final FreightTrain train;

  @override
  Widget build(BuildContext context) {
    final speed = train.speedKmh;
    final subtitle = <String>[
      train.operatorName,
      if (train.terminus != null) '→ ${train.terminus!.stationName}',
      if (speed != null && speed > 0) '${speed.round()} km/h' else 'stationary',
    ].join(' · ');

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          train.isMoving ? Icons.train : Icons.pause,
          size: 18,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text('Train ${train.trainNumber}'),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: DelayChip(status: train.delayStatus, minutes: train.worstDelay),
      onTap: () => context.go('/rail/${train.id}'),
    );
  }
}
