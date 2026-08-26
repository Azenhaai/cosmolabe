import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmolabe/core/angles.dart';
import 'package:cosmolabe/core/catalog/constellation_lines.dart';
import 'package:cosmolabe/core/catalog/star_catalog.dart';

/// Exercises the shipped asset, so a bad rebuild fails here rather than on a
/// phone at midnight.
void main() {
  late StarCatalog catalog;
  late ConstellationLines lines;

  setUpAll(() {
    catalog = StarCatalog.parse(
      ByteData.sublistView(File('assets/catalog/stars.bin').readAsBytesSync()),
    );
    lines = ConstellationLines.parse(
      ByteData.sublistView(
        File('assets/catalog/constellations.bin').readAsBytesSync(),
      ),
      catalog: catalog,
    );
  });

  group('Coverage', () {
    test('covers all 88 constellations', () {
      // Serpens is drawn as two disconnected figures, so there is one more
      // figure than there are constellations.
      final abbreviations =
          lines.figures.map((f) => f.abbreviation).toSet();
      expect(abbreviations, hasLength(88));
      expect(lines.figures.length, 89);
    });

    test('every abbreviation matches one the star catalogue knows', () {
      final known = catalog.constellations.toSet();
      for (final figure in lines.figures) {
        expect(known, contains(figure.abbreviation),
            reason: figure.abbreviation);
      }
    });

    test('Serpens is split into head and tail', () {
      final serpens =
          lines.figures.where((f) => f.abbreviation == 'Ser').toList();
      expect(serpens, hasLength(2));
      expect(
        serpens.map((f) => f.name),
        containsAll(['Serpens Caput', 'Serpens Cauda']),
      );
    });

    test('the familiar figures are all present and named', () {
      for (final entry in {
        'Ori': 'Orion',
        'UMa': 'Ursa Major',
        'UMi': 'Ursa Minor',
        'Cas': 'Cassiopeia',
        'Cru': 'Crux',
        'Lyr': 'Lyra',
      }.entries) {
        final figure = lines.byAbbreviation[entry.key];
        expect(figure, isNotNull, reason: entry.key);
        expect(figure!.name, entry.value);
      }
    });

    test('Orion has the belt and the shoulders', () {
      final orion = lines.byAbbreviation['Ori']!;
      final hips = {
        for (final line in orion.polylines)
          for (var i = 0; i < line.length; i++) line.hip[i],
      };
      // Betelgeuse, Rigel, Bellatrix, Saiph, and the three belt stars.
      for (final hip in [27989, 24436, 25336, 27366, 26311, 26727, 25930]) {
        expect(hips, contains(hip), reason: 'HIP $hip');
      }
    });
  });

  group('Vertices', () {
    test('nearly all resolve to a catalogue star', () {
      var total = 0;
      var resolved = 0;
      for (final figure in lines.figures) {
        for (final line in figure.polylines) {
          for (var i = 0; i < line.length; i++) {
            total++;
            if (line.starIndex[i] >= 0) resolved++;
          }
        }
      }
      expect(total, greaterThan(800));
      // A vertex that fails to resolve falls back to its stored position, so a
      // handful is harmless — a lot would mean the magnitude cut is wrong.
      expect(resolved / total, greaterThan(0.97));
    });

    test('resolved vertices sit on the star they claim', () {
      var worst = 0.0;
      for (final figure in lines.figures) {
        for (final line in figure.polylines) {
          for (var i = 0; i < line.length; i++) {
            final index = line.starIndex[i];
            if (index < 0) continue;
            expect(catalog.hip[index], line.hip[i]);
            final separation = angularSeparation(
              line.raDeg[i],
              line.decDeg[i],
              catalog.raDeg[index],
              catalog.decDeg[index],
            );
            if (separation > worst) worst = separation;
          }
        }
      }
      // Positions were taken from the catalogue at build time, so this is a
      // float32 rounding check rather than a real astronomical tolerance.
      expect(worst * 3600, lessThan(2.0));
    });

    test('every position is physically possible', () {
      for (final figure in lines.figures) {
        for (final line in figure.polylines) {
          for (var i = 0; i < line.length; i++) {
            expect(line.raDeg[i], inInclusiveRange(0.0, 360.0));
            expect(line.decDeg[i], inInclusiveRange(-90.0, 90.0));
          }
        }
      }
    });

    test('the line stars are naked-eye ones', () {
      final magnitudes = <double>[];
      for (final figure in lines.figures) {
        for (final line in figure.polylines) {
          for (var i = 0; i < line.length; i++) {
            final index = line.starIndex[i];
            if (index >= 0) magnitudes.add(catalog.magnitude[index]);
          }
        }
      }
      magnitudes.sort();
      final median = magnitudes[magnitudes.length ~/ 2];

      // The typical vertex is a properly bright star.
      expect(median, lessThan(4.5));
      // The faintest is around magnitude 6.6, in the sparse southern figures
      // — Mensa and its neighbours have nothing brighter to join up. Past the
      // catalogue's own cut would mean a bad match rather than a real vertex.
      expect(magnitudes.last, lessThan(catalog.magnitudeLimit));
    });

    test('no stroke is a single point', () {
      for (final figure in lines.figures) {
        for (final line in figure.polylines) {
          expect(line.length, greaterThanOrEqualTo(2),
              reason: figure.abbreviation);
        }
      }
    });
  });

  group('Centroids', () {
    test('label positions fall inside the figure they name', () {
      for (final figure in lines.figures) {
        final centroid = figure.centroid;
        var nearest = 999.0;
        for (final line in figure.polylines) {
          for (var i = 0; i < line.length; i++) {
            final separation = angularSeparation(
              centroid.raDeg,
              centroid.decDeg,
              line.raDeg[i],
              line.decDeg[i],
            );
            if (separation < nearest) nearest = separation;
          }
        }
        // Hydra sprawls a quarter of the way round the sky, so the tolerance
        // has to be generous; the point is that the label is not off in
        // another constellation entirely.
        expect(nearest, lessThan(35.0), reason: figure.abbreviation);
      }
    });

    test('Pisces does not have its label flung across the sky', () {
      // A plain mean of right ascension would put it near 180 degrees, on the
      // far side of the sphere, because Pisces straddles zero hours.
      final centroid = lines.byAbbreviation['Psc']!.centroid;
      final wrapped = normalizeDegreesSigned(centroid.raDeg);
      expect(wrapped.abs(), lessThan(45.0));
    });
  });

  test('the whole set stays small', () {
    expect(lines.vertexCount, greaterThan(800));
    expect(File('assets/catalog/constellations.bin').lengthSync(),
        lessThan(40 * 1024));
  });
}
