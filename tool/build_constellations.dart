// Converts constellation figure data into the binary asset the app ships.
//
//   dart run tool/build_constellations.dart <source> [--boundaries <source>]
//
// Three input shapes are understood, detected from the file itself, because
// the licensing question decides the source and the source decides the format:
//
//   * Stellarium `constellationship.fab` — `Abbr count hip hip hip hip ...`,
//     read as consecutive pairs.
//   * GeoJSON with MultiLineString geometry, as used by d3-celestial and
//     friends — vertices are [longitude, latitude] in degrees, where longitude
//     runs -180..180 and maps to right ascension.
//   * Plain JSON `{ "Ori": [[hip, hip, ...], ...] }` — one array per stroke.
//
// Vertices are written with both the Hipparcos number and the J2000 position,
// so a figure never breaks because a star fell outside the magnitude cut.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int formatVersion = 1;

/// How close a line vertex has to sit to a catalogue star before we accept
/// that it *is* that star. The figures are traced through real stars, so a
/// genuine match lands within a couple of arcminutes; anything looser is a
/// coincidence and gets left as a bare coordinate.
const double snapToleranceDeg = 0.15;

/// Full names for the 88 IAU abbreviations. The line data carries only the
/// three-letter code, and a label reading "PSA" helps nobody.
const Map<String, String> constellationNames = {
  'And': 'Andromeda', 'Ant': 'Antlia', 'Aps': 'Apus', 'Aqr': 'Aquarius',
  'Aql': 'Aquila', 'Ara': 'Ara', 'Ari': 'Aries', 'Aur': 'Auriga',
  'Boo': 'Boötes', 'Cae': 'Caelum', 'Cam': 'Camelopardalis', 'Cnc': 'Cancer',
  'CVn': 'Canes Venatici', 'CMa': 'Canis Major', 'CMi': 'Canis Minor',
  'Cap': 'Capricornus', 'Car': 'Carina', 'Cas': 'Cassiopeia',
  'Cen': 'Centaurus', 'Cep': 'Cepheus', 'Cet': 'Cetus', 'Cha': 'Chamaeleon',
  'Cir': 'Circinus', 'Col': 'Columba', 'Com': 'Coma Berenices',
  'CrA': 'Corona Australis', 'CrB': 'Corona Borealis', 'Crv': 'Corvus',
  'Crt': 'Crater', 'Cru': 'Crux', 'Cyg': 'Cygnus', 'Del': 'Delphinus',
  'Dor': 'Dorado', 'Dra': 'Draco', 'Equ': 'Equuleus', 'Eri': 'Eridanus',
  'For': 'Fornax', 'Gem': 'Gemini', 'Gru': 'Grus', 'Her': 'Hercules',
  'Hor': 'Horologium', 'Hya': 'Hydra', 'Hyi': 'Hydrus', 'Ind': 'Indus',
  'Lac': 'Lacerta', 'Leo': 'Leo', 'LMi': 'Leo Minor', 'Lep': 'Lepus',
  'Lib': 'Libra', 'Lup': 'Lupus', 'Lyn': 'Lynx', 'Lyr': 'Lyra',
  'Men': 'Mensa', 'Mic': 'Microscopium', 'Mon': 'Monoceros', 'Mus': 'Musca',
  'Nor': 'Norma', 'Oct': 'Octans', 'Oph': 'Ophiuchus', 'Ori': 'Orion',
  'Pav': 'Pavo', 'Peg': 'Pegasus', 'Per': 'Perseus', 'Phe': 'Phoenix',
  'Pic': 'Pictor', 'Psc': 'Pisces', 'PsA': 'Piscis Austrinus',
  'Pup': 'Puppis', 'Pyx': 'Pyxis', 'Ret': 'Reticulum', 'Sge': 'Sagitta',
  'Sgr': 'Sagittarius', 'Sco': 'Scorpius', 'Scl': 'Sculptor',
  'Sct': 'Scutum', 'Ser': 'Serpens', 'Sex': 'Sextans', 'Tau': 'Taurus',
  'Tel': 'Telescopium', 'Tri': 'Triangulum', 'TrA': 'Triangulum Australe',
  'Tuc': 'Tucana', 'UMa': 'Ursa Major', 'UMi': 'Ursa Minor', 'Vel': 'Vela',
  'Vir': 'Virgo', 'Vol': 'Volans', 'Vul': 'Vulpecula',
};

class Vertex {
  Vertex(this.hip, this.raDeg, this.decDeg);
  final int hip;
  final double raDeg;
  final double decDeg;
}

