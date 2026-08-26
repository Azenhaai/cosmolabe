import 'dart:math' as math;

import 'angles.dart';
import 'julian.dart';

/// A direction on the celestial sphere, in equatorial coordinates.
///
/// [raDeg] is right ascension in degrees (not hours) so that it composes with
/// the rest of the maths without constant factor-of-15 conversions.
class Equatorial {
  const Equatorial(this.raDeg, this.decDeg, {this.distanceAu});

  final double raDeg;
  final double decDeg;

  /// Distance in astronomical units, when the body has a meaningful one.
  /// Null for stars, which we treat as being at infinity.
  final double? distanceAu;

  double get raHours => degreesToHours(raDeg);

  @override
  String toString() => 'Equatorial(ra: $raDeg°, dec: $decDeg°)';
}

/// A direction in the observer's local sky.
///
/// [azimuthDeg] is measured from north, increasing towards east, which matches
/// the convention the device sensors report.
class Horizontal {
  const Horizontal(this.azimuthDeg, this.altitudeDeg);

  final double azimuthDeg;
  final double altitudeDeg;

  bool get isAboveHorizon => altitudeDeg > 0;

  @override
  String toString() => 'Horizontal(az: $azimuthDeg°, alt: $altitudeDeg°)';
}

/// A direction in ecliptic coordinates, the natural frame for solar system
/// bodies before they are rotated onto the equator.
class Ecliptic {
  const Ecliptic(this.longitudeDeg, this.latitudeDeg, {this.distanceAu});

  final double longitudeDeg;
  final double latitudeDeg;
  final double? distanceAu;

  /// Rotates onto the equator using the obliquity [obliquityDeg].
  Equatorial toEquatorial(double obliquityDeg) {
    final lambda = longitudeDeg * degToRad;
    final beta = latitudeDeg * degToRad;
    final eps = obliquityDeg * degToRad;

    final sinBeta = math.sin(beta);
    final cosBeta = math.cos(beta);
    final sinLambda = math.sin(lambda);

    final ra = math.atan2(
      sinLambda * math.cos(eps) - math.tan(beta) * math.sin(eps),
      math.cos(lambda),
    );
    final dec = math.asin(
      sinBeta * math.cos(eps) + cosBeta * math.sin(eps) * sinLambda,
    );

    return Equatorial(
      normalizeDegrees(ra * radToDeg),
      dec * radToDeg,
      distanceAu: distanceAu,
    );
  }
}

/// Precesses equatorial coordinates from J2000.0 to the equinox of [jde].
///
/// Rigorous rotation from Meeus ch. 21, not the small-angle approximation:
/// near the celestial poles the approximation falls apart, and Polaris is
/// exactly where users point their phone first.
Equatorial precessFromJ2000(Equatorial position, double jde) {
  final t = julianCenturiesFromJ2000(jde);
  if (t == 0) return position;

  final zeta = polynomial(t, [0.0, 2306.2181, 0.30188, 0.017998]) * arcsecToDeg;
  final z = polynomial(t, [0.0, 2306.2181, 1.09468, 0.018203]) * arcsecToDeg;
  final theta =
      polynomial(t, [0.0, 2004.3109, -0.42665, -0.041833]) * arcsecToDeg;

  final ra0 = position.raDeg * degToRad;
  final dec0 = position.decDeg * degToRad;
  final zetaRad = zeta * degToRad;
  final zRad = z * degToRad;
  final thetaRad = theta * degToRad;

  final cosDec0 = math.cos(dec0);
  final sinDec0 = math.sin(dec0);
  final cosRaZeta = math.cos(ra0 + zetaRad);
  final sinRaZeta = math.sin(ra0 + zetaRad);

  final a = cosDec0 * sinRaZeta;
  final b = math.cos(thetaRad) * cosDec0 * cosRaZeta -
      math.sin(thetaRad) * sinDec0;
  final c = math.sin(thetaRad) * cosDec0 * cosRaZeta +
      math.cos(thetaRad) * sinDec0;

  final ra = math.atan2(a, b) + zRad;

  // Near the poles `asin(c)` loses precision; the hypot form stays stable.
  final dec = c.abs() > 0.9
      ? math.acos(math.sqrt(a * a + b * b)) * (c.isNegative ? -1 : 1)
      : math.asin(c);

  return Equatorial(
    normalizeDegrees(ra * radToDeg),
    dec * radToDeg,
    distanceAu: position.distanceAu,
  );
}

