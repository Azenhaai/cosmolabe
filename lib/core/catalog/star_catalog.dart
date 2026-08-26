import 'dart:convert';
import 'dart:typed_data';

import '../angles.dart';
import '../coordinates.dart';

/// The packed star catalogue, held as parallel typed arrays.
///
/// Deliberately not a `List<Star>`: fifteen thousand Dart objects would mean
/// fifteen thousand allocations and a pointer chase per star per frame. Flat
/// arrays keep the render loop reading contiguous memory.
class StarCatalog {
  StarCatalog._({
    required this.raDeg,
    required this.decDeg,
    required this.magnitude,
    required this.colorIndex,
    required this.pmRaMas,
    required this.pmDecMas,
    required this.hip,
    required this.constellationIds,
    required this.constellations,
    required this.names,
    required this.magnitudeLimit,
  }) : hipToIndex = {
          for (var i = 0; i < hip.length; i++)
            if (hip[i] != 0) hip[i]: i,
        };

  /// Right ascension in degrees at the J2000 epoch.
  final Float32List raDeg;

  /// Declination in degrees at the J2000 epoch.
  final Float32List decDeg;

  final Float32List magnitude;

  /// B−V colour index: negative is blue-white, positive is orange-red.
  final Float32List colorIndex;

  /// Proper motion in milliarcseconds per year, RA already carrying the
  /// cos(declination) factor.
  final Int16List pmRaMas;
  final Int16List pmDecMas;

  /// Hipparcos number, or zero. Constellation lines are drawn between these.
  final Int32List hip;

  /// One-based index into [constellations]; zero means no membership.
  final Uint8List constellationIds;

  final List<String> constellations;

  /// Display names, keyed by star index. Only a fifth of the catalogue has one.
  final Map<int, String> names;

  /// Faintest magnitude present in the file.
  final double magnitudeLimit;

  /// Reverse lookup for constellation line endpoints.
  final Map<int, int> hipToIndex;

  int get length => raDeg.length;

  /// Stars are stored brightest first, so a magnitude cut is a prefix.
  ///
  /// Returns the number of stars at or brighter than [limit] — the renderer
  /// iterates `0..cutoff` and never looks at the rest.
  int cutoffFor(double limit) {
    if (limit >= magnitudeLimit) return length;
    var low = 0;
    var high = length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (magnitude[mid] <= limit) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  Equatorial positionAt(int index) =>
      Equatorial(raDeg[index], decDeg[index]);

  String? nameAt(int index) => names[index];

  String? constellationAt(int index) {
    final id = constellationIds[index];
    return id == 0 ? null : constellations[id - 1];
  }

  /// Index of the star nearest to a direction, or null if nothing lies within
  /// [maxSeparationDeg]. Used for tap-to-identify and for star calibration.
  int? nearest(double targetRaDeg, double targetDecDeg,
      {double maxSeparationDeg = 2.0}) {
    var best = -1;
    var bestSeparation = maxSeparationDeg;
    for (var i = 0; i < length; i++) {
      final separation =
          angularSeparation(targetRaDeg, targetDecDeg, raDeg[i], decDeg[i]);
      if (separation < bestSeparation) {
        bestSeparation = separation;
        best = i;
      }
    }
    return best < 0 ? null : best;
  }

  /// Case-insensitive prefix search over the named stars, brightest first.
  List<int> search(String query, {int limit = 20}) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final matches = <int>[];
    // `names` is populated in catalogue order, which is already brightest
    // first, so the first hits are the ones a user is most likely to want.
    for (final entry in names.entries) {
      if (entry.value.toLowerCase().startsWith(needle)) {
        matches.add(entry.key);
        if (matches.length >= limit) break;
      }
    }
    return matches;
  }

  /// Parses the binary asset produced by `tool/build_catalog.dart`.
  factory StarCatalog.parse(ByteData data) {
    if (data.getUint8(0) != 0x53 ||
        data.getUint8(1) != 0x4D ||
        data.getUint8(2) != 0x41 ||
        data.getUint8(3) != 0x50) {
      throw const FormatException('not a cosmolabe catalogue');
    }
    final version = data.getUint16(4, Endian.little);
    if (version != 1) {
      throw FormatException('unsupported catalogue version $version');
    }

    final count = data.getUint32(6, Endian.little);
    final magnitudeLimit = data.getFloat32(10, Endian.little);

    final ra = Float32List(count);
    final dec = Float32List(count);
    final mag = Float32List(count);
    final ci = Float32List(count);
    final pmRa = Int16List(count);
    final pmDec = Int16List(count);
    final hip = Int32List(count);

    var offset = 14;
    for (var i = 0; i < count; i++) {
      ra[i] = data.getFloat32(offset, Endian.little);
      dec[i] = data.getFloat32(offset + 4, Endian.little);
      mag[i] = data.getInt16(offset + 8, Endian.little) / 100.0;
      ci[i] = data.getInt16(offset + 10, Endian.little) / 1000.0;
      pmRa[i] = data.getInt16(offset + 12, Endian.little);
      pmDec[i] = data.getInt16(offset + 14, Endian.little);
      hip[i] = data.getInt32(offset + 16, Endian.little);
      offset += 20;
    }

    final membership = Uint8List(count);
    for (var i = 0; i < count; i++) {
      membership[i] = data.getUint8(offset + i);
    }
    offset += count;

    final constellationCount = data.getUint16(offset, Endian.little);
    offset += 2;
    final constellations = <String>[];
    for (var i = 0; i < constellationCount; i++) {
      constellations.add(
        String.fromCharCodes([
          data.getUint8(offset),
          data.getUint8(offset + 1),
          data.getUint8(offset + 2),
        ]).trim(),
      );
      offset += 3;
    }

    final nameCount = data.getUint32(offset, Endian.little);
    offset += 4;
    final names = <int, String>{};
    for (var i = 0; i < nameCount; i++) {
      final index = data.getUint32(offset, Endian.little);
      final length = data.getUint8(offset + 4);
      offset += 5;
      names[index] = utf8.decode(
        data.buffer.asUint8List(data.offsetInBytes + offset, length),
      );
      offset += length;
    }

    return StarCatalog._(
      raDeg: ra,
      decDeg: dec,
      magnitude: mag,
      colorIndex: ci,
      pmRaMas: pmRa,
      pmDecMas: pmDec,
      hip: hip,
      constellationIds: membership,
      constellations: constellations,
      names: names,
      magnitudeLimit: magnitudeLimit,
    );
  }
}

/// Approximate sRGB colour for a B−V colour index.
///
/// Real stars span a narrow, desaturated range; pushing the saturation any
/// further makes the sky look like confetti rather than a sky.
({double r, double g, double b}) colorFromBv(double bv) {
  final t = bv.clamp(-0.4, 2.0);
  // Piecewise fit through the familiar spectral classes: blue-white O/B,
  // white A, yellow G, orange K, red M.
  if (t < 0.0) {
    final k = (t + 0.4) / 0.4;
    return (r: 0.61 + 0.11 * k, g: 0.70 + 0.07 * k, b: 1.0);
  }
  if (t < 0.4) {
    final k = t / 0.4;
    return (r: 0.83 + 0.17 * k, g: 0.87 + 0.11 * k, b: 1.0 - 0.10 * k);
  }
  if (t < 1.6) {
    final k = (t - 0.4) / 1.2;
    return (r: 1.0, g: 0.98 - 0.26 * k, b: 0.90 - 0.44 * k);
  }
  final k = (t - 1.6) / 0.4;
  return (r: 1.0, g: 0.72 - 0.12 * k, b: 0.46 - 0.14 * k);
}
