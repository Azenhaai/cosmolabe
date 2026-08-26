import 'package:flutter/material.dart';

import '../core/angles.dart';
import '../render/sky_painter.dart';
import 'sky_screen.dart';

/// Every knob, in one sheet.
///
/// The whole sky is a function of the observer, so exposing these is not a
/// power-user afterthought: entering coordinates by hand is a first-class way
/// to use the app, not a fallback for when GPS fails.
class ControlsSheet extends StatefulWidget {
  const ControlsSheet({
    super.key,
    required this.settings,
    required this.site,
    required this.utc,
    required this.timeScale,
    required this.fieldOfViewDeg,
    required this.declinationDeg,
    required this.declinationFromModel,
    required this.refraction,
    required this.locating,
    required this.locationNote,
    required this.onLocate,
    required this.onResetDeclination,
    required this.onSettings,
    required this.onSite,
    required this.onUtc,
    required this.onTimeScale,
    required this.onNow,
    required this.onFieldOfView,
    required this.onDeclination,
    required this.onRefraction,
  });

  final SkySettings settings;
  final ObservingSite site;
  final DateTime utc;
  final double timeScale;
  final double fieldOfViewDeg;
  final double declinationDeg;

  /// True while the declination is the World Magnetic Model's own value for
  /// this place and date, false once the user has typed a correction.
  final bool declinationFromModel;

  final bool refraction;
  final bool locating;
  final String? locationNote;

  final VoidCallback onLocate;
  final VoidCallback onResetDeclination;
  final ValueChanged<SkySettings> onSettings;
  final ValueChanged<ObservingSite> onSite;
  final ValueChanged<DateTime> onUtc;
  final ValueChanged<double> onTimeScale;
  final VoidCallback onNow;
  final ValueChanged<double> onFieldOfView;
  final ValueChanged<double> onDeclination;
  final ValueChanged<bool> onRefraction;

  @override
  State<ControlsSheet> createState() => _ControlsSheetState();
}

