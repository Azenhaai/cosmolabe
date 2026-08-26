import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import '../core/angles.dart';
import '../core/coordinates.dart';
import '../sensors/attitude.dart';

/// How the sky is flattened onto the screen.
enum ProjectionKind {
  /// Pinhole camera. Straight lines stay straight and the sky matches what a
  /// camera at the same field of view would see, which is what makes the
  /// phone work as a window. Stretches badly past about 100 degrees.
  gnomonic('Gnomonic'),

  /// Conformal: shapes stay true even at very wide angles, so constellations
  /// keep their form near the edge. Straight lines bend.
  stereographic('Stereographic'),

  /// What the sky would look like drawn on a globe seen from outside. Never
  /// shows more than a hemisphere, so it cannot blow up at the edges.
  orthographic('Orthographic');

  const ProjectionKind(this.displayName);

  final String displayName;
}

/// Maps directions in the sky onto screen pixels for one frame.
///
/// Built fresh each frame from the device attitude and thrown away, so it
/// holds no state worth mutating. Everything is precomputed in the
/// constructor because [project] runs once per visible star.
class SkyProjection {
  SkyProjection({
    required this.attitude,
    required this.size,
    required this.fieldOfViewDeg,
    this.kind = ProjectionKind.gnomonic,
  })  : _center = Offset(size.width / 2, size.height / 2),
        _forward = attitude.orientation.rotate(0, 0, -1),
        _right = attitude.orientation.rotate(1, 0, 0),
        _up = attitude.orientation.rotate(0, 1, 0),
        // The field of view is quoted across the shorter screen edge, so
        // rotating the phone does not change how much sky is on show.
        _focal = math.min(size.width, size.height) /
            2 /
            math.tan(fieldOfViewDeg * degToRad / 2);

  final DeviceAttitude attitude;
  final Size size;

  /// Angular width of the shorter screen edge.
  final double fieldOfViewDeg;

  final ProjectionKind kind;

  final Offset _center;
  final (double, double, double) _forward;
  final (double, double, double) _right;
  final (double, double, double) _up;
  final double _focal;

  Offset get center => _center;

  /// Radius in pixels beyond which nothing can be on screen, used to reject
  /// stars before the expensive part of drawing them.
  double get cullRadius =>
      math.sqrt(size.width * size.width + size.height * size.height) / 2 + 32;

  /// Unit vector in East-North-Up for a direction in the sky.
  static (double, double, double) directionOf(double azimuthDeg, double altitudeDeg) {
    final cosAlt = cosDeg(altitudeDeg);
    return (
      cosAlt * sinDeg(azimuthDeg),
      cosAlt * cosDeg(azimuthDeg),
      sinDeg(altitudeDeg),
    );
  }

  /// Screen position for a direction, or null when it falls behind the camera
  /// or outside the projection's valid range.
  Offset? project(double azimuthDeg, double altitudeDeg) {
    final (e, n, u) = directionOf(azimuthDeg, altitudeDeg);
    return projectVector(e, n, u);
  }

  /// Same as [project] for a caller that already has the unit vector.
  Offset? projectVector(double e, double n, double u) {
    // Camera-space coordinates: x to the right, y up, z towards the view.
    final x = e * _right.$1 + n * _right.$2 + u * _right.$3;
    final y = e * _up.$1 + n * _up.$2 + u * _up.$3;
    final z = e * _forward.$1 + n * _forward.$2 + u * _forward.$3;

    final double scale;
    switch (kind) {
      case ProjectionKind.gnomonic:
        // Everything at or behind the camera plane is unrepresentable, and
        // near it the division explodes; cut well before that.
        if (z <= 0.05) return null;
        scale = _focal / z;
      case ProjectionKind.stereographic:
        // Projected from the antipode of the view direction, so only the one
        // point directly behind the observer is lost.
        final denominator = 1 + z;
        if (denominator <= 1e-6) return null;
        scale = 2 * _focal / denominator;
      case ProjectionKind.orthographic:
        if (z <= 0) return null;
        scale = _focal;
    }

    return Offset(_center.dx + x * scale, _center.dy - y * scale);
  }

  /// Direction corresponding to a point on screen, for tap-to-identify and for
  /// the star calibration flow.
  ///
  /// Returns null when the point lies outside what the projection can invert.
  Horizontal? unproject(Offset point) {
    final dx = point.dx - _center.dx;
    final dy = _center.dy - point.dy;

    final double x, y, z;
    switch (kind) {
      case ProjectionKind.gnomonic:
        final length = math.sqrt(dx * dx + dy * dy + _focal * _focal);
        x = dx / length;
        y = dy / length;
        z = _focal / length;
      case ProjectionKind.stereographic:
        final r2 = (dx * dx + dy * dy) / (4 * _focal * _focal);
        final denominator = 1 + r2;
        x = dx / (_focal * denominator);
        y = dy / (_focal * denominator);
        z = (1 - r2) / denominator;
      case ProjectionKind.orthographic:
        x = dx / _focal;
        y = dy / _focal;
        final remainder = 1 - x * x - y * y;
        if (remainder < 0) return null;
        z = math.sqrt(remainder);
    }

    final e = x * _right.$1 + y * _up.$1 + z * _forward.$1;
    final n = x * _right.$2 + y * _up.$2 + z * _forward.$2;
    final u = x * _right.$3 + y * _up.$3 + z * _forward.$3;

    final length = math.sqrt(e * e + n * n + u * u);
    if (length < 1e-9) return null;

    return Horizontal(
      normalizeDegrees(math.atan2(e / length, n / length) * radToDeg),
      math.asin((u / length).clamp(-1.0, 1.0)) * radToDeg,
    );
  }

  /// Angle subtended by one screen pixel at the centre of the view, in
  /// degrees. The renderer uses it to decide when labels would collide and
  /// when a disc is large enough to draw as a disc rather than a point.
  double get degreesPerPixel => fieldOfViewDeg / math.min(size.width, size.height);
}
