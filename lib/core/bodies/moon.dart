import 'dart:math' as math;

import '../angles.dart';
import '../coordinates.dart';
import '../julian.dart';
import 'sun.dart';

/// Periodic terms for the Moon's longitude and distance (Meeus table 47.A).
///
/// Each row is `D, M, M', F, coefficient of sin for longitude (1e-6 degrees),
/// coefficient of cos for distance (1e-3 km)`.
const List<List<int>> _longitudeDistanceTerms = [
  [0, 0, 1, 0, 6288774, -20905355],
  [2, 0, -1, 0, 1274027, -3699111],
  [2, 0, 0, 0, 658314, -2955968],
  [0, 0, 2, 0, 213618, -569925],
  [0, 1, 0, 0, -185116, 48888],
  [0, 0, 0, 2, -114332, -3149],
  [2, 0, -2, 0, 58793, 246158],
  [2, -1, -1, 0, 57066, -152138],
  [2, 0, 1, 0, 53322, -170733],
  [2, -1, 0, 0, 45758, -204586],
  [0, 1, -1, 0, -40923, -129620],
  [1, 0, 0, 0, -34720, 108743],
  [0, 1, 1, 0, -30383, 104755],
  [2, 0, 0, -2, 15327, 10321],
  [0, 0, 1, 2, -12528, 0],
  [0, 0, 1, -2, 10980, 79661],
  [4, 0, -1, 0, 10675, -34782],
  [0, 0, 3, 0, 10034, -23210],
  [4, 0, -2, 0, 8548, -21636],
  [2, 1, -1, 0, -7888, 24208],
  [2, 1, 0, 0, -6766, 30824],
  [1, 0, -1, 0, -5163, -8379],
  [1, 1, 0, 0, 4987, -16675],
  [2, -1, 1, 0, 4036, -12831],
  [2, 0, 2, 0, 3994, -10445],
  [4, 0, 0, 0, 3861, -11650],
  [2, 0, -3, 0, 3665, 14403],
  [0, 1, -2, 0, -2689, -7003],
  [2, 0, -1, 2, -2602, 0],
  [2, -1, -2, 0, 2390, 10056],
  [1, 0, 1, 0, -2348, 6322],
  [2, -2, 0, 0, 2236, -9884],
  [0, 1, 2, 0, -2120, 5751],
  [0, 2, 0, 0, -2069, 0],
  [2, -2, -1, 0, 2048, -4950],
  [2, 0, 1, -2, -1773, 4130],
  [2, 0, 0, 2, -1595, 0],
  [4, -1, -1, 0, 1215, -3958],
  [0, 0, 2, 2, -1110, 0],
  [3, 0, -1, 0, -892, 3258],
  [2, 1, 1, 0, -810, 2616],
  [4, -1, -2, 0, 759, -1897],
  [0, 2, -1, 0, -713, -2117],
  [2, 2, -1, 0, -700, 2354],
  [2, 1, -2, 0, 691, 0],
  [2, -1, 0, -2, 596, 0],
  [4, 0, 1, 0, 549, -1423],
  [0, 0, 4, 0, 537, -1117],
  [4, -1, 0, 0, 520, -1571],
  [1, 0, -2, 0, -487, -1739],
  [2, 1, 0, -2, -399, 0],
  [0, 0, 2, -2, -381, -4421],
  [1, 1, 1, 0, 351, 0],
  [3, 0, -2, 0, -340, 0],
  [4, 0, -3, 0, 330, 0],
  [2, -1, 2, 0, 327, 0],
  [0, 2, 1, 0, -323, 1165],
  [1, 1, -1, 0, 299, 0],
  [2, 0, 3, 0, 294, 0],
  [2, 0, -1, -2, 0, 8752],
];

