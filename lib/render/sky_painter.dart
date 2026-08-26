import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/angles.dart';
import '../core/bodies/moon.dart';
import '../core/bodies/planets.dart';
import '../core/bodies/sun.dart';
import '../core/catalog/constellation_lines.dart';
import '../core/catalog/star_catalog.dart';
import '../core/coordinates.dart';
import '../core/observer.dart';
import 'sky_projection.dart';

/// Everything the painter needs that is not the projection itself.
class SkySettings {
  const SkySettings({
    this.magnitudeLimit = 6.0,
    this.showHorizon = true,
    this.showCardinals = true,
    this.showAltAzGrid = false,
    this.showEquatorialGrid = false,
    this.showEcliptic = false,
    this.showLabels = true,
    this.showConstellations = true,
    this.showConstellationNames = true,
    this.nightMode = false,
    this.bortleClass = 4,
  });

  final double magnitudeLimit;
  final bool showHorizon;
  final bool showCardinals;
  final bool showAltAzGrid;
  final bool showEquatorialGrid;
  final bool showEcliptic;
  final bool showLabels;
  final bool showConstellations;
  final bool showConstellationNames;

  /// Red-only rendering, to keep dark adaptation.
  final bool nightMode;

  /// 1 is a pristine sky, 9 is an inner city. Dims the faint stars the way
  /// light pollution really does, from the bottom of the range upwards.
  final int bortleClass;

  SkySettings copyWith({
    double? magnitudeLimit,
    bool? showHorizon,
    bool? showCardinals,
    bool? showAltAzGrid,
    bool? showEquatorialGrid,
    bool? showEcliptic,
    bool? showLabels,
    bool? showConstellations,
    bool? showConstellationNames,
    bool? nightMode,
    int? bortleClass,
  }) =>
      SkySettings(
        magnitudeLimit: magnitudeLimit ?? this.magnitudeLimit,
        showHorizon: showHorizon ?? this.showHorizon,
        showCardinals: showCardinals ?? this.showCardinals,
        showAltAzGrid: showAltAzGrid ?? this.showAltAzGrid,
        showEquatorialGrid: showEquatorialGrid ?? this.showEquatorialGrid,
        showEcliptic: showEcliptic ?? this.showEcliptic,
        showLabels: showLabels ?? this.showLabels,
        showConstellations: showConstellations ?? this.showConstellations,
        showConstellationNames:
            showConstellationNames ?? this.showConstellationNames,
        nightMode: nightMode ?? this.nightMode,
        bortleClass: bortleClass ?? this.bortleClass,
      );
}

/// Draws the sky.
class SkyPainter extends CustomPainter {
  SkyPainter({
    required this.projection,
    required this.observer,
    required this.catalog,
    required this.settings,
    this.constellations,
    this.selectedStar,
  });

  final SkyProjection projection;
  final Observer observer;
  final StarCatalog catalog;
  final SkySettings settings;
  final ConstellationLines? constellations;
  final int? selectedStar;

  @override
  void paint(Canvas canvas, Size size) {
    final sun = computeSun(observer.julianEphemeris);
    final sunSky = observer.projectOfDate(sun.equatorial);
    final darkness = skyDarkness(sunSky.altitudeDeg);

    _paintBackground(canvas, size, darkness);
    if (settings.showAltAzGrid) _paintAltAzGrid(canvas);
    if (settings.showEquatorialGrid) _paintEquatorialGrid(canvas);
    if (settings.showEcliptic) _paintEcliptic(canvas);
    // Figures go under the stars so a line never cuts across a star's disc.
    if (settings.showConstellations) _paintConstellations(canvas, darkness);

    _paintStars(canvas, darkness);
    _paintPlanets(canvas);
    _paintMoon(canvas);
    if (sunSky.altitudeDeg > -1) _paintSun(canvas, sunSky, sun);

    if (settings.showHorizon) _paintHorizon(canvas, size);
    if (settings.showCardinals) _paintCardinals(canvas);
    if (selectedStar != null) _paintSelection(canvas, selectedStar!);
  }

