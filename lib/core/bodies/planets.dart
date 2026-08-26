import 'dart:math' as math;

import '../angles.dart';
import '../coordinates.dart';
import '../julian.dart';

/// Speed of light in astronomical units per day, for the light-time correction.
const double _auPerDay = 173.1446;

enum Planet {
  mercury('Mercury', 6.74, -0.42),
  venus('Venus', 16.92, -4.40),
  earth('Earth', 0.0, 0.0),
  mars('Mars', 9.36, -1.52),
  jupiter('Jupiter', 196.94, -9.40),
  saturn('Saturn', 165.60, -8.88),
  uranus('Uranus', 65.80, -7.19),
  neptune('Neptune', 62.20, -6.87);

  const Planet(this.displayName, this.angularDiameterAt1Au, this.absoluteMagnitude);

  final String displayName;

  /// Equatorial angular diameter in arcseconds seen from one AU.
  final double angularDiameterAt1Au;

  /// Magnitude at unit distance and zero phase angle.
  final double absoluteMagnitude;

  /// The planets a user can actually be shown, Earth excluded.
  static List<Planet> get visible =>
      values.where((p) => p != Planet.earth).toList(growable: false);
}

/// Keplerian elements and their per-century rates.
///
/// Standish's "Approximate Positions of the Planets", fitted for 1800–2050.
/// Good to a few arcminutes for the outer planets and better than an
/// arcminute for the inner ones — invisible at any zoom the app offers, and a
/// hundredth of the data a full VSOP87 truncation would need.
class _Elements {
  const _Elements(
    this.semiMajorAxis,
    this.eccentricity,
    this.inclination,
    this.meanLongitude,
    this.longitudeOfPerihelion,
    this.longitudeOfAscendingNode,
    this.semiMajorAxisRate,
    this.eccentricityRate,
    this.inclinationRate,
    this.meanLongitudeRate,
    this.longitudeOfPerihelionRate,
    this.longitudeOfAscendingNodeRate,
  );

  final double semiMajorAxis; // AU
  final double eccentricity;
  final double inclination; // degrees
  final double meanLongitude; // degrees
  final double longitudeOfPerihelion; // degrees
  final double longitudeOfAscendingNode; // degrees

  final double semiMajorAxisRate;
  final double eccentricityRate;
  final double inclinationRate;
  final double meanLongitudeRate;
  final double longitudeOfPerihelionRate;
  final double longitudeOfAscendingNodeRate;
}

const Map<Planet, _Elements> _elements = {
  Planet.mercury: _Elements(
    0.38709927, 0.20563593, 7.00497902, 252.25032350, 77.45779628, 48.33076593,
    0.00000037, 0.00001906, -0.00594749, 149472.67411175, 0.16047689, -0.12534081,
  ),
  Planet.venus: _Elements(
    0.72333566, 0.00677672, 3.39467605, 181.97909950, 131.60246718, 76.67984255,
    0.00000390, -0.00004107, -0.00078890, 58517.81538729, 0.00268329, -0.27769418,
  ),
  Planet.earth: _Elements(
    1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0,
    0.00000562, -0.00004392, -0.01294668, 35999.37244981, 0.32327364, 0.0,
  ),
  Planet.mars: _Elements(
    1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891,
    0.00001847, 0.00007882, -0.00813131, 19140.30268499, 0.44441088, -0.29257343,
  ),
  Planet.jupiter: _Elements(
    5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909,
    -0.00011607, -0.00013253, -0.00183714, 3034.74612775, 0.21252668, 0.20469106,
  ),
  Planet.saturn: _Elements(
    9.53667594, 0.05386179, 2.48599187, 49.95424423, 92.59887831, 113.66242448,
    -0.00125060, -0.00050991, 0.00193609, 1222.49362201, -0.41897216, -0.28867794,
  ),
  Planet.uranus: _Elements(
    19.18916464, 0.04725744, 0.77263783, 313.23810451, 170.95427630, 74.01692503,
    -0.00196176, -0.00004397, -0.00242939, 428.48202785, 0.40805281, 0.04240589,
  ),
  Planet.neptune: _Elements(
    30.06992276, 0.00859048, 1.77004347, -55.12002969, 44.96476227, 131.78422574,
    0.00026291, 0.00005105, 0.00035372, 218.45945325, -0.32241464, -0.00508664,
  ),
};

/// A heliocentric rectangular position in the J2000 ecliptic frame, in AU.
class Vector3 {
  const Vector3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  double get length => math.sqrt(x * x + y * y + z * z);

  Vector3 operator -(Vector3 other) =>
      Vector3(x - other.x, y - other.y, z - other.z);

  @override
  String toString() => 'Vector3($x, $y, $z)';
}

/// Solves Kepler's equation for the eccentric anomaly, in degrees.
///
/// Newton–Raphson converges in a handful of steps for every planetary
/// eccentricity; the iteration cap is only there so a pathological input can
/// never hang the render loop.
double _solveKepler(double meanAnomalyDeg, double eccentricity) {
  final m = normalizeDegreesSigned(meanAnomalyDeg);
  final eStar = radToDeg * eccentricity;
  var e = m + eStar * sinDeg(m);
  for (var i = 0; i < 12; i++) {
    final deltaM = m - (e - eStar * sinDeg(e));
    final deltaE = deltaM / (1 - eccentricity * cosDeg(e));
    e += deltaE;
    if (deltaE.abs() < 1e-9) break;
  }
  return e;
}

