# Cosmolabe

A gyroscope-driven star atlas: point the phone at the sky and see what is
there. Fully offline — the app makes no network requests at all.

Alongside the atlas sits a teaching module on finding your position by the sky,
from the compass to the sextant. Its design is in
[docs/navigation-school.md](docs/navigation-school.md).

`SkyDream` is the project name; the Dart package and bundle identifier are
still `starmap` / `com.azenha.starmap`, which is worth settling before anything
reaches a store.

## Status

The astronomical core, the star catalogue and the sensor bridges are done. The
renderer is not written yet.

| Layer | State |
| --- | --- |
| Time, sidereal time, obliquity, ΔT | done |
| Precession, proper motion, coordinate transforms, refraction | done |
| Sun, Moon (phase, parallax), planets | done |
| Star catalogue (15,598 stars, 88 constellations) | done |
| Attitude maths, smoothing, calibration | done |
| Device orientation bridge (iOS / Android) | written, **unverified on hardware** |
| Renderer | not started |
| Constellation lines | not started |
| Navigation school | designed, not started |

## Sensors

Both platforms hand Dart a quaternion already expressed in East-North-Up, so
nothing above `lib/sensors/` knows which phone it is running on. Neither
platform's raw sensor streams are touched: iOS `CMDeviceMotion` and Android
`TYPE_ROTATION_VECTOR` both run the manufacturer's own fusion, which is better
than anything reassembled on the Dart side.

The one difference that survives is which north they mean. iOS reports true
north via `xTrueNorthZVertical`; Android reports magnetic, so the declination
is applied in Dart.

**Unverified:** whether Core Motion's quaternion runs device-to-reference or
the other way round is not stated unambiguously in Apple's documentation, and
the frame correction in `ios/Runner/MotionBridge.swift` assumes the former. A
wrong guess shows up instantly as a sky that mirrors when you turn around. It
needs one evening outdoors with a known star to confirm or flip, and the fix is
a single line.

## Architecture

Everything the app draws is a pure function of a single value object,
`Observer`: latitude, longitude, elevation, UTC instant, and the handful of
settings that shift computed positions. GPS and the system clock only supply
*initial values* for it — they are never wired into the maths.

That one decision is what makes manual coordinate entry, the time machine, and
offline unit testing fall out for free instead of needing to be retrofitted.

```
lib/core/
  angles.dart              angle utilities, sexagesimal parsing and formatting
  julian.dart              Julian dates, sidereal time, ΔT, obliquity
  coordinates.dart         precession, proper motion, equatorial ↔ horizontal,
                           refraction, horizon dip
  observer.dart            the Observer value object and the projection chain
  bodies/sun.dart          solar position, twilight bands
  bodies/moon.dart         lunar position, phase, bright limb, parallax
  bodies/planets.dart      the seven visible planets
  catalog/star_catalog.dart  packed catalogue and lookups
  catalog/catalog_loader.dart  bundle loading
```

## Accuracy

Verified against the worked examples in Jean Meeus, *Astronomical Algorithms*
(2nd ed.). See `test/core/` — the reference values are cited by chapter.

| Quantity | Method | Accuracy |
| --- | --- | --- |
| Sidereal time, precession | rigorous | exact to the model |
| Sun | Meeus ch. 25, low accuracy | ~0.01° |
| Moon | Meeus ch. 47, full 60+60 term series | ~10″ longitude, ~4″ latitude |
| Planets | Standish Keplerian elements, 1800–2050 | a few arcminutes |
| Nutation | abbreviated series | ~0.5″ |

The planets are the weakest link. Standish's elements are a few arcminutes off
for Jupiter and Saturn, which is invisible at normal zoom but would show at
high magnification. Upgrading means a truncated VSOP87 series; the code is
structured so only `bodies/planets.dart` would change. Those coefficient tables
must be generated from an authoritative source file, not transcribed by hand.

Saturn's magnitude ignores the ring tilt, which swings its real brightness by
up to 0.8 magnitudes over its orbit.

## Building the catalogue

The binary asset is checked in, so this only needs rerunning if the magnitude
limit or record format changes.

```bash
curl -L -o hygdata_v41.csv \
  https://raw.githubusercontent.com/astronexus/HYG-Database/main/hyg/CURRENT/hygdata_v41.csv
dart run tool/build_catalog.dart hygdata_v41.csv
```

32 MB of CSV becomes a 346 KB binary of parallel typed arrays: 20 bytes per
star, sorted brightest first so a magnitude cut is a prefix rather than a
filter.

## Data sources and licensing

- **Stars** — the [HYG database](https://github.com/astronexus/HYG-Database)
  v4.1, CC BY-SA 4.0. Attribution is required and must appear in the app's
  credits screen before release.
- **Constellation lines** — not yet chosen. Stellarium's `constellationship.fab`
  is the obvious source but is GPL, which is incompatible with a closed app
  store binary. A public-domain or CC0 line set is needed instead.

## Tests

```bash
flutter test
```
