import 'dart:math' as math;

import '../core/angles.dart';
import '../core/coordinates.dart';

/// A unit quaternion describing the rotation from the device's own axes to the
/// local East-North-Up frame.
///
/// Both platforms normalise into ENU before handing the value over, so nothing
/// above this layer has to know that iOS reports north-west-up and Android
/// reports east-north-up.
class Quaternion {
  const Quaternion(this.w, this.x, this.y, this.z);

  static const identity = Quaternion(1, 0, 0, 0);

  final double w;
  final double x;
  final double y;
  final double z;

  factory Quaternion.fromAxisAngle(double ax, double ay, double az, double radians) {
    final half = radians / 2;
    final s = math.sin(half);
    final length = math.sqrt(ax * ax + ay * ay + az * az);
    if (length == 0) return identity;
    return Quaternion(
      math.cos(half),
      ax / length * s,
      ay / length * s,
      az / length * s,
    );
  }

  /// Builds the attitude of a device pointing at a given patch of sky.
  ///
  /// This is what manual mode runs on — dragging a finger sets an azimuth and
  /// altitude, and the rest of the renderer cannot tell the difference between
  /// that and a real gyroscope reading.
  factory Quaternion.lookAt(
    double azimuthDeg,
    double altitudeDeg, {
    double rollDeg = 0,
  }) {
    // View direction in East-North-Up.
    final cosAlt = math.cos(altitudeDeg * degToRad);
    final fx = cosAlt * math.sin(azimuthDeg * degToRad);
    final fy = cosAlt * math.cos(azimuthDeg * degToRad);
    final fz = math.sin(altitudeDeg * degToRad);

    // Screen right is the view direction crossed with the world zenith. Very
    // close to straight up or down that degenerates, so fall back to a fixed
    // reference and let the roll term decide the orientation.
    var rx = fy * 1.0 - fz * 0.0;
    var ry = fz * 0.0 - fx * 1.0;
    var rz = 0.0;
    var length = math.sqrt(rx * rx + ry * ry + rz * rz);
    if (length < 1e-6) {
      rx = 1.0;
      ry = 0.0;
      rz = 0.0;
      length = 1.0;
    }
    rx /= length;
    ry /= length;
    rz /= length;

    // Screen up completes the right-handed set.
    final ux = ry * fz - rz * fy;
    final uy = rz * fx - rx * fz;
    final uz = rx * fy - ry * fx;

    // Columns of the rotation matrix: device X maps to right, Y to up, and Z
    // to the reverse of the view direction.
    final base = _fromBasis(rx, ry, rz, ux, uy, uz, -fx, -fy, -fz);
    if (rollDeg == 0) return base;
    return _multiply(
      base,
      Quaternion.fromAxisAngle(0, 0, 1, rollDeg * degToRad),
    );
  }

  /// Quaternion from three orthonormal basis vectors, given as the columns of
  /// the rotation matrix. Uses the branch with the largest divisor, which is
  /// the standard way to keep the conversion numerically stable.
  static Quaternion _fromBasis(
    double m00, double m10, double m20,
    double m01, double m11, double m21,
    double m02, double m12, double m22,
  ) {
    final trace = m00 + m11 + m22;
    if (trace > 0) {
      final s = math.sqrt(trace + 1.0) * 2;
      return Quaternion(
        0.25 * s,
        (m21 - m12) / s,
        (m02 - m20) / s,
        (m10 - m01) / s,
      ).normalized();
    }
    if (m00 > m11 && m00 > m22) {
      final s = math.sqrt(1.0 + m00 - m11 - m22) * 2;
      return Quaternion(
        (m21 - m12) / s,
        0.25 * s,
        (m01 + m10) / s,
        (m02 + m20) / s,
      ).normalized();
    }
    if (m11 > m22) {
      final s = math.sqrt(1.0 + m11 - m00 - m22) * 2;
      return Quaternion(
        (m02 - m20) / s,
        (m01 + m10) / s,
        0.25 * s,
        (m12 + m21) / s,
      ).normalized();
    }
    final s = math.sqrt(1.0 + m22 - m00 - m11) * 2;
    return Quaternion(
      (m10 - m01) / s,
      (m02 + m20) / s,
      (m12 + m21) / s,
      0.25 * s,
    ).normalized();
  }

