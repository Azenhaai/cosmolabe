import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/angles.dart';
import '../core/catalog/star_catalog.dart';
import '../core/navigation/polaris.dart';
import '../core/observer.dart';
import '../sensors/attitude.dart';
import '../sensors/orientation_service.dart';

/// The first lesson of the navigation school: find your latitude from Polaris.
///
/// The app already knows the answer, which is the whole point — every sight can
/// be marked, and the learner is told not just how far off they were but which
/// step cost them the distance.
class PolarisLesson extends StatefulWidget {
  const PolarisLesson({
    super.key,
    required this.observer,
    required this.catalog,
    required this.orientation,
    required this.sensorsAvailable,
  });

  final Observer observer;
  final StarCatalog catalog;
  final OrientationService orientation;
  final bool sensorsAvailable;

  @override
  State<PolarisLesson> createState() => _PolarisLessonState();
}

class _PolarisLessonState extends State<PolarisLesson> {
  StreamSubscription<DeviceAttitude>? _subscription;

  /// Live altitude from the accelerometer, before the learner commits to it.
  double? _liveAltitude;

  /// The sight actually taken. Null until the learner captures one.
  double? _sight;

  /// Manual entry, for a real instrument or for indoors.
  final _manual = TextEditingController();

  /// Year for the drift slider.
  double _year = 2026;

  @override
  void initState() {
    super.initState();
    if (widget.sensorsAvailable) {
      _subscription = widget.orientation.attitude.listen((attitude) {
        if (!mounted) return;
        setState(() => _liveAltitude = attitude.pointing.altitudeDeg);
      }, onError: (_) {});
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _manual.dispose();
    super.dispose();
  }

  PolarisSight? get _reduced {
    final altitude = _sight;
    if (altitude == null) return null;
    return reducePolarisSight(
      observer: widget.observer,
      catalog: widget.catalog,
      observedAltitudeDeg: altitude,
    );
  }

  /// Where Polaris really is, so the lesson can show the target and mark the
  /// sight against it.
  PolarisSight get _truth => reducePolarisSight(
        observer: widget.observer,
        catalog: widget.catalog,
        observedAltitudeDeg: widget.observer.latitudeDeg,
      );

  @override
  Widget build(BuildContext context) {
    final truth = _truth;
    final reduced = _reduced;

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        title: const Text('Latitude from Polaris'),
        backgroundColor: const Color(0xFF0B0D12),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        children: [
          const _Lede(
            'The altitude of the celestial pole is your latitude. That is the '
            'whole method, and it is why anyone bothered to find the pole star '
            'at all.',
          ),
          const SizedBox(height: 8),
          const _Body(
            'Polaris is not at the pole. It circles it, two thirds of a degree '
            'away today. So the sight has to be corrected by where in that '
            'circle Polaris currently stands — and you read that off the '
            'Guards, the two stars Kochab and Pherkad.',
          ),

          const _Heading('Where the Guards stand'),
          Center(
            child: SizedBox(
              width: 260,
              height: 260,
              child: CustomPaint(
                painter: _GuardsDialPainter(
                  guardsAngleDeg: truth.guards.positionAngleDeg,
                  polarisAngleDeg:
                      normalizeDegrees(360.0 - truth.hourAngleDeg),
                  polarDistanceDeg: truth.polarDistanceDeg,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _Readout('Guards', truth.guards.clockLabel),
          _Readout('Figure', 'at the ${truth.guards.figureStation}'),
          _Readout(
            'Polaris',
            '${truth.polarDistanceDeg.toStringAsFixed(2)}° from the pole, '
                'hour angle ${truth.hourAngleDeg.toStringAsFixed(1)}°',
          ),
          _Readout(
            'Correction',
            '${truth.correctionDeg >= 0 ? '+' : ''}'
                '${truth.correctionDeg.toStringAsFixed(2)}°',
          ),

          const _Heading('Take the sight'),
          if (widget.sensorsAvailable) ...[
            const _Body(
              'Point the back of the phone at Polaris and hold it steady. The '
              'reading comes from gravity, not the compass, which is why '
              'altitude is the one thing a phone measures well — about half a '
              'degree, against a sextant\'s one arcminute.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _liveAltitude == null
                        ? 'waiting for the sensors'
                        : '${_liveAltitude!.toStringAsFixed(2)}°',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _liveAltitude == null
                      ? null
                      : () => setState(() => _sight = _liveAltitude),
                  icon: const Icon(Icons.adjust, size: 18),
                  label: const Text('Capture'),
                ),
              ],
            ),
          ] else
            const _Body(
              'No motion sensors here, so type the altitude you measured '
              'instead — with a real instrument, or from the sky view.',
            ),

          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manual,
                  keyboardType: TextInputType.text,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Measured altitude',
                    hintText: "32.5 or 32°30'",
                    labelStyle: TextStyle(color: Colors.white38),
                    hintStyle: TextStyle(color: Colors.white24),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () {
                  final value = parseSexagesimal(_manual.text);
                  if (value == null) return;
                  setState(() => _sight = value);
                },
                child: const Text('Use'),
              ),
            ],
          ),

          if (reduced != null) ...[
            const _Heading('Your position'),
            _ResultCard(
              sight: reduced,
              trueLatitude: widget.observer.latitudeDeg,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _sight = null),
                icon: const Icon(Icons.replay, size: 17),
                label: const Text('Take another'),
              ),
            ),
          ],

