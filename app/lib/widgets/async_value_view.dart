import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/freight_repository.dart';

/// Renders the four states every async screen has, in one place.
///
/// Without this, loading spinners, error text and empty states get
/// reimplemented slightly differently on each screen. `AsyncValue` already
/// models loading/error/data; the only thing it does not know about is
/// "succeeded, but there is nothing to show", which for this app is a normal
/// outcome rather than a bug — Finnish freight rail genuinely goes quiet at
/// three in the morning.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    required this.value,
    required this.data,
    this.onRetry,
    this.isEmpty,
    this.emptyTitle = 'Nothing to show',
    this.emptyMessage,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(T value) data;
  final VoidCallback? onRetry;

  /// Defaults to "an empty collection is empty".
  final bool Function(T value)? isEmpty;
  final String emptyTitle;
  final String? emptyMessage;

  bool _looksEmpty(T value) {
    final predicate = isEmpty;
    if (predicate != null) return predicate(value);
    return value is Iterable && value.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return value.when(
      // Keep the previous data on screen while a refresh is in flight, so
      // pull-to-refresh does not blank the list.
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Message(
        icon: Icons.cloud_off,
        title: error is FreightException ? error.message : 'Something broke',
        detail: error is FreightException ? error.detail : error.toString(),
        onRetry: onRetry,
      ),
      data: (resolved) {
        if (_looksEmpty(resolved)) {
          return _Message(
            icon: Icons.inbox_outlined,
            title: emptyTitle,
            detail: emptyMessage,
            onRetry: onRetry,
          );
        }
        return data(resolved);
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (detail != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                detail!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown above real data when it came from the snapshot store rather than the
/// network. Being explicit about staleness is more useful than either hiding
/// it or replacing the content with an error.
class StaleBanner extends StatelessWidget {
  const StaleBanner({required this.capturedAt, super.key});

  final DateTime capturedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final age = DateTime.now().toUtc().difference(capturedAt);
    final label = age.inMinutes < 1
        ? 'moments ago'
        : age.inHours < 1
        ? '${age.inMinutes} min ago'
        : '${age.inHours} h ago';

    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.cloud_off,
              size: 16,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Offline — showing data cached $label',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