/// Heliocentric position of [planet] in the J2000 ecliptic frame.
Vector3 heliocentricPosition(Planet planet, double jde) {
  final el = _elements[planet]!;
  final t = julianCenturiesFromJ2000(jde);

  final a = el.semiMajorAxis + el.semiMajorAxisRate * t;
  final e = el.eccentricity + el.eccentricityRate * t;
  final i = el.inclination + el.inclinationRate * t;
  final l = el.meanLongitude + el.meanLongitudeRate * t;
  final peri = el.longitudeOfPerihelion + el.longitudeOfPerihelionRate * t;
  final node =
      el.longitudeOfAscendingNode + el.longitudeOfAscendingNodeRate * t;

  final argumentOfPerihelion = peri - node;
  final eccentricAnomaly = _solveKepler(l - peri, e);

  // Position in the orbital plane, perihelion along +x.
  final xOrbital = a * (cosDeg(eccentricAnomaly) - e);
  final yOrbital = a * math.sqrt(1 - e * e) * sinDeg(eccentricAnomaly);

  final cosW = cosDeg(argumentOfPerihelion);
  final sinW = sinDeg(argumentOfPerihelion);
  final cosO = cosDeg(node);
  final sinO = sinDeg(node);
  final cosI = cosDeg(i);
  final sinI = sinDeg(i);

  return Vector3(
    (cosW * cosO - sinW * sinO * cosI) * xOrbital +
        (-sinW * cosO - cosW * sinO * cosI) * yOrbital,
    (cosW * sinO + sinW * cosO * cosI) * xOrbital +
        (-sinW * sinO + cosW * cosO * cosI) * yOrbital,
    (sinW * sinI) * xOrbital + (cosW * sinI) * yOrbital,
  );
}

/// Apparent position and appearance of a planet as seen from Earth.
class PlanetPosition {
  const PlanetPosition({
    required this.planet,
    required this.equatorial,
    required this.distanceAu,
    required this.heliocentricDistanceAu,
    required this.phaseAngleDeg,
    required this.magnitude,
    required this.angularDiameterArcsec,
  });

  final Planet planet;

  /// Referred to the equinox of date, matching the Sun and Moon routines.
  final Equatorial equatorial;

  /// Distance from Earth.
  final double distanceAu;

  /// Distance from the Sun.
  final double heliocentricDistanceAu;

  final double phaseAngleDeg;
  final double magnitude;
  final double angularDiameterArcsec;

  /// Fraction of the disc that is lit — noticeable for Venus and Mercury.
  double get illuminatedFraction => (1 + cosDeg(phaseAngleDeg)) / 2.0;
}

/// Computes the apparent position of [planet] at dynamical time [jde].
PlanetPosition computePlanet(Planet planet, double jde) {
  assert(planet != Planet.earth, 'Earth has no apparent position from Earth');

  final earth = heliocentricPosition(Planet.earth, jde);

  // Light-time correction: we see the planet where it was when the light left.
  // One pass is enough — the residual is well under an arcsecond.
  var target = heliocentricPosition(planet, jde);
  var delta = target - earth;
  final lightTimeDays = delta.length / _auPerDay;
  target = heliocentricPosition(planet, jde - lightTimeDays);
  delta = target - earth;

  final distance = delta.length;
  final heliocentricDistance = target.length;

  final longitude = normalizeDegrees(radToDeg * math.atan2(delta.y, delta.x));
  final latitude = radToDeg *
      math.atan2(delta.z, math.sqrt(delta.x * delta.x + delta.y * delta.y));

  // The elements are referred to the J2000 ecliptic, so convert with the
  // J2000 obliquity and then precess, rather than mixing frames.
  final j2000Equatorial = Ecliptic(longitude, latitude, distanceAu: distance)
      .toEquatorial(meanObliquity(j2000));
  final ofDate = precessFromJ2000(j2000Equatorial, jde);

  // Phase angle at the planet, between the Sun and the Earth.
  final cosPhase = (heliocentricDistance * heliocentricDistance +
          distance * distance -
          earth.length * earth.length) /
      (2 * heliocentricDistance * distance);
  final phaseAngle = radToDeg * math.acos(cosPhase.clamp(-1.0, 1.0));

  return PlanetPosition(
    planet: planet,
    equatorial: ofDate,
    distanceAu: distance,
    heliocentricDistanceAu: heliocentricDistance,
    phaseAngleDeg: phaseAngle,
    magnitude:
        _apparentMagnitude(planet, heliocentricDistance, distance, phaseAngle),
    angularDiameterArcsec: planet.angularDiameterAt1Au / distance,
  );
}

/// Visual magnitude, from the standard phase-angle polynomials.
///
/// Saturn's rings are ignored: they swing its brightness by up to 0.8
/// magnitudes over its orbit, but the tilt geometry needs more than these
/// elements provide, so the value is deliberately the ringless one.
double _apparentMagnitude(
  Planet planet,
  double r,
  double delta,
  double phaseAngle,
) {
  final base = planet.absoluteMagnitude + 5 * (math.log(r * delta) / math.ln10);
  final i = phaseAngle;
  return switch (planet) {
    Planet.mercury =>
      base + 0.0380 * i - 0.000273 * i * i + 0.000002 * i * i * i,
    Planet.venus =>
      base + 0.0009 * i + 0.000239 * i * i - 0.00000065 * i * i * i,
    Planet.mars => base + 0.016 * i,
    Planet.jupiter => base + 0.005 * i,
    _ => base,
  };
}

/// Computes every visible planet at once, which is what the renderer wants.
List<PlanetPosition> computeAllPlanets(double jde) =>
    Planet.visible.map((p) => computePlanet(p, jde)).toList(growable: false);