          const _Heading('Why the rule existed'),
          _Body(
            'Polaris has been closing on the pole for centuries. Drag the year '
            'and watch the correction grow into the reason a pilot needed a '
            'written rule at all.',
          ),
          const SizedBox(height: 6),
          Text(
            '${_year.round()}    '
            '${polarisPolarDistanceAt(DateTime.utc(_year.round()), widget.catalog).toStringAsFixed(2)}° '
            'from the pole',
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 17,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          Slider(
            value: _year,
            min: 1400,
            max: 2100,
            divisions: 700 ~/ 5,
            onChanged: (value) => setState(() => _year = value),
          ),
          _Body(
            'At its worst that is '
            '${(polarisPolarDistanceAt(DateTime.utc(1500), widget.catalog) * 60).round()} '
            'nautical miles of latitude — about '
            '${(polarisPolarDistanceAt(DateTime.utc(1500), widget.catalog) / 0.5).round()} '
            'full Moon widths in the sky — for anyone who simply treated '
            'Polaris as the pole. Which is what the Regimento do Norte was '
            'written to prevent.',
          ),
        ],
      ),
    );
  }
}

/// The pole, Polaris circling it, and the Guards — the picture the whole rule
/// depends on.
class _GuardsDialPainter extends CustomPainter {
  _GuardsDialPainter({
    required this.guardsAngleDeg,
    required this.polarisAngleDeg,
    required this.polarDistanceDeg,
  });

  /// Clockwise from straight up.
  final double guardsAngleDeg;
  final double polarisAngleDeg;
  final double polarDistanceDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 26;

    Offset at(double angleDeg, double r) {
      // Clockwise from up, which is how a clock face reads.
      final a = (angleDeg - 90) * degToRad;
      return centre + Offset(math.cos(a) * r, math.sin(a) * r);
    }