/// Applies proper motion to a catalogue position.
///
/// [pmRaMasPerYear] is the projected motion (already containing the cos(dec)
/// factor, as the HYG catalogue stores it), both in milliarcseconds per year.
Equatorial applyProperMotion(
  Equatorial position,
  double pmRaMasPerYear,
  double pmDecMasPerYear,
  double years,
) {
  if (years == 0 || (pmRaMasPerYear == 0 && pmDecMasPerYear == 0)) {
    return position;
  }
  final decDeg = position.decDeg + pmDecMasPerYear * years / 3600000.0;
  final cosDec = cosDeg(position.decDeg);
  // Guard the division at the poles, where RA becomes meaningless anyway.
  final raDeg = cosDec.abs() < 1e-9
      ? position.raDeg
      : position.raDeg + pmRaMasPerYear * years / 3600000.0 / cosDec;
  return Equatorial(
    normalizeDegrees(raDeg),
    decDeg.clamp(-90.0, 90.0),
    distanceAu: position.distanceAu,
  );
}

/// Converts equatorial to horizontal coordinates.
///
/// [localSiderealTimeDeg] fixes the moment, [latitudeDeg] the place. The result
/// is the geometric direction, before any atmospheric refraction.
Horizontal equatorialToHorizontal(
  Equatorial position,
  double localSiderealTimeDeg,
  double latitudeDeg,
) {
  final hourAngle = (localSiderealTimeDeg - position.raDeg) * degToRad;
  final dec = position.decDeg * degToRad;
  final lat = latitudeDeg * degToRad;

  final sinDec = math.sin(dec);
  final cosDec = math.cos(dec);
  final sinLat = math.sin(lat);
  final cosLat = math.cos(lat);
  final cosH = math.cos(hourAngle);

  // Local ENU components of the unit vector towards the object.
  final north = sinDec * cosLat - cosDec * cosH * sinLat;
  final east = -cosDec * math.sin(hourAngle);
  final up = sinDec * sinLat + cosDec * cosH * cosLat;

  return Horizontal(
    normalizeDegrees(math.atan2(east, north) * radToDeg),
    math.asin(up.clamp(-1.0, 1.0)) * radToDeg,
  );
}

/// Converts horizontal back to equatorial coordinates.
///
/// Needed for the "calibrate on a known star" flow, where the user hands us a
/// screen direction and we have to say which patch of sky it corresponds to.
Equatorial horizontalToEquatorial(
  Horizontal position,
  double localSiderealTimeDeg,
  double latitudeDeg,
) {
  final az = position.azimuthDeg * degToRad;
  final alt = position.altitudeDeg * degToRad;
  final lat = latitudeDeg * degToRad;

  final north = math.cos(alt) * math.cos(az);
  final east = math.cos(alt) * math.sin(az);
  final up = math.sin(alt);

  final dec = math.asin((up * math.sin(lat) + north * math.cos(lat)).clamp(-1.0, 1.0));
  final hourAngle = math.atan2(-east, up * math.cos(lat) - north * math.sin(lat));

  return Equatorial(
    normalizeDegrees(localSiderealTimeDeg - hourAngle * radToDeg),
    dec * radToDeg,
  );
}

/// Atmospheric refraction in degrees to add to a true altitude.
///
/// Saemundsson's formula (Meeus 16.4) with the pressure and temperature
/// correction. At the horizon this is about half a degree, which is why the
/// Sun appears to set later than it geometrically does.
double refractionDegrees(
  double trueAltitudeDeg, {
  double pressureMillibars = 1010.0,
  double temperatureCelsius = 10.0,
}) {
  // Below a few degrees under the horizon the formula diverges; nothing is
  // visible there anyway, so clamp rather than return nonsense.
  if (trueAltitudeDeg < -2.0) return 0.0;
  final h = trueAltitudeDeg;
  final arcminutes = 1.02 / tanDeg(h + 10.3 / (h + 5.11));
  final corrected = arcminutes *
      (pressureMillibars / 1010.0) *
      (283.0 / (273.0 + temperatureCelsius));
  return corrected / 60.0;
}

/// Applies [refractionDegrees] to a horizontal position.
Horizontal applyRefraction(
  Horizontal position, {
  double pressureMillibars = 1010.0,
  double temperatureCelsius = 10.0,
}) {
  final r = refractionDegrees(
    position.altitudeDeg,
    pressureMillibars: pressureMillibars,
    temperatureCelsius: temperatureCelsius,
  );
  return Horizontal(position.azimuthDeg, position.altitudeDeg + r);
}

/// Angle from the zenith down to the geometric horizon, for an observer
/// [elevationMeters] above sea level.
///
/// From a mountain the horizon sits measurably below level, which is exactly
/// the case worth getting right on Madeira.
double horizonDipDegrees(double elevationMeters) {
  if (elevationMeters <= 0) return 0.0;
  // Standard dip including average terrestrial refraction.
  return 0.0293 * math.sqrt(elevationMeters);
}
