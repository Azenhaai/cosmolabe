import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/angles.dart';
import '../core/catalog/catalog_loader.dart';
import '../core/catalog/constellation_lines.dart';
import '../core/catalog/star_catalog.dart';
import '../core/coordinates.dart';
import '../core/observer.dart';
import '../render/sky_painter.dart';
import '../render/sky_projection.dart';
import '../core/geomagnetism.dart';
import '../sensors/attitude.dart';
import '../sensors/location_service.dart';
import '../sensors/orientation_service.dart';
import 'controls_sheet.dart';
import 'polaris_lesson.dart';

/// A place worth keeping. Manual entry writes into the same shape, so a typed
/// pair of coordinates behaves exactly like a preset.
class ObservingSite {
  const ObservingSite({
    required this.name,
    required this.latitudeDeg,
    required this.longitudeDeg,
    required this.elevationMeters,
  });

  final String name;
  final double latitudeDeg;
  final double longitudeDeg;
  final double elevationMeters;
}

const defaultSites = [
  ObservingSite(
    name: 'Pico do Arieiro',
    latitudeDeg: 32.735278,
    longitudeDeg: -16.928611,
    elevationMeters: 1818,
  ),
  ObservingSite(
    name: 'Funchal',
    latitudeDeg: 32.6669,
    longitudeDeg: -16.9241,
    elevationMeters: 25,
  ),
  ObservingSite(
    name: 'Porto Santo',
    latitudeDeg: 33.0667,
    longitudeDeg: -16.3333,
    elevationMeters: 10,
  ),
  ObservingSite(
    name: 'Lisboa',
    latitudeDeg: 38.7223,
    longitudeDeg: -9.1393,
    elevationMeters: 100,
  ),
];

class SkyScreen extends StatefulWidget {
  const SkyScreen({super.key});

  @override
  State<SkyScreen> createState() => _SkyScreenState();
}

