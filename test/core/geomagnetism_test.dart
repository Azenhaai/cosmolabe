import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmolabe/core/geomagnetism.dart';
import 'package:cosmolabe/core/wmm_coefficients.dart';

/// Validated against the 100 official test values NOAA publishes with the
/// model, which is the only honest way to check a spherical harmonic
/// expansion — the intermediate quantities are not checkable by eye, but the
/// published answers are exact.
void main() {
  late List<List<double>> official;

  setUpAll(() {
    official = File('test/data/WMM2025_TestValues.txt')
        .readAsLinesSync()
        .where((line) => line.trim().isNotEmpty && !line.startsWith('#'))
        .map((line) => line
            .trim()
            .split(RegExp(r'\s+'))
            .map(double.parse)
            .toList())
        .toList();
  });

  group('Official NOAA test values', () {
    test('the file holds the full set', () {
      expect(official, hasLength(100));
      expect(official.first, hasLength(18));
    });

    test('declination matches every published value', () {
      var worst = 0.0;
      var worstCase = '';
      for (final row in official) {
        final field = magneticFieldAt(
          decimalYear: row[0],
          heightMeters: row[1] * 1000,
          latitudeDeg: row[2],
          longitudeDeg: row[3],
        );
        // The published values are rounded to two decimals.
        var error = (field.declinationDeg - row[4]).abs();
        // Declination wraps; near the poles the published value and ours can
        // sit either side of 180 degrees while agreeing perfectly.
        if (error > 180) error = 360 - error;
        if (error > worst) {
          worst = error;
          worstCase = 'lat ${row[2]} lon ${row[3]} alt ${row[1]}km '
              'expected ${row[4]} got ${field.declinationDeg.toStringAsFixed(2)}';
        }
      }
      expect(worst, lessThan(0.01), reason: worstCase);
    });

    test('inclination matches every published value', () {
      var worst = 0.0;
      for (final row in official) {
        final field = magneticFieldAt(
          decimalYear: row[0],
          heightMeters: row[1] * 1000,
          latitudeDeg: row[2],
          longitudeDeg: row[3],
        );
        final error = (field.inclinationDeg - row[5]).abs();
        if (error > worst) worst = error;
      }
      expect(worst, lessThan(0.01));
    });

    test('the field components match', () {
      var worstH = 0.0, worstX = 0.0, worstY = 0.0, worstZ = 0.0, worstF = 0.0;
      for (final row in official) {
        final field = magneticFieldAt(
          decimalYear: row[0],
          heightMeters: row[1] * 1000,
          latitudeDeg: row[2],
          longitudeDeg: row[3],
        );
        double worse(double current, double a, double b) {
          final error = (a - b).abs();
          return error > current ? error : current;
        }

        worstH = worse(worstH, field.horizontalNanoTesla, row[6]);
        worstX = worse(worstX, field.northNanoTesla, row[7]);
        worstY = worse(worstY, field.eastNanoTesla, row[8]);
        worstZ = worse(worstZ, field.downNanoTesla, row[9]);
        worstF = worse(worstF, field.totalNanoTesla, row[10]);
      }
      // Published to six decimals of a nanotesla; a tenth is far tighter than
      // any magnetometer will ever resolve.
      for (final worst in [worstH, worstX, worstY, worstZ, worstF]) {
        expect(worst, lessThan(0.1));
      }
    });
  });

  group('Places that matter', () {
    test('Madeira sits a few degrees west', () {
      final declination = magneticDeclination(
        latitudeDeg: 32.735278,
        longitudeDeg: -16.928611,
        heightMeters: 1818,
        moment: DateTime.utc(2026, 8, 16),
      );
      // West is negative. The exact figure drifts year to year, so the test
      // pins the sign and the rough size rather than a value that will rot.
      expect(declination, lessThan(0));
      expect(declination.abs(), inInclusiveRange(1.0, 8.0));
    });

    test('the correction is worth making at all', () {
      // If declination were negligible everywhere, none of this code would
      // earn its place. It is not: the spread across inhabited latitudes is
      // tens of degrees.
      final samples = [
        magneticDeclination(
            latitudeDeg: 64.1, longitudeDeg: -21.9, moment: DateTime.utc(2026)),
        magneticDeclination(
            latitudeDeg: 60.2, longitudeDeg: 24.9, moment: DateTime.utc(2026)),
        magneticDeclination(
            latitudeDeg: -33.9, longitudeDeg: 151.2, moment: DateTime.utc(2026)),
      ];
      final spread = samples.reduce((a, b) => a > b ? a : b) -
          samples.reduce((a, b) => a < b ? a : b);
      expect(spread, greaterThan(20));
    });

    test('the compass is flagged as useless near the magnetic pole', () {
      final field = magneticFieldAt(
        latitudeDeg: 86.0,
        longitudeDeg: 150.0,
        decimalYear: 2026.0,
      );
      expect(field.compassUnreliable, isTrue);
      expect(field.inclinationDeg, greaterThan(85));
    });

    test('the equator has a nearly horizontal field', () {
      final field = magneticFieldAt(
        latitudeDeg: 0,
        longitudeDeg: 10,
        decimalYear: 2026.0,
      );
      expect(field.inclinationDeg.abs(), lessThan(30));
      expect(field.compassUnreliable, isFalse);
    });
  });

  group('Validity window', () {
    test('the shipped model covers the present', () {
      expect(wmmEpoch, 2025.0);
      expect(wmmValidUntil, 2030.0);
      expect(
        magneticFieldAt(
          latitudeDeg: 32.7,
          longitudeDeg: -16.9,
          decimalYear: 2026.6,
        ).outOfDate,
        isFalse,
      );
    });

    test('a date past the window is flagged rather than silently wrong', () {
      expect(
        magneticFieldAt(
          latitudeDeg: 32.7,
          longitudeDeg: -16.9,
          decimalYear: 2031.0,
        ).outOfDate,
        isTrue,
      );
    });

    test('the time machine running to 1900 is flagged too', () {
      expect(
        magneticFieldAt(
          latitudeDeg: 32.7,
          longitudeDeg: -16.9,
          decimalYear: 1900.0,
        ).outOfDate,
        isTrue,
      );
    });
  });

  group('Decimal year', () {
    test('new year is the year itself', () {
      expect(decimalYearOf(DateTime.utc(2026, 1, 1)), closeTo(2026.0, 1e-9));
    });

    test('midsummer is halfway', () {
      expect(decimalYearOf(DateTime.utc(2026, 7, 2, 12)), closeTo(2026.5, 0.01));
    });

    test('leap years are handled', () {
      expect(decimalYearOf(DateTime.utc(2028, 7, 2)), closeTo(2028.5, 0.01));
    });
  });

  test('the coefficient table is complete', () {
    // Degree and order 12 means 12 + 11 + ... plus the zonal terms.
    expect(wmmCoefficients, hasLength(90));
    expect(wmmMaxDegree, 12);
    for (final row in wmmCoefficients) {
      expect(row, hasLength(6));
      expect(row[1], lessThanOrEqualTo(row[0]));
    }
  });
}
