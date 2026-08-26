import 'dart:math' as math;

import 'angles.dart';
import 'wmm_coefficients.dart';

/// The Earth's magnetic field at a place and time, from the World Magnetic
/// Model.
///
/// The app needs exactly one number out of this — the declination, the angle
/// between magnetic and true north — but that number is why a compass points
/// five degrees wrong on Madeira, and getting it wrong rotates the entire sky.
class MagneticField {
  const MagneticField({
    required this.declinationDeg,
    required this.inclinationDeg,
    required this.horizontalNanoTesla,
    required this.northNanoTesla,
    required this.eastNanoTesla,
    required this.downNanoTesla,
    required this.outOfDate,
  });

  /// East positive. Add it to a magnetic bearing to get a true bearing.
  final double declinationDeg;

  /// Dip below horizontal, positive downwards. Near the poles the horizontal
  /// component vanishes and the compass becomes useless; this is how the app
  /// knows to say so.
  final double inclinationDeg;

  final double horizontalNanoTesla;
  final double northNanoTesla;
  final double eastNanoTesla;
  final double downNanoTesla;

  /// True when the date falls outside the model's five-year validity window.
  final bool outOfDate;

  double get totalNanoTesla => math.sqrt(
        horizontalNanoTesla * horizontalNanoTesla +
            downNanoTesla * downNanoTesla,
      );

  /// The compass is unreliable where the field is nearly vertical — inside the
  /// blackout zones the model itself declares.
  bool get compassUnreliable => horizontalNanoTesla < 2000;

  @override
  String toString() =>
      'MagneticField(declination: ${declinationDeg.toStringAsFixed(2)}°)';
}

/// WGS84 semi-major axis, kilometres.
const double _wgs84A = 6378.137;

/// WGS84 flattening.
const double _wgs84F = 1 / 298.257223563;

/// Geomagnetic reference radius, kilometres.
const double _geomagneticRadius = 6371.2;