class _SkyScreenState extends State<SkyScreen>
    with SingleTickerProviderStateMixin {
  final _orientation = OrientationService();
  final _location = const LocationService();

  StarCatalog? _catalog;
  ConstellationLines? _constellations;
  String? _loadError;

  late Ticker _ticker;
  Duration _lastTick = Duration.zero;

  // Place and time — the Observer is rebuilt from these every frame.
  ObservingSite _site = defaultSites.first;
  DateTime _utc = DateTime.now().toUtc();
  double _timeScale = 1.0;
  bool _followingClock = true;

  double _declinationDeg = 0;
  /// True while the declination is the model's own value. A hand-typed
  /// correction pins it, so moving the site no longer overwrites it.
  bool _declinationFromModel = true;
  bool _refraction = true;

  LocationFix? _lastFix;
  bool _locating = false;

  // Where the phone is pointing, or where the finger has dragged.
  DeviceAttitude _attitude = DeviceAttitude(
    orientation: Quaternion.lookAt(180, 30),
    headingAccuracyDeg: 0,
    referencedToTrueNorth: true,
  );
  StreamSubscription<DeviceAttitude>? _sensorSubscription;
  bool _sensorsAvailable = false;
  bool _sensorMode = false;

  double _manualAzimuth = 180;
  double _manualAltitude = 30;
  double _fieldOfViewDeg = 65;
  double _fovAtGestureStart = 65;

  SkySettings _settings = const SkySettings();
  int? _selected;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _refreshDeclination();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await CatalogLoader.load();
      if (!mounted) return;
      setState(() {
        _catalog = data.catalog;
        _constellations = data.constellations;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = '$error');
      return;
    }

    final available = await _orientation.isAvailable();
    if (!mounted) return;
    setState(() => _sensorsAvailable = available);
    if (available) _startSensors();
  }

  /// Recomputes the declination for the current place and date.
  ///
  /// The field drifts, so this is a function of both position and time, not a
  /// constant to set once. A manual override wins and is never clobbered.
  void _refreshDeclination() {
    if (!_declinationFromModel) return;
    final field = magneticFieldAt(
      latitudeDeg: _site.latitudeDeg,
      longitudeDeg: _site.longitudeDeg,
      heightMeters: _site.elevationMeters,
      decimalYear: decimalYearOf(_utc),
    );
    _declinationDeg = field.declinationDeg;
    _orientation.declinationDeg = _declinationDeg;
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final fix = await _location.current();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _lastFix = fix;
      if (fix.hasPosition) {
        _site = ObservingSite(
          name: 'Here',
          latitudeDeg: fix.latitudeDeg!,
          longitudeDeg: fix.longitudeDeg!,
          elevationMeters: fix.elevationMeters ?? _site.elevationMeters,
        );
        _refreshDeclination();
      }
    });
  }

  void _startSensors() {
    _orientation.declinationDeg = _declinationDeg;
    _sensorSubscription = _orientation.attitude.listen(
      (attitude) {
        if (!_sensorMode) return;
        setState(() => _attitude = attitude);
      },
      onError: (_) {
        if (mounted) setState(() => _sensorMode = false);
      },
    );
    setState(() => _sensorMode = true);
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _lastTick;
    _lastTick = elapsed;
    if (_timeScale == 0) return;

    setState(() {
      if (_followingClock && _timeScale == 1.0) {
        _utc = DateTime.now().toUtc();
      } else {
        _utc = _utc.add(
          Duration(microseconds: (delta.inMicroseconds * _timeScale).round()),
        );
      }
    });
  }

  Observer get _observer => Observer(
        latitudeDeg: _site.latitudeDeg,
        longitudeDeg: _site.longitudeDeg,
        elevationMeters: _site.elevationMeters,
        utc: _utc,
        magneticDeclinationDeg: _declinationDeg,
        applyRefraction: _refraction,
      );

  @override
  void dispose() {
    _ticker.dispose();
    _sensorSubscription?.cancel();
    super.dispose();
  }

  void _setManualLook(double azimuth, double altitude) {
    _manualAzimuth = normalizeDegrees(azimuth);
    _manualAltitude = altitude.clamp(-89.0, 89.0);
    _attitude = DeviceAttitude(
      orientation: Quaternion.lookAt(_manualAzimuth, _manualAltitude),
      headingAccuracyDeg: 0,
      referencedToTrueNorth: true,
    );
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size size) {
    setState(() {
      if (details.scale != 1.0) {
        _fieldOfViewDeg = (_fovAtGestureStart / details.scale).clamp(1.0, 140.0);
      }
      if (_sensorMode || details.focalPointDelta == Offset.zero) return;

      // Drag by the angle the pixels correspond to, so the sky tracks the
      // finger rather than sliding at some arbitrary rate.
      final perPixel = _fieldOfViewDeg / math.min(size.width, size.height);
      _setManualLook(
        _manualAzimuth - details.focalPointDelta.dx * perPixel,
        _manualAltitude + details.focalPointDelta.dy * perPixel,
      );
    });
  }

  void _onTap(Offset position, Size size) {
    final catalog = _catalog;
    if (catalog == null) return;

    final projection = _projectionFor(size);
    final direction = projection.unproject(position);
    if (direction == null) return;

    // Screen coordinates are horizontal; the catalogue is equatorial, so the
    // tap has to be carried back through the same chain in reverse.
    final equatorial = horizontalToEquatorial(
      direction,
      _observer.siderealTimeDeg,
      _observer.latitudeDeg,
    );
    // Tolerance follows the zoom: a wide field forgives a sloppier tap.
    final tolerance = (_fieldOfViewDeg / 20).clamp(0.5, 4.0);
    final found = catalog.nearest(
      equatorial.raDeg,
      equatorial.decDeg,
      maxSeparationDeg: tolerance,
    );
    setState(() => _selected = found);
  }

  SkyProjection _projectionFor(Size size) => SkyProjection(
        attitude: _attitude,
        size: size,
        fieldOfViewDeg: _fieldOfViewDeg,
      );

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load the star catalogue.\n$_loadError',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    final catalog = _catalog;
    if (catalog == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (_) => _fovAtGestureStart = _fieldOfViewDeg,
                onScaleUpdate: (details) => _onScaleUpdate(details, size),
                onTapUp: (details) => _onTap(details.localPosition, size),
                child: CustomPaint(
                  size: size,
                  painter: SkyPainter(
                    projection: _projectionFor(size),
                    observer: _observer,
                    catalog: catalog,
                    settings: _settings,
                    constellations: _constellations,
                    selectedStar: _selected,
                  ),
                ),
              ),
              _StatusBar(
                site: _site,
                utc: _utc,
                attitude: _attitude,
                fieldOfViewDeg: _fieldOfViewDeg,
                timeScale: _timeScale,
                nightMode: _settings.nightMode,
              ),
              _ButtonBar(
                nightMode: _settings.nightMode,
                sensorMode: _sensorMode,
                sensorsAvailable: _sensorsAvailable,
                needsCalibration:
                    _sensorMode && _attitude.needsCalibration,
                onToggleSensor: _toggleSensorMode,
                onToggleNight: () => setState(
                  () => _settings = _settings.copyWith(
                    nightMode: !_settings.nightMode,
                  ),
                ),
                onOpenControls: _openControls,
                onOpenLesson: _openLesson,
              ),
            ],
          );
        },
      ),
    );
  }

  void _toggleSensorMode() {
    if (!_sensorsAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No motion sensors here — drag to look around.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() {
      _sensorMode = !_sensorMode;
      if (!_sensorMode) {
        // Carry the current view into manual mode so nothing jumps.
        final pointing = _attitude.pointing;
        _setManualLook(pointing.azimuthDeg, pointing.altitudeDeg);
      }
    });
  }

  /// Opens the first navigation lesson.
  ///
  /// The observer is passed by value, so the lesson grades the sight against
  /// exactly the coordinates the sky view is drawn from — typed or located.
  void _openLesson() {
    final catalog = _catalog;
    if (catalog == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PolarisLesson(
          observer: _observer,
          catalog: catalog,
          orientation: _orientation,
          sensorsAvailable: _sensorsAvailable,
        ),
      ),
    );
  }

  void _openControls() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0D12),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => ControlsSheet(
        settings: _settings,
        site: _site,
        utc: _utc,
        timeScale: _timeScale,
        fieldOfViewDeg: _fieldOfViewDeg,
        declinationDeg: _declinationDeg,
        declinationFromModel: _declinationFromModel,
        refraction: _refraction,
        locating: _locating,
        locationNote: _lastFix?.explanation,
        onLocate: () {
          Navigator.of(context).pop();
          _locate();
        },
        onResetDeclination: () => setState(() {
          _declinationFromModel = true;
          _refreshDeclination();
        }),
        onSettings: (value) => setState(() => _settings = value),
        onSite: (value) => setState(() {
          _site = value;
          _refreshDeclination();
        }),
        onUtc: (value) => setState(() {
          _utc = value;
          _followingClock = false;
        }),
        onTimeScale: (value) => setState(() {
          _timeScale = value;
          if (value == 1.0) _followingClock = true;
        }),
        onNow: () => setState(() {
          _utc = DateTime.now().toUtc();
          _timeScale = 1.0;
          _followingClock = true;
        }),
        onFieldOfView: (value) => setState(() => _fieldOfViewDeg = value),
        onDeclination: (value) => setState(() {
          _declinationFromModel = false;
          _declinationDeg = value;
          _orientation.declinationDeg = value;
        }),
        onRefraction: (value) => setState(() => _refraction = value),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.site,
    required this.utc,
    required this.attitude,
    required this.fieldOfViewDeg,
    required this.timeScale,
    required this.nightMode,
  });

  final ObservingSite site;
  final DateTime utc;
  final DeviceAttitude attitude;
  final double fieldOfViewDeg;
  final double timeScale;
  final bool nightMode;

  @override
  Widget build(BuildContext context) {
    final colour = nightMode ? const Color(0xFFFF6B6B) : Colors.white70;
    final pointing = attitude.pointing;
    final local = utc.toLocal();

    String two(int value) => value.toString().padLeft(2, '0');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: DefaultTextStyle(
          style: TextStyle(
            color: colour,
            fontSize: 12,
            fontFeatures: const [FontFeature.tabularFigures()],
            shadows: const [Shadow(color: Colors.black87, blurRadius: 4)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(site.name, style: TextStyle(color: colour, fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                '${two(local.day)}.${two(local.month)}.${local.year}  '
                '${two(local.hour)}:${two(local.minute)}:${two(local.second)}'
                '${timeScale == 1.0 ? '' : '   ×${timeScale.toStringAsFixed(0)}'}',
              ),
              Text(
                'az ${pointing.azimuthDeg.toStringAsFixed(1)}°   '
                'alt ${pointing.altitudeDeg.toStringAsFixed(1)}°   '
                'fov ${fieldOfViewDeg.toStringAsFixed(0)}°',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ButtonBar extends StatelessWidget {
  const _ButtonBar({
    required this.nightMode,
    required this.sensorMode,
    required this.sensorsAvailable,
    required this.needsCalibration,
    required this.onToggleSensor,
    required this.onToggleNight,
    required this.onOpenControls,
    required this.onOpenLesson,
  });

  final bool nightMode;
  final bool sensorMode;
  final bool sensorsAvailable;
  final bool needsCalibration;
  final VoidCallback onToggleSensor;
  final VoidCallback onToggleNight;
  final VoidCallback onOpenControls;
  final VoidCallback onOpenLesson;

  @override
  Widget build(BuildContext context) {
    final tint = nightMode ? const Color(0xFFFF6B6B) : Colors.white;

    Widget button(IconData icon, VoidCallback onPressed, {bool active = false}) {
      return Padding(
        padding: const EdgeInsets.only(left: 10),
        child: Material(
          color: active
              ? tint.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.08),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(icon, size: 22, color: tint),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.bottomRight,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (needsCalibration)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    'compass\nneeds a figure-8',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: tint.withValues(alpha: 0.8),
                      fontSize: 11,
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              button(
                sensorMode ? Icons.explore : Icons.pan_tool_alt_outlined,
                onToggleSensor,
                active: sensorMode,
              ),
              button(
                nightMode ? Icons.nightlight_round : Icons.nightlight_outlined,
                onToggleNight,
                active: nightMode,
              ),
              // A drafting compass, not the sensor toggle's magnetic one.
              button(Icons.architecture, onOpenLesson),
              button(Icons.tune, onOpenControls),
            ],
          ),
        ),
      ),
    );
  }
}
