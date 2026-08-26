import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../angles.dart';
import '../coordinates.dart';
import 'star_catalog.dart';

/// One stroke of a constellation figure: a run of stars joined end to end.
///
/// Figures are stored as polylines rather than loose segments because that is
/// how they are drawn and how they are authored — Orion's belt is one stroke,
/// not three unrelated pairs — and it removes the duplicated endpoints.
class ConstellationPolyline {
  const ConstellationPolyline({
    required this.hip,
    required this.raDeg,
    required this.decDeg,
    required this.starIndex,
  });

  /// Hipparcos number of each vertex, or 0 where the source gave only a
  /// position.
  final Int32List hip;

  /// J2000 position of each vertex, always present.
  ///
  /// Kept even when the star resolves, so a figure never breaks just because a
  /// vertex fell outside the magnitude cut of the shipped catalogue.
  final Float32List raDeg;
  final Float32List decDeg;

  /// Index into the star catalogue, or -1 when the vertex did not resolve.
  ///
  /// Resolved vertices are drawn from the catalogue so that proper motion
  /// carries the figure with the stars when the time machine runs far out.
  final Int32List starIndex;

  int get length => hip.length;
}

/// A named figure in the sky.
class ConstellationFigure {
  const ConstellationFigure({
    required this.abbreviation,
    required this.name,
    required this.polylines,
  });

  /// Three-letter IAU abbreviation, matching the star catalogue's own field.
  final String abbreviation;

  final String name;
  final List<ConstellationPolyline> polylines;

  /// Mean position of every vertex, for placing the label.
  ///
  /// Averaged as unit vectors rather than as angles: a plain mean of right
  /// ascension puts Pisces, which straddles zero hours, on the wrong side of
  /// the sky.
  Equatorial get centroid {
    var x = 0.0, y = 0.0, z = 0.0;
    var count = 0;
    for (final line in polylines) {
      for (var i = 0; i < line.length; i++) {
        final ra = line.raDeg[i] * degToRad;
        final dec = line.decDeg[i] * degToRad;
        final cosDec = math.cos(dec);
        x += cosDec * math.cos(ra);
        y += cosDec * math.sin(ra);
        z += math.sin(dec);
        count++;
      }
    }
    if (count == 0) return const Equatorial(0, 0);
    return Equatorial(
      normalizeDegrees(math.atan2(y, x) * radToDeg),
      math.atan2(z, math.sqrt(x * x + y * y)) * radToDeg,
    );
  }
}

/// The whole set of figures, as shipped.
class ConstellationLines {
  ConstellationLines(this.figures)
      : byAbbreviation = {
          for (final f in figures) f.abbreviation: f,
        };

  final List<ConstellationFigure> figures;
  final Map<String, ConstellationFigure> byAbbreviation;

  int get vertexCount => figures
      .expand((f) => f.polylines)
      .fold(0, (sum, line) => sum + line.length);

  /// Parses the binary asset written by `tool/build_constellations.dart`.
  ///
  /// [catalog] resolves Hipparcos numbers to catalogue rows; pass null to skip
  /// resolution and rely on the stored positions alone.
  factory ConstellationLines.parse(ByteData data, {StarCatalog? catalog}) {
    if (data.getUint8(0) != 0x43 || // 'C'
        data.getUint8(1) != 0x4C || // 'L'
        data.getUint8(2) != 0x49 || // 'I'
        data.getUint8(3) != 0x4E) {
      throw const FormatException('not a cosmolabe constellation file');
    }
    final version = data.getUint16(4, Endian.little);
    if (version != 1) {
      throw FormatException('unsupported constellation version $version');
    }

    var offset = 6;
    final figureCount = data.getUint16(offset, Endian.little);
    offset += 2;

    final figures = <ConstellationFigure>[];
    for (var f = 0; f < figureCount; f++) {
      final abbreviation = String.fromCharCodes([
        data.getUint8(offset),
        data.getUint8(offset + 1),
        data.getUint8(offset + 2),
      ]).trim();
      offset += 3;

      final nameLength = data.getUint8(offset);
      offset += 1;
      final name = utf8.decode(
        data.buffer.asUint8List(data.offsetInBytes + offset, nameLength),
      );
      offset += nameLength;

      final polylineCount = data.getUint16(offset, Endian.little);
      offset += 2;

      final polylines = <ConstellationPolyline>[];
      for (var p = 0; p < polylineCount; p++) {
        final vertexCount = data.getUint16(offset, Endian.little);
        offset += 2;

        final hip = Int32List(vertexCount);
        final ra = Float32List(vertexCount);
        final dec = Float32List(vertexCount);
        final index = Int32List(vertexCount);

        for (var v = 0; v < vertexCount; v++) {
          hip[v] = data.getInt32(offset, Endian.little);
          ra[v] = data.getFloat32(offset + 4, Endian.little);
          dec[v] = data.getFloat32(offset + 8, Endian.little);
          index[v] = catalog == null || hip[v] == 0
              ? -1
              : (catalog.hipToIndex[hip[v]] ?? -1);
          offset += 12;
        }

        polylines.add(ConstellationPolyline(
          hip: hip,
          raDeg: ra,
          decDeg: dec,
          starIndex: index,
        ));
      }

      figures.add(ConstellationFigure(
        abbreviation: abbreviation,
        name: name,
        polylines: polylines,
      ));
    }

    return ConstellationLines(figures);
  }
}