class _ControlsSheetState extends State<ControlsSheet> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white38,
              indicatorColor: Colors.lightBlueAccent,
              tabs: [
                Tab(text: 'Place'),
                Tab(text: 'Time'),
                Tab(text: 'Sky'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _PlaceTab(
                    site: widget.site,
                    declinationDeg: widget.declinationDeg,
                    declinationFromModel: widget.declinationFromModel,
                    refraction: widget.refraction,
                    locating: widget.locating,
                    locationNote: widget.locationNote,
                    onSite: widget.onSite,
                    onLocate: widget.onLocate,
                    onDeclination: widget.onDeclination,
                    onResetDeclination: widget.onResetDeclination,
                    onRefraction: widget.onRefraction,
                  ),
                  _TimeTab(
                    utc: widget.utc,
                    timeScale: widget.timeScale,
                    onUtc: widget.onUtc,
                    onTimeScale: widget.onTimeScale,
                    onNow: widget.onNow,
                  ),
                  _SkyTab(
                    settings: widget.settings,
                    fieldOfViewDeg: widget.fieldOfViewDeg,
                    onSettings: widget.onSettings,
                    onFieldOfView: widget.onFieldOfView,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceTab extends StatefulWidget {
  const _PlaceTab({
    required this.site,
    required this.declinationDeg,
    required this.declinationFromModel,
    required this.refraction,
    required this.locating,
    required this.locationNote,
    required this.onSite,
    required this.onLocate,
    required this.onDeclination,
    required this.onResetDeclination,
    required this.onRefraction,
  });

  final ObservingSite site;
  final double declinationDeg;
  final bool declinationFromModel;
  final bool refraction;
  final bool locating;
  final String? locationNote;
  final ValueChanged<ObservingSite> onSite;
  final VoidCallback onLocate;
  final ValueChanged<double> onDeclination;
  final VoidCallback onResetDeclination;
  final ValueChanged<bool> onRefraction;

  @override
  State<_PlaceTab> createState() => _PlaceTabState();
}

class _PlaceTabState extends State<_PlaceTab> {
  late final _latitude = TextEditingController(
    text: Sexagesimal.fromDegrees(widget.site.latitudeDeg).format(),
  );
  late final _longitude = TextEditingController(
    text: Sexagesimal.fromDegrees(widget.site.longitudeDeg).format(),
  );
  late final _elevation = TextEditingController(
    text: widget.site.elevationMeters.round().toString(),
  );
  String? _error;

  @override
  void dispose() {
    _latitude.dispose();
    _longitude.dispose();
    _elevation.dispose();
    super.dispose();
  }

  void _apply() {
    final latitude = parseSexagesimal(_latitude.text);
    final longitude = parseSexagesimal(_longitude.text);
    final elevation = double.tryParse(_elevation.text.trim()) ?? 0;

    if (latitude == null || latitude.abs() > 90) {
      setState(() => _error = 'Latitude must be between -90 and 90');
      return;
    }
    if (longitude == null || longitude.abs() > 180) {
      setState(() => _error = 'Longitude must be between -180 and 180');
      return;
    }

    setState(() => _error = null);
    widget.onSite(ObservingSite(
      name: 'Custom  ${Sexagesimal.fromDegrees(latitude.abs()).format(secondsDigits: 0)}'
          '${latitude >= 0 ? 'N' : 'S'}',
      latitudeDeg: latitude,
      longitudeDeg: longitude,
      elevationMeters: elevation,
    ));
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        const _SectionTitle('Where you are'),
        Row(
          children: [
            FilledButton.icon(
              onPressed: widget.locating ? null : widget.onLocate,
              icon: widget.locating
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, size: 18),
              label: Text(widget.locating ? 'Locating' : 'Use my location'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.site.name,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (widget.locationNote != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.locationNote!,
            style: const TextStyle(
                color: Colors.white38, fontSize: 12, height: 1.4),
          ),
        ],
        const SizedBox(height: 6),
        const Text(
          'Optional. The sky is drawn from whatever coordinates are set below, '
          'typed or located — the app never needs to know where you are.',
          style: TextStyle(color: Colors.white30, fontSize: 12, height: 1.4),
        ),
        const _SectionTitle('Saved places'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final site in defaultSites)
              ActionChip(
                label: Text(site.name),
                backgroundColor: site.name == widget.site.name
                    ? Colors.lightBlue.withValues(alpha: 0.3)
                    : Colors.white10,
                labelStyle: const TextStyle(color: Colors.white, fontSize: 13),
                side: BorderSide.none,
                onPressed: () {
                  widget.onSite(site);
                  _latitude.text =
                      Sexagesimal.fromDegrees(site.latitudeDeg).format();
                  _longitude.text =
                      Sexagesimal.fromDegrees(site.longitudeDeg).format();
                  _elevation.text = site.elevationMeters.round().toString();
                },
              ),
          ],
        ),
        const _SectionTitle('Coordinates'),
        const Text(
          'Decimal degrees or sexagesimal — 32.7353, 32 44 07 N and '
          "32°44'07\" all work. North and east are positive.",
          style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 12),
        _field(_latitude, 'Latitude'),
        const SizedBox(height: 10),
        _field(_longitude, 'Longitude'),
        const SizedBox(height: 10),
        _field(_elevation, 'Elevation, metres', keyboard: TextInputType.number),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(onPressed: _apply, child: const Text('Apply')),
        ),
        const _SectionTitle('Compass'),
        Text(
          widget.declinationFromModel
              ? 'From the World Magnetic Model for this place and date. '
                  'Magnetic north is not true north, and the gap drifts year '
                  'by year.'
              : 'Set by hand. The model value is no longer applied.',
          style: const TextStyle(
              color: Colors.white38, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 10),
        _slider(
          label: 'Magnetic declination',
          value: widget.declinationDeg,
          min: -30,
          max: 30,
          divisions: 240,
          format: (v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}°'
              '  ${v >= 0 ? 'E' : 'W'}',
          onChanged: widget.onDeclination,
        ),
        if (!widget.declinationFromModel)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onResetDeclination,
              icon: const Icon(Icons.restart_alt, size: 17),
              label: const Text('Back to the model value'),
            ),
          ),
        const Text(
          'True north minus magnetic north. Madeira sits near 5° west today. '
          'Only applied on platforms that report magnetic north.',
          style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
        ),
        const _SectionTitle('Atmosphere'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: widget.refraction,
          onChanged: widget.onRefraction,
          title: const Text('Atmospheric refraction',
              style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text(
            'Lifts everything near the horizon by up to half a degree — the '
            'reason the Sun sets later than the geometry says.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.white10,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
      onSubmitted: (_) => _apply(),
    );
  }
}

class _TimeTab extends StatelessWidget {
  const _TimeTab({
    required this.utc,
    required this.timeScale,
    required this.onUtc,
    required this.onTimeScale,
    required this.onNow,
  });

  final DateTime utc;
  final double timeScale;
  final ValueChanged<DateTime> onUtc;
  final ValueChanged<double> onTimeScale;
  final VoidCallback onNow;

  @override
  Widget build(BuildContext context) {
    final local = utc.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        const _SectionTitle('Moment'),
        Text(
          '${two(local.day)}.${two(local.month)}.${local.year}   '
          '${two(local.hour)}:${two(local.minute)}:${two(local.second)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} UTC',
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _step(context, '−1 d', const Duration(days: -1)),
            _step(context, '−1 h', const Duration(hours: -1)),
            _step(context, '−10 m', const Duration(minutes: -10)),
            _step(context, '+10 m', const Duration(minutes: 10)),
            _step(context, '+1 h', const Duration(hours: 1)),
            _step(context, '+1 d', const Duration(days: 1)),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            FilledButton.icon(
              onPressed: onNow,
              icon: const Icon(Icons.schedule, size: 18),
              label: const Text('Now'),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: local,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2100),
                );
                if (date == null) return;
                onUtc(DateTime(
                  date.year,
                  date.month,
                  date.day,
                  local.hour,
                  local.minute,
                ).toUtc());
              },
              child: const Text('Pick a date'),
            ),
          ],
        ),
        const _SectionTitle('Speed'),
        const Text(
          'The sky is a function of the moment, so winding time forward costs '
          'nothing — this is the same code path as live view.',
          style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final speed in [-3600.0, -60.0, 0.0, 1.0, 60.0, 3600.0, 86400.0])
              ChoiceChip(
                label: Text(switch (speed) {
                  0.0 => 'frozen',
                  1.0 => 'live',
                  _ => '${speed > 0 ? '' : '−'}×${speed.abs().toStringAsFixed(0)}',
                }),
                selected: timeScale == speed,
                backgroundColor: Colors.white10,
                selectedColor: Colors.lightBlue.withValues(alpha: 0.35),
                labelStyle: const TextStyle(color: Colors.white, fontSize: 13),
                side: BorderSide.none,
                onSelected: (_) => onTimeScale(speed),
              ),
          ],
        ),
      ],
    );
  }

  Widget _step(BuildContext context, String label, Duration delta) {
    return ActionChip(
      label: Text(label),
      backgroundColor: Colors.white10,
      labelStyle: const TextStyle(color: Colors.white, fontSize: 13),
      side: BorderSide.none,
      onPressed: () => onUtc(utc.add(delta)),
    );
  }
}

