import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings.dart';
import '../widgets/page_body.dart';

/// Everything here writes straight through to storage and invalidates only the
/// providers that depend on the value changed.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: <Widget>[
            _SectionLabel('Home port'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final port in HomePort.values)
                    ChoiceChip(
                      label: Text(port.label),
                      selected: settings.homePort == port,
                      onSelected: (_) => controller.setHomePort(port),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionLabel('Search radius'),
            ListTile(
              title: Slider(
                value: settings.radiusKm,
                min: 20,
                max: 300,
                divisions: 28,
                label: '${settings.radiusKm.round()} km',
                onChanged: controller.setRadiusKm,
              ),
              subtitle: Text(
                'Vessels within ${settings.radiusKm.round()} km of '
                '${settings.homePort.label}',
                style: theme.textTheme.bodySmall,
              ),
            ),
            _SectionLabel('Refresh interval'),
            ListTile(
              title: Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final seconds in <int>[10, 20, 60])
                    ChoiceChip(
                      label: Text('${seconds}s'),
                      selected: settings.pollSeconds == seconds,
                      onSelected: (_) => controller.setPollSeconds(seconds),
                    ),
                ],
              ),
              subtitle: Text(
                'Digitraffic allows 60 requests a minute; at '
                '${settings.pollSeconds}s this app uses '
                '${(60 / settings.pollSeconds).round()}.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            _SectionLabel('Appearance'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<ThemeMode>(
                // A segmented button rather than radio tiles: `RadioListTile`'s
                // groupValue/onChanged were deprecated in Flutter 3.32 in favour
                // of a RadioGroup ancestor, and for three mutually exclusive
                // options this is less markup either way.
                segments: const <ButtonSegment<ThemeMode>>[
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.system,
                    label: Text('System'),
                    icon: Icon(Icons.brightness_auto),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode),
                  ),
                ],
                selected: <ThemeMode>{settings.themeMode},
                onSelectionChanged: (selection) =>
                    controller.setThemeMode(selection.first),
              ),
            ),
            const Divider(height: 32),
            const AboutSection(),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Data sources', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            'Rail traffic from the Fintraffic Digitraffic GraphQL API; vessel '
            'positions and port calls from the Digitraffic marine REST APIs. '
            'Both are open data and need no API key.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text('Licence', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          // CC BY 4.0 asks for four things: credit the source, link to it,
          // indicate the licence, and say so where the material was modified.
          // This screen is the only place in the app a user can read all four,
          // which is why it states them rather than just naming the source.
          SelectableText(
            'Fintraffic Digitraffic data is licensed under Creative Commons '
            'Attribution 4.0 International (CC BY 4.0).\n\n'
            'Source: https://www.digitraffic.fi/en/\n'
            'Licence: https://creativecommons.org/licenses/by/4.0/\n\n'
            'Modified: this app classifies delays into bands and derives '
            'corridors by linking a cargo train to the nearest port with a '
            'matching call, so what is shown is a derived work rather than '
            'raw Digitraffic output.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
