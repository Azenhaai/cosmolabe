import 'angles.dart';
import 'coordinates.dart';
import 'julian.dart';

/// Everything the sky depends on: where the observer stands, when, and the
/// handful of settings that shift computed positions.
///
/// The whole rendered sky is a pure function of this object. GPS and the system
/// clock only ever supply *initial values* for it — they are never wired
/// directly into the maths. That is what makes manual entry, the time machine
/// and offline unit tests all fall out for free.
class Observer {
  Observer({
    required this.latitudeDeg,
    required this.longitudeDeg,
    required DateTime utc,
    this.elevationMeters = 0.0,
    this.magneticDeclinationDeg,
    this.pressureMillibars = 1010.0,
    this.temperatureCelsius = 10.0,
    this.applyRefraction = true,
  })  : assert(latitudeDeg >= -90 && latitudeDeg <= 90),
        assert(longitudeDeg >= -180 && longitudeDeg <= 180),
        utc = utc.toUtc();

  /// Positive north.
  final double latitudeDeg;

  /// Positive east.
  final double longitudeDeg;

  final double elevationMeters;

  final DateTime utc;

  /// Manual compass correction. Null means "use the WMM model value", which
  /// the sensor layer supplies; a non-null value is the user overriding it,
  /// typically after calibrating on a known star.
  final double? magneticDeclinationDeg;

  final double pressureMillibars;
  final double temperatureCelsius;
  final bool applyRefraction;

  /// Julian Day in universal time.
  late final double julianDay = julianDayFromDateTime(utc);

  /// Julian Day in dynamical time, which is what the ephemerides want.
  late final double julianEphemeris = julianEphemerisDay(julianDay);

  /// Local mean sidereal time in degrees — the angle that rotates the sky.
  late final double siderealTimeDeg =
      localMeanSiderealTime(julianDay, longitudeDeg);

  /// Obliquity of the ecliptic at this moment.
  late final double obliquityDeg = meanObliquity(julianEphemeris);

  /// Years elapsed since J2000.0, for proper motion.
  late final double yearsSinceJ2000 = (julianDay - j2000) / 365.25;

  /// How far the true horizon sits below the level plane, from this elevation.
  late final double horizonDipDeg = horizonDipDegrees(elevationMeters);

  /// Projects a J2000 catalogue position into this observer's local sky.
  ///
  /// This is the one call the renderer makes per object, so it does the whole
  /// chain: precession, then the sidereal rotation, then refraction.
  Horizontal project(Equatorial j2000Position) {
    final ofDate = precessFromJ2000(j2000Position, julianEphemeris);
    final horizontal =
        equatorialToHorizontal(ofDate, siderealTimeDeg, latitudeDeg);
    if (!applyRefraction) return horizontal;
    return Horizontal(
      horizontal.azimuthDeg,
      horizontal.altitudeDeg +
          refractionDegrees(
            horizontal.altitudeDeg,
            pressureMillibars: pressureMillibars,
            temperatureCelsius: temperatureCelsius,
          ),
    );
  }

  /// Projects a position already expressed in the equinox of date, which is how
  /// the solar system routines return their results.
  Horizontal projectOfDate(Equatorial ofDate) {
    final horizontal =
        equatorialToHorizontal(ofDate, siderealTimeDeg, latitudeDeg);
    if (!applyRefraction) return horizontal;
    return Horizontal(
      horizontal.azimuthDeg,
      horizontal.altitudeDeg +
          refractionDegrees(
            horizontal.altitudeDeg,
            pressureMillibars: pressureMillibars,
            temperatureCelsius: temperatureCelsius,
          ),
    );
  }

  Observer copyWith({
    double? latitudeDeg,
    double? longitudeDeg,
    DateTime? utc,
    double? elevationMeters,
    double? magneticDeclinationDeg,
    bool clearMagneticDeclination = false,
    double? pressureMillibars,
    double? temperatureCelsius,
    bool? applyRefraction,
  }) {
    return Observer(
      latitudeDeg: latitudeDeg ?? this.latitudeDeg,
      longitudeDeg: longitudeDeg ?? this.longitudeDeg,
      utc: utc ?? this.utc,
      elevationMeters: elevationMeters ?? this.elevationMeters,
      magneticDeclinationDeg: clearMagneticDeclination
          ? null
          : (magneticDeclinationDeg ?? this.magneticDeclinationDeg),
      pressureMillibars: pressureMillibars ?? this.pressureMillibars,
      temperatureCelsius: temperatureCelsius ?? this.temperatureCelsius,
      applyRefraction: applyRefraction ?? this.applyRefraction,
    );
  }

  /// Same place and settings, different moment. The time machine runs on this.
  Observer at(DateTime moment) => copyWith(utc: moment);

  /// Human-readable position, e.g. `32°45'00.0"N 16°58'00.0"W`.
  String get formattedPosition {
    final lat = Sexagesimal.fromDegrees(latitudeDeg.abs()).format();
    final lon = Sexagesimal.fromDegrees(longitudeDeg.abs()).format();
    return '$lat${latitudeDeg >= 0 ? 'N' : 'S'} '
        '$lon${longitudeDeg >= 0 ? 'E' : 'W'}';
  }

  @override
  String toString() => 'Observer($formattedPosition @ ${utc.toIso8601String()})';
}

/// Pico do Arieiro — the darkest easily reachable sky on Madeira, and the
/// default the app opens with until a location is chosen.
const madeiraPicoDoArieiro = (
  name: 'Pico do Arieiro',
  latitudeDeg: 32.735278,
  longitudeDeg: -16.928611,
  elevationMeters: 1818.0,
);
