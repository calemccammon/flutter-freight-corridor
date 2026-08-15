import 'package:ferry/ferry.dart';
import 'package:freight_core/freight_core.dart';

import 'graphql/__generated__/cargo_trains.data.gql.dart';
import 'graphql/__generated__/cargo_trains.req.gql.dart';
import 'graphql/__generated__/schema.schema.gql.dart';

/// Reads live cargo trains from the Digitraffic railway GraphQL API.
///
/// Everything ferry-shaped stops at this class. It accepts generated
/// built_value types and returns `freight_core` models, so no GraphQL concept
/// reaches the repository, the providers, or the widgets.
class RailDataSource {
  RailDataSource(this._client);

  final Client _client;

  /// Every cargo train currently running on the Finnish network.
  Future<List<FreightTrain>> cargoTrains() async {
    final response = await _execute(
      GCargoTrainsReq((b) => b..fetchPolicy = FetchPolicy.NetworkOnly),
    );
    final trains = response.data?.currentlyRunningTrains;
    if (trains == null) return const <FreightTrain>[];
    return trains
        .map((train) => _trainFromSummary(train, stops: train.timeTableRows))
        .toList(growable: false);
  }

  /// One train, with its wagon composition attached.
  Future<FreightTrain?> trainDetail({
    required int trainNumber,
    required String departureDate,
  }) async {
    final response = await _execute(
      GTrainDetailReq(
        (b) => b
          ..fetchPolicy = FetchPolicy.NetworkOnly
          ..vars.trainNumber = trainNumber
          ..vars.departureDate = departureDate,
      ),
    );

    // `train` is a list because the query accepts filters; we asked for one.
    final matches = response.data?.train;
    if (matches == null || matches.isEmpty) return null;
    final train = matches.first;

    return _trainFromSummary(
      train,
      stops: train.timeTableRows,
      composition: _compositionFrom(train.compositions),
    );
  }

  Future<OperationResponse<TData, TVars>> _execute<TData, TVars>(
    OperationRequest<TData, TVars> request,
  ) async {
    final response = await _client
        .request(request)
        .firstWhere((response) => !response.loading);

    if (response.hasErrors) {
      final failure = response.linkException ?? response.graphqlErrors?.first;
      throw RailRequestException(
        failure?.toString() ?? 'Unknown GraphQL error',
      );
    }
    return response;
  }

  /// Maps the shared `TrainSummary` fragment, which both queries select, so
  /// the two code paths cannot drift apart.
  FreightTrain _trainFromSummary(
    GTrainSummary summary, {
    Iterable<GStopRow>? stops,
    WagonComposition? composition,
  }) {
    final latest = summary.trainLocations.isEmpty
        ? null
        : summary.trainLocations.first;

    return FreightTrain(
      trainNumber: summary.trainNumber,
      departureDate: summary.departureDate,
      operatorShortCode: summary.operator.shortCode,
      operatorName: summary.operator.name,
      trainTypeName: summary.trainType.name,
      runningCurrently: summary.runningCurrently,
      position: latest == null
          ? null
          : GeoPoint.fromLonLat(latest.location.toList()),
      speedKmh: latest?.speed.toDouble(),
      positionReportedAt: latest == null ? null : _parseTime(latest.timestamp),
      stops: (stops ?? const <GStopRow>[])
          .map(_stopFrom)
          .whereType<TimetableStop>()
          .toList(growable: false),
      composition: composition,
    );
  }

  TimetableStop? _stopFrom(GStopRow row) {
    final scheduled = _parseTime(row.scheduledTime);
    if (scheduled == null) return null;

    final station = row.station;
    return TimetableStop(
      stationName: station?.name ?? 'Unknown',
      stationShortCode: station?.shortCode ?? '',
      type: row.type == GTimeTableRowType.DEPARTURE
          ? StopType.departure
          : StopType.arrival,
      scheduledTime: scheduled,
      actualTime: _parseTime(row.actualTime),
      differenceInMinutes: row.differenceInMinutes,
      stationLocation: station == null
          ? null
          : GeoPoint.fromLonLat(station.location.toList()),
      cancelled: row.cancelled,
    );
  }

  WagonComposition? _compositionFrom(
    Iterable<GTrainDetailData_train_compositions>? compositions,
  ) {
    if (compositions == null || compositions.isEmpty) return null;

    final sections = <JourneySection>[
      for (final composition in compositions)
        for (final section in composition.journeySections)
          JourneySection(
            maximumSpeedKmh: section.maximumSpeed,
            totalLengthMetres: section.totalLength,
            wagons: section.wagons
                .map(
                  (wagon) => Wagon(
                    salesNumber: wagon.salesNumber,
                    // The API reports wagon length in centimetres.
                    lengthMetres: wagon.length / 100,
                    wagonType: wagon.wagonType,
                  ),
                )
                .toList(growable: false),
            locomotives: section.locomotives
                .map(
                  (locomotive) => Locomotive(
                    locomotiveType: locomotive.locomotiveType,
                    powerType: locomotive.powerTypeAbbreviation,
                  ),
                )
                .toList(growable: false),
          ),
    ];

    if (sections.isEmpty) return null;
    return WagonComposition(sections: sections);
  }

  /// The schema's `Date`/`DateTime` scalars are mapped to `String` in
  /// build.yaml so that all time handling lives here rather than in generated
  /// code. A malformed value yields null instead of taking down the response.
  DateTime? _parseTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }
}

/// Raised when the rail API answers with GraphQL or transport errors.
class RailRequestException implements Exception {
  const RailRequestException(this.message);

  final String message;

  @override
  String toString() => 'RailRequestException: $message';
}
