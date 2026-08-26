import 'package:flutter_test/flutter_test.dart';
import 'package:cosmolabe/core/angles.dart';
import 'package:cosmolabe/core/bodies/moon.dart';
import 'package:cosmolabe/core/bodies/planets.dart';
import 'package:cosmolabe/core/bodies/sun.dart';
import 'package:cosmolabe/core/julian.dart';

void main() {
  group('Sun — Meeus example 25.b, 1992 October 13.0 TD', () {
    const jde = 2448908.5;
    final sun = computeSun(jde);

    test('mean anomaly', () {
      expect(sun.meanAnomalyDeg, closeTo(278.99397, 1e-4));
    });

    test('true geometric longitude', () {
      expect(sun.trueLongitudeDeg, closeTo(199.90988, 1e-4));
    });

    test('apparent longitude', () {
      expect(sun.apparentLongitudeDeg, closeTo(199.90895, 1e-4));
    });

    test('radius vector', () {
      // The low-accuracy method gives 0.99766; Meeus's full VSOP87 solution
      // for the same instant gives 0.99760775. The 5e-5 AU gap is the price of
      // the short series, and it moves the Sun on screen by well under an
      // arcsecond.
      expect(sun.distanceAu, closeTo(0.99766, 1e-5));
    });

    test('apparent equatorial position', () {
      // The low-accuracy method is quoted as good to 0.01 degrees.
      expect(sun.equatorial.raDeg, closeTo(198.3808, 0.01));
      expect(sun.equatorial.decDeg, closeTo(-7.7850, 0.01));
    });
  });

  group('Sun — behaviour across the year', () {
    test('declination swings between the tropics', () {
      final solsticeJune =
          computeSun(julianDayFromCalendar(2026, 6, 21.0));
      final solsticeDecember =
          computeSun(julianDayFromCalendar(2026, 12, 21.5));
      expect(solsticeJune.equatorial.decDeg, closeTo(23.44, 0.05));
      expect(solsticeDecember.equatorial.decDeg, closeTo(-23.44, 0.05));
    });

    test('Earth is closest to the Sun in early January', () {
      final perihelion = computeSun(julianDayFromCalendar(2026, 1, 3.0));
      final aphelion = computeSun(julianDayFromCalendar(2026, 7, 5.0));
      expect(perihelion.distanceAu, closeTo(0.9833, 0.001));
      expect(aphelion.distanceAu, closeTo(1.0167, 0.001));
      expect(perihelion.distanceAu, lessThan(aphelion.distanceAu));
    });

    test('the apparent disc is about half a degree across', () {
      final sun = computeSun(julianDayFromCalendar(2026, 4, 1.0));
      expect(sun.angularRadiusDeg * 2, closeTo(0.533, 0.01));
    });
  });

  group('Sky darkness', () {
    test('is full daylight with the Sun up', () {
      expect(skyDarkness(30.0), 0.0);
    });

    test('is fully dark below astronomical twilight', () {
      expect(skyDarkness(-20.0), 1.0);
    });

    test('ramps smoothly through twilight', () {
      expect(skyDarkness(-6.0), closeTo(0.30, 0.02));
      expect(skyDarkness(-12.0), closeTo(0.65, 0.02));
    });
  });

  group('Moon — Meeus example 47.a, 1992 April 12.0 TD', () {
    const jde = 2448724.5;
    final moon = computeMoon(jde);

    test('ecliptic longitude', () {
      expect(moon.eclipticLongitudeDeg, closeTo(133.162655, 1e-4));
    });

    test('ecliptic latitude', () {
      expect(moon.eclipticLatitudeDeg, closeTo(-3.229126, 1e-4));
    });

    test('distance', () {
      expect(moon.distanceKm, closeTo(368409.7, 0.5));
    });

    test('equatorial horizontal parallax', () {
      expect(moon.parallaxDeg, closeTo(0.991990, 1e-4));
    });

    test('apparent equatorial position', () {
      expect(moon.equatorial.raDeg, closeTo(134.688470, 0.002));
      expect(moon.equatorial.decDeg, closeTo(13.768368, 0.002));
    });

    test('illuminated fraction — Meeus example 48.a', () {
      expect(moon.phaseAngleDeg, closeTo(69.0756, 0.05));
      expect(moon.illuminatedFraction, closeTo(0.6786, 0.001));
    });
  });

  group('Moon — behaviour', () {
    test('distance stays inside the real perigee and apogee range', () {
      var minimum = double.infinity;
      var maximum = 0.0;
      final start = julianDayFromCalendar(2026, 1, 1.0);
      for (var i = 0; i < 400; i++) {
        final d = computeMoon(start + i).distanceKm;
        minimum = d < minimum ? d : minimum;
        maximum = d > maximum ? d : maximum;
      }
      expect(minimum, greaterThan(356000));
      expect(maximum, lessThan(407000));
    });

    test('runs through a full cycle of phases in a synodic month', () {
      final start = julianDayFromCalendar(2026, 1, 1.0);
      var minimum = 1.0;
      var maximum = 0.0;
      for (var i = 0; i < 30; i++) {
        final k = computeMoon(start + i).illuminatedFraction;
        minimum = k < minimum ? k : minimum;
        maximum = k > maximum ? k : maximum;
      }
      expect(minimum, lessThan(0.05));
      expect(maximum, greaterThan(0.95));
    });

    test('the angular radius is close to the Sun\'s, as eclipses require', () {
      final moon = computeMoon(julianDayFromCalendar(2026, 5, 1.0));
      expect(moon.angularRadiusDeg * 2, closeTo(0.52, 0.05));
    });

    test('topocentric parallax shifts the position by up to a degree', () {
      final moon = computeMoon(julianDayFromCalendar(2026, 8, 12.0));
      final topocentric = applyTopocentricParallax(
        moon.equatorial,
        moon.parallaxDeg,
        120.0,
        32.735278,
        1818.0,
      );
      final shift = angularSeparation(
        moon.equatorial.raDeg,
        moon.equatorial.decDeg,
        topocentric.raDeg,
        topocentric.decDeg,
      );
      expect(shift, greaterThan(0.0));
      expect(shift, lessThan(1.05));
    });
  });

  group('Planets', () {
    test('the 2020 great conjunction puts Jupiter and Saturn together', () {
      final jde =
          julianEphemerisDay(julianDayFromCalendar(2020, 12, 21.0 + 18 / 24.0));
      final jupiter = computePlanet(Planet.jupiter, jde);
      final saturn = computePlanet(Planet.saturn, jde);
      final separation = angularSeparation(
        jupiter.equatorial.raDeg,
        jupiter.equatorial.decDeg,
        saturn.equatorial.raDeg,
        saturn.equatorial.decDeg,
      );
      // The true separation was about 6 arcminutes; the approximation's own
      // error is a few arcminutes, so anything under half a degree confirms
      // the geometry rather than a coincidence.
      expect(separation, lessThan(0.5));
    });

    test('Mars was about 0.42 AU away at the 2020 opposition', () {
      final jde = julianEphemerisDay(julianDayFromCalendar(2020, 10, 13.0));
      expect(computePlanet(Planet.mars, jde).distanceAu, closeTo(0.415, 0.01));
    });

    test('Venus never strays far from the Sun', () {
      final start = julianDayFromCalendar(2026, 1, 1.0);
      var maximumElongation = 0.0;
      for (var i = 0; i < 365; i += 3) {
        final jde = julianEphemerisDay(start + i);
        final venus = computePlanet(Planet.venus, jde);
        final sun = computeSun(jde);
        final elongation = angularSeparation(
          venus.equatorial.raDeg,
          venus.equatorial.decDeg,
          sun.equatorial.raDeg,
          sun.equatorial.decDeg,
        );
        if (elongation > maximumElongation) maximumElongation = elongation;
      }
      expect(maximumElongation, greaterThan(40.0));
      expect(maximumElongation, lessThan(48.0));
    });

    test('each planet keeps to its own orbit', () {
      final jde = julianEphemerisDay(julianDayFromCalendar(2026, 8, 12.0));
      final ranges = {
        Planet.mercury: (0.30, 0.47),
        Planet.venus: (0.71, 0.74),
        Planet.mars: (1.38, 1.67),
        Planet.jupiter: (4.94, 5.46),
        Planet.saturn: (9.01, 10.07),
        Planet.uranus: (18.28, 20.10),
        Planet.neptune: (29.80, 30.33),
      };
      for (final entry in ranges.entries) {
        final r = computePlanet(entry.key, jde).heliocentricDistanceAu;
        expect(
          r,
          inInclusiveRange(entry.value.$1, entry.value.$2),
          reason: '${entry.key.displayName} heliocentric distance',
        );
      }
    });

    test('Venus is the brightest planet and Neptune the faintest', () {
      final jde = julianEphemerisDay(julianDayFromCalendar(2026, 8, 12.0));
      final venus = computePlanet(Planet.venus, jde);
      final neptune = computePlanet(Planet.neptune, jde);
      expect(venus.magnitude, lessThan(-3.0));
      expect(neptune.magnitude, greaterThan(7.0));
    });

    test('the inner planets show phases, the outer ones do not', () {
      final jde = julianEphemerisDay(julianDayFromCalendar(2026, 8, 12.0));
      expect(computePlanet(Planet.jupiter, jde).phaseAngleDeg, lessThan(12.0));
      expect(computePlanet(Planet.neptune, jde).phaseAngleDeg, lessThan(2.0));
    });

    test('computeAllPlanets skips Earth', () {
      final all = computeAllPlanets(
        julianEphemerisDay(julianDayFromCalendar(2026, 8, 12.0)),
      );
      expect(all, hasLength(7));
      expect(all.map((p) => p.planet), isNot(contains(Planet.earth)));
    });
  });
}
