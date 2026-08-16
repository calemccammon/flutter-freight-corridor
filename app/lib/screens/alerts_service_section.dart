import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/alerts_client.dart';
import '../providers/alerts_sync.dart';
import '../providers/watchlist.dart';

/// Connects the app to the companion alerts service.
///
/// The watchlist on this device only matters while the app is open. Registering
/// it with the service means a delay is caught while the phone is in a pocket,
/// and survives a reinstall — which is the whole reason this section exists.
///
/// Stateful because it owns two text controllers and a transient status line;
/// the persisted values live in [alertsConnectionProvider].
class AlertsServiceSection extends ConsumerStatefulWidget {
  const AlertsServiceSection({super.key});

  @override
  ConsumerState<AlertsServiceSection> createState() =>
      _AlertsServiceSectionState();
}

class _AlertsServiceSectionState extends ConsumerState<AlertsServiceSection> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;

  String? _status;
  bool _statusIsError = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final connection = ref.read(alertsConnectionProvider);
    _urlController = TextEditingController(text: connection.baseUrl);
    _tokenController = TextEditingController(text: connection.token);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _report(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusIsError = isError;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await _run(() async {
      await ref
          .read(alertsConnectionProvider.notifier)
          .save(baseUrl: _urlController.text, token: _tokenController.text);
      try {
        final login = await ref
            .read(alertsSyncProvider.notifier)
            .testConnection();
        _report('Connected as $login');
      } on AlertsException catch (error) {
        // The service's own message says more than "connection failed" would.
        _report(error.message, isError: true);
      }
    });
  }

  Future<void> _sync() async {
    await _run(() async {
      final outcome = await ref
          .read(alertsSyncProvider.notifier)
          .syncWatchlist();
      if (!outcome.succeeded) {
        _report(outcome.error!, isError: true);
        return;
      }
      final skipped = outcome.skippedVessels;
      _report(
        'Registered ${outcome.synced} '
        '${outcome.synced == 1 ? 'train' : 'trains'}'
        // Named rather than dropped silently: the service is rail-only, and a
        // vanished vessel would look like a bug.
        '${skipped > 0 ? ' — $skipped watched ${skipped == 1 ? 'vessel is' : 'vessels are'} not supported by the service yet' : ''}',
      );
    });
  }

  Future<void> _disconnect() async {
    await _run(() async {
      await ref.read(alertsConnectionProvider.notifier).disconnect();
      _urlController.clear();
      _tokenController.clear();
      _report('Disconnected');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connection = ref.watch(alertsConnectionProvider);
    final watchlist = ref.watch(watchlistProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Register this watchlist with the companion service so delays are '
              'caught while the app is closed. Sign in there with GitHub, mint a '
              'device token, and paste it below.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _urlController,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Service URL',
                hintText: 'https://alerts.example.com',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              validator: AlertsClient.validateBaseUrl,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tokenController,
              autocorrect: false,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Device token',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              validator: AlertsClient.validateToken,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton(
                  onPressed: _busy ? null : _connect,
                  child: const Text('Connect'),
                ),
                OutlinedButton(
                  // Nothing to sync without a connection or a watchlist, so the
                  // button says so by being unavailable rather than failing.
                  onPressed: _busy || !connection.isConfigured || watchlist.isEmpty
                      ? null
                      : _sync,
                  child: Text('Sync ${watchlist.trainIds.length} trains'),
                ),
                if (connection.isConfigured)
                  TextButton(
                    onPressed: _busy ? null : _disconnect,
                    child: const Text('Disconnect'),
                  ),
              ],
            ),
            if (_busy) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_status != null) ...<Widget>[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    _statusIsError ? Icons.error_outline : Icons.check_circle_outline,
                    size: 18,
                    color: _statusIsError
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _status!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _statusIsError ? theme.colorScheme.error : null,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
