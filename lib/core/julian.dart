import 'angles.dart';

/// Julian Day number of the J2000.0 epoch (2000 January 1.5 TT).
const double j2000 = 2451545.0;

/// Days in a Julian century.
const double julianCentury = 36525.0;

/// Converts a calendar date to a Julian Day.
///
/// [day] may carry a fraction. Dates before 1582 October 15 are interpreted in
/// the Julian calendar, matching the historical switch (Meeus, ch. 7).
double julianDayFromCalendar(int year, int month, double day) {
  var y = year;
  var m = month;
  if (m <= 2) {
    y -= 1;
    m += 12;
  }

  // The Gregorian correction only applies after the 1582 reform.
  final isGregorian = year > 1582 ||
      (year == 1582 && (month > 10 || (month == 10 && day >= 15)));
  var b = 0;
  if (isGregorian) {
    final a = (y / 100).floor();
    b = 2 - a + (a / 4).floor();
  }

  return (365.25 * (y + 4716)).floor() +
      (30.6001 * (m + 1)).floor() +
      day +
      b -
      1524.5;
}

/// Julian Day (UT) for a [DateTime]. The value is converted to UTC first.
double julianDayFromDateTime(DateTime dateTime) {
  final utc = dateTime.toUtc();
  final dayFraction = (utc.hour +
          utc.minute / 60.0 +
          utc.second / 3600.0 +
          utc.millisecond / 3600000.0) /
      24.0;
  return julianDayFromCalendar(utc.year, utc.month, utc.day + dayFraction);
}

/// Calendar date for a Julian Day, as a UTC [DateTime].
DateTime dateTimeFromJulianDay(double jd) {
  final shifted = jd + 0.5;
  final z = shifted.floor();
  final f = shifted - z;

  var a = z;
  if (z >= 2299161) {
    final alpha = ((z - 1867216.25) / 36524.25).floor();
    a = z + 1 + alpha - (alpha / 4).floor();
  }
  final b = a + 1524;
  final c = ((b - 122.1) / 365.25).floor();
  final d = (365.25 * c).floor();
  final e = ((b - d) / 30.6001).floor();

  final dayWithFraction = b - d - (30.6001 * e).floor() + f;
  final month = e < 14 ? e - 1 : e - 13;
  final year = month > 2 ? c - 4716 : c - 4715;

  final day = dayWithFraction.floor();
  final millis = ((dayWithFraction - day) * 86400000.0).round();
  return DateTime.utc(year, month, day).add(Duration(milliseconds: millis));
}

/// Julian centuries from J2000.0.
double julianCenturiesFromJ2000(double jd) => (jd - j2000) / julianCentury;

/// Difference TT − UT1 in seconds, the accumulated drift of civil time from
/// uniform dynamical time.
///
/// Uses the Espenak & Meeus polynomial fits. Star positions barely notice
/// (~15" per minute of error for the Moon, far less for everything else), but
/// getting it roughly right keeps lunar positions honest.
double deltaTSeconds(double year) {
  if (year >= 2005 && year < 2050) {
    final t = year - 2000;
    return polynomial(t, [62.92, 0.32217, 0.005589]);
  }
  if (year >= 1986 && year < 2005) {
    final t = year - 2000;
    return polynomial(t, [
      63.86,
      0.3345,
      -0.060374,
      0.0017275,
      0.000651814,
      0.00002373599,
    ]);
  }
  if (year >= 1961 && year < 1986) {
    final t = year - 1975;
    return polynomial(t, [45.45, 1.067, -1 / 260.0, -1 / 718.0]);
  }
  if (year >= 1941 && year < 1961) {
    final t = year - 1950;
    return polynomial(t, [29.07, 0.407, -1 / 233.0, 1 / 2547.0]);
  }
  if (year >= 2050 && year < 2150) {
    final u = (year - 1820) / 100.0;
    return -20 + 32 * u * u - 0.5628 * (2150 - year);
  }
  // Long-range parabola for everything outside the fitted intervals.
  final u = (year - 1820) / 100.0;
  return -20 + 32 * u * u;
}

/// Decimal year for a Julian Day, accurate enough for [deltaTSeconds].
double decimalYearFromJulianDay(double jd) => 2000.0 + (jd - j2000) / 365.25;

/// Converts a UT Julian Day to the dynamical-time Julian Day (JDE) that the
/// ephemeris formulae expect.
double julianEphemerisDay(double jdUt) =>
    jdUt + deltaTSeconds(decimalYearFromJulianDay(jdUt)) / 86400.0;

/// Greenwich mean sidereal time in degrees, for a UT Julian Day.
double greenwichMeanSiderealTime(double jdUt) {
  final t = julianCenturiesFromJ2000(jdUt);
  final theta = 280.46061837 +
      360.98564736629 * (jdUt - j2000) +
      0.000387933 * t * t -
      t * t * t / 38710000.0;
  return normalizeDegrees(theta);
}

/// Local mean sidereal time in degrees. [longitudeDeg] is positive east.
double localMeanSiderealTime(double jdUt, double longitudeDeg) =>
    normalizeDegrees(greenwichMeanSiderealTime(jdUt) + longitudeDeg);

/// Mean obliquity of the ecliptic in degrees (Laskar's expansion, Meeus 22.3).
double meanObliquity(double jde) {
  final u = julianCenturiesFromJ2000(jde) / 100.0;
  return polynomial(u, [
        23.0 + 26.0 / 60.0 + 21.448 / 3600.0,
        -4680.93 * arcsecToDeg,
        -1.55 * arcsecToDeg,
        1999.25 * arcsecToDeg,
        -51.38 * arcsecToDeg,
        -249.67 * arcsecToDeg,
        -39.05 * arcsecToDeg,
        7.12 * arcsecToDeg,
        27.87 * arcsecToDeg,
        5.79 * arcsecToDeg,
        2.45 * arcsecToDeg,
      ]);
}
