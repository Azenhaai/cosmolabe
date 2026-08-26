import 'dart:async';

import 'package:flutter/services.dart';

import 'attitude.dart';

/// Receives device attitude from the native bridges.
///
/// Both platforms deliver a quaternion already expressed in East-North-Up, so
/// everything above this point is platform-agnostic. The one difference that
/// survives is which north they mean: iOS gives true north, Android gives
/// magnetic, and [declinationDeg] closes that gap.
class OrientationService {
  OrientationService({
    AttitudeSmoother? smoother,
    EventChannel? channel,
    MethodChannel? control,
  })  : _smoother = smoother ?? AttitudeSmoother(),
        _channel = channel ?? const EventChannel(_channelName),
        _control = control ?? const MethodChannel('$_channelName/control');

  static const String _channelName = 'cosmolabe/orientation';

  final AttitudeSmoother _smoother;
  final EventChannel _channel;
  final MethodChannel _control;

  /// Magnetic declination at the observer's location, east positive.
  ///
  /// Applied only when the platform reports magnetic north. Set it from the
  /// world magnetic model, or from the user's manual override after they
  /// calibrate on a known star.
  double declinationDeg = 0.0;

  /// Extra correction the user dialled in by sighting a star they can name.
  ///
  /// Kept apart from [declinationDeg] so that moving to a new location
  /// recomputes the model value without silently discarding the calibration,
  /// and so the settings screen can show and clear the two independently.
  double manualOffsetDeg = 0.0;

  Stream<DeviceAttitude>? _stream;

  /// True when the device has the sensors this needs at all.
  Future<bool> isAvailable() async {
    try {
      return await _control.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Desktop and test environments have no bridge registered.
      return false;
    }
  }

  /// Smoothed attitude, corrected to true north.
  Stream<DeviceAttitude> get attitude {
    return _stream ??= _channel
        .receiveBroadcastStream()
        .map(_decode)
        .where((attitude) => attitude != null)
        .cast<DeviceAttitude>();
  }

  DeviceAttitude? _decode(dynamic event) {
    if (event is! Map) return null;

    final w = (event['w'] as num?)?.toDouble();
    final x = (event['x'] as num?)?.toDouble();
    final y = (event['y'] as num?)?.toDouble();
    final z = (event['z'] as num?)?.toDouble();
    if (w == null || x == null || y == null || z == null) return null;

    final smoothed = _smoother.add(Quaternion(w, x, y, z).normalized());

    var attitude = DeviceAttitude(
      orientation: smoothed,
      headingAccuracyDeg: (event['accuracy'] as num?)?.toDouble() ?? 180.0,
      referencedToTrueNorth: event['trueNorth'] == true,
    );

    if (!attitude.referencedToTrueNorth && declinationDeg != 0) {
      attitude = attitude.withDeclination(declinationDeg);
    }
    if (manualOffsetDeg != 0) {
      attitude = attitude.withDeclination(manualOffsetDeg);
    }
    return attitude;
  }

  /// Records the correction needed to make the device agree with a star the
  /// user has identified, and returns it.
  ///
  /// This is the fix for a phone whose compass is simply wrong — a magnetic
  /// case, a nearby speaker, or a magnetometer that never calibrated. Point at
  /// a bright star, say which one it is, and the residual becomes the offset.
  double calibrateOn({
    required double observedAzimuthDeg,
    required double trueAzimuthDeg,
  }) {
    var error = trueAzimuthDeg - observedAzimuthDeg;
    // Shortest way round, so sighting something near due north cannot produce
    // a 350 degree "correction".
    error = (error + 540) % 360 - 180;
    manualOffsetDeg += error;
    manualOffsetDeg = (manualOffsetDeg + 540) % 360 - 180;
    return manualOffsetDeg;
  }

  void clearCalibration() => manualOffsetDeg = 0.0;

  void reset() => _smoother.reset();
}
