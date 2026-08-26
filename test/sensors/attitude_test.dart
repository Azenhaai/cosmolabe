import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmolabe/core/angles.dart';
import 'package:cosmolabe/sensors/attitude.dart';

/// The reference frame is East-North-Up. The device's +Z axis points out of
/// the screen towards the user, +Y towards the top edge, +X to the right.
void main() {
  DeviceAttitude attitudeOf(Quaternion q) => DeviceAttitude(
        orientation: q,
        headingAccuracyDeg: 1.0,
        referencedToTrueNorth: true,
      );

  Quaternion aboutEast(double degrees) =>
      Quaternion.fromAxisAngle(1, 0, 0, degrees * degToRad);
  Quaternion aboutUp(double degrees) =>
      Quaternion.fromAxisAngle(0, 0, 1, degrees * degToRad);

  group('Quaternion algebra', () {
    test('the identity leaves vectors alone', () {
      final (x, y, z) = Quaternion.identity.rotate(0.3, -0.5, 0.8);
      expect(x, closeTo(0.3, 1e-12));
      expect(y, closeTo(-0.5, 1e-12));
      expect(z, closeTo(0.8, 1e-12));
    });

    test('a quarter turn about the up axis sends north to west', () {
      // Rotations follow the right-hand rule, so a positive turn about "up"
      // runs anticlockwise seen from above — the opposite sense to compass
      // bearings, which is the trap this whole file exists to pin down.
      final (east, north, up) = aboutUp(90).rotate(0, 1, 0);
      expect(east, closeTo(-1.0, 1e-9));
      expect(north, closeTo(0.0, 1e-9));
      expect(up, closeTo(0.0, 1e-9));
    });

    test('rotation preserves length', () {
      final q = Quaternion.fromAxisAngle(0.3, -0.7, 0.2, 1.1);
      final (x, y, z) = q.rotate(0.0, 0.0, -1.0);
      expect(math.sqrt(x * x + y * y + z * z), closeTo(1.0, 1e-12));
    });

    test('normalising a scaled quaternion restores the unit norm', () {
      const scaled = Quaternion(2, 4, 6, 8);
      expect(scaled.normalized().norm, closeTo(1.0, 1e-12));
    });
  });

  group('Pointing direction', () {
    test('a phone lying face up looks straight down', () {
      // Screen up means the camera on the back faces the ground.
      expect(attitudeOf(Quaternion.identity).pointing.altitudeDeg,
          closeTo(-90.0, 1e-9));
    });

    test('tipping the phone upright looks at the northern horizon', () {
      final pointing = attitudeOf(aboutEast(90)).pointing;
      expect(pointing.altitudeDeg, closeTo(0.0, 1e-9));
      expect(pointing.azimuthDeg, closeTo(0.0, 1e-6));
    });

    test('tipping it all the way back looks at the zenith', () {
      expect(attitudeOf(aboutEast(180)).pointing.altitudeDeg,
          closeTo(90.0, 1e-9));
    });

    test('halfway up is halfway up', () {
      expect(attitudeOf(aboutEast(135)).pointing.altitudeDeg,
          closeTo(45.0, 1e-9));
    });

    test('turning the body swings the azimuth', () {
      for (final bearing in [0.0, 45.0, 90.0, 180.0, 270.0, 315.0]) {
        // Stand the phone up, then turn the whole body to face the bearing.
        // Bearings run clockwise, rotations anticlockwise, hence the negation.
        final q = _multiplyForTest(aboutUp(-bearing), aboutEast(90));
        expect(
          attitudeOf(q).pointing.azimuthDeg,
          closeTo(bearing, 1e-6),
          reason: 'bearing $bearing',
        );
      }
    });

    test('the top edge points at the zenith when held upright', () {
      final up = attitudeOf(aboutEast(90)).screenUp;
      expect(up.altitudeDeg, closeTo(90.0, 1e-9));
    });
  });

  group('Roll', () {
    test('is zero when the phone is held square to the horizon', () {
      expect(attitudeOf(aboutEast(90)).rollDeg.abs(), lessThan(1e-6));
      expect(attitudeOf(aboutEast(135)).rollDeg.abs(), lessThan(1e-6));
    });

    test('tracks rotation about the viewing axis', () {
      final upright = aboutEast(90);
      for (final tilt in [15.0, -30.0, 90.0]) {
        // Spin about the device's own Z axis, the axis we look along.
        final q = _multiplyForTest(
          upright,
          Quaternion.fromAxisAngle(0, 0, 1, tilt * degToRad),
        );
        expect(
          normalizeDegreesSigned(attitudeOf(q).rollDeg),
          closeTo(-tilt, 1e-6),
          reason: 'tilt $tilt',
        );
      }
    });

    test('is held at zero when pointing at the zenith, where it is undefined', () {
      expect(attitudeOf(aboutEast(180)).rollDeg, 0.0);
    });
  });

  group('Declination correction', () {
    test('rotates the heading without touching the altitude', () {
      final magnetic = attitudeOf(aboutEast(120));
      final corrected = magnetic.withDeclination(-5.0);
      expect(
        corrected.pointing.altitudeDeg,
        closeTo(magnetic.pointing.altitudeDeg, 1e-9),
      );
      expect(
        normalizeDegreesSigned(
          corrected.pointing.azimuthDeg - magnetic.pointing.azimuthDeg,
        ),
        closeTo(-5.0, 1e-6),
      );
    });

    test('marks the result as referenced to true north', () {
      const magnetic = DeviceAttitude(
        orientation: Quaternion.identity,
        headingAccuracyDeg: 8.0,
        referencedToTrueNorth: false,
      );
      expect(magnetic.withDeclination(-5.0).referencedToTrueNorth, isTrue);
    });

    test('zero declination is a no-op', () {
      final attitude = attitudeOf(aboutEast(90));
      expect(attitude.withDeclination(0.0), same(attitude));
    });
  });

  group('Calibration warning', () {
    test('a confident heading needs no calibration', () {
      expect(attitudeOf(Quaternion.identity).needsCalibration, isFalse);
    });

    test('an uncertain heading asks for one', () {
      expect(DeviceAttitude.unknown.needsCalibration, isTrue);
    });
  });

  group('Smoothing', () {
    test('the first sample is taken as-is', () {
      final smoother = AttitudeSmoother();
      final sample = aboutEast(90);
      final result = smoother.add(sample);
      expect(result.dot(sample).abs(), closeTo(1.0, 1e-9));
    });

    test('small jitter is damped', () {
      final smoother = AttitudeSmoother();
      smoother.add(aboutEast(90));
      // A tenth of a degree of tremor, well under the movement threshold.
      final jittered = smoother.add(aboutEast(90.1));
      final movedBy = 2 *
          math.acos(jittered.dot(aboutEast(90)).abs().clamp(0.0, 1.0)) *
          radToDeg;
      expect(movedBy, lessThan(0.05));
    });

    test('a deliberate sweep passes through quickly', () {
      final smoother = AttitudeSmoother();
      smoother.add(aboutEast(90));
      final swept = smoother.add(aboutEast(120));
      final movedBy = 2 *
          math.acos(swept.dot(aboutEast(90)).abs().clamp(0.0, 1.0)) *
          radToDeg;
      expect(movedBy, greaterThan(12.0));
    });

    test('converges on a steady reading', () {
      final smoother = AttitudeSmoother();
      smoother.add(aboutEast(90));
      final target = aboutEast(120);
      for (var i = 0; i < 60; i++) {
        smoother.add(target);
      }
      expect(smoother.current.dot(target).abs(), closeTo(1.0, 1e-6));
    });

    test('never flips the long way round the sphere', () {
      final smoother = AttitudeSmoother();
      final a = aboutUp(179);
      smoother.add(a);
      // The same rotation expressed with the opposite sign.
      final result = smoother.add(-a);
      expect(result.dot(a).abs(), closeTo(1.0, 1e-6));
    });

    test('reset clears the fix', () {
      final smoother = AttitudeSmoother();
      smoother.add(aboutEast(90));
      expect(smoother.hasFix, isTrue);
      smoother.reset();
      expect(smoother.hasFix, isFalse);
    });
  });
}

/// Hamilton product, duplicated here so the test does not depend on a private
/// helper in the implementation.
Quaternion _multiplyForTest(Quaternion a, Quaternion b) => Quaternion(
      a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
      a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
      a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
      a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
    );