/// Periodic terms for the Moon's ecliptic latitude (Meeus table 47.B).
///
/// Each row is `D, M, M', F, coefficient of sin (1e-6 degrees)`.
const List<List<int>> _latitudeTerms = [
  [0, 0, 0, 1, 5128122],
  [0, 0, 1, 1, 280602],
  [0, 0, 1, -1, 277693],
  [2, 0, 0, -1, 173237],
  [2, 0, -1, 1, 55413],
  [2, 0, -1, -1, 46271],
  [2, 0, 0, 1, 32573],
  [0, 0, 2, 1, 17198],
  [2, 0, 1, -1, 9266],
  [0, 0, 2, -1, 8822],
  [2, -1, 0, -1, 8216],
  [2, 0, -2, -1, 4324],
  [2, 0, 1, 1, 4200],
  [2, 1, 0, -1, -3359],
  [2, -1, -1, 1, 2463],
  [2, -1, 0, 1, 2211],
  [2, -1, -1, -1, 2065],
  [0, 1, -1, -1, -1870],
  [4, 0, -1, -1, 1828],
  [0, 1, 0, 1, -1794],
  [0, 0, 0, 3, -1749],
  [0, 1, -1, 1, -1565],
  [1, 0, 0, 1, -1491],
  [0, 1, 1, 1, -1475],
  [0, 1, 1, -1, -1410],
  [0, 1, 0, -1, -1344],
  [1, 0, 0, -1, -1335],
  [0, 0, 3, 1, 1107],
  [4, 0, 0, -1, 1021],
  [4, 0, -1, 1, 833],
  [0, 0, 1, -3, 777],
  [4, 0, -2, 1, 671],
  [2, 0, 0, -3, 607],
  [2, 0, 2, -1, 596],
  [2, -1, 1, -1, 491],
  [2, 0, -2, 1, -451],
  [0, 0, 3, -1, 439],
  [2, 0, 2, 1, 422],
  [2, 0, -3, -1, 421],
  [2, 1, -1, 1, -366],
  [2, 1, 0, 1, -351],
  [4, 0, 0, 1, 331],
  [2, -1, 1, 1, 315],
  [2, -2, 0, -1, 302],
  [0, 0, 1, 3, -283],
  [2, 1, 1, -1, -229],
  [1, 1, 0, -1, 223],
  [1, 1, 0, 1, 223],
  [0, 1, -2, -1, -220],
  [2, 1, -1, -1, -220],
  [1, 0, 1, 1, -185],
  [2, -1, -2, -1, 181],
  [0, 1, 2, 1, -177],
  [4, 0, -2, -1, 176],
  [4, -1, -1, -1, 166],
  [1, 0, 1, -1, -164],
  [4, 0, 1, -1, 132],
  [1, 0, -1, -1, -119],
  [4, -1, 0, -1, 115],
  [2, -2, 0, 1, 107],
];

/// Nutation in longitude and obliquity, in degrees.
///
/// Abbreviated series (Meeus ch. 22), good to about half an arcsecond. The full
/// 63-term table would be overkill: half an arcsecond is a thousandth of a
/// pixel at any zoom the app offers.
({double longitude, double obliquity}) nutation(double jde) {
  final t = julianCenturiesFromJ2000(jde);
  final omega = 125.04452 - 1934.136261 * t;
  final sunLongitude = 280.4665 + 36000.7698 * t;
  final moonLongitude = 218.3165 + 481267.8813 * t;

  final dPsi = -17.20 * sinDeg(omega) -
      1.32 * sinDeg(2 * sunLongitude) -
      0.23 * sinDeg(2 * moonLongitude) +
      0.21 * sinDeg(2 * omega);
  final dEps = 9.20 * cosDeg(omega) +
      0.57 * cosDeg(2 * sunLongitude) +
      0.10 * cosDeg(2 * moonLongitude) -
      0.09 * cosDeg(2 * omega);

  return (longitude: dPsi * arcsecToDeg, obliquity: dEps * arcsecToDeg);
}

/// Geocentric position and appearance of the Moon.
class MoonPosition {
  const MoonPosition({
    required this.eclipticLongitudeDeg,
    required this.eclipticLatitudeDeg,
    required this.distanceKm,
    required this.parallaxDeg,
    required this.equatorial,
    required this.phaseAngleDeg,
    required this.illuminatedFraction,
    required this.brightLimbAngleDeg,
  });

