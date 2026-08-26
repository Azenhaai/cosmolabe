
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'constellation_lines.dart';
import 'star_catalog.dart';

/// Everything the renderer reads from the bundle, loaded once.
class SkyData {
  const SkyData({required this.catalog, this.constellations});

  final StarCatalog catalog;

  /// Null when the constellation asset is absent, which is a legitimate build:
  /// the atlas works without figures.
  final ConstellationLines? constellations;
}

/// Loads the packed catalogue from the app bundle, once.
///
/// Parsing 15,000 records takes a few milliseconds, but it happens during the
/// first frame, so the future is cached and every later caller gets the same
/// instance rather than a second copy in memory.
class CatalogLoader {
  CatalogLoader._();

  static const String starsAsset = 'assets/catalog/stars.bin';
  static const String constellationsAsset = 'assets/catalog/constellations.bin';

  static Future<SkyData>? _pending;

  static Future<SkyData> load() => _pending ??= _load();

  static Future<SkyData> _load() async {
    final starBytes = await rootBundle.load(starsAsset);
    final catalog = StarCatalog.parse(
      ByteData.sublistView(starBytes.buffer.asUint8List()),
    );

    ConstellationLines? constellations;
    try {
      final lineBytes = await rootBundle.load(constellationsAsset);
      constellations = ConstellationLines.parse(
        ByteData.sublistView(lineBytes.buffer.asUint8List()),
        catalog: catalog,
      );
    } on FlutterError {
      // Asset not bundled — draw the stars without the figures.
      constellations = null;
    } on FormatException catch (error) {
      // A corrupt figure file must not take the whole sky down with it.
      debugPrint('constellation data ignored: $error');
      constellations = null;
    }

    return SkyData(catalog: catalog, constellations: constellations);
  }

  /// Drops the cached data. Only useful in tests.
  static void reset() => _pending = null;
}