  Color _tint(Color color) {
    if (!settings.nightMode) return color;
    // Preserve brightness, throw away everything but red.
    final luminance = color.computeLuminance();
    return Color.fromRGBO(255, 0, 0, color.a * (0.35 + 0.65 * luminance));
  }

  void _paintBackground(Canvas canvas, Size size, double darkness) {
    // Twilight runs from a washed blue to near black; a flat fill would make
    // dusk look like midnight.
    final zenith = Color.lerp(
      const Color(0xFF4A7BB5),
      const Color(0xFF01030A),
      darkness,
    )!;
    final horizon = Color.lerp(
      const Color(0xFFB9C7D6),
      const Color(0xFF0A1020),
      darkness,
    )!;

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width / 2, 0),
          Offset(size.width / 2, size.height),
          [_tint(zenith), _tint(horizon)],
        ),
    );
  }

  void _paintStars(Canvas canvas, double darkness) {
    // Light pollution eats the faint end. Bortle 4 costs about a magnitude
    // against a pristine sky, Bortle 8 costs nearly four.
    final pollutionLoss = (settings.bortleClass - 1) * 0.45;
    final limit = math.min(
      settings.magnitudeLimit,
      catalog.magnitudeLimit - pollutionLoss,
    );
    final cutoff = catalog.cutoffFor(limit);
    if (cutoff == 0) return;

    final cullRadius = projection.cullRadius;
    final centre = projection.center;

    // Faint stars are drawn in batches, one paint per size bucket. Colour is
    // dropped for them on purpose: below about magnitude 3 the eye's own cone
    // cells stop responding, and real faint stars genuinely look white.
    final buckets = <int, List<Offset>>{};

    for (var i = 0; i < cutoff; i++) {
      final sky = observer.project(catalog.positionAt(i));
      if (sky.altitudeDeg < -2) continue;

      final point = projection.project(sky.azimuthDeg, sky.altitudeDeg);
      if (point == null) continue;
      if ((point - centre).distance > cullRadius) continue;

      final magnitude = catalog.magnitude[i];
      final radius = _radiusFor(magnitude, limit);

      if (magnitude > 3.0) {
        buckets.putIfAbsent((radius * 4).round(), () => []).add(point);
      } else {
        _paintBrightStar(canvas, point, i, magnitude, radius, darkness);
      }
    }

    buckets.forEach((key, points) {
      final radius = key / 4;
      final alpha = (0.35 + 0.65 * (radius / 1.6)).clamp(0.2, 1.0);
      canvas.drawPoints(
        ui.PointMode.points,
        points,
        Paint()
          ..color = _tint(Colors.white.withValues(alpha: alpha * darkness))
          ..strokeWidth = radius * 2
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    });
  }

  /// Apparent size on screen. Magnitude is a logarithmic scale, so the step
  /// from -1 to 0 has to look far bigger than the step from 5 to 6.
  double _radiusFor(double magnitude, double limit) {
    final brightness = (limit - magnitude).clamp(0.0, 12.0);
    return 0.5 + 0.42 * math.pow(brightness, 1.22).toDouble() / 3.2;
  }

  void _paintBrightStar(
    Canvas canvas,
    Offset point,
    int index,
    double magnitude,
    double radius,
    double darkness,
  ) {
    final bv = catalog.colorIndex[index];
    final rgb = colorFromBv(bv);
    final color = Color.from(
      alpha: darkness.clamp(0.0, 1.0),
      red: rgb.r,
      green: rgb.g,
      blue: rgb.b,
    );

    // A soft halo is what makes a bright star read as bright rather than as a
    // large dot; the eye does the same thing through an atmosphere.
    canvas.drawCircle(
      point,
      radius * 3.2,
      Paint()
        ..color = _tint(color.withValues(alpha: 0.13 * darkness))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 1.6),
    );
    canvas.drawCircle(point, radius, Paint()..color = _tint(color));

    if (settings.showLabels && magnitude < 1.9) {
      final name = catalog.nameAt(index);
      if (name != null && name.length > 2) {
        _paintLabel(canvas, point + Offset(radius + 6, -7), name, 11,
            Colors.white70);
      }
    }
  }

  /// Draws the constellation figures.
  ///
  /// Each vertex prefers its catalogue row over the stored position, so the
  /// figures are carried along by proper motion when the time machine runs
  /// out to a distant century — the stick figures slowly deform, which is
  /// exactly what really happens.
  void _paintConstellations(Canvas canvas, double darkness) {
    final lines = constellations;
    if (lines == null) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = _tint(
        const Color(0xFF8FB6E0).withValues(alpha: 0.34 * darkness),
      );

    for (final figure in lines.figures) {
      final path = Path();
      var anyVisible = false;

      for (final polyline in figure.polylines) {
        var started = false;
        Offset? previous;

        for (var i = 0; i < polyline.length; i++) {
          final index = polyline.starIndex[i];
          final position = index >= 0
              ? catalog.positionAt(index)
              : Equatorial(polyline.raDeg[i], polyline.decDeg[i]);

          final sky = observer.project(position);
          final point = sky.altitudeDeg < -8
              ? null
              : projection.project(sky.azimuthDeg, sky.altitudeDeg);

          if (point == null) {
            started = false;
            previous = null;
            continue;
          }
          // A vertex that jumps across the whole screen means the figure
          // wrapped behind the viewer between one star and the next.
          if (previous != null && (point - previous).distance > 600) {
            started = false;
          }
          if (!started) {
            path.moveTo(point.dx, point.dy);
            started = true;
          } else {
            path.lineTo(point.dx, point.dy);
          }
          previous = point;
          anyVisible = true;
        }
      }

      if (!anyVisible) continue;
      canvas.drawPath(path, paint);

      if (settings.showConstellationNames) {
        final sky = observer.project(figure.centroid);
        if (sky.altitudeDeg < -4) continue;
        final at = projection.project(sky.azimuthDeg, sky.altitudeDeg);
        if (at == null) continue;
        _paintLabel(
          canvas,
          at,
          figure.name.toUpperCase(),
          10.5,
          const Color(0xFF9FC4E8).withValues(alpha: 0.55),
        );
      }
    }
  }

  void _paintPlanets(Canvas canvas) {
    for (final planet in computeAllPlanets(observer.julianEphemeris)) {
      final sky = observer.projectOfDate(planet.equatorial);
      if (sky.altitudeDeg < -2) continue;
      final point = projection.project(sky.azimuthDeg, sky.altitudeDeg);
      if (point == null) continue;

      // Draw the true disc once it is bigger than the dot would be, so Jupiter
      // grows into a disc as you zoom rather than popping.
      final discRadius =
          planet.angularDiameterArcsec / 3600 / 2 / projection.degreesPerPixel;
      final radius = math.max(_radiusFor(planet.magnitude, 6.0), discRadius);
      final color = _planetColor(planet.planet);

      canvas.drawCircle(
        point,
        radius * 3.0,
        Paint()
          ..color = _tint(color.withValues(alpha: 0.16))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 1.5),
      );
      canvas.drawCircle(point, radius, Paint()..color = _tint(color));

      if (settings.showLabels) {
        _paintLabel(canvas, point + Offset(radius + 7, -7),
            planet.planet.displayName, 11.5, Colors.amber.shade100);
      }
    }
  }

  Color _planetColor(Planet planet) => switch (planet) {
        Planet.mercury => const Color(0xFFBFB6A8),
        Planet.venus => const Color(0xFFFFF3D0),
        Planet.mars => const Color(0xFFE07B4F),
        Planet.jupiter => const Color(0xFFE8D2A6),
        Planet.saturn => const Color(0xFFE3D4A0),
        Planet.uranus => const Color(0xFFA8D8E0),
        Planet.neptune => const Color(0xFF7C9BE0),
        Planet.earth => Colors.white,
      };

  void _paintMoon(Canvas canvas) {
    final moon = computeMoon(observer.julianEphemeris);
    final topocentric = applyTopocentricParallax(
      moon.equatorial,
      moon.parallaxDeg,
      observer.siderealTimeDeg,
      observer.latitudeDeg,
      observer.elevationMeters,
    );
    final sky = observer.projectOfDate(topocentric);
    if (sky.altitudeDeg < -2) return;

    final point = projection.project(sky.azimuthDeg, sky.altitudeDeg);
    if (point == null) return;

    final radius = math.max(
      3.0,
      moon.angularRadiusDeg / projection.degreesPerPixel,
    );

    canvas.drawCircle(
      point,
      radius * 2.4,
      Paint()
        ..color = _tint(Colors.white.withValues(alpha: 0.10))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius),
    );

    // The dark limb still catches earthshine, so it is not black.
    canvas.drawCircle(
      point,
      radius,
      Paint()..color = _tint(const Color(0xFF2A2E36)),
    );

    canvas.save();
    canvas.translate(point.dx, point.dy);
    // The bright limb's position angle is measured east from north; on screen
    // that has to be turned into the direction the crescent faces.
    canvas.rotate(-moon.brightLimbAngleDeg * degToRad);
    _paintMoonPhase(canvas, radius, moon.illuminatedFraction);
    canvas.restore();
  }

  /// The terminator is the projection of a circle, so it is an ellipse whose
  /// width tracks the illuminated fraction. Drawing two half-shapes and
  /// combining them gives every phase from crescent to gibbous.
  void _paintMoonPhase(Canvas canvas, double radius, double illuminated) {
    final paint = Paint()..color = _tint(const Color(0xFFF4EFE2));
    final full = Rect.fromCircle(center: Offset.zero, radius: radius);

    // Half-width of the terminator ellipse, signed: negative means the lit
    // side bulges past the middle, which is what makes a gibbous moon.
    final terminator = radius * (1 - 2 * illuminated);

    final path = Path()
      // The lit limb: a half circle.
      ..addArc(full, -math.pi / 2, math.pi);

    final terminatorRect = Rect.fromLTRB(
      -terminator.abs(),
      -radius,
      terminator.abs(),
      radius,
    );

    if (illuminated < 0.5) {
      // Crescent: cut the terminator ellipse out of the half circle.
      final cut = Path()..addOval(terminatorRect);
      canvas.drawPath(
        Path.combine(PathOperation.difference, path, cut),
        paint,
      );
    } else {
      // Gibbous: add the ellipse onto the half circle.
      final add = Path()..addOval(terminatorRect);
      canvas.drawPath(Path.combine(PathOperation.union, path, add), paint);
    }
  }

  void _paintSun(Canvas canvas, Horizontal sky, SunPosition sun) {
    final point = projection.project(sky.azimuthDeg, sky.altitudeDeg);
    if (point == null) return;

    final radius = math.max(
      4.0,
      sun.angularRadiusDeg / projection.degreesPerPixel,
    );
    canvas.drawCircle(
      point,
      radius * 4,
      Paint()
        ..color = _tint(const Color(0xFFFFE9A8).withValues(alpha: 0.25))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 2),
    );
    canvas.drawCircle(
      point,
      radius,
      Paint()..color = _tint(const Color(0xFFFFF6DC)),
    );
  }

  void _paintHorizon(Canvas canvas, Size size) {
    final path = Path();
    var started = false;
    // The horizon is a great circle, so it has to be walked point by point
    // rather than drawn as a straight line.
    for (var azimuth = 0.0; azimuth <= 360.0; azimuth += 1.0) {
      final point = projection.project(azimuth, -observer.horizonDipDeg);
      if (point == null) {
        started = false;
        continue;
      }
      if (!started) {
        path.moveTo(point.dx, point.dy);
        started = true;
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _tint(const Color(0xFF6E8AA8).withValues(alpha: 0.65)),
    );
  }

  void _paintCardinals(Canvas canvas) {
    const marks = <(double, String)>[
      (0.0, 'N'),
      (45.0, 'NE'),
      (90.0, 'E'),
      (135.0, 'SE'),
      (180.0, 'S'),
      (225.0, 'SW'),
      (270.0, 'W'),
      (315.0, 'NW'),
    ];
    for (final (azimuth, label) in marks) {
      final point = projection.project(azimuth, 0);
      if (point == null) continue;
      final major = label.length == 1;
      _paintLabel(
        canvas,
        point + const Offset(-7, 6),
        label,
        major ? 15 : 11,
        major ? Colors.lightBlue.shade200 : Colors.lightBlue.shade200.withValues(alpha: 0.6),
      );
    }
  }

  void _paintAltAzGrid(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = _tint(const Color(0xFF4A7BB5).withValues(alpha: 0.28));

    for (var altitude = -60.0; altitude <= 80.0; altitude += 20.0) {
      _strokeCircle(canvas, paint,
          (t) => projection.project(t, altitude), 0, 360, 2.0);
    }
    for (var azimuth = 0.0; azimuth < 360.0; azimuth += 30.0) {
      _strokeCircle(canvas, paint,
          (t) => projection.project(azimuth, t), -80, 80, 2.0);
    }
  }

  void _paintEquatorialGrid(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = _tint(const Color(0xFF7BB55A).withValues(alpha: 0.28));

    Offset? at(double ra, double dec) {
      final sky = observer.project(Equatorial(ra, dec));
      return projection.project(sky.azimuthDeg, sky.altitudeDeg);
    }

    for (var dec = -60.0; dec <= 60.0; dec += 30.0) {
      _strokeCircle(canvas, paint, (t) => at(t, dec), 0, 360, 3.0);
    }
    for (var ra = 0.0; ra < 360.0; ra += 30.0) {
      _strokeCircle(canvas, paint, (t) => at(ra, t), -85, 85, 3.0);
    }
  }

  void _paintEcliptic(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = _tint(const Color(0xFFE0B45A).withValues(alpha: 0.45));

    _strokeCircle(canvas, paint, (longitude) {
      final equatorial =
          Ecliptic(longitude, 0).toEquatorial(observer.obliquityDeg);
      final sky = observer.projectOfDate(equatorial);
      return projection.project(sky.azimuthDeg, sky.altitudeDeg);
    }, 0, 360, 2.0);
  }

  /// Walks a curve in sky coordinates, breaking the path wherever the
  /// projection drops out so lines never jump across the screen.
  void _strokeCircle(
    Canvas canvas,
    Paint paint,
    Offset? Function(double) at,
    double from,
    double to,
    double step,
  ) {
    final path = Path();
    var started = false;
    Offset? previous;

    for (var t = from; t <= to; t += step) {
      final point = at(t);
      if (point == null) {
        started = false;
        previous = null;
        continue;
      }
      // A large jump means the curve wrapped around behind the viewer.
      if (previous != null && (point - previous).distance > 400) {
        started = false;
      }
      if (!started) {
        path.moveTo(point.dx, point.dy);
        started = true;
      } else {
        path.lineTo(point.dx, point.dy);
      }
      previous = point;
    }
    canvas.drawPath(path, paint);
  }

  void _paintSelection(Canvas canvas, int index) {
    final sky = observer.project(catalog.positionAt(index));
    final point = projection.project(sky.azimuthDeg, sky.altitudeDeg);
    if (point == null) return;

    canvas.drawCircle(
      point,
      16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _tint(Colors.amber.withValues(alpha: 0.9)),
    );

    final name = catalog.nameAt(index) ?? 'HIP ${catalog.hip[index]}';
    final constellation = catalog.constellationAt(index);
    final magnitude = catalog.magnitude[index].toStringAsFixed(2);
    _paintLabel(
      canvas,
      point + const Offset(22, -10),
      constellation == null
          ? '$name   $magnitudeᵐ'
          : '$name  ($constellation)   $magnitudeᵐ',
      13,
      Colors.amber.shade100,
    );
  }

  void _paintLabel(
    Canvas canvas,
    Offset at,
    String text,
    double fontSize,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _tint(color),
          fontSize: fontSize,
          letterSpacing: 0.4,
          shadows: const [
            Shadow(color: Colors.black87, blurRadius: 3),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(SkyPainter oldDelegate) => true;
}