/// Evaluates the World Magnetic Model.
///
/// [latitudeDeg] and [longitudeDeg] are geodetic, north and east positive.
/// [heightMeters] is above the WGS84 ellipsoid — close enough to height above
/// sea level for any purpose here. [decimalYear] is the time.
MagneticField magneticFieldAt({
  required double latitudeDeg,
  required double longitudeDeg,
  double heightMeters = 0,
  required double decimalYear,
}) {
  final dt = decimalYear - wmmEpoch;

  // Geodetic to geocentric spherical. The Earth is an ellipsoid, so the
  // vertical at a point does not pass through the centre, and skipping this
  // costs up to a fifth of a degree of declination at mid latitudes.
  final phi = latitudeDeg * degToRad;
  final lambda = longitudeDeg * degToRad;
  final heightKm = heightMeters / 1000.0;

  final eSquared = _wgs84F * (2 - _wgs84F);
  final sinPhi = math.sin(phi);
  final cosPhi = math.cos(phi);
  final rc = _wgs84A / math.sqrt(1 - eSquared * sinPhi * sinPhi);
  final p = (rc + heightKm) * cosPhi;
  final z = (rc * (1 - eSquared) + heightKm) * sinPhi;
  final r = math.sqrt(p * p + z * z);
  final phiPrime = math.asin(z / r);

  // Colatitude, the natural variable for the Legendre functions.
  final u = math.sin(phiPrime); // cos(colatitude)
  final v = math.cos(phiPrime); // sin(colatitude)

  const n = wmmMaxDegree;
  // Schmidt semi-normalised associated Legendre functions and their
  // derivatives with respect to colatitude.
  final legendre = List.generate(n + 1, (_) => List<double>.filled(n + 1, 0));
  final derivative =
      List.generate(n + 1, (_) => List<double>.filled(n + 1, 0));

  legendre[0][0] = 1;
  derivative[0][0] = 0;

  for (var degree = 1; degree <= n; degree++) {
    for (var order = 0; order <= degree; order++) {
      if (order == degree) {
        // The sqrt(2) in the Schmidt factor only appears for m > 0, which is
        // why the first diagonal step has no scaling of its own.
        final scale =
            degree == 1 ? 1.0 : math.sqrt((2 * degree - 1) / (2.0 * degree));
        legendre[degree][order] = scale * v * legendre[degree - 1][order - 1];
        derivative[degree][order] = scale *
            (u * legendre[degree - 1][order - 1] +
                v * derivative[degree - 1][order - 1]);
      } else {
        final a = math.sqrt(
          (degree * degree - order * order).toDouble(),
        );
        final b = degree >= 2
            ? math.sqrt(
                (((degree - 1) * (degree - 1)) - order * order).toDouble(),
              )
            : 0.0;
        final previous = legendre[degree - 1][order];
        final previousDerivative = derivative[degree - 1][order];
        final twoBack = degree >= 2 ? legendre[degree - 2][order] : 0.0;
        final twoBackDerivative =
            degree >= 2 ? derivative[degree - 2][order] : 0.0;

        legendre[degree][order] =
            ((2 * degree - 1) * u * previous - b * twoBack) / a;
        derivative[degree][order] =
            ((2 * degree - 1) * (u * previousDerivative - v * previous) -
                    b * twoBackDerivative) /
                a;
      }
    }
  }

  // Time-adjusted Gauss coefficients, indexed for the summation below.
  final g = List.generate(n + 1, (_) => List<double>.filled(n + 1, 0));
  final h = List.generate(n + 1, (_) => List<double>.filled(n + 1, 0));
  for (final row in wmmCoefficients) {
    final degree = row[0].toInt();
    final order = row[1].toInt();
    g[degree][order] = row[2] + dt * row[4];
    h[degree][order] = row[3] + dt * row[5];
  }

  final ratio = _geomagneticRadius / r;
  var north = 0.0;
  var east = 0.0;
  var down = 0.0;

  for (var degree = 1; degree <= n; degree++) {
    final power = math.pow(ratio, degree + 2).toDouble();
    for (var order = 0; order <= degree; order++) {
      final cosML = math.cos(order * lambda);
      final sinML = math.sin(order * lambda);
      final gh = g[degree][order] * cosML + h[degree][order] * sinML;
      final hg = g[degree][order] * sinML - h[degree][order] * cosML;

      north += power * gh * derivative[degree][order];
      down -= power * (degree + 1) * gh * legendre[degree][order];
      if (order > 0) {
        east += power * order * hg * legendre[degree][order];
      }
    }
  }

  // The east component divides by cos(latitude), which blows up at the poles.
  // Nothing useful is happening there for a compass anyway, so clamp rather
  // than emit an infinity.
  east = v.abs() < 1e-10 ? 0.0 : east / v;

  // Rotate from the geocentric frame back to the geodetic one.
  final delta = phiPrime - phi;
  final cosDelta = math.cos(delta);
  final sinDelta = math.sin(delta);
  final x = north * cosDelta - down * sinDelta;
  final zDown = north * sinDelta + down * cosDelta;
  final y = east;

  final horizontal = math.sqrt(x * x + y * y);

  return MagneticField(
    declinationDeg: math.atan2(y, x) * radToDeg,
    inclinationDeg: math.atan2(zDown, horizontal) * radToDeg,
    horizontalNanoTesla: horizontal,
    northNanoTesla: x,
    eastNanoTesla: y,
    downNanoTesla: zDown,
    outOfDate: decimalYear < wmmEpoch || decimalYear > wmmValidUntil,
  );
}

/// Decimal year for a moment, which is what the model wants.
double decimalYearOf(DateTime moment) {
  final utc = moment.toUtc();
  final startOfYear = DateTime.utc(utc.year);
  final startOfNext = DateTime.utc(utc.year + 1);
  final elapsed = utc.difference(startOfYear).inSeconds;
  final total = startOfNext.difference(startOfYear).inSeconds;
  return utc.year + elapsed / total;
}

/// Magnetic declination in degrees, east positive — the one number the sky
/// view actually needs.
double magneticDeclination({
  required double latitudeDeg,
  required double longitudeDeg,
  double heightMeters = 0,
  required DateTime moment,
}) =>
    magneticFieldAt(
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
      heightMeters: heightMeters,
      decimalYear: decimalYearOf(moment),
    ).declinationDeg;