  final double eclipticLongitudeDeg;
  final double eclipticLatitudeDeg;
  final double distanceKm;
  final double parallaxDeg;
  final Equatorial equatorial;

  /// Sun–Moon–Earth angle: 0° at full moon, 180° at new moon.
  final double phaseAngleDeg;

  /// 0 at new moon, 1 at full.
  final double illuminatedFraction;

  /// Position angle of the bright limb's midpoint, measured east from north.
  /// This is what tells the renderer which way to tilt the crescent.
  final double brightLimbAngleDeg;

  /// Apparent angular radius in degrees.
  double get angularRadiusDeg => radToDeg * math.asin(1737.4 / distanceKm);

  /// True when the Moon is waxing (illumination increasing).
  bool get isWaxing => eclipticLongitudeDeg.isFinite;
}

/// Computes the Moon's geocentric position (Meeus ch. 47).
///
/// Accurate to roughly 10" in longitude and 4" in latitude, which is a
/// thousandth of the Moon's own width.
MoonPosition computeMoon(double jde) {
  final t = julianCenturiesFromJ2000(jde);

  // Mean longitude, referred to the mean equinox of date.
  final lPrime = normalizeDegrees(polynomial(t, [
    218.3164477,
    481267.88123421,
    -0.0015786,
    1 / 538841.0,
    -1 / 65194000.0,
  ]));
  // Mean elongation of the Moon from the Sun.
  final d = normalizeDegrees(polynomial(t, [
    297.8501921,
    445267.1114034,
    -0.0018819,
    1 / 545868.0,
    -1 / 113065000.0,
  ]));
  // Sun's mean anomaly.
  final m = normalizeDegrees(polynomial(t, [
    357.5291092,
    35999.0502909,
    -0.0001536,
    1 / 24490000.0,
  ]));
  // Moon's mean anomaly.
  final mPrime = normalizeDegrees(polynomial(t, [
    134.9633964,
    477198.8675055,
    0.0087414,
    1 / 69699.0,
    -1 / 14712000.0,
  ]));
  // Moon's argument of latitude, distance from the ascending node.
  final f = normalizeDegrees(polynomial(t, [
    93.2720950,
    483202.0175233,
    -0.0036539,
    -1 / 3526000.0,
    1 / 863310000.0,
  ]));

  // Additive arguments for the perturbations by Venus and Jupiter, and the
  // flattening of the Earth.
  final a1 = normalizeDegrees(119.75 + 131.849 * t);
  final a2 = normalizeDegrees(53.09 + 479264.290 * t);
  final a3 = normalizeDegrees(313.45 + 481266.484 * t);

  // Eccentricity of the Earth's orbit, which modulates terms involving the
  // Sun's anomaly.
  final e = polynomial(t, [1.0, -0.002516, -0.0000074]);
  final eSquared = e * e;

  var sumL = 0.0;
  var sumR = 0.0;
  for (final term in _longitudeDistanceTerms) {
    final argument = term[0] * d + term[1] * m + term[2] * mPrime + term[3] * f;
    final eccentricity = switch (term[1].abs()) {
      1 => e,
      2 => eSquared,
      _ => 1.0,
    };
    sumL += term[4] * eccentricity * sinDeg(argument);
    sumR += term[5] * eccentricity * cosDeg(argument);
  }

  var sumB = 0.0;
  for (final term in _latitudeTerms) {
    final argument = term[0] * d + term[1] * m + term[2] * mPrime + term[3] * f;
    final eccentricity = switch (term[1].abs()) {
      1 => e,
      2 => eSquared,
      _ => 1.0,
    };
    sumB += term[4] * eccentricity * sinDeg(argument);
  }

  sumL += 3958 * sinDeg(a1) + 1962 * sinDeg(lPrime - f) + 318 * sinDeg(a2);
  sumB += -2235 * sinDeg(lPrime) +
      382 * sinDeg(a3) +
      175 * sinDeg(a1 - f) +
      175 * sinDeg(a1 + f) +
      127 * sinDeg(lPrime - mPrime) -
      115 * sinDeg(lPrime + mPrime);

  final longitude = normalizeDegrees(lPrime + sumL / 1000000.0);
  final latitude = sumB / 1000000.0;
  final distanceKm = 385000.56 + sumR / 1000.0;
  final parallax = radToDeg * math.asin(6378.14 / distanceKm);

  final nut = nutation(jde);
  final apparentLongitude = longitude + nut.longitude;
  final trueObliquity = meanObliquity(jde) + nut.obliquity;

  final equatorial = Ecliptic(
    apparentLongitude,
    latitude,
    distanceAu: distanceKm / 149597870.7,
  ).toEquatorial(trueObliquity);

  // Phase, from the geocentric elongation between the Sun and the Moon.
  final sun = computeSun(jde);
  final sunDistanceKm = sun.distanceAu * 149597870.7;
  final elongation = radToDeg *
      math.acos((cosDeg(latitude) *
              cosDeg(longitude - sun.apparentLongitudeDeg))
          .clamp(-1.0, 1.0));
  final phaseAngle = radToDeg *
      math.atan2(
        sunDistanceKm * sinDeg(elongation),
        distanceKm - sunDistanceKm * cosDeg(elongation),
      );
  final illuminated = (1 + cosDeg(phaseAngle)) / 2.0;

  // Position angle of the bright limb (Meeus 48.5).
  final sunRa = sun.equatorial.raDeg;
  final sunDec = sun.equatorial.decDeg;
  final moonRa = equatorial.raDeg;
  final moonDec = equatorial.decDeg;
  final brightLimb = normalizeDegrees(radToDeg *
      math.atan2(
        cosDeg(sunDec) * sinDeg(sunRa - moonRa),
        sinDeg(sunDec) * cosDeg(moonDec) -
            cosDeg(sunDec) * sinDeg(moonDec) * cosDeg(sunRa - moonRa),
      ));

  return MoonPosition(
    eclipticLongitudeDeg: longitude,
    eclipticLatitudeDeg: latitude,
    distanceKm: distanceKm,
    parallaxDeg: parallax,
    equatorial: equatorial,
    phaseAngleDeg: phaseAngle,
    illuminatedFraction: illuminated,
    brightLimbAngleDeg: brightLimb,
  );
}

