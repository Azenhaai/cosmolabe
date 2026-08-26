import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/sky_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _registerDataLicenses();
  // The sky fills the screen; system chrome only gets in the way, and a bright
  // status bar ruins dark adaptation.
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: [SystemUiOverlay.top],
  );
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const CosmolabeApp());
}

/// Adds the notices for the astronomical data to the licence page.
///
/// Flutter collects the licences of packages automatically, but the star
/// catalogue and the constellation figures are data files rather than
/// dependencies, so nothing would list them. The BSD licence on the figures
/// obliges us to reproduce its full text in the shipped binary's materials —
/// a one-line credit would not satisfy it.
void _registerDataLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final entry in {
      'HYG star catalogue': 'assets/licenses/hyg-database.txt',
      'Constellation figures': 'assets/licenses/constellation-figures.txt',
      'd3-celestial': 'assets/licenses/d3-celestial.txt',
      'World Magnetic Model': 'assets/licenses/world-magnetic-model.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks(
        [entry.key],
        await rootBundle.loadString(entry.value),
      );
    }
  });
}

class CosmolabeApp extends StatelessWidget {
  const CosmolabeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cosmolabe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A7BB5),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
        sliderTheme: const SliderThemeData(
          trackHeight: 2,
          showValueIndicator: ShowValueIndicator.never,
        ),
      ),
      home: const SkyScreen(),
    );
  }
}
