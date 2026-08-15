import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freight_core/freight_core.dart';
import 'package:go_router/go_router.dart';

import '../data/freight_repository.dart';
import '../providers/watchlist.dart';
import '../widgets/common.dart';
import '../widgets/page_body.dart';

/// Trains and vessels the user has pinned, with a delay threshold they set.
class WatchlistScreen extends ConsumerWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watchlist = ref.watch(watchlistProvider);
    final trains =
        ref.watch(watchedTrainsProvider).value ?? const <FreightTrain>[];
    final vessels =
        ref.watch(watchedVesselsProvider).value ?? const <TrackedVessel>[];
    final alerts = ref.watch(watchlistAlertsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Watchlist'),
        actions: <Widget>[
          if (!watchlist.isEmpty)
            IconButton(
              tooltip: 'Clear watchlist',
              onPressed: () => ref.read(watchlistProvider.notifier).clear(),
              icon: const Icon(Icons.playlist_remove),
            ),
        ],
      ),
      body: PageBody(
        child: watchlist.isEmpty
            ? const _EmptyWatchlist()
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: <Widget>[
                  // Size and colour animate together when an alert appears or
                  // clears, so a change is noticed without a notification.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    transitionBuilder: (child, animation) => SizeTransition(
                      sizeFactor: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: alerts.isEmpty
                        ? const SizedBox.shrink(
                            key: ValueKey<String>('no-alerts'),
                          )
                        : _AlertBanner(
                            key: const ValueKey<String>('alerts'),
                            count: alerts.length,
                            minutes: watchlist.alertMinutes,
                          ),
                  ),
                  const AlertThresholdForm(),
                  if (trains.isNotEmpty) ...<Widget>[
                    _SectionHeader('Trains (${trains.length})'),
                    ...trains.map(
                      (train) => _DismissibleTile(
                        dismissKey: 'train-${train.id}',
                        onDismissed: () => ref
                            .read(watchlistProvider.notifier)
                            .toggleTrain(train.id),
                        removedLabel: 'Train ${train.trainNumber} removed',
                        onUndo: () => ref
                            .read(watchlistProvider.notifier)
                            .toggleTrain(train.id),
                        child: ListTile(
                          leading: const Icon(Icons.train_outlined),
                          title: Text('Train ${train.trainNumber}'),
                          subtitle: Text(
                            train.terminus?.stationName ??
                                'Destination unknown',
                          ),
                          trailing: DelayChip(
                            status: train.delayStatus,
                            minutes: train.worstDelay,
                          ),
                          onTap: () => context.go('/rail/${train.id}'),
                        ),
                      ),
                    ),
                  ],
                  if (vessels.isNotEmpty) ...<Widget>[
                    _SectionHeader('Vessels (${vessels.length})'),
                    ...vessels.map(
                      (tracked) => _DismissibleTile(
                        dismissKey: 'vessel-${tracked.mmsi}',
                        onDismissed: () => ref
                            .read(watchlistProvider.notifier)
                            .toggleVessel(tracked.mmsi),
                        removedLabel: '${tracked.vessel.name} removed',
                        onUndo: () => ref
                            .read(watchlistProvider.notifier)
                            .toggleVessel(tracked.mmsi),
                        child: ListTile(
                          leading: const Icon(Icons.directions_boat_outlined),
                          title: Text(tracked.vessel.name),
                          subtitle: Text(
                            '${tracked.vessel.category.label} · '
                            '${tracked.position.navigationStatus.label}',
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (trains.isEmpty && vessels.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Everything you pinned has finished its run or moved '
                        'out of range. Pins are kept until you remove them.',
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Swipe-to-remove with an undo, so a mis-swipe is not destructive.
class _DismissibleTile extends StatelessWidget {
  const _DismissibleTile({
    required this.dismissKey,
    required this.child,
    required this.onDismissed,
    required this.removedLabel,
    required this.onUndo,
  });

  final String dismissKey;
  final Widget child;
  final VoidCallback onDismissed;
  final String removedLabel;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey<String>(dismissKey),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: scheme.errorContainer,
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) {
        onDismissed();
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Text(removedLabel),
            action: SnackBarAction(label: 'Undo', onPressed: onUndo),
          ),
        );
      },
      child: child,
    );
  }
}

/// The one place in the app that takes free-text input.
///
/// Stateful on purpose: a [TextEditingController] and a [FocusNode] are
/// lifecycle-bound resources that must be created in [State.initState] and
/// released in [State.dispose]. Riverpod handles application state; this is
/// widget-owned state that belongs to the widget's lifetime.
class AlertThresholdForm extends ConsumerStatefulWidget {
  const AlertThresholdForm({super.key});

  @override
  ConsumerState<AlertThresholdForm> createState() => _AlertThresholdFormState();
}

class _AlertThresholdFormState extends ConsumerState<AlertThresholdForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(watchlistProvider).alertMinutes.toString(),
    );
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _focusNode.unfocus();
    await ref
        .read(watchlistProvider.notifier)
        .setAlertMinutes(int.parse(_controller.text.trim()));

    if (!mounted) return;
    setState(() => _saved = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _saved = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Form(
        key: _formKey,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: TextFormField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: Watchlist.validateAlertMinutes,
                decoration: const InputDecoration(
                  labelText: 'Alert when later than',
                  suffixText: 'min',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: FilledButton.tonal(
                onPressed: _submit,
                // Swapping the label rather than firing a snackbar keeps the
                // confirmation next to the control that caused it.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _saved
                      ? Icon(
                          Icons.check,
                          key: const ValueKey<String>('saved'),
                          color: theme.colorScheme.primary,
                        )
                      : const Text('Save', key: ValueKey<String>('save')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.count, required this.minutes, super.key});

  final int count;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.warning_amber, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$count watched ${count == 1 ? 'train is' : 'trains are'} '
              'more than $minutes min late',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _EmptyWatchlist extends StatelessWidget {
  const _EmptyWatchlist();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.bookmark_border,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text('Nothing pinned yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Tap the bookmark on any train in the Rail tab to follow it '
              'here, and set a delay threshold to be warned when it slips.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
