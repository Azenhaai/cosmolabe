import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmolabe/core/angles.dart';
import 'package:cosmolabe/core/catalog/star_catalog.dart';
import 'package:cosmolabe/core/observer.dart';

/// Exercises the real shipped asset rather than a fixture. If the packing tool
/// and the loader ever drift apart, these fail loudly.
void main() {
  late StarCatalog catalog;

  setUpAll(() {
    final bytes = File('assets/catalog/stars.bin').readAsBytesSync();
    catalog = StarCatalog.parse(ByteData.sublistView(bytes));
  });

  group('Catalogue integrity', () {
    test('holds the expected number of stars', () {
      expect(catalog.length, greaterThan(15000));
      expect(catalog.length, lessThan(16000));
    });

    test('covers exactly the 88 modern constellations', () {
      expect(catalog.constellations, hasLength(88));
      expect(catalog.constellations, contains('Ori'));
      expect(catalog.constellations, contains('UMa'));
      expect(catalog.constellations, contains('Cru'));
    });

    test('is sorted brightest first', () {
      for (var i = 1; i < catalog.length; i++) {
        expect(catalog.magnitude[i], greaterThanOrEqualTo(catalog.magnitude[i - 1]));
      }
    });

    test('every position is physically possible', () {
      for (var i = 0; i < catalog.length; i++) {
        expect(catalog.raDeg[i], inInclusiveRange(0.0, 360.0));
        expect(catalog.decDeg[i], inInclusiveRange(-90.0, 90.0));
        expect(catalog.magnitude[i], lessThanOrEqualTo(7.0));
      }
    });

    test('reaches magnitude 7', () {
      expect(catalog.magnitudeLimit, closeTo(7.0, 1e-6));
      expect(catalog.magnitude.last, greaterThan(6.9));
    });
  });

  group('Known stars', () {
    test('Sirius is the brightest star in the sky', () {
      expect(catalog.nameAt(0), 'Sirius');
      expect(catalog.magnitude[0], closeTo(-1.44, 0.02));
      expect(catalog.raDeg[0], closeTo(101.287, 0.01));
      expect(catalog.decDeg[0], closeTo(-16.716, 0.01));
      expect(catalog.constellationAt(0), 'CMa');
    });

    test('the ten brightest are the ones every atlas lists', () {
      final brightest = [
        for (var i = 0; i < 10; i++) catalog.nameAt(i),
      ];
      expect(
        brightest,
        containsAll(['Sirius', 'Canopus', 'Arcturus', 'Vega', 'Capella']),
      );
    });

    test('Polaris sits within a degree of the celestial pole', () {
      final index = catalog.hipToIndex[11767];
      expect(index, isNotNull);
      expect(catalog.decDeg[index!], closeTo(89.264, 0.01));
      expect(catalog.nameAt(index), 'Polaris');
    });

    test('Groombridge 1830 carries its large proper motion', () {
      // Barnard's Star would be the obvious choice, but at magnitude 9.5 it
      // falls outside the magnitude 7 cut. Groombridge 1830 is the fastest
      // star the naked eye can reach.
      final index = catalog.hipToIndex[57939];
      expect(index, isNotNull);
      expect(catalog.pmRaMas[index!], closeTo(4004, 2));
      expect(catalog.pmDecMas[index], closeTo(-5813, 2));
      expect(catalog.nameAt(index), 'Groombridge 1830');
    });

    test('proper motion survives the round trip into Int16', () {
      // The packed field would silently wrap past 32767 mas/yr; nothing in the
      // catalogue comes close, and this fails if that ever stops being true.
      for (var i = 0; i < catalog.length; i++) {
        expect(catalog.pmRaMas[i].abs(), lessThan(32000));
        expect(catalog.pmDecMas[i].abs(), lessThan(32000));
      }
    });

    test('Betelgeuse is red and Rigel is blue', () {
      final betelgeuse = catalog.hipToIndex[27989]!;
      final rigel = catalog.hipToIndex[24436]!;
      expect(catalog.colorIndex[betelgeuse], greaterThan(1.4));
      expect(catalog.colorIndex[rigel], lessThan(0.0));

      final red = colorFromBv(catalog.colorIndex[betelgeuse]);
      final blue = colorFromBv(catalog.colorIndex[rigel]);
      expect(red.r, greaterThan(red.b));
      expect(blue.b, greaterThan(blue.r));
    });
  });

  group('Magnitude cutoff', () {
    test('a naked-eye limit keeps a few thousand stars', () {
      final cutoff = catalog.cutoffFor(6.0);
      expect(cutoff, greaterThan(4000));
      expect(cutoff, lessThan(10000));
      expect(catalog.magnitude[cutoff - 1], lessThanOrEqualTo(6.0));
      expect(catalog.magnitude[cutoff], greaterThan(6.0));
    });

    test('a city limit keeps only the bright ones', () {
      expect(catalog.cutoffFor(3.0), lessThan(400));
    });

    test('the full limit keeps everything', () {
      expect(catalog.cutoffFor(7.0), catalog.length);
      expect(catalog.cutoffFor(99.0), catalog.length);
    });

    test('a limit brighter than Sirius keeps nothing', () {
      expect(catalog.cutoffFor(-2.0), 0);
    });
  });

  group('Search and identification', () {
    test('finds a star by the start of its name', () {
      final results = catalog.search('beteig');
      final betelgeuseByName = catalog.search('Bet');
      expect(betelgeuseByName, isNotEmpty);
      // The HYG spelling is "Betelgeuse"; the alternate spelling should miss.
      expect(results, isEmpty);
      expect(catalog.search('Vega'), isNotEmpty);
      expect(catalog.nameAt(catalog.search('Vega').first), 'Vega');
    });

    test('search is case-insensitive', () {
      expect(catalog.search('rigel'), isNotEmpty);
      expect(catalog.search('RIGEL'), isNotEmpty);
    });

    test('an empty query returns nothing rather than everything', () {
      expect(catalog.search(''), isEmpty);
      expect(catalog.search('   '), isEmpty);
    });

    test('identifies the star nearest a direction', () {
      final vega = catalog.hipToIndex[91262]!;
      final found = catalog.nearest(
        catalog.raDeg[vega] + 0.1,
        catalog.decDeg[vega] + 0.1,
      );
      expect(found, vega);
    });

    test('returns nothing when the sky there is empty', () {
      // A deliberately tight radius around a random direction.
      expect(
        catalog.nearest(45.0, -12.0, maxSeparationDeg: 0.02),
        isNull,
      );
    });
  });

  group('Projecting the catalogue', () {
    test('Polaris stands at the observer latitude, due north', () {
      final observer = Observer(
        latitudeDeg: madeiraPicoDoArieiro.latitudeDeg,
        longitudeDeg: madeiraPicoDoArieiro.longitudeDeg,
        elevationMeters: madeiraPicoDoArieiro.elevationMeters,
        utc: DateTime.utc(2026, 8, 12, 23, 0),
        applyRefraction: false,
      );
      final polaris = catalog.hipToIndex[11767]!;
      final sky = observer.project(catalog.positionAt(polaris));

      // Polaris is three quarters of a degree off the pole, so it circles the
      // true north point by that much over the course of a day.
      expect(sky.altitudeDeg, closeTo(observer.latitudeDeg, 0.8));
      expect(normalizeDegreesSigned(sky.azimuthDeg).abs(), lessThan(1.5));
    });

    test('the Southern Cross never rises from Madeira', () {
      final observer = Observer(
        latitudeDeg: madeiraPicoDoArieiro.latitudeDeg,
        longitudeDeg: madeiraPicoDoArieiro.longitudeDeg,
        utc: DateTime.utc(2026, 1, 1),
      );
      final acrux = catalog.hipToIndex[60718]!;
      for (var hour = 0; hour < 24; hour++) {
        final sky = observer
            .at(DateTime.utc(2026, 1, 1, hour))
            .project(catalog.positionAt(acrux));
        expect(sky.altitudeDeg, lessThan(0));
      }
    });

    test('the same star from Chile clears the horizon easily', () {
      final observer = Observer(
        latitudeDeg: -24.6,
        longitudeDeg: -70.4,
        elevationMeters: 2635,
        utc: DateTime.utc(2026, 5, 1, 3, 0),
      );
      final acrux = catalog.hipToIndex[60718]!;
      final sky = observer.project(catalog.positionAt(acrux));
      expect(sky.altitudeDeg, greaterThan(20));
    });

    test('projecting the whole catalogue stays quick', () {
      final observer = Observer(
        latitudeDeg: 32.735278,
        longitudeDeg: -16.928611,
        utc: DateTime.utc(2026, 8, 12, 23, 0),
      );
      final stopwatch = Stopwatch()..start();
      var aboveHorizon = 0;
      for (var i = 0; i < catalog.length; i++) {
        if (observer.project(catalog.positionAt(i)).isAboveHorizon) {
          aboveHorizon++;
        }
      }
      stopwatch.stop();

      // Roughly half the sky is up at any moment.
      expect(aboveHorizon, greaterThan(catalog.length ~/ 4));
      expect(aboveHorizon, lessThan(catalog.length * 3 ~/ 4));
      // A full pass must fit comfortably inside a frame budget even in debug
      // mode; the renderer will only ever project the visible subset.
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });
  });
}
