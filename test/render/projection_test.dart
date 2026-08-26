import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmolabe/core/angles.dart';
import 'package:cosmolabe/render/sky_projection.dart';
import 'package:cosmolabe/sensors/attitude.dart';

void main() {
  const size = Size(400, 800);

  SkyProjection lookingAt(
    double azimuth,
    double altitude, {
    double fov = 60,
    ProjectionKind kind = ProjectionKind.gnomonic,
    double roll = 0,
  }) =>
      SkyProjection(
        attitude: DeviceAttitude(
          orientation: Quaternion.lookAt(azimuth, altitude, rollDeg: roll),
          headingAccuracyDeg: 1,
          referencedToTrueNorth: true,
        ),
        size: size,
        fieldOfViewDeg: fov,
        kind: kind,
      );

  group('lookAt', () {
    test('points where it is told', () {
      for (final azimuth in [0.0, 47.0, 90.0, 180.0, 271.0, 359.0]) {
        for (final altitude in [-40.0, 0.0, 25.0, 70.0]) {
          final attitude = DeviceAttitude(
            orientation: Quaternion.lookAt(azimuth, altitude),
            headingAccuracyDeg: 1,
            referencedToTrueNorth: true,
          );
          expect(attitude.pointing.azimuthDeg, closeTo(azimuth, 1e-6),
              reason: 'az $azimuth alt $altitude');
          expect(attitude.pointing.altitudeDeg, closeTo(altitude, 1e-6),
              reason: 'az $azimuth alt $altitude');
        }
      }
    });

    test('keeps the horizon level when no roll is asked for', () {
      final attitude = DeviceAttitude(
        orientation: Quaternion.lookAt(120, 30),
        headingAccuracyDeg: 1,
        referencedToTrueNorth: true,
      );
      expect(attitude.rollDeg.abs(), lessThan(1e-6));
    });

    test('survives being pointed at the zenith', () {
      final attitude = DeviceAttitude(
        orientation: Quaternion.lookAt(0, 90),
        headingAccuracyDeg: 1,
        referencedToTrueNorth: true,
      );
      expect(attitude.pointing.altitudeDeg, closeTo(90, 1e-6));
    });
  });

  group('Projection', () {
    test('the view direction lands in the centre of the screen', () {
      final projection = lookingAt(135, 20);
      final point = projection.project(135, 20);
      expect(point, isNotNull);
      expect((point! - projection.center).distance, lessThan(1e-6));
    });

    test('the field of view spans the short screen edge', () {
      final projection = lookingAt(0, 0, fov: 60);
      // Half a field of view to the right should land on the short edge.
      final edge = projection.project(30, 0);
      expect(edge, isNotNull);
      expect(edge!.dx - projection.center.dx, closeTo(size.width / 2, 0.5));
    });

    test('higher altitude draws higher on screen', () {
      final projection = lookingAt(0, 0);
      final low = projection.project(0, 5)!;
      final high = projection.project(0, 20)!;
      expect(high.dy, lessThan(low.dy));
    });

    test('east of centre draws to the right', () {
      final projection = lookingAt(0, 0);
      expect(projection.project(15, 0)!.dx, greaterThan(projection.center.dx));
      expect(projection.project(345, 0)!.dx, lessThan(projection.center.dx));
    });

    test('anything behind the camera is dropped', () {
      final projection = lookingAt(0, 0);
      expect(projection.project(180, 0), isNull);
      expect(projection.project(120, 0), isNull);
    });

    test('a narrower field of view magnifies', () {
      final wide = lookingAt(0, 0, fov: 90).project(10, 0)!;
      final narrow = lookingAt(0, 0, fov: 30).project(10, 0)!;
      final wideOffset = (wide.dx - 200).abs();
      final narrowOffset = (narrow.dx - 200).abs();
      expect(narrowOffset, greaterThan(wideOffset * 2));
    });

    test('roll rotates the field', () {
      final upright = lookingAt(0, 0).project(0, 10)!;
      final rolled = lookingAt(0, 0, roll: 90).project(0, 10)!;
      // What was directly above the centre moves onto the horizontal.
      expect((upright.dx - 200).abs(), lessThan(1));
      expect((rolled.dy - 400).abs(), lessThan(1));
    });
  });

  group('Round trip', () {
    for (final kind in ProjectionKind.values) {
      test('unproject inverts project — ${kind.displayName}', () {
        final projection = lookingAt(70, 25, kind: kind);
        for (final azimuth in [60.0, 70.0, 82.0]) {
          for (final altitude in [15.0, 25.0, 38.0]) {
            final point = projection.project(azimuth, altitude);
            expect(point, isNotNull, reason: '$azimuth/$altitude');
            final back = projection.unproject(point!);
            expect(back, isNotNull);
            expect(
              angularSeparation(azimuth, altitude, back!.azimuthDeg,
                  back.altitudeDeg),
              lessThan(1e-6),
              reason: '${kind.displayName} $azimuth/$altitude',
            );
          }
        }
      });
    }

    test('the centre of the screen unprojects to the view direction', () {
      final projection = lookingAt(212, -8);
      final back = projection.unproject(projection.center)!;
      expect(back.azimuthDeg, closeTo(212, 1e-6));
      expect(back.altitudeDeg, closeTo(-8, 1e-6));
    });
  });

  group('Wide angles', () {
    test('stereographic keeps showing sky past 90 degrees off axis', () {
      final projection =
          lookingAt(0, 0, fov: 120, kind: ProjectionKind.stereographic);
      expect(projection.project(100, 0), isNotNull);
      expect(projection.project(179, 0), isNotNull);
    });

    test('orthographic stops at the hemisphere', () {
      final projection =
          lookingAt(0, 0, fov: 120, kind: ProjectionKind.orthographic);
      expect(projection.project(80, 0), isNotNull);
      expect(projection.project(100, 0), isNull);
    });

    test('gnomonic gives up well before the horizon of the view', () {
      final projection = lookingAt(0, 0, fov: 120);
      expect(projection.project(88, 0), isNull);
    });
  });

  test('degrees per pixel matches the field of view', () {
    final projection = lookingAt(0, 0, fov: 60);
    expect(projection.degreesPerPixel, closeTo(60 / 400, 1e-9));
  });
}
