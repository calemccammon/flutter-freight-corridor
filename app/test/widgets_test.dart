import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x moved `Override` out of the main barrel.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:freight_core/freight_core.dart';
import 'package:freight_corridor/data/freight_repository.dart';
import 'package:freight_corridor/providers/freight_providers.dart';
import 'package:freight_corridor/providers/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freight_corridor/screens/rail_screen.dart';
import 'package:freight_corridor/widgets/async_value_view.dart';
import 'package:freight_corridor/widgets/common.dart';

FreightTrain _train({
  required int number,
  required String terminus,
  int? delay,
  double speed = 60,
}) {
  final now = DateTime.utc(2026, 8, 15, 12);
  return FreightTrain(
    trainNumber: number,
    departureDate: '2026-08-15',
    operatorShortCode: 'vr',
    operatorName: 'VR-Yhtymä Oyj',
    trainTypeName: 'T',
    runningCurrently: true,
    speedKmh: speed,
    position: const GeoPoint(latitude: 61, longitude: 25),
    stops: <TimetableStop>[
      TimetableStop(
        stationName: terminus,
        stationShortCode: 'XX',
        type: StopType.arrival,
        scheduledTime: now,
        actualTime: delay == null ? null : now,
        differenceInMinutes: delay,
      ),
    ],
  );
}

Widget _wrap(Widget child, {List<Override> overrides = const <Override>[]}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

/// Rail tiles read the watchlist, which is backed by SharedPreferences, so
/// screen tests have to supply the same override `main()` does at startup.
late SharedPreferences _preferences;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _preferences = await SharedPreferences.getInstance();
  });
  group('AsyncValueView', () {
    testWidgets('shows a spinner while loading', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AsyncValueView<List<int>>(
            value: const AsyncValue<List<int>>.loading(),
            data: (_) => const Text('data'),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('data'), findsNothing);
    });

    testWidgets('shows the message and a retry button on error', (
      tester,
    ) async {
      var retried = false;

      await tester.pumpWidget(
        _wrap(
          AsyncValueView<List<int>>(
            value: AsyncValue<List<int>>.error(
              const FreightException(
                'Could not load cargo trains',
                detail: 'Digitraffic answered 503',
              ),
              StackTrace.empty,
            ),
            onRetry: () => retried = true,
            data: (_) => const Text('data'),
          ),
        ),
      );

      expect(find.text('Could not load cargo trains'), findsOneWidget);
      expect(find.text('Digitraffic answered 503'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      expect(retried, isTrue);
    });

    testWidgets('treats an empty collection as its own state', (tester) async {
      // A quiet night on the rail network is a normal outcome, not an error.
      await tester.pumpWidget(
        _wrap(
          AsyncValueView<List<int>>(
            value: const AsyncValue<List<int>>.data(<int>[]),
            emptyTitle: 'No cargo trains match',
            emptyMessage: 'Finnish freight rail is quiet at some hours',
            data: (_) => const Text('data'),
          ),
        ),
      );

      expect(find.text('No cargo trains match'), findsOneWidget);
      expect(find.text('data'), findsNothing);
    });

    testWidgets('renders data when there is some', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AsyncValueView<List<int>>(
            value: const AsyncValue<List<int>>.data(<int>[1]),
            data: (value) => Text('got ${value.length}'),
          ),
        ),
      );

      expect(find.text('got 1'), findsOneWidget);
    });
  });

  group('DelayChip', () {
    testWidgets('labels each adherence bucket', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Column(
            children: <Widget>[
              DelayChip(status: DelayStatus.early, minutes: -6),
              DelayChip(status: DelayStatus.onTime, minutes: 0),
              DelayChip(status: DelayStatus.major, minutes: 79),
              DelayChip(status: DelayStatus.unknown),
            ],
          ),
        ),
      );

      expect(find.text('6 min early'), findsOneWidget);
      expect(find.text('On time'), findsOneWidget);
      expect(find.text('79 min late'), findsOneWidget);
      expect(find.text('No data'), findsOneWidget);
    });
  });

  group('CompositionBar', () {
    testWidgets('summarises wagons, locomotives and length', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const CompositionBar(
            composition: WagonComposition(
              sections: <JourneySection>[
                JourneySection(
                  maximumSpeedKmh: 100,
                  totalLengthMetres: 220,
                  locomotives: <Locomotive>[
                    Locomotive(locomotiveType: 'Sr2', powerType: 'S'),
                  ],
                  wagons: <Wagon>[
                    Wagon(salesNumber: 1, lengthMetres: 20, wagonType: 'Sim'),
                    Wagon(salesNumber: 2, lengthMetres: 20, wagonType: 'Sim'),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('1 locomotive · 2 wagons · 220 m'), findsOneWidget);
    });
  });

  group('RailScreen', () {
    testWidgets('lists trains worst delay first with their chips', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const RailScreen(),
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(_preferences),
            cargoTrainsProvider.overrideWith(
              (ref) async => <FreightTrain>[
                _train(number: 2228, terminus: 'Kouvola lajittelu'),
                _train(number: 52210, terminus: 'Kotka Mussalo', delay: 79),
                _train(number: 4036, terminus: 'Uusikaupunki', delay: 5),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Train 52210'), findsOneWidget);
      expect(find.text('79 min late'), findsOneWidget);

      // Sorted by lateness, so the worst offender is the first tile.
      final titles = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => (tile.title! as Text).data)
          .toList();
      expect(titles.first, 'Train 52210');
      expect(titles[1], 'Train 4036');
    });

    testWidgets('filters the list by the search field', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RailScreen(),
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(_preferences),
            cargoTrainsProvider.overrideWith(
              (ref) async => <FreightTrain>[
                _train(number: 52210, terminus: 'Kotka Mussalo', delay: 79),
                _train(number: 4036, terminus: 'Uusikaupunki', delay: 5),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(2));

      await tester.enterText(find.byType(SearchBar), 'kotka');
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('Train 52210'), findsOneWidget);
    });

    testWidgets('explains an empty result rather than showing a blank page', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const RailScreen(),
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(_preferences),
            cargoTrainsProvider.overrideWith(
              (ref) async => const <FreightTrain>[],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No cargo trains match'), findsOneWidget);
    });

    testWidgets('surfaces a repository failure with a retry', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RailScreen(),
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(_preferences),
            cargoTrainsProvider.overrideWith(
              (ref) async =>
                  throw const FreightException('Could not load cargo trains'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load cargo trains'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