class Figure {
  Figure(this.abbreviation);
  final String abbreviation;
  final List<List<Vertex>> polylines = [];

  /// Set when one abbreviation covers two disconnected figures.
  String? nameOverride;

  String get name =>
      nameOverride ?? constellationNames[abbreviation] ?? abbreviation;
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/build_constellations.dart <lines-source>',
    );
    exit(64);
  }

  final source = File(args.first);
  if (!source.existsSync()) {
    stderr.writeln('not found: ${source.path}');
    exit(66);
  }

  // The HYG catalogue serves two purposes: giving positions to HIP-only
  // sources, and giving Hipparcos numbers to position-only sources.
  final stars = _loadStars(args);
  final hipPositions = {
    for (final s in stars) s.hip: (s.raDeg, s.decDeg),
  };

  final text = source.readAsStringSync();
  final figures = _parse(text, hipPositions);

  if (stars.isNotEmpty) _snapToStars(figures, stars);
  _disambiguateSplitFigures(figures);

  if (figures.isEmpty) {
    stderr.writeln('no figures parsed — is the format one of the three?');
    exit(65);
  }

  var vertices = 0;
  var missingPositions = 0;
  for (final figure in figures) {
    for (final line in figure.polylines) {
      vertices += line.length;
      for (final v in line) {
        if (v.raDeg == 0 && v.decDeg == 0) missingPositions++;
      }
    }
  }

  final builder = BytesBuilder();
  final head = ByteData(8)
    ..setUint8(0, 0x43) // 'C'
    ..setUint8(1, 0x4C) // 'L'
    ..setUint8(2, 0x49) // 'I'
    ..setUint8(3, 0x4E) // 'N'
    ..setUint16(4, formatVersion, Endian.little)
    ..setUint16(6, figures.length, Endian.little);
  builder.add(head.buffer.asUint8List());

  for (final figure in figures) {
    builder.add(ascii.encode(figure.abbreviation.padRight(3).substring(0, 3)));

    final nameBytes = utf8.encode(figure.name);
    builder.add(Uint8List.fromList([nameBytes.length]));
    builder.add(nameBytes);

    final countBytes = ByteData(2)
      ..setUint16(0, figure.polylines.length, Endian.little);
    builder.add(countBytes.buffer.asUint8List());

    for (final line in figure.polylines) {
      final lineHeader = ByteData(2)
        ..setUint16(0, line.length, Endian.little);
      builder.add(lineHeader.buffer.asUint8List());

      final body = ByteData(line.length * 12);
      for (var i = 0; i < line.length; i++) {
        body.setInt32(i * 12, line[i].hip, Endian.little);
        body.setFloat32(i * 12 + 4, line[i].raDeg, Endian.little);
        body.setFloat32(i * 12 + 8, line[i].decDeg, Endian.little);
      }
      builder.add(body.buffer.asUint8List());
    }
  }

  final output = File('assets/catalog/constellations.bin');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(builder.takeBytes());

  stdout.writeln('${figures.length} figures');
  stdout.writeln(
    '${figures.fold(0, (s, f) => s + f.polylines.length)} strokes, '
    '$vertices vertices',
  );
  if (missingPositions > 0) {
    stdout.writeln(
      '$missingPositions vertices have no position — they will fall back to '
      'the catalogue lookup, and break if the star is not in it',
    );
  }
  final missingNames =
      figures.where((f) => !constellationNames.containsKey(f.abbreviation));
  if (missingNames.isNotEmpty) {
    stdout.writeln(
      'unknown abbreviations: ${missingNames.map((f) => f.abbreviation).join(', ')}',
    );
  }
  stdout.writeln(
    'wrote ${output.path} — '
    '${(output.lengthSync() / 1024).toStringAsFixed(1)} KB',
  );
}

class Star {
  const Star(this.hip, this.raDeg, this.decDeg, this.magnitude);
  final int hip;
  final double raDeg;
  final double decDeg;
  final double magnitude;
}

