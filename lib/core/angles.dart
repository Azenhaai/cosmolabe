import 'dart:math' as math;

const double degToRad = math.pi / 180.0;
const double radToDeg = 180.0 / math.pi;
const double arcsecToDeg = 1.0 / 3600.0;

/// Wraps [degrees] into `[0, 360)`.
double normalizeDegrees(double degrees) {
  final r = degrees % 360.0;
  return r < 0 ? r + 360.0 : r;
}

/// Wraps [degrees] into `[-180, 180)`.
double normalizeDegreesSigned(double degrees) {
  final r = normalizeDegrees(degrees + 180.0);
  return r - 180.0;
}

/// Wraps [radians] into `[0, 2pi)`.
double normalizeRadians(double radians) {
  final r = radians % (2 * math.pi);
  return r < 0 ? r + 2 * math.pi : r;
}

/// Horner evaluation of a polynomial in [t], lowest order first.
double polynomial(double t, List<double> coefficients) {
  var result = 0.0;
  for (var i = coefficients.length - 1; i >= 0; i--) {
    result = result * t + coefficients[i];
  }
  return result;
}

double sinDeg(double degrees) => math.sin(degrees * degToRad);

double cosDeg(double degrees) => math.cos(degrees * degToRad);

double tanDeg(double degrees) => math.tan(degrees * degToRad);

/// A sexagesimal angle split into sign, whole units, minutes and seconds.
///
/// Used for both degrees/arcminutes/arcseconds and hours/minutes/seconds; the
/// caller decides which by choosing [Sexagesimal.fromDegrees] or
/// [Sexagesimal.fromHours].
class Sexagesimal {
  const Sexagesimal(this.negative, this.units, this.minutes, this.seconds);

  final bool negative;
  final int units;
  final int minutes;
  final double seconds;

  factory Sexagesimal._split(double value) {
    final negative = value < 0;
    var remainder = value.abs();
    var units = remainder.floor();
    remainder = (remainder - units) * 60.0;
    var minutes = remainder.floor();
    var seconds = (remainder - minutes) * 60.0;
    // Guard against 59.9999... rounding up into an invalid 60.
    if (seconds >= 59.9999995) {
      seconds = 0.0;
      minutes += 1;
    }
    if (minutes >= 60) {
      minutes -= 60;
      units += 1;
    }
    return Sexagesimal(negative, units, minutes, seconds);
  }

  factory Sexagesimal.fromDegrees(double degrees) => Sexagesimal._split(degrees);

  factory Sexagesimal.fromHours(double hours) => Sexagesimal._split(hours);

  /// Builds the signed decimal value back from the components.
  ///
  /// [negative] applies to the angle as a whole, so `-0 30 00` is `-0.5`.
  double get value {
    final magnitude = units + minutes / 60.0 + seconds / 3600.0;
    return negative ? -magnitude : magnitude;
  }

  /// Formats as `54°21'17.4"` (or the hour equivalent when [hours] is true).
  String format({bool hours = false, int secondsDigits = 1}) {
    final sign = negative ? '-' : '';
    final s = seconds.toStringAsFixed(secondsDigits).padLeft(
          secondsDigits > 0 ? secondsDigits + 3 : 2,
          '0',
        );
    final m = minutes.toString().padLeft(2, '0');
    if (hours) return '$sign${units}h${m}m${s}s';
    return '$sign$units°$m\'$s"';
  }
}

/// Degrees to hours (15 degrees per hour).
double degreesToHours(double degrees) => degrees / 15.0;

/// Hours to degrees.
double hoursToDegrees(double hours) => hours * 15.0;

final _hemispherePattern = RegExp(r'^([NnSsEeWw])\b|([NnSsEeWw])$');
final _numberPattern = RegExp(r'\d+(?:\.\d+)?');
final _allowedCharacters = RegExp(r"^[0-9+\-.\s°'′″°dhms:\x22]*$");

/// Parses free-form sexagesimal input into signed decimal degrees.
///
/// Accepts `54 21 17`, `54°21'17"`, `-3:25:10`, `54.354`, `12h30m` and a
/// leading or trailing hemisphere letter (`N`/`S`/`E`/`W`), which overrides any
/// sign. Returns null when the input cannot be understood, so callers can keep
/// the user's partially typed text on screen instead of clobbering it.
double? parseSexagesimal(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;

  // Pull the hemisphere off first. Doing this before tokenising avoids the
  // trap where a trailing "S" is mistaken for a seconds marker.
  bool? hemisphereIsNegative;
  final hemisphere = _hemispherePattern.firstMatch(text);
  if (hemisphere != null) {
    final letter = (hemisphere.group(1) ?? hemisphere.group(2))!.toUpperCase();
    hemisphereIsNegative = letter == 'S' || letter == 'W';
    text = text.replaceFirst(_hemispherePattern, '').trim();
    if (text.isEmpty) return null;
  }

  final negativeSign = text.startsWith('-');
  if (negativeSign || text.startsWith('+')) {
    text = text.substring(1).trim();
  }

  // Anything outside the sexagesimal vocabulary means we misread the input.
  if (!_allowedCharacters.hasMatch(text)) return null;

  final numbers = _numberPattern
      .allMatches(text)
      .map((m) => double.parse(m.group(0)!))
      .toList();
  if (numbers.isEmpty || numbers.length > 3) return null;

  final units = numbers[0];
  final minutes = numbers.length > 1 ? numbers[1] : 0.0;
  final seconds = numbers.length > 2 ? numbers[2] : 0.0;
  if (minutes >= 60.0 || seconds >= 60.0) return null;
  // A fraction is only meaningful on the last component.
  if (numbers.length > 1 && units != units.roundToDouble()) return null;
  if (numbers.length > 2 && minutes != minutes.roundToDouble()) return null;

  final magnitude = units + minutes / 60.0 + seconds / 3600.0;
  final negative = hemisphereIsNegative ?? negativeSign;
  return negative ? -magnitude : magnitude;
}

/// Shortest angular separation between two directions on the sky, in degrees.
///
/// Uses the haversine-style form rather than `acos` of the dot product, which
/// loses precision for the small separations we care about most.
double angularSeparation(
  double ra1Deg,
  double dec1Deg,
  double ra2Deg,
  double dec2Deg,
) {
  final d1 = dec1Deg * degToRad;
  final d2 = dec2Deg * degToRad;
  final dRa = (ra2Deg - ra1Deg) * degToRad;
  final dDec = d2 - d1;
  final a = math.pow(math.sin(dDec / 2), 2) +
      math.cos(d1) * math.cos(d2) * math.pow(math.sin(dRa / 2), 2);
  return 2 * math.asin(math.min(1.0, math.sqrt(a))) * radToDeg;
}