    // The dial.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white24,
    );

    for (var hour = 1; hour <= 12; hour++) {
      final angle = hour * 30.0;
      final tick = at(angle, radius);
      final inner = at(angle, radius - (hour % 3 == 0 ? 14 : 8));
      canvas.drawLine(
        inner,
        tick,
        Paint()
          ..strokeWidth = hour % 3 == 0 ? 2 : 1
          ..color = Colors.white38,
      );
    }

    // Up is towards the zenith — the direction that makes the dial mean
    // anything, since the correction depends on above versus below the pole.
    final painter = TextPainter(
      text: const TextSpan(
        text: 'zenith',
        style: TextStyle(color: Colors.white38, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at(0, radius + 8) - Offset(painter.width / 2, 14));

    // Polaris circles the pole at this radius, scaled up hugely so the
    // geometry is legible; the real circle is two thirds of a degree across.
    final circleRadius = radius * 0.42;
    canvas.drawCircle(
      centre,
      circleRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.amber.withValues(alpha: 0.3),
    );

    // The pole itself.
    canvas.drawCircle(centre, 3.5, Paint()..color = Colors.white70);
    _label(canvas, centre + const Offset(8, -4), 'pole', Colors.white54);

    // Polaris on its circle.
    final polaris = at(polarisAngleDeg, circleRadius);
    canvas.drawCircle(polaris, 7, Paint()..color = Colors.amber);
    _label(canvas, polaris + const Offset(11, -6), 'Polaris', Colors.amber);

    // The Guards, out at the rim, on the line that gives the reading.
    final guards = at(guardsAngleDeg, radius * 0.82);
    canvas.drawLine(
      centre,
      guards,
      Paint()
        ..strokeWidth = 1.4
        ..color = Colors.lightBlueAccent.withValues(alpha: 0.45),
    );
    canvas.drawCircle(guards, 6, Paint()..color = Colors.lightBlueAccent);
    _label(
      canvas,
      guards + const Offset(10, -6),
      'Guards',
      Colors.lightBlueAccent,
    );
  }

  void _label(Canvas canvas, Offset at, String text, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_GuardsDialPainter old) =>
      old.guardsAngleDeg != guardsAngleDeg ||
      old.polarisAngleDeg != polarisAngleDeg;
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.sight, required this.trueLatitude});

  final PolarisSight sight;
  final double trueLatitude;

  @override
  Widget build(BuildContext context) {
    final error = sight.errorAgainst(trueLatitude);
    final miles = sight.errorNauticalMiles(trueLatitude).abs();

    // A 15th-century pilot was doing well at half a degree, which is thirty
    // miles. Grading against that rather than against perfection is the honest
    // comparison, and the encouraging one.
    final (verdict, colour) = switch (miles) {
      < 10 => ('Better than any pilot of the age', Colors.greenAccent),
      < 35 => ('As good as a good 15th-century sight', Colors.lightGreen),
      < 90 => ('Within the ordinary error of the period', Colors.amber),
      _ => ('Far enough out to miss an island', Colors.orangeAccent),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Readout(
            'Measured',
            '${sight.observedAltitudeDeg.toStringAsFixed(2)}°',
          ),
          _Readout(
            'Correction',
            '${sight.correctionDeg >= 0 ? '+' : ''}'
                '${sight.correctionDeg.toStringAsFixed(2)}°',
          ),
          const Divider(color: Colors.white12, height: 20),
          _Readout(
            'Your latitude',
            Sexagesimal.fromDegrees(sight.latitudeDeg.abs())
                    .format(secondsDigits: 0) +
                (sight.latitudeDeg >= 0 ? ' N' : ' S'),
            emphasis: true,
          ),
          _Readout(
            'Actually',
            Sexagesimal.fromDegrees(trueLatitude.abs())
                    .format(secondsDigits: 0) +
                (trueLatitude >= 0 ? ' N' : ' S'),
          ),
          const SizedBox(height: 10),
          Text(
            '${error >= 0 ? 'Too far north' : 'Too far south'} by '
            '${miles.toStringAsFixed(1)} nautical miles',
            style: TextStyle(color: colour, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(verdict, style: TextStyle(color: colour.withValues(alpha: 0.75), fontSize: 13)),
        ],
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout(this.label, this.value, {this.emphasis = false});

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: emphasis ? Colors.amber : Colors.white,
                fontSize: emphasis ? 19 : 14,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 30, bottom: 12),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Colors.lightBlueAccent,
            fontSize: 11.5,
            letterSpacing: 1.3,
          ),
        ),
      );
}

class _Lede extends StatelessWidget {
  const _Lede(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.45),
      );
}

class _Body extends StatelessWidget {
  const _Body(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style:
            const TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
      );
}
