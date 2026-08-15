import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/settings.dart';
import 'screens/corridors_screen.dart';
import 'screens/map_screen.dart';
import 'screens/overview_screen.dart';
import 'screens/rail_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/train_detail_screen.dart';

class FreightCorridorApp extends ConsumerWidget {
  const FreightCorridorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));

    return MaterialApp.router(
      title: 'Freight Corridor',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      routerConfig: _router,
    );
  }
}

ThemeData _theme(Brightness brightness) {
  // Slate blue reads as infrastructure rather than consumer app, and holds up
  // in both light and dark.
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2E5A88),
    brightness: brightness,
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

/// Bottom tabs whose navigation state survives switching between them, with
/// the train detail pushed inside the Rail branch so it keeps the tab bar and
/// the back gesture.
///
/// Routing by URL also means every screen is deep-linkable in the web build —
/// `/corridors` is a shareable link, which a purely widget-based navigator
/// could not give you.
final _router = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/',
  routes: <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          _Shell(navigationShell: navigationShell),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (context, state) => const OverviewScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _shellKey,
          routes: <RouteBase>[
            GoRoute(
              path: '/rail',
              builder: (context, state) => const RailScreen(),
              routes: <RouteBase>[
                GoRoute(
                  path: ':trainNumber/:departureDate',
                  builder: (context, state) => TrainDetailScreen(
                    trainId:
                        '${state.pathParameters['trainNumber']}'
                        '/${state.pathParameters['departureDate']}',
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/corridors',
              builder: (context, state) => const CorridorsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/map',
              builder: (context, state) => const MapScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

class _Shell extends StatelessWidget {
  const _Shell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        // `initialLocation: true` on a re-tap pops that branch back to its
        // root, which is the behaviour people expect from tab bars.
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.train_outlined),
            selectedIcon: Icon(Icons.train),
            label: 'Rail',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_horiz_outlined),
            selectedIcon: Icon(Icons.swap_horiz),
            label: 'Corridors',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