  double get norm => math.sqrt(w * w + x * x + y * y + z * z);

  Quaternion normalized() {
    final n = norm;
    if (n == 0 || (n - 1).abs() < 1e-12) return this;
    return Quaternion(w / n, x / n, y / n, z / n);
  }

  Quaternion operator -() => Quaternion(-w, -x, -y, -z);

  double dot(Quaternion other) =>
      w * other.w + x * other.x + y * other.y + z * other.z;

  /// Rotates a vector from device axes into the reference frame.
  (double, double, double) rotate(double vx, double vy, double vz) {
    // v + 2w(q x v) + 2(q x (q x v)), cheaper than building a matrix for the
    // two or three vectors we actually need each frame.
    final cx = y * vz - z * vy;
    final cy = z * vx - x * vz;
    final cz = x * vy - y * vx;

    final ccx = y * cz - z * cy;
    final ccy = z * cx - x * cz;
    final ccz = x * cy - y * cx;

    return (
      vx + 2 * (w * cx + ccx),
      vy + 2 * (w * cy + ccy),
      vz + 2 * (w * cz + ccz),
    );
  }

  /// Spherical interpolation, used to damp sensor jitter without introducing
  /// the lag a plain low-pass filter on angles would.
  Quaternion slerp(Quaternion target, double t) {
    var other = target;
    var cosine = dot(other);
    // Quaternions double-cover rotations; flip so we take the short way round.
    if (cosine < 0) {
      other = -other;
      cosine = -cosine;
    }
    if (cosine > 0.9995) {
      // Nearly parallel — linear interpolation is both accurate and stable.
      return Quaternion(
        w + (other.w - w) * t,
        x + (other.x - x) * t,
        y + (other.y - y) * t,
        z + (other.z - z) * t,
      ).normalized();
    }
    final theta = math.acos(cosine.clamp(-1.0, 1.0));
    final sinTheta = math.sin(theta);
    final a = math.sin((1 - t) * theta) / sinTheta;
    final b = math.sin(t * theta) / sinTheta;
    return Quaternion(
      w * a + other.w * b,
      x * a + other.x * b,
      y * a + other.y * b,
      z * a + other.z * b,
    ).normalized();
  }

  @override
  String toString() =>
      'Quaternion(${w.toStringAsFixed(4)}, ${x.toStringAsFixed(4)}, '
      '${y.toStringAsFixed(4)}, ${z.toStringAsFixed(4)})';
}

/// Where the device is pointing, and how much to trust it.
class DeviceAttitude {
  const DeviceAttitude({
    required this.orientation,
    required this.headingAccuracyDeg,
    required this.referencedToTrueNorth,
  });

  static const unknown = DeviceAttitude(
    orientation: Quaternion.identity,
    headingAccuracyDeg: 180.0,
    referencedToTrueNorth: false,
  );

  final Quaternion orientation;

  /// Platform's own estimate of compass error. Anything past about 15 degrees
  /// means the magnetometer needs calibrating and the UI should say so.
  final double headingAccuracyDeg;

  /// False when only magnetic north was available, so the caller still has to
  /// apply the declination itself.
  final bool referencedToTrueNorth;

  bool get needsCalibration => headingAccuracyDeg > 15.0;

  /// Direction the back of the device points — the sky the camera would see.
  ///
  /// The device's own +Z axis comes out of the screen towards the user, so the
  /// viewing direction is -Z.
  Horizontal get pointing {
    final (east, north, up) = orientation.rotate(0, 0, -1);
    return Horizontal(
      normalizeDegrees(math.atan2(east, north) * radToDeg),
      math.asin(up.clamp(-1.0, 1.0)) * radToDeg,
    );
  }

  /// Direction the top edge of the device points, in the same frame. The
  /// renderer needs it to know which way is "up" on screen.
  Horizontal get screenUp {
    final (east, north, up) = orientation.rotate(0, 1, 0);
    return Horizontal(
      normalizeDegrees(math.atan2(east, north) * radToDeg),
      math.asin(up.clamp(-1.0, 1.0)) * radToDeg,
    );
  }