/// Reads the naked-eye stars out of the HYG CSV, when one is passed with
/// --hyg. Constellation figures only ever join bright stars, so the faint
/// tail of the catalogue is dead weight for this job.
List<Star> _loadStars(List<String> args) {
  final flag = args.indexOf('--hyg');
  if (flag < 0 || flag + 1 >= args.length) return const [];

  final file = File(args[flag + 1]);
  if (!file.existsSync()) {
    stderr.writeln('--hyg file not found: ${file.path}');
    exit(66);
  }

  final stars = <Star>[];
  final lines = file.readAsLinesSync();
  final header =
      lines.first.split(',').map((s) => s.replaceAll('"', '')).toList();
  final hipColumn = header.indexOf('hip');
  final raColumn = header.indexOf('ra');
  final decColumn = header.indexOf('dec');
  final magColumn = header.indexOf('mag');

  for (var i = 1; i < lines.length; i++) {
    final fields = lines[i].split(',');
    if (fields.length <= magColumn) continue;
    final hip = int.tryParse(fields[hipColumn]);
    if (hip == null) continue;
    final ra = double.tryParse(fields[raColumn]);
    final dec = double.tryParse(fields[decColumn]);
    final mag = double.tryParse(fields[magColumn]);
    if (ra == null || dec == null || mag == null || mag > 7.5) continue;
    // The CSV stores right ascension in hours.
    stars.add(Star(hip, ra * 15.0, dec, mag));
  }
  stdout.writeln('${stars.length} naked-eye stars loaded for snapping');
  return stars;
}

/// Attaches a Hipparcos number to every vertex that sits on a real star.
///
/// The GeoJSON sources bake positions rather than star references, which means
/// the figures float free of whatever catalogue the app actually renders. Two
/// arcminutes of disagreement is invisible in a printed chart and glaring on a
/// zoomed phone screen, where the line ends beside the star instead of on it.
/// Matching once here fixes the endpoints to our own stars and lets proper
/// motion carry the figures when the time machine runs out to a far century.
void _snapToStars(List<Figure> figures, List<Star> stars) {
  // Bucket by declination so each vertex only tests a narrow band.
  const bandDeg = 5.0;
  final bands = <int, List<Star>>{};
  for (final star in stars) {
    bands.putIfAbsent((star.decDeg / bandDeg).floor(), () => []).add(star);
  }

  var matched = 0;
  var total = 0;
  final separations = <double>[];

  for (final figure in figures) {
    for (final polyline in figure.polylines) {
      for (var i = 0; i < polyline.length; i++) {
        final vertex = polyline[i];
        if (vertex.hip != 0) continue;
        total++;

        Star? best;
        var bestSeparation = snapToleranceDeg;
        final band = (vertex.decDeg / bandDeg).floor();
        for (var b = band - 1; b <= band + 1; b++) {
          for (final star in bands[b] ?? const <Star>[]) {
            final separation =
                _angularSeparation(vertex.raDeg, vertex.decDeg, star.raDeg, star.decDeg);
            if (separation < bestSeparation) {
              bestSeparation = separation;
              best = star;
            }
          }
        }

        if (best != null) {
          // Keep the catalogue's own position, not the source's, so the line
          // lands exactly on the drawn star.
          polyline[i] = Vertex(best.hip, best.raDeg, best.decDeg);
          separations.add(bestSeparation);
          matched++;
        }
      }
    }
  }

  if (total == 0) return;
  separations.sort();
  final median = separations.isEmpty
      ? 0.0
      : separations[separations.length ~/ 2] * 3600;
  final worst = separations.isEmpty ? 0.0 : separations.last * 3600;
  stdout.writeln(
    'snapped $matched of $total vertices to catalogue stars '
    '(median ${median.toStringAsFixed(1)}", worst ${worst.toStringAsFixed(1)}")',
  );
  if (median > 30) {
    stdout.writeln(
      'WARNING: median offset above half an arcminute suggests the source is '
      'not on the J2000 equinox — check before shipping',
    );
  }
}

double _angularSeparation(double ra1, double dec1, double ra2, double dec2) {
  const toRad = math.pi / 180.0;
  final d1 = dec1 * toRad;
  final d2 = dec2 * toRad;
  final dRa = (ra2 - ra1) * toRad;
  final dDec = d2 - d1;
  final a = math.pow(math.sin(dDec / 2), 2) +
      math.cos(d1) * math.cos(d2) * math.pow(math.sin(dRa / 2), 2);
  return 2 * math.asin(math.min(1.0, math.sqrt(a))) / toRad;
}

/// Serpens is the one constellation split into two disconnected halves, and
/// the sources give both the same abbreviation. Left alone that puts one label
/// between them, in the middle of Ophiuchus, where no part of Serpens is.
void _disambiguateSplitFigures(List<Figure> figures) {
  final counts = <String, int>{};
  for (final figure in figures) {
    counts[figure.abbreviation] = (counts[figure.abbreviation] ?? 0) + 1;
  }

  for (final entry in counts.entries) {
    if (entry.value < 2) continue;
    if (entry.key != 'Ser') {
      stdout.writeln('note: ${entry.key} appears ${entry.value} times');
      continue;
    }
    final halves = figures.where((f) => f.abbreviation == 'Ser').toList();
    halves.sort((a, b) => _meanRa(a).compareTo(_meanRa(b)));
    // The head lies west of the tail.
    halves.first.nameOverride = 'Serpens Caput';
    halves.last.nameOverride = 'Serpens Cauda';
    stdout.writeln('split Serpens into Caput and Cauda');
  }
}

