import 'package:flutter/material.dart';
import 'package:freight_core/freight_core.dart';

/// Colour-coded schedule adherence.
///
/// The bucketing itself lives in `freight_core`, so this widget only decides
/// how each bucket looks — the rule for what counts as "late" is testable
/// without a widget tree.
class DelayChip extends StatelessWidget {
  const DelayChip({required this.status, this.minutes, super.key});

  final DelayStatus status;
  final int? minutes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (Color background, Color foreground, String text) = switch (status) {
      DelayStatus.early => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        minutes == null ? 'Early' : '${minutes!.abs()} min early',
      ),
      DelayStatus.onTime => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        'On time',
      ),
      DelayStatus.minor => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        '${minutes ?? 0} min late',
      ),
      DelayStatus.major => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        '${minutes ?? 0} min late',
      ),
      DelayStatus.unknown => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        'No data',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground),
      ),
    );
  }
}

/// A single headline number.
class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.value,
    this.detail,
    this.icon,
    super.key,
  });

  final String label;
  final String value;
  final String? detail;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: theme.textTheme.headlineSmall),
            if (detail != null)
              Text(
                detail!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

/// Proportional bar showing what a train is made of.
class CompositionBar extends StatelessWidget {
  const CompositionBar({required this.composition, super.key});

  final WagonComposition composition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wagons = composition.wagonCount;
    final locomotives = composition.locomotiveCount;
    final total = wagons + locomotives;
    if (total == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: locomotives,
                child: Container(height: 12, color: theme.colorScheme.primary),
              ),
              Expanded(
                flex: wagons,
                child: Container(
                  height: 12,
                  color: theme.colorScheme.primaryContainer,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$locomotives locomotive${locomotives == 1 ? '' : 's'} · '
          '$wagons wagon${wagons == 1 ? '' : 's'} · '
          '${composition.totalLengthMetres.round()} m',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
