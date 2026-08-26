import '../angles.dart';
import '../coordinates.dart';
import '../julian.dart';

/// Geometric and apparent position of the Sun (Meeus ch. 25).
///
/// Accurate to about 0.01°, which is a fifth of the Sun's own diameter — well
/// past what any phone screen can show.
class SunPosition {
  const SunPosition({
    required this.apparentLongitudeDeg,
    required this.trueLongitudeDeg,
    required this.meanAnomalyDeg,
    required this.distanceAu,
    required this.equatorial,
  });

  final double apparentLongitudeDeg;
  final double trueLongitudeDeg;
  final double meanAnomalyDeg;
  final double distanceAu;
  final Equatorial equatorial;

  /// Apparent angular radius in degrees, for drawing the disc to scale.
  double get angularRadiusDeg => 0.2665833 / distanceAu;
}

SunPosition computeSun(double jde) {
  final t = julianCenturiesFromJ2000(jde);

  final l0 = normalizeDegrees(
    polynomial(t, [280.46646, 36000.76983, 0.0003032]),
  );
  final m = normalizeDegrees(
    polynomial(t, [357.52911, 35999.05029, -0.0001537]),
  );
  final e = polynomial(t, [0.016708634, -0.000042037, -0.0000001267]);

  // Equation of the centre: the orbit is an ellipse, so the Sun runs ahead of
  // and behind its mean position over the year.
  final c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sinDeg(m) +
      (0.019993 - 0.000101 * t) * sinDeg(2 * m) +
      0.000289 * sinDeg(3 * m);

  final trueLongitude = l0 + c;
  final trueAnomaly = m + c;
  final distance =
      1.000001018 * (1 - e * e) / (1 + e * cosDeg(trueAnomaly));

  // Correction for nutation and aberration.
  final omega = 125.04 - 1934.136 * t;
  final apparentLongitude =
      trueLongitude - 0.00569 - 0.00478 * sinDeg(omega);

  final obliquity = meanObliquity(jde) + 0.00256 * cosDeg(omega);

  final equatorial = Ecliptic(
    apparentLongitude,
    0.0,
    distanceAu: distance,
  ).toEquatorial(obliquity);

  return SunPosition(
    apparentLongitudeDeg: normalizeDegrees(apparentLongitude),
    trueLongitudeDeg: normalizeDegrees(trueLongitude),
    meanAnomalyDeg: m,
    distanceAu: distance,
    equatorial: equatorial,
  );
}

/// Altitude thresholds that define the twilight phases, in degrees of solar
/// altitude. Used to decide how dark to draw the sky background.
class Twilight {
  static const double sunset = -0.833; // Upper limb, refracted.
  static const double civil = -6.0;
  static const double nautical = -12.0;
  static const double astronomical = -18.0;
}

/// How dark the sky is, from 0 (full daylight) to 1 (fully dark).
///
/// Ramps across the twilight bands rather than switching abruptly, so the
/// background fades the way the real sky does.
double skyDarkness(double sunAltitudeDeg) {
  if (sunAltitudeDeg >= Twilight.sunset) return 0.0;
  if (sunAltitudeDeg <= Twilight.astronomical) return 1.0;
  final span = Twilight.sunset - Twilight.astronomical;
  return (Twilight.sunset - sunAltitudeDeg) / span;
}
