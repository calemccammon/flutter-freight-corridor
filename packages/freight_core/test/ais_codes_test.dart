import 'package:freight_core/freight_core.dart';
import 'package:test/test.dart';

void main() {
  group('shipCategoryFromCode', () {
    test('maps the ITU bands that decide what counts as freight', () {
      // Codes and proportions taken from a live pull of 1,403 vessels.
      expect(shipCategoryFromCode(70), ShipCategory.cargo);
      expect(shipCategoryFromCode(79), ShipCategory.cargo);
      expect(shipCategoryFromCode(80), ShipCategory.tanker);
      expect(shipCategoryFromCode(89), ShipCategory.tanker);
      expect(shipCategoryFromCode(60), ShipCategory.passenger);
      expect(shipCategoryFromCode(30), ShipCategory.fishing);
      expect(shipCategoryFromCode(52), ShipCategory.service);
      expect(shipCategoryFromCode(90), ShipCategory.other);
    });

    test('treats absent and out-of-range codes as unknown', () {
      expect(shipCategoryFromCode(null), ShipCategory.unknown);
      expect(shipCategoryFromCode(0), ShipCategory.unknown);
      expect(shipCategoryFromCode(-1), ShipCategory.unknown);
      expect(shipCategoryFromCode(100), ShipCategory.unknown);
    });

    test('only cargo and tankers are freight', () {
      expect(ShipCategory.cargo.isFreight, isTrue);
      expect(ShipCategory.tanker.isFreight, isTrue);
      expect(ShipCategory.passenger.isFreight, isFalse);
      expect(ShipCategory.unknown.isFreight, isFalse);
    });
  });

  group('navigationStatusFromCode', () {
    test('maps the statuses that separate berthed from moving', () {
      expect(navigationStatusFromCode(0), NavigationStatus.underWayUsingEngine);
      expect(navigationStatusFromCode(1), NavigationStatus.atAnchor);
      expect(navigationStatusFromCode(5), NavigationStatus.moored);
      expect(navigationStatusFromCode(6), NavigationStatus.aground);
      expect(navigationStatusFromCode(15), NavigationStatus.unknown);
      expect(navigationStatusFromCode(null), NavigationStatus.unknown);
    });

    test('flags stationary states', () {
      expect(NavigationStatus.moored.isStationary, isTrue);
      expect(NavigationStatus.atAnchor.isStationary, isTrue);
      expect(NavigationStatus.underWayUsingEngine.isStationary, isFalse);
    });
  });

  group('decodeAisEta', () {
    // AIS packs an ETA into 20 bits: month<<16 | day<<11 | hour<<6 | minute.
    int pack(int month, int day, int hour, int minute) =>
        (month << 16) | (day << 11) | (hour << 6) | minute;

    final reference = DateTime.utc(2026, 8, 15, 12);

    test('unpacks a well-formed value', () {
      final eta = decodeAisEta(pack(9, 3, 14, 30), reference: reference);
      expect(eta, DateTime.utc(2026, 9, 3, 14, 30));
    });

    test('returns null for the not-available sentinels', () {
      // Month 0 and hour 24 / minute 60 are the documented "no ETA" values.
      expect(decodeAisEta(pack(0, 0, 24, 60), reference: reference), isNull);
      expect(decodeAisEta(pack(13, 1, 0, 0), reference: reference), isNull);
      expect(decodeAisEta(pack(1, 0, 0, 0), reference: reference), isNull);
      expect(decodeAisEta(null), isNull);
    });

    test('rejects days that do not exist in the month', () {
      expect(decodeAisEta(pack(2, 31, 0, 0), reference: reference), isNull);
    });

    test('rolls a long-past month into next year', () {
      // In mid-August, a January ETA belongs to the coming January.
      final eta = decodeAisEta(pack(1, 10, 6, 0), reference: reference);
      expect(eta, DateTime.utc(2027, 1, 10, 6));
    });
  });

  group('vessel dimensions and draught', () {
    test('length and beam are sums of the reference points', () {
      // Live record for EAGLE SAN ANTONIO: A=227 B=47 C=28 D=21.
      final dimensions = vesselDimensions(
        referencePointA: 227,
        referencePointB: 47,
        referencePointC: 28,
        referencePointD: 21,
      );
      expect(dimensions.lengthMetres, 274);
      expect(dimensions.beamMetres, 49);
    });

    test('missing or zero reference points yield null, not zero', () {
      final dimensions = vesselDimensions(referencePointA: 227);
      expect(dimensions.lengthMetres, isNull);
      expect(
        vesselDimensions(referencePointC: 0, referencePointD: 0).beamMetres,
        isNull,
      );
    });

    test(
      'draught converts decimetres to metres and drops the zero sentinel',
      () {
        expect(draughtMetresFromAis(147), closeTo(14.7, 1e-9));
        expect(draughtMetresFromAis(0), isNull);
        expect(draughtMetresFromAis(null), isNull);
      },
    );
  });
}