  /// Rotation of the horizon within the frame, in degrees.
  ///
  /// Zero means the horizon runs level across the screen. Positive means the
  /// device is tilted clockwise from the user's point of view, so the horizon
  /// climbs towards the right.
  ///
  /// The renderer does not need this — it builds its basis from the attitude
  /// directly. It exists for the horizon indicator and the "hold the phone
  /// level" prompt in the sextant exercises, where a number is what the user
  /// is actually being asked to control.
  double get rollDeg {
    // Project the device's up axis onto the plane perpendicular to the view
    // direction, then measure it against the true zenith direction.
    final (vx, vy, vz) = orientation.rotate(0, 0, -1);
    final (ux, uy, uz) = orientation.rotate(0, 1, 0);
    final (rx, ry, rz) = orientation.rotate(1, 0, 0);

    // Component of world "up" (0,0,1) perpendicular to the view axis.
    final zenithDotView = vz;
    final px = -zenithDotView * vx;
    final py = -zenithDotView * vy;
    final pz = 1 - zenithDotView * vz;

    final length = math.sqrt(px * px + py * py + pz * pz);
    // Pointing at the zenith or nadir leaves roll undefined; hold it at zero
    // rather than letting the star field spin wildly overhead.
    if (length < 1e-6) return 0.0;

    final alongUp = (px * ux + py * uy + pz * uz) / length;
    final alongRight = (px * rx + py * ry + pz * rz) / length;
    // Negated so that a clockwise tilt of the device reads positive.
    return -math.atan2(alongRight, alongUp) * radToDeg;
  }

  /// Applies a magnetic declination correction, rotating the whole attitude
  /// about the local vertical.
  ///
  /// [declinationDeg] follows the usual convention of east positive, so
  /// Madeira's present-day 5° west is passed as -5 and shifts every bearing
  /// five degrees anticlockwise. Needed on any platform that only offers
  /// magnetic north, and for the manual override after the user calibrates on
  /// a known star.
  DeviceAttitude withDeclination(double declinationDeg) {
    if (declinationDeg == 0) return this;
    // Azimuth runs clockwise from north while rotations about the up axis run
    // anticlockwise, so the correction goes in negated.
    final correction = Quaternion.fromAxisAngle(
      0, 0, 1, -declinationDeg * degToRad,
    );
    return DeviceAttitude(
      orientation: _multiply(correction, orientation).normalized(),
      headingAccuracyDeg: headingAccuracyDeg,
      referencedToTrueNorth: true,
    );
  }
}

Quaternion _multiply(Quaternion a, Quaternion b) => Quaternion(
      a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
      a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
      a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
      a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
    );

/// Damps sensor noise while staying responsive to real movement.
///
/// A fixed smoothing factor forces a choice between a jittery sky and a laggy
/// one. This adapts: large, deliberate sweeps pass through almost untouched,
/// while the small tremor of a hand held still gets averaged away.
class AttitudeSmoother {
  AttitudeSmoother({
    this.restingFactor = 0.08,
    this.movingFactor = 0.55,
    this.movementThresholdDeg = 3.0,
  });

  /// Blend applied when the device is essentially still.
  final double restingFactor;

  /// Blend applied during a deliberate sweep.
  final double movingFactor;

  /// Angular change per update above which motion counts as deliberate.
  final double movementThresholdDeg;

  Quaternion? _current;

  Quaternion get current => _current ?? Quaternion.identity;

  bool get hasFix => _current != null;

  Quaternion add(Quaternion sample) {
    final previous = _current;
    if (previous == null) {
      _current = sample.normalized();
      return _current!;
    }

    // Angle between the two orientations, via the quaternion dot product.
    final cosine = previous.dot(sample).abs().clamp(0.0, 1.0);
    final deltaDeg = 2 * math.acos(cosine) * radToDeg;

    final t = deltaDeg >= movementThresholdDeg
        ? movingFactor
        : restingFactor +
            (movingFactor - restingFactor) * (deltaDeg / movementThresholdDeg);

    _current = previous.slerp(sample, t);
    return _current!;
  }

  void reset() => _current = null;
}
