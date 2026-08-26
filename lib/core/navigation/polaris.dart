import 'dart:math' as math;

import '../angles.dart';
import '../catalog/star_catalog.dart';
import '../coordinates.dart';
import '../observer.dart';

/// Hipparcos number of Polaris, alpha Ursae Minoris.
const int hipPolaris = 11767;

/// Kochab, beta Ursae Minoris — the brighter of the two Guards.
const int hipKochab = 72607;

/// Pherkad, gamma Ursae Minoris — the other Guard.
const int hipPherkad = 75097;

/// Where the Guards stand, in the eight-fold division the regimentos used.
///
/// The 15th-century rule described the Guards' position as parts of a figure
/// standing at the pole — head, shoulders, arms, feet — because a pilot could
/// name a position at a glance in the dark far faster than he could measure
/// one. The clock face is the same idea in a form a modern reader already
/// knows, so the app shows both.
class GuardsPosition {
  const GuardsPosition({
    required this.positionAngleDeg,
    required this.hourAngleDeg,
  });

  /// Angle of the Guards about the pole, measured clockwise from straight up.
  final double positionAngleDeg;

  /// Local hour angle of Kochab.
  final double hourAngleDeg;

  /// Position on a twelve-hour clock face, 12 meaning directly above the pole.
  double get clockPosition {
    final hours = positionAngleDeg / 30.0;
    return hours == 0 ? 12.0 : hours;
  }

  /// The clock reading a person would say out loud.
  String get clockLabel {
    final rounded = (positionAngleDeg / 30.0).round() % 12;
    return '${rounded == 0 ? 12 : rounded} o\'clock';
  }

  /// The nearest of the eight named stations of the figure.
  ///
  /// These are descriptive rather than a transcription of any one regimento:
  /// the surviving rules differ between manuscripts, and inventing a specific
  /// wording for a specific text would be a forgery rather than a translation.
  String get figureStation {
    const stations = [
      'head',
      'left shoulder',
      'left arm',
      'left foot',
      'feet',
      'right foot',
      'right arm',
      'right shoulder',
    ];
    final index = ((positionAngleDeg / 45.0).round()) % 8;
    return stations[index];
  }
}

/// The result of taking a sight on Polaris and working it into a latitude.
class PolarisSight {
  const PolarisSight({
    required this.observedAltitudeDeg,
    required this.polarDistanceDeg,
    required this.hourAngleDeg,
    required this.correctionDeg,
    required this.latitudeDeg,
    required this.guards,
    required this.polarisAltitudeDeg,
  });

  /// The altitude the observer measured, or the app measured for them.
  final double observedAltitudeDeg;

  /// How far Polaris currently lies from the true pole. Two thirds of a
  /// degree today; three and a half degrees when the rule was written.
  final double polarDistanceDeg;

  /// Local hour angle of Polaris, which decides the sign of the correction.
  final double hourAngleDeg;

  /// What has to be added to the observed altitude.
  final double correctionDeg;

  /// The latitude the sight yields.
  final double latitudeDeg;

  final GuardsPosition guards;

  /// Where Polaris actually is, for comparison with what was measured.
  final double polarisAltitudeDeg;

  /// How far the derived latitude is from the truth, in degrees.
  double errorAgainst(double trueLatitudeDeg) =>
      latitudeDeg - trueLatitudeDeg;

  /// The same error as distance on the ground. One minute of latitude is one
  /// nautical mile, which is the whole reason the unit exists.
  double errorNauticalMiles(double trueLatitudeDeg) =>
      errorAgainst(trueLatitudeDeg) * 60.0;
}

/// Position of a star at the observer's date, from its J2000 catalogue entry.
Equatorial _ofDate(
  StarCatalog catalog,
  int hip,
  Observer observer,
) {
  final index = catalog.hipToIndex[hip];
  if (index == null) {
    throw ArgumentError('HIP $hip is not in the catalogue');
  }
  final moved = applyProperMotion(
    catalog.positionAt(index),
    catalog.pmRaMas[index].toDouble(),
    catalog.pmDecMas[index].toDouble(),
    observer.yearsSinceJ2000,
  );
  return precessFromJ2000(moved, observer.julianEphemeris);
}

/// Works a measured altitude of Polaris into a latitude.
///
/// The altitude of the celestial pole *is* the latitude — that is the whole
/// idea. Polaris only stands in for the pole, and the correction is the price
/// of it not being exactly there.
PolarisSight reducePolarisSight({
  required Observer observer,
  required StarCatalog catalog,
  required double observedAltitudeDeg,
}) {
  final polaris = _ofDate(catalog, hipPolaris, observer);
  final kochab = _ofDate(catalog, hipKochab, observer);

  final polarDistance = 90.0 - polaris.decDeg;
  final hourAngle = normalizeDegrees(observer.siderealTimeDeg - polaris.raDeg);
  final kochabHourAngle =
      normalizeDegrees(observer.siderealTimeDeg - kochab.raDeg);

  // Hour angle grows westward, and west is to the left when facing north, so
  // the position angle about the pole runs the other way round the dial.
  final guardsAngle = normalizeDegrees(360.0 - kochabHourAngle);

  // The classic reduction. The first term is the whole of it to a couple of
  // arcminutes; the second is the curvature of Polaris's little circle, worth
  // about a third of an arcminute and therefore worth keeping in a method
  // whose entire claim is one-minute accuracy.
  final p = polarDistance * degToRad;
  final firstOrder = -polarDistance * cosDeg(hourAngle);
  final secondOrder = 0.5 *
      p *
      p *
      math.pow(sinDeg(hourAngle), 2) *
      tanDeg(observedAltitudeDeg) *
      radToDeg;
  final correction = firstOrder + secondOrder;

  return PolarisSight(
    observedAltitudeDeg: observedAltitudeDeg,
    polarDistanceDeg: polarDistance,
    hourAngleDeg: hourAngle,
    correctionDeg: correction,
    latitudeDeg: observedAltitudeDeg + correction,
    // Already precessed and carried by proper motion, so it goes through the
    // of-date path rather than being precessed a second time.
    polarisAltitudeDeg: observer.projectOfDate(polaris).altitudeDeg,
    guards: GuardsPosition(
      positionAngleDeg: guardsAngle,
      hourAngleDeg: kochabHourAngle,
    ),
  );
}

/// How far Polaris lay from the pole at a given moment.
///
/// This is the number that makes the lesson worth teaching. Today it is about
/// two thirds of a degree and the correction is a detail; in 1500 it was three
/// and a half degrees, seven full Moon widths, and a pilot who ignored it put
/// himself two hundred miles out.
double polarisPolarDistanceAt(DateTime moment, StarCatalog catalog) {
  final observer = Observer(
    latitudeDeg: 0,
    longitudeDeg: 0,
    utc: moment,
  );
  return 90.0 - _ofDate(catalog, hipPolaris, observer).decDeg;
}

/// Altitude of the true celestial pole, which is the latitude by definition.
///
/// Used to grade the exercise: the app knows the answer before the user takes
/// the sight, which is what lets it say how far off they were and why.
double truePoleAltitude(Observer observer) => observer.latitudeDeg;