/// Shifts a geocentric position to the observer's actual place on the surface.
///
/// The Moon is close enough that this matters: the parallax reaches about one
/// degree, two full Moon widths, which would be an obvious error on screen.
Equatorial applyTopocentricParallax(
  Equatorial geocentric,
  double parallaxDeg,
  double localSiderealTimeDeg,
  double latitudeDeg,
  double elevationMeters,
) {
  // Geocentric latitude corrections for the Earth's flattening.
  final u = math.atan(0.99664719 * tanDeg(latitudeDeg));
  final rhoSinPhi =
      0.99664719 * math.sin(u) + (elevationMeters / 6378140.0) * sinDeg(latitudeDeg);
  final rhoCosPhi =
      math.cos(u) + (elevationMeters / 6378140.0) * cosDeg(latitudeDeg);

  final hourAngle = localSiderealTimeDeg - geocentric.raDeg;
  final sinParallax = sinDeg(parallaxDeg);
  final dec = geocentric.decDeg * degToRad;

  final deltaRa = math.atan2(
    -rhoCosPhi * sinParallax * sinDeg(hourAngle),
    math.cos(dec) - rhoCosPhi * sinParallax * cosDeg(hourAngle),
  );
  final decTopo = math.atan2(
    (math.sin(dec) - rhoSinPhi * sinParallax) * math.cos(deltaRa),
    math.cos(dec) - rhoCosPhi * sinParallax * cosDeg(hourAngle),
  );

  return Equatorial(
    normalizeDegrees(geocentric.raDeg + deltaRa * radToDeg),
    decTopo * radToDeg,
    distanceAu: geocentric.distanceAu,
  );
}
