import 'package:geolocator/geolocator.dart';

/// What happened when we asked for a position.
///
/// Location is a convenience here, never a requirement: the whole app works
/// from coordinates typed by hand, so every failure path ends in "carry on
/// with what the user set" rather than in a dead end.
enum LocationOutcome {
  ok,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  failed,
}

class LocationFix {
  const LocationFix({
    required this.outcome,
    this.latitudeDeg,
    this.longitudeDeg,
    this.elevationMeters,
    this.accuracyMeters,
    this.message,
  });

  final LocationOutcome outcome;
  final double? latitudeDeg;
  final double? longitudeDeg;
  final double? elevationMeters;
  final double? accuracyMeters;
  final String? message;

  bool get hasPosition => latitudeDeg != null && longitudeDeg != null;

  /// Human-readable reason, for the one line of text the settings sheet shows.
  String get explanation => switch (outcome) {
        LocationOutcome.ok => 'Located to within '
            '${(accuracyMeters ?? 0).round()} m',
        LocationOutcome.serviceDisabled =>
          'Location services are switched off. Enter coordinates by hand, or '
              'turn them on in system settings.',
        LocationOutcome.permissionDenied =>
          'Location permission was declined. Coordinates can still be typed in.',
        LocationOutcome.permissionDeniedForever =>
          'Location permission is blocked for this app. Change it in system '
              'settings, or just type the coordinates.',
        LocationOutcome.failed => message ?? 'Could not get a fix.',
      };
}

/// Asks the platform where we are.
class LocationService {
  const LocationService();

  /// A single fix, with every failure reported rather than thrown.
  ///
  /// Ten metres of accuracy is far more than the sky needs — a kilometre of
  /// error moves a star by about a thousandth of a degree — so this asks for
  /// low accuracy, which returns faster and costs much less battery.
  Future<LocationFix> current({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationFix(outcome: LocationOutcome.serviceDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationFix(
          outcome: LocationOutcome.permissionDeniedForever,
        );
      }
      if (permission == LocationPermission.denied) {
        return const LocationFix(outcome: LocationOutcome.permissionDenied);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: timeout,
        ),
      );

      return LocationFix(
        outcome: LocationOutcome.ok,
        latitudeDeg: position.latitude,
        longitudeDeg: position.longitude,
        // Altitude is often junk indoors and only affects the horizon dip and
        // refraction, so a bad value is discarded rather than trusted.
        elevationMeters:
            position.altitude.isFinite && position.altitude.abs() < 9000
                ? position.altitude
                : null,
        accuracyMeters: position.accuracy,
      );
    } catch (error) {
      return LocationFix(
        outcome: LocationOutcome.failed,
        message: '$error',
      );
    }
  }
}
