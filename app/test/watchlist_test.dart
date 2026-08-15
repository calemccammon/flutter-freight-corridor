import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:freight_core/freight_core.dart';
import 'package:freight_corridor/providers/freight_providers.dart';
import 'package:freight_corridor/providers/settings.dart';
import 'package:freight_corridor/providers/watchlist.dart';
import 'package:freight_corridor/screens/watchlist_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

FreightTrain _train(int number, {int? delay}) {
  final now = DateTime.utc(2026, 8, 15, 12);
  return FreightTrain(
    trainNumber: number,
    departureDate: '2026-08-15',
    operatorShortCode: 'vr',
    operatorName: 'VR-Yhtymä Oyj',
    trainTypeName: 'T',
    runningCurrently: true,
    speedKmh: 60,
    stops: <TimetableStop>[
      TimetableStop(
        stationName: 'Kotka Mussalo',
        stationShortCode: 'KTMU',
        type: StopType.arrival,
        scheduledTime: now,
        actualTime: delay == null ? null : now,
        differenceInMinutes: delay,
      ),
    ],
  );
}

Future<ProviderContainer> _container({
  Map<String, Object> prefs = const <String, Object>{},
  List<Override> overrides = const <Override>[],
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final preferences = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(preferences),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Watchlist.validateAlertMinutes', () {
    test('accepts a plain whole number inside the range', () {
      expect(Watchlist.validateAlertMinutes('15'), isNull);
      expect(Watchlist.validateAlertMinutes(' 240 '), isNull);
    });

    test('rejects empty, non-numeric and out-of-range input', () {
      expect(Watchlist.validateAlertMinutes(''), 'Enter a number of minutes');
      expect(Watchlist.validateAlertMinutes(null), 'Enter a number of minutes');
      expect(Watchlist.validateAlertMinutes('soon'), 'Whole minutes only');
      expect(Watchlist.validateAlertMinutes('0'), contains('at least'));
      expect(Watchlist.validateAlertMinutes('999'), contains('240'));
    });
  });

  group('WatchlistController', () {
    test(
      'toggling a train adds then removes it, and persists both times',
      () async {
        final container = await _container();
        final controller = container.read(watchlistProvider.notifier);

        await controller.toggleTrain('3425/2026-08-15');
        expect(
          container.read(watchlistProvider).watchesTrain('3425/2026-08-15'),
          isTrue,
        );

        final preferences = container.read(sharedPreferencesProvider);
        expect(preferences.getStringList('watchlist:trains'), <String>[
          '3425/2026-08-15',
        ]);

        await controller.toggleTrain('3425/2026-08-15');
        expect(
          container.read(watchlistProvider).watchesTrain('3425/2026-08-15'),
          isFalse,
        );
        expect(preferences.getStringList('watchlist:trains'), isEmpty);
      },
    );

    test('rehydrates pins and threshold from storage', () async {
      final container = await _container(
        prefs: <String, Object>{
          'watchlist:trains': <String>['3425/2026-08-15'],
          'watchlist:vessels': <String>['230108610', 'not-a-number'],
          'watchlist:alertMinutes': 30,
        },
      );

      final watchlist = container.read(watchlistProvider);
      expect(watchlist.watchesTrain('3425/2026-08-15'), isTrue);
      // The malformed entry is dropped rather than crashing the launch.
      expect(watchlist.vesselMmsis, <int>{230108610});
      expect(watchlist.alertMinutes, 30);
      expect(watchlist.length, 2);
    });

    test('clamps a threshold set outside the allowed range', () async {
      final container = await _container();
      final controller = container.read(watchlistProvider.notifier);

      await controller.setAlertMinutes(9999);
      expect(
        container.read(watchlistProvider).alertMinutes,
        Watchlist.maxAlertMinutes,
      );

      await controller.setAlertMinutes(-5);
      expect(
        container.read(watchlistProvider).alertMinutes,
        Watchlist.minAlertMinutes,
      );
    });

    test('clear removes pins but keeps the threshold', () async {
      final container = await _container(
        prefs: <String, Object>{'watchlist:alertMinutes': 25},
      );
      final controller = container.read(watchlistProvider.notifier);

      await controller.toggleTrain('1/2026-08-15');
      await controller.toggleVessel(42);
      await controller.clear();

      final watchlist = container.read(watchlistProvider);
      expect(watchlist.isEmpty, isTrue);
      expect(watchlist.alertMinutes, 25);
    });
  });

  group('derived watchlist providers', () {
    test('resolve pins against the live feed and drop finished runs', () async {
      final container = await _container(
        prefs: <String, Object>{
          'watchlist:trains': <String>['3425/2026-08-15', '9999/2026-08-15'],
        },
        overrides: <Override>[
          cargoTrainsProvider.overrideWith(
            (ref) async => <FreightTrain>[
              _train(3425, delay: 20),
              _train(4036),
            ],
          ),
        ],
      );

      await container.read(cargoTrainsProvider.future);

      final watched = container.read(watchedTrainsProvider).value!;
      // 9999 is pinned but no longer running, so it simply does not appear.
      expect(watched.map((t) => t.trainNumber), <int>[3425]);
    });

    test('alerts only fire above the configured threshold', () async {
      final container = await _container(
        prefs: <String, Object>{
          'watchlist:trains': <String>['3425/2026-08-15'],
          'watchlist:alertMinutes': 15,
        },
        overrides: <Override>[
          cargoTrainsProvider.overrideWith(
            (ref) async => <FreightTrain>[_train(3425, delay: 20)],
          ),
        ],
      );
      await container.read(cargoTrainsProvider.future);
      expect(container.read(watchlistAlertsProvider), hasLength(1));

      await container.read(watchlistProvider.notifier).setAlertMinutes(25);
      expect(container.read(watchlistAlertsProvider), isEmpty);
    });
  });

  group('WatchlistScreen', () {
    Future<void> pump(
      WidgetTester tester, {
      required Map<String, Object> prefs,
      List<Override> overrides = const <Override>[],
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(preferences),
            ...overrides,
          ],
          child: const MaterialApp(home: WatchlistScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('explains how to add pins when nothing is watched', (
      tester,
    ) async {
      await pump(tester, prefs: const <String, Object>{});

      expect(find.text('Nothing pinned yet'), findsOneWidget);
      expect(find.byType(Dismissible), findsNothing);
    });

    testWidgets('lists watched trains and removes one on swipe', (
      tester,
    ) async {
      await pump(
        tester,
        prefs: const <String, Object>{
          'watchlist:trains': <String>['3425/2026-08-15'],
        },
        overrides: <Override>[
          cargoTrainsProvider.overrideWith(
            (ref) async => <FreightTrain>[_train(3425)],
          ),
        ],
      );

      expect(find.text('Train 3425'), findsOneWidget);

      await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('Train 3425'), findsNothing);
      expect(find.text('Train 3425 removed'), findsOneWidget); // undo snackbar
    });

    testWidgets('rejects an invalid threshold and keeps the stored value', (
      tester,
    ) async {
      await pump(
        tester,
        prefs: const <String, Object>{
          'watchlist:trains': <String>['3425/2026-08-15'],
          'watchlist:alertMinutes': 15,
        },
        overrides: <Override>[
          cargoTrainsProvider.overrideWith(
            (ref) async => <FreightTrain>[_train(3425)],
          ),
        ],
      );

      await tester.enterText(find.byType(TextFormField), '999');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('240 or less'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(WatchlistScreen)),
      );
      expect(container.read(watchlistProvider).alertMinutes, 15);
    });

    testWidgets('accepts a valid threshold and confirms in place', (
      tester,
    ) async {
      await pump(
        tester,
        prefs: const <String, Object>{
          'watchlist:trains': <String>['3425/2026-08-15'],
        },
        overrides: <Override>[
          cargoTrainsProvider.overrideWith(
            (ref) async => <FreightTrain>[_train(3425)],
          ),
        ],
      );

      await tester.enterText(find.byType(TextFormField), '45');
      await tester.tap(find.text('Save'));
      await tester.pump(); // let the AnimatedSwitcher swap in the tick
      await tester.pump(const Duration(milliseconds: 300));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(WatchlistScreen)),
      );
      expect(container.read(watchlistProvider).alertMinutes, 45);
      expect(find.byIcon(Icons.check), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets(
      'shows an alert banner when a watched train passes the threshold',
      (tester) async {
        await pump(
          tester,
          prefs: const <String, Object>{
            'watchlist:trains': <String>['3425/2026-08-15'],
            'watchlist:alertMinutes': 15,
          },
          overrides: <Override>[
            cargoTrainsProvider.overrideWith(
              (ref) async => <FreightTrain>[_train(3425, delay: 79)],
            ),
          ],
        );

        expect(find.textContaining('more than 15 min late'), findsOneWidget);
      },
    );
  });
}