double _meanRa(Figure figure) {
  var sum = 0.0;
  var count = 0;
  for (final line in figure.polylines) {
    for (final v in line) {
      sum += v.raDeg;
      count++;
    }
  }
  return count == 0 ? 0 : sum / count;
}

List<Figure> _parse(String text, Map<int, (double, double)> positions) {
  final trimmed = text.trimLeft();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    final decoded = jsonDecode(text);
    if (decoded is Map && decoded['type'] == 'FeatureCollection') {
      return _parseGeoJson(decoded, positions);
    }
    return _parseSimpleJson(decoded, positions);
  }
  return _parseFab(text, positions);
}

/// Stellarium's `constellationship.fab`: an abbreviation, a pair count, then
/// that many pairs of Hipparcos numbers.
List<Figure> _parseFab(String text, Map<int, (double, double)> positions) {
  final figures = <Figure>[];

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    final tokens = line.split(RegExp(r'\s+'));
    if (tokens.length < 4) continue;

    final figure = Figure(tokens.first);
    final pairs = int.tryParse(tokens[1]);
    if (pairs == null) continue;

    // Pairs are independent segments; stitch consecutive ones that share an
    // endpoint back into a single stroke, which halves the vertex count and
    // makes the drawn path continuous.
    List<Vertex>? current;
    for (var p = 0; p < pairs; p++) {
      final a = int.tryParse(tokens[2 + p * 2]);
      final b = int.tryParse(tokens[3 + p * 2]);
      if (a == null || b == null) break;

      if (current != null && current.last.hip == a) {
        current.add(_vertex(b, positions));
      } else {
        current = [_vertex(a, positions), _vertex(b, positions)];
        figure.polylines.add(current);
      }
    }
    if (figure.polylines.isNotEmpty) figures.add(figure);
  }
  return figures;
}

/// GeoJSON MultiLineString, coordinates as [longitude, latitude] in degrees.
List<Figure> _parseGeoJson(
  Map<dynamic, dynamic> root,
  Map<int, (double, double)> positions,
) {
  final figures = <Figure>[];

  for (final feature in (root['features'] as List)) {
    final properties = (feature['properties'] as Map?) ?? const {};
    final id = (feature['id'] ?? properties['id'] ?? properties['abbr'] ?? '')
        .toString();
    if (id.isEmpty) continue;

    // Sources differ on capitalisation; the catalogue uses the IAU form.
    final abbreviation = constellationNames.keys.firstWhere(
      (k) => k.toLowerCase() == id.toLowerCase(),
      orElse: () => id,
    );

    final figure = Figure(abbreviation);
    final geometry = feature['geometry'] as Map?;
    if (geometry == null) continue;

    final coordinates = geometry['coordinates'] as List;
    final strokes = geometry['type'] == 'LineString'
        ? [coordinates]
        : coordinates;

    for (final stroke in strokes) {
      final vertices = <Vertex>[];
      for (final point in (stroke as List)) {
        final longitude = (point[0] as num).toDouble();
        final latitude = (point[1] as num).toDouble();
        // Longitude runs -180..180; right ascension runs 0..360.
        final ra = longitude < 0 ? longitude + 360.0 : longitude;
        vertices.add(Vertex(0, ra, latitude));
      }
      if (vertices.length >= 2) figure.polylines.add(vertices);
    }
    if (figure.polylines.isNotEmpty) figures.add(figure);
  }
  return figures;
}

/// `{ "Ori": [[hip, hip, ...], ...] }`.
List<Figure> _parseSimpleJson(
  dynamic root,
  Map<int, (double, double)> positions,
) {
  if (root is! Map) return const [];
  final figures = <Figure>[];

  root.forEach((key, value) {
    if (value is! List) return;
    final figure = Figure(key.toString());
    for (final stroke in value) {
      if (stroke is! List || stroke.length < 2) continue;
      figure.polylines.add([
        for (final hip in stroke) _vertex((hip as num).toInt(), positions),
      ]);
    }
    if (figure.polylines.isNotEmpty) figures.add(figure);
  });
  return figures;
}

Vertex _vertex(int hip, Map<int, (double, double)> positions) {
  final position = positions[hip];
  if (position == null) return Vertex(hip, 0, 0);
  return Vertex(hip, position.$1, position.$2);
}