class _SkyTab extends StatelessWidget {
  const _SkyTab({
    required this.settings,
    required this.fieldOfViewDeg,
    required this.onSettings,
    required this.onFieldOfView,
  });

  final SkySettings settings;
  final double fieldOfViewDeg;
  final ValueChanged<SkySettings> onSettings;
  final ValueChanged<double> onFieldOfView;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        const _SectionTitle('Depth'),
        _slider(
          label: 'Limiting magnitude',
          value: settings.magnitudeLimit,
          min: 1,
          max: 7,
          divisions: 60,
          format: (v) => '${v.toStringAsFixed(1)}ᵐ',
          onChanged: (v) => onSettings(settings.copyWith(magnitudeLimit: v)),
        ),
        _slider(
          label: 'Light pollution, Bortle class',
          value: settings.bortleClass.toDouble(),
          min: 1,
          max: 9,
          divisions: 8,
          format: (v) => switch (v.round()) {
            1 => '1 — pristine',
            2 || 3 => '${v.round()} — rural',
            4 || 5 => '${v.round()} — suburban',
            6 || 7 => '${v.round()} — town',
            _ => '${v.round()} — inner city',
          },
          onChanged: (v) =>
              onSettings(settings.copyWith(bortleClass: v.round())),
        ),
        const _SectionTitle('View'),
        _slider(
          label: 'Field of view',
          value: fieldOfViewDeg,
          min: 5,
          max: 140,
          divisions: 135,
          format: (v) => '${v.toStringAsFixed(0)}°',
          onChanged: onFieldOfView,
        ),
        const _SectionTitle('Overlays'),
        _toggle('Horizon', settings.showHorizon,
            (v) => onSettings(settings.copyWith(showHorizon: v))),
        _toggle('Cardinal points', settings.showCardinals,
            (v) => onSettings(settings.copyWith(showCardinals: v))),
        _toggle('Star names', settings.showLabels,
            (v) => onSettings(settings.copyWith(showLabels: v))),
        _toggle('Constellation figures', settings.showConstellations,
            (v) => onSettings(settings.copyWith(showConstellations: v))),
        _toggle('Constellation names', settings.showConstellationNames,
            (v) => onSettings(settings.copyWith(showConstellationNames: v))),
        _toggle('Horizontal grid — altitude and azimuth', settings.showAltAzGrid,
            (v) => onSettings(settings.copyWith(showAltAzGrid: v))),
        _toggle('Equatorial grid — right ascension and declination',
            settings.showEquatorialGrid,
            (v) => onSettings(settings.copyWith(showEquatorialGrid: v))),
        _toggle('Ecliptic', settings.showEcliptic,
            (v) => onSettings(settings.copyWith(showEcliptic: v))),
      ],
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: onChanged,
      title: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 14)),
    );
  }
}

Widget _slider({
  required String label,
  required double value,
  required double min,
  required double max,
  required int divisions,
  required String Function(double) format,
  required ValueChanged<double> onChanged,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(
            format(value),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
      ),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Colors.lightBlueAccent,
          fontSize: 11,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
