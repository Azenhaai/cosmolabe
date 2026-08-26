// Converts the HYG star catalogue CSV into the compact binary asset the app
// ships. Run it from the project root:
//
//   dart run tool/build_catalog.dart path/to/hygdata_v41.csv
//
// The CSV is 32 MB of text; parsing that on a phone at every launch would cost
// seconds and a lot of garbage collection. The binary form is a few hundred
// kilobytes that loads straight into typed arrays.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Faintest star to include. Magnitude 7.0 is a little past what the darkest
/// skies show the naked eye, so there is headroom when zoomed in without
/// carrying the catalogue's full 120,000 entries.
const double magnitudeLimit = 7.0;

const int formatVersion = 1;
const int recordBytes = 20;

void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/build_catalog.dart <hygdata.csv>');
    exit(64);
  }

  final source = File(args.first);
  if (!source.existsSync()) {
    stderr.writeln('not found: ${source.path}');
    exit(66);
  }

  final rows = await source
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .toList();

  final header = _splitCsvLine(rows.first);
  final column = {for (var i = 0; i < header.length; i++) header[i]: i};

  int columnIndex(String name) {
    final index = column[name];
    if (index == null) throw StateError('missing column "$name"');
    return index;
  }

  final raColumn = columnIndex('ra');
  final decColumn = columnIndex('dec');
  final magColumn = columnIndex('mag');
  final ciColumn = columnIndex('ci');
  final pmRaColumn = columnIndex('pmra');
  final pmDecColumn = columnIndex('pmdec');
  final hipColumn = columnIndex('hip');
  final properColumn = columnIndex('proper');
  final bayerColumn = columnIndex('bayer');
  final flamColumn = columnIndex('flam');
  final conColumn = columnIndex('con');

  final stars = <_Star>[];
  final constellations = <String>[];
  final constellationIndex = <String, int>{};

  for (var i = 1; i < rows.length; i++) {
    final line = rows[i];
    if (line.isEmpty) continue;
    final fields = _splitCsvLine(line);

    final magnitude = double.tryParse(fields[magColumn]);
    if (magnitude == null || magnitude > magnitudeLimit) continue;

    final raHours = double.tryParse(fields[raColumn]);
    final dec = double.tryParse(fields[decColumn]);
    if (raHours == null || dec == null) continue;
    // The Sun sits at the origin with distance zero; it has its own routine.
    if (raHours == 0 && dec == 0) continue;

    final constellation = fields[conColumn].trim();
    var conId = 0;
    if (constellation.isNotEmpty) {
      conId = constellationIndex.putIfAbsent(constellation, () {
        constellations.add(constellation);
        return constellations.length;
      });
    }

    stars.add(_Star(
      raDeg: raHours * 15.0,
      decDeg: dec,
      magnitude: magnitude,
      colorIndex: double.tryParse(fields[ciColumn]) ?? 0.0,
      pmRaMas: double.tryParse(fields[pmRaColumn]) ?? 0.0,
      pmDecMas: double.tryParse(fields[pmDecColumn]) ?? 0.0,
      hip: int.tryParse(fields[hipColumn]) ?? 0,
      properName: fields[properColumn].trim(),
      bayer: fields[bayerColumn].trim(),
      flamsteed: fields[flamColumn].trim(),
      constellationId: conId,
    ));
  }

  // Brightest first: the renderer draws in catalogue order and stops early
  // once it passes the current magnitude limit, so sorting here saves a sort
  // at every frame.
  stars.sort((a, b) => a.magnitude.compareTo(b.magnitude));

  final builder = BytesBuilder();

  final head = ByteData(14);
  head.setUint8(0, 0x53); // 'S'
  head.setUint8(1, 0x4D); // 'M'
  head.setUint8(2, 0x41); // 'A'
  head.setUint8(3, 0x50); // 'P'
  head.setUint16(4, formatVersion, Endian.little);
  head.setUint32(6, stars.length, Endian.little);
  head.setFloat32(10, magnitudeLimit, Endian.little);
  builder.add(head.buffer.asUint8List());

  final records = ByteData(stars.length * recordBytes);
  for (var i = 0; i < stars.length; i++) {
    final star = stars[i];
    final offset = i * recordBytes;
    records.setFloat32(offset, star.raDeg, Endian.little);
    records.setFloat32(offset + 4, star.decDeg, Endian.little);
    records.setInt16(
        offset + 8, (star.magnitude * 100).round().clamp(-32768, 32767), Endian.little);
    records.setInt16(
        offset + 10, (star.colorIndex * 1000).round().clamp(-32768, 32767), Endian.little);
    records.setInt16(
        offset + 12, star.pmRaMas.round().clamp(-32768, 32767), Endian.little);
    records.setInt16(
        offset + 14, star.pmDecMas.round().clamp(-32768, 32767), Endian.little);
    records.setInt32(offset + 16, star.hip, Endian.little);
  }
  builder.add(records.buffer.asUint8List());

  // Constellation membership, one byte per star.
  final membership = Uint8List(stars.length);
  for (var i = 0; i < stars.length; i++) {
    membership[i] = stars[i].constellationId;
  }
  builder.add(membership);

  // Constellation abbreviations, three ASCII characters each.
  final conHeader = ByteData(2)..setUint16(0, constellations.length, Endian.little);
  builder.add(conHeader.buffer.asUint8List());
  for (final abbreviation in constellations) {
    builder.add(ascii.encode(abbreviation.padRight(3).substring(0, 3)));
  }

  // Names, only for the stars that have one.
  final named = <int, String>{};
  for (var i = 0; i < stars.length; i++) {
    final star = stars[i];
    final name = star.displayName;
    if (name != null) named[i] = name;
  }
  final nameHeader = ByteData(4)..setUint32(0, named.length, Endian.little);
  builder.add(nameHeader.buffer.asUint8List());
  named.forEach((index, name) {
    final bytes = utf8.encode(name);
    final entry = ByteData(5)
      ..setUint32(0, index, Endian.little)
      ..setUint8(4, bytes.length);
    builder.add(entry.buffer.asUint8List());
    builder.add(bytes);
  });

  final output = File('assets/catalog/stars.bin');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(builder.takeBytes());

  final kilobytes = (output.lengthSync() / 1024).toStringAsFixed(1);
  stdout.writeln('${stars.length} stars to magnitude $magnitudeLimit');
  stdout.writeln('${constellations.length} constellations');
  stdout.writeln('${named.length} named stars');
  stdout.writeln('wrote ${output.path} — $kilobytes KB');
}

class _Star {
  _Star({
    required this.raDeg,
    required this.decDeg,
    required this.magnitude,
    required this.colorIndex,
    required this.pmRaMas,
    required this.pmDecMas,
    required this.hip,
    required this.properName,
    required this.bayer,
    required this.flamsteed,
    required this.constellationId,
  });

  final double raDeg;
  final double decDeg;
  final double magnitude;
  final double colorIndex;
  final double pmRaMas;
  final double pmDecMas;
  final int hip;
  final String properName;
  final String bayer;
  final String flamsteed;
  final int constellationId;

  /// Prefers the common name, then the Bayer letter, then the Flamsteed
  /// number. Stars with none of the three stay anonymous and cost no bytes.
  String? get displayName {
    if (properName.isNotEmpty) return properName;
    if (bayer.isNotEmpty) return bayer;
    if (flamsteed.isNotEmpty) return flamsteed;
    return null;
  }
}

/// Minimal CSV splitter: the HYG file quotes only simple text fields and has
/// no embedded newlines, so a full parser would be dead weight.
List<String> _splitCsvLine(String line) {
  final fields = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buffer.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char == ',' && !inQuotes) {
      fields.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  fields.add(buffer.toString());
  return fields;
}
