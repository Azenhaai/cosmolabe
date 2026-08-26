import 'package:flutter_test/flutter_test.dart';
import 'package:cosmolabe/core/angles.dart';
import 'package:cosmolabe/core/coordinates.dart';
import 'package:cosmolabe/core/julian.dart';

void main() {
  group('Angle parsing', () {
    test('reads plain decimal degrees', () {
      expect(parseSexagesimal('54.354'), closeTo(54.354, 1e-9));
      expect(parseSexagesimal('-16.9286'), closeTo(-16.9286, 1e-9));
    });

    test('reads space, colon and symbol separated sexagesimal', () {
      expect(parseSexagesimal('54 21 18'), closeTo(54.355, 1e-9));
      expect(parseSexagesimal('54:21:18'), closeTo(54.355, 1e-9));
      expect(parseSexagesimal("54°21'18\""), closeTo(54.355, 1e-9));
    });

    test('a hemisphere letter sets the sign', () {
      expect(parseSexagesimal('32 44 07 N'), closeTo(32.735278, 1e-5));
      expect(parseSexagesimal('16 55 43 W'), closeTo(-16.928611, 1e-5));
      expect(parseSexagesimal('16 55 43 S'), lessThan(0));
    });

    test('rejects out-of-range minutes and seconds', () {
      expect(parseSexagesimal('54 61 00'), isNull);
      expect(parseSexagesimal('54 21 75'), isNull);
    });

    test('returns null for junk rather than guessing', () {
      expect(parseSexagesimal(''), isNull);
      expect(parseSexagesimal('north-ish'), isNull);
    });

    test('formatting round-trips through parsing', () {
      const value = 32.735278;
      final formatted = Sexagesimal.fromDegrees(value).format(secondsDigits: 3);
      expect(parseSexagesimal(formatted), closeTo(value, 1e-7));
    });

    test('negative angles keep their sign through the split', () {
      final s = Sexagesimal.fromDegrees(-6.7198917);
      expect(s.negative, isTrue);
      expect(s.units, 6);
      expect(s.minutes, 43);
      expect(s.seconds, closeTo(11.61, 0.01));
      expect(s.value, closeTo(-6.7198917, 1e-9));
    });
  });

  group('Equatorial to horizontal', () {
    // Meeus example 13.a: Venus seen from Washington on 1987 April 10.
    const raDeg = 347.3193375; // 23h09m16.641s
    const decDeg = -6.7198917; // -6°43'11.61"
    const latitude = 38.9213;
    const longitude = -77.0655; // Meeus writes it as 77.0655 west.
    const greenwichSidereal = 128.7378734;
    const localSidereal = greenwichSidereal + longitude;

    test('matches the published altitude and azimuth', () {
      final horizontal = equatorialToHorizontal(
        const Equatorial(raDeg, decDeg),
        localSidereal,
        latitude,
      );
      expect(horizontal.altitudeDeg, closeTo(15.1249, 0.001));
      // Meeus measures azimuth westward from south; we measure eastward from
      // north, which is 180 degrees away.
      expect(horizontal.azimuthDeg, closeTo(68.0337 + 180.0, 0.001));
    });

    test('inverts back to the original equatorial position', () {
      const original = Equatorial(raDeg, decDeg);
      final horizontal =
          equatorialToHorizontal(original, localSidereal, latitude);
      final restored =
          horizontalToEquatorial(horizontal, localSidereal, latitude);
      expect(restored.raDeg, closeTo(original.raDeg, 1e-8));
      expect(restored.decDeg, closeTo(original.decDeg, 1e-8));
    });

    test('the celestial pole sits due north at the observer latitude', () {
      final pole = equatorialToHorizontal(
        const Equatorial(0, 90),
        123.456,
        latitude,
      );
      expect(pole.altitudeDeg, closeTo(latitude, 1e-9));
      // Due north is the seam of the 0-360 range, so compare on the signed
      // branch rather than tripping over a value of 359.999...
      expect(normalizeDegreesSigned(pole.azimuthDeg), closeTo(0.0, 1e-6));
    });

    test('the south pole is below the horizon in the north', () {
      final pole = equatorialToHorizontal(
        const Equatorial(0, -90),
        200.0,
        latitude,
      );
      expect(pole.altitudeDeg, closeTo(-latitude, 1e-9));
      expect(pole.azimuthDeg, closeTo(180.0, 1e-6));
    });

    test('an object on the meridian south of the zenith reads azimuth 180', () {
      // Hour angle zero puts the object on the meridian.
      const lst = 100.0;
      final horizontal = equatorialToHorizontal(
        const Equatorial(lst, 10.0),
        lst,
        latitude,
      );
      expect(horizontal.azimuthDeg, closeTo(180.0, 1e-6));
      expect(horizontal.altitudeDeg, closeTo(90 - latitude + 10.0, 1e-6));
    });

    test('an object six hours east of the meridian rises in the east', () {
      const lst = 100.0;
      final horizontal = equatorialToHorizontal(
        const Equatorial(lst + 90.0, 0.0),
        lst,
        0.0,
      );
      expect(horizontal.azimuthDeg, closeTo(90.0, 1e-6));
    });
  });

  group('Precession', () {
    test('Meeus example 21.b — theta Persei to 2028 November 13.19', () {
      // Meeus applies proper motion first; these are his intermediate values.
      const raDeg = 41.054063; // 2h44m12.975s
      const decDeg = 49.227750; // 49°13'39.90"
      final jde = julianDayFromCalendar(2028, 11, 13.19);

      final precessed = precessFromJ2000(const Equatorial(raDeg, decDeg), jde);
      expect(precessed.raDeg, closeTo(41.547214, 1e-5));
      expect(precessed.decDeg, closeTo(49.348483, 1e-5));
    });

    test('is a no-op at the J2000 epoch itself', () {
      const position = Equatorial(120.0, 45.0);
      final result = precessFromJ2000(position, j2000);
      expect(result.raDeg, closeTo(position.raDeg, 1e-12));
      expect(result.decDeg, closeTo(position.decDeg, 1e-12));
    });

    test('moves positions by roughly 50 arcseconds per year', () {
      const position = Equatorial(0.0, 0.0);
      final oneCentury = precessFromJ2000(position, j2000 + 36525);
      final shift = angularSeparation(
        position.raDeg,
        position.decDeg,
        oneCentury.raDeg,
        oneCentury.decDeg,
      );
      expect(shift * 3600 / 100, closeTo(50.3, 1.5));
    });

    test('stays stable right at the pole', () {
      final result = precessFromJ2000(const Equatorial(0.0, 89.99), j2000 + 36525);
      expect(result.decDeg.isFinite, isTrue);
      expect(result.decDeg, inInclusiveRange(89.0, 90.0));
    });
  });

  group('Proper motion', () {
    test("Barnard's Star moves about 10 arcseconds a year", () {
      const barnard = Equatorial(269.452, 4.693);
      // Catalogue proper motion in milliarcseconds per year.
      final moved = applyProperMotion(barnard, -798.58, 10328.12, 1.0);
      final shift = angularSeparation(
        barnard.raDeg,
        barnard.decDeg,
        moved.raDeg,
        moved.decDeg,
      );
      expect(shift * 3600, closeTo(10.36, 0.05));
    });

    test('is a no-op for a star with no measured motion', () {
      const position = Equatorial(10.0, 20.0);
      final moved = applyProperMotion(position, 0, 0, 25.0);
      expect(moved.raDeg, position.raDeg);
      expect(moved.decDeg, position.decDeg);
    });
  });

  group('Refraction', () {
    test('lifts objects at the horizon by about half a degree', () {
      expect(refractionDegrees(0.0) * 60, closeTo(29.0, 1.0));
    });

    test('is about one arcminute at 45 degrees', () {
      expect(refractionDegrees(45.0) * 60, closeTo(1.0, 0.1));
    });

    test('is negligible at the zenith', () {
      expect(refractionDegrees(90.0) * 60, lessThan(0.05));
    });

    test('decreases monotonically with altitude', () {
      var previous = double.infinity;
      for (var alt = 0.0; alt <= 90.0; alt += 5.0) {
        final r = refractionDegrees(alt);
        expect(r, lessThan(previous));
        previous = r;
      }
    });

    test('thinner air refracts less', () {
      final sealevel = refractionDegrees(10.0, pressureMillibars: 1010);
      final mountain = refractionDegrees(10.0, pressureMillibars: 810);
      expect(mountain, lessThan(sealevel));
    });
  });

  group('Horizon dip', () {
    test('is zero at sea level', () {
      expect(horizonDipDegrees(0), 0.0);
    });

    test('is about 1.2 degrees from Pico do Arieiro', () {
      expect(horizonDipDegrees(1818), closeTo(1.25, 0.1));
    });
  });
}
