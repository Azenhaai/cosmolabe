import 'package:flutter_test/flutter_test.dart';
import 'package:cosmolabe/core/julian.dart';

/// Reference values are the worked examples from Jean Meeus,
/// "Astronomical Algorithms" (2nd ed.), chapters 7 and 12.
void main() {
  group('Julian day', () {
    test('Meeus example 7.a — 1957 October 4.81', () {
      expect(julianDayFromCalendar(1957, 10, 4.81), closeTo(2436116.31, 1e-6));
    });

    test('J2000.0 epoch', () {
      expect(julianDayFromCalendar(2000, 1, 1.5), closeTo(2451545.0, 1e-9));
    });

    test('start of 1999', () {
      expect(julianDayFromCalendar(1999, 1, 1.0), closeTo(2451179.5, 1e-9));
    });

    test('Julian calendar dates before the 1582 reform', () {
      // Meeus example 7.b and the surrounding table.
      expect(julianDayFromCalendar(333, 1, 27.5), closeTo(1842713.0, 1e-6));
      expect(julianDayFromCalendar(837, 4, 10.3), closeTo(2026871.8, 1e-6));
      expect(julianDayFromCalendar(-1000, 7, 12.5), closeTo(1356001.0, 1e-6));
    });

    test('the reform boundary is continuous', () {
      final lastJulian = julianDayFromCalendar(1582, 10, 4.0);
      final firstGregorian = julianDayFromCalendar(1582, 10, 15.0);
      expect(firstGregorian - lastJulian, closeTo(1.0, 1e-9));
    });

    test('DateTime conversion round-trips', () {
      final original = DateTime.utc(2026, 8, 12, 22, 41, 17);
      final jd = julianDayFromDateTime(original);
      final restored = dateTimeFromJulianDay(jd);
      expect(
        restored.difference(original).inMilliseconds.abs(),
        lessThan(50),
      );
    });

    test('DateTime conversion honours the local time zone', () {
      final utc = DateTime.utc(2026, 8, 12, 12, 0, 0);
      final local = utc.toLocal();
      expect(
        julianDayFromDateTime(local),
        closeTo(julianDayFromDateTime(utc), 1e-9),
      );
    });
  });

  group('Sidereal time', () {
    test('Meeus example 12.a — 1987 April 10, 0h UT', () {
      final jd = julianDayFromCalendar(1987, 4, 10.0);
      expect(jd, closeTo(2446895.5, 1e-9));
      expect(greenwichMeanSiderealTime(jd), closeTo(197.693195, 1e-5));
    });

    test('Meeus example 12.b — 1987 April 10, 19h21m UT', () {
      final jd = julianDayFromCalendar(1987, 4, 10.0 + (19 + 21 / 60.0) / 24.0);
      expect(greenwichMeanSiderealTime(jd), closeTo(128.7378734, 1e-5));
    });

    test('local sidereal time shifts with longitude', () {
      final jd = julianDayFromCalendar(2026, 8, 12.5);
      final greenwich = greenwichMeanSiderealTime(jd);
      // Madeira sits about 17 degrees west.
      expect(
        localMeanSiderealTime(jd, -16.928611),
        closeTo((greenwich - 16.928611 + 360) % 360, 1e-9),
      );
    });

    test('advances by roughly 360.9856 degrees per day', () {
      final jd = julianDayFromCalendar(2026, 3, 1.0);
      final today = greenwichMeanSiderealTime(jd);
      final tomorrow = greenwichMeanSiderealTime(jd + 1);
      expect((tomorrow - today + 360) % 360, closeTo(0.98564736, 1e-5));
    });
  });

  group('Obliquity and delta T', () {
    test('mean obliquity at J2000 matches the IAU value', () {
      expect(meanObliquity(2451545.0), closeTo(23.4392911, 1e-6));
    });

    test('Meeus example 22.a — 1987 April 10', () {
      expect(meanObliquity(2446895.5), closeTo(23.44094629, 1e-6));
    });

    test('obliquity decreases slowly with time', () {
      expect(meanObliquity(2451545.0 + 36525), lessThan(meanObliquity(2451545.0)));
    });

    test('delta T is around 75 seconds in the mid 2020s', () {
      expect(deltaTSeconds(2026), closeTo(75.0, 2.0));
    });

    test('delta T was around 55 seconds in 1990', () {
      expect(deltaTSeconds(1990), closeTo(56.9, 1.5));
    });
  });
}
