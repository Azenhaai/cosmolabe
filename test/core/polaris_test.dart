import 'dart:io';
import 'dart:typed_data';

import 'package:cosmolabe/core/catalog/star_catalog.dart';
import 'package:cosmolabe/core/coordinates.dart';
import 'package:cosmolabe/core/navigation/polaris.dart';
import 'package:cosmolabe/core/observer.dart';
import 'package:flutter_test/flutter_test.dart';

/// The exercise only works if the app can grade it, so the central test is a
/// round trip: take the altitude Polaris really has, reduce it, and check the
/// latitude that comes back is the one we started from.
void main() {
  late StarCatalog catalog;

  setUpAll(() {
    catalog = StarCatalog.parse(
      ByteData.sublistView(File('assets/catalog/stars.bin').readAsBytesSync()),
    );
  });

  Observer at(double latitude, double longitude, DateTime moment) => Observer(
        latitudeDeg: latitude,
        longitudeDeg: longitude,
        utc: moment,
        applyRefraction: false,
      );

  /// The altitude Polaris genuinely has for this observer.
  double polarisAltitude(Observer observer) {
    final index = catalog.hipToIndex[hipPolaris]!;
    return observer.project(catalog.positionAt(index)).altitudeDeg;
  }

  group('Reduction round trip', () {
    test('recovers the latitude it started from', () {
      for (final latitude in [10.0, 32.735278, 45.0, 51.5, 64.1, 70.0]) {
        for (final hour in [0, 4, 8, 12, 16, 20]) {
          final observer =
              at(latitude, -16.9, DateTime.utc(2026, 8, 16, hour));
          final sight = reducePolarisSight(
            observer: observer,
            catalog: catalog,
            observedAltitudeDeg: polarisAltitude(observer),
          );
          // A couple of arcminutes is the honest accuracy of the classic
          // reduction; the residual is the higher-order terms it drops.
          expect(
            sight.latitudeDeg,
            closeTo(latitude, 0.04),
            reason: 'lat $latitude at ${hour}h',
          );
        }
      }
    });

    test('works from the other side of the world', () {
      final observer = at(35.0, 139.7, DateTime.utc(2026, 2, 1, 18));
      final sight = reducePolarisSight(
        observer: observer,
        catalog: catalog,
        observedAltitudeDeg: polarisAltitude(observer),
      );
      expect(sight.latitudeDeg, closeTo(35.0, 0.04));
    });

    test('an error in the sight carries straight into the latitude', () {
      final observer = at(32.735278, -16.928611, DateTime.utc(2026, 8, 16, 23));
      final truth = polarisAltitude(observer);
      final sloppy = reducePolarisSight(
        observer: observer,
        catalog: catalog,
        observedAltitudeDeg: truth + 0.5,
      );
      expect(sloppy.errorAgainst(32.735278), closeTo(0.5, 0.01));
      // Half a degree of sloppiness is thirty nautical miles of position.
      expect(sloppy.errorNauticalMiles(32.735278), closeTo(30, 1));
    });
  });

  group('The correction', () {
    test('is at its largest when Polaris is above or below the pole', () {
      // Sweep a full day and find the extremes of the correction.
      var maximum = -99.0;
      var minimum = 99.0;
      for (var minutes = 0; minutes < 24 * 60; minutes += 10) {
        final observer = at(
          45,
          0,
          DateTime.utc(2026, 8, 16).add(Duration(minutes: minutes)),
        );
        final sight = reducePolarisSight(
          observer: observer,
          catalog: catalog,
          observedAltitudeDeg: polarisAltitude(observer),
        );
        if (sight.correctionDeg > maximum) maximum = sight.correctionDeg;
        if (sight.correctionDeg < minimum) minimum = sight.correctionDeg;
      }
      // It swings symmetrically by the polar distance either way.
      final polarDistance =
          polarisPolarDistanceAt(DateTime.utc(2026), catalog);
      expect(maximum, closeTo(polarDistance, 0.03));
      expect(minimum, closeTo(-polarDistance, 0.03));
    });

    test('is subtracted when Polaris rides above the pole', () {
      // Upper culmination is hour angle zero.
      var best = 999.0;
      PolarisSight? atCulmination;
      for (var minutes = 0; minutes < 24 * 60; minutes += 2) {
        final observer = at(
          45,
          0,
          DateTime.utc(2026, 8, 16).add(Duration(minutes: minutes)),
        );
        final sight = reducePolarisSight(
          observer: observer,
          catalog: catalog,
          observedAltitudeDeg: polarisAltitude(observer),
        );
        if (sight.hourAngleDeg < best) {
          best = sight.hourAngleDeg;
          atCulmination = sight;
        }
      }
      expect(atCulmination!.correctionDeg, lessThan(0));
      expect(atCulmination.observedAltitudeDeg, greaterThan(45));
    });
  });

  group('Polaris drifts towards the pole', () {
    test('sits about two thirds of a degree away today', () {
      // The often-quoted 0.74 degrees is the J2000 figure; a quarter century
      // of precession has since closed the gap, and it keeps closing until
      // around 2100.
      expect(
        polarisPolarDistanceAt(DateTime.utc(2026), catalog),
        closeTo(0.63, 0.04),
      );
    });

    test('stood three and a half degrees away in 1500', () {
      // This is the number that made the regimento necessary — seven full
      // Moon widths of error for anyone who treated Polaris as the pole.
      expect(
        polarisPolarDistanceAt(DateTime.utc(1500), catalog),
        closeTo(3.5, 0.35),
      );
    });

    test('keeps closing in through this century', () {
      final now = polarisPolarDistanceAt(DateTime.utc(2026), catalog);
      final later = polarisPolarDistanceAt(DateTime.utc(2090), catalog);
      expect(later, lessThan(now));
    });

    test('was far away in antiquity', () {
      expect(
        polarisPolarDistanceAt(DateTime.utc(1, 1, 1), catalog),
        greaterThan(10.0),
      );
    });
  });

  group('The Guards', () {
    test('read as a clock face', () {
      final observer = at(45, 0, DateTime.utc(2026, 8, 16, 22));
      final sight = reducePolarisSight(
        observer: observer,
        catalog: catalog,
        observedAltitudeDeg: polarisAltitude(observer),
      );
      expect(sight.guards.positionAngleDeg, inInclusiveRange(0.0, 360.0));
      expect(sight.guards.clockLabel, matches(r"^([1-9]|1[0-2]) o'clock$"));
    });

    test('go right round the dial in a day', () {
      final seen = <int>{};
      for (var minutes = 0; minutes < 24 * 60; minutes += 15) {
        final observer = at(
          45,
          0,
          DateTime.utc(2026, 8, 16).add(Duration(minutes: minutes)),
        );
        final sight = reducePolarisSight(
          observer: observer,
          catalog: catalog,
          observedAltitudeDeg: polarisAltitude(observer),
        );
        seen.add((sight.guards.positionAngleDeg / 45).floor() % 8);
      }
      // A sidereal day takes the Guards through all eight stations.
      expect(seen, hasLength(8));
    });

    test('turn anticlockwise, the way the sky really goes', () {
      final first = reducePolarisSight(
        observer: at(45, 0, DateTime.utc(2026, 8, 16, 20)),
        catalog: catalog,
        observedAltitudeDeg: 45,
      );
      final later = reducePolarisSight(
        observer: at(45, 0, DateTime.utc(2026, 8, 16, 21)),
        catalog: catalog,
        observedAltitudeDeg: 45,
      );
      // An hour moves them about fifteen degrees, decreasing.
      var moved = first.guards.positionAngleDeg - later.guards.positionAngleDeg;
      if (moved < 0) moved += 360;
      expect(moved, closeTo(15.04, 0.2));
    });

    test('every station has a name', () {
      for (var angle = 0.0; angle < 360; angle += 7.5) {
        final guards =
            GuardsPosition(positionAngleDeg: angle, hourAngleDeg: 0);
        expect(guards.figureStation, isNotEmpty);
      }
    });
  });

  group('Grading the exercise', () {
    test('the true pole altitude is the latitude, by definition', () {
      final observer = at(32.735278, -16.928611, DateTime.utc(2026, 8, 16, 23));
      expect(truePoleAltitude(observer), 32.735278);
      // And the pole of date really does stand at that altitude. It has to go
      // through the of-date path: precessing the J2000 pole would move it off
      // the pole it is supposed to be, by about four arcminutes a decade.
      final pole = observer.projectOfDate(const Equatorial(0, 90));
      expect(pole.altitudeDeg, closeTo(32.735278, 1e-9));

      // The J2000 pole, precessed, is demonstrably somewhere else by now.
      final staleP = observer.project(const Equatorial(0, 90));
      expect((staleP.altitudeDeg - 32.735278).abs(), greaterThan(0.01));
    });

    test('a phone-grade sight lands within a degree', () {
      // The accelerometer is good to about half a degree, so a sight taken
      // with the phone should reduce to a latitude good to roughly the same.
      final observer = at(32.735278, -16.928611, DateTime.utc(2026, 8, 16, 23));
      final sight = reducePolarisSight(
        observer: observer,
        catalog: catalog,
        observedAltitudeDeg: polarisAltitude(observer) + 0.5,
      );
      expect(sight.errorAgainst(32.735278).abs(), lessThan(1.0));
    });
  });
}
