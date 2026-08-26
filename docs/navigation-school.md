# Navigation School — design

A teaching module about finding your position by the sky: the compass, the
mariner's astrolabe, the cross-staff, the sextant, and the rules that turned
them into positions. It ships twice — as pages on the website, and as live
instruments inside the app.

## Why this belongs here rather than in a museum

Every one of these instruments answers the same question: *where am I?* The app
already computes the true answer — it has the Sun, the Moon, the planets, 15,598
stars, and the observer's real coordinates from GPS.

That closes a loop nothing else can. The learner takes a sight, works out a
position the way a pilot did in 1500, and the app says how far off they were and
which step cost them the distance. A book cannot mark the work. A planetarium
cannot either, because it does not know where the reader is standing.

The engine for this is already built. A sextant is nothing more than *known sky*
plus *known device attitude*, which is exactly `Observer` plus `DeviceAttitude`.
Nothing new has to be invented; the instruments are a second face on the core.

## What the phone is honestly good at

This distinction shapes the whole module, so it goes in the copy, not just the
code.

| Measurement | Sensor doing the work | Realistic error |
| --- | --- | --- |
| **Altitude** above the horizon | accelerometer sensing gravity | **0.5°–1°** |
| **Azimuth** — a bearing | magnetometer sensing a weak, easily disturbed field | **5°–15°** |

Gravity is a strong, clean, local signal that nothing in a pocket disturbs. The
Earth's magnetic field is a hundred times weaker than the magnet in a phone case.

So altitude-based methods — latitude from Polaris, latitude from the noon Sun —
work respectably on a phone. Bearing-based methods do not, and the module should
say so plainly instead of pretending. That is not a disclaimer buried in a
footer: "why your compass lies" is one of the most interesting lessons here, and
the phone's own weakness is the demonstration.

A real sextant reads to one arcminute. The phone reads to about half a degree,
thirty times worse. The phone teaches the *method*; it does not replace the
instrument. Saying that earns trust rather than losing it.

## The instruments

Ordered so each one needs only what came before.

### 1. The compass — *agulha de marear*

**Answers:** which way am I facing?

**The catch:** magnetic north is not true north, the gap changes with place, and
it drifts with the years. Madeira sits at about 5° west today.

**Interactive:** two needles on one dial — magnetic and true — with the angle
between them labelled and the source named. Then a century slider: the
declination at Funchal from 1590 to now, which wanders by more than twenty
degrees. A pilot who ignored it put himself tens of miles off after a week's
sailing.

**Field exercise:** walk 200 m on a true bearing of 45°; GPS grades the result.

**The demonstration that lands:** bring a magnet, or a case with one, near the
phone and watch the needle lie. Variation is the Earth's fault; deviation is the
ship's iron. The phone has both problems, which makes it an honest teacher.

### 2. Latitude from Polaris — *Regimento do Norte*

**Answers:** how far north am I?

**The idea:** the altitude of the celestial pole equals your latitude. Measure
the pole, and you have it.

**The complication that makes it worth a lesson:** Polaris is not at the pole. It
sits three quarters of a degree away today — and in 1500 it was **three and a
half degrees** away, seven full Moon widths. So the correction depends on where
Polaris has rotated to, which you read from the Guards, the two stars Kochab and
Pherkad. The 15th-century regimento gives a correction for each of eight
positions of the Guards, described as parts of a human figure: head, shoulders,
arms, feet.

**Interactive:** point at Polaris. The app draws the Guards' current clock
position, names it the way the regimento did, gives the correction, and shows
the corrected latitude beside the GPS value. A time slider runs the correction
back through the centuries so the learner watches the problem grow into the
reason the rule existed.

**Why start here:** it needs only altitude, the measurement the phone is good
at, and it works any clear night without waiting for noon.

### 3. The mariner's astrolabe — *astrolábio náutico*

**Answers:** how far north am I, from the Sun?

**The instrument:** Portuguese, from the 1480s, stripped down from the scholar's
planispheric astrolabe into something usable on a heaving deck — a heavy cast
ring so the wind cannot spin it, and an alidade with two pinholes.

**The method:** measure the Sun's altitude at local noon, then

```
latitude = 90° − noon altitude + declination
```

with the declination read from a table. Those tables — the *Regimento do
Astrolábio e do Quadrante*, around 1509 — were the state secret that made the
method work.

**Interactive:** the app's own declination, computed rather than tabulated, sat
next to a facsimile table so the learner sees what the pilot was reading.

**Field exercise:** sight the noon Sun, compute the latitude, compare with GPS. A
good pilot managed half a degree to a degree — thirty to sixty nautical miles.
Matching that is the goal, and missing it by less is a genuine achievement.

**Safety, non-negotiable:** never sight the Sun directly. The exercise uses the
shadow method — hold the phone so the Sun casts the shadow of one edge, which is
how the astrolabe was actually used at sea. The app must refuse to run the
exercise in a mode that invites looking at the Sun, and must say why.

### 4. The quadrant

**Answers:** the same question, more cheaply.

Older and simpler than the astrolabe: a quarter circle, a plumb line, two
sights. The Portuguese trick was to mark it with *places* instead of degrees —
sail south until Polaris drops to the mark scratched for Lisbon, then turn.

**Interactive:** build your own quadrant. Mark it with the places that matter —
Funchal, Porto Santo, Lisboa — and it becomes a personal instrument rather than
a diagram.

### 5. The cross-staff and the backstaff — *balestilha*

**Answers:** the angle between the horizon and a star.

Slide the crosspiece until it just spans the gap. Cheap, quick, and it ruined
the eyesight of everyone who used it on the Sun, because you had to look at the
Sun and the horizon at once. John Davis's backstaff of 1594 fixed it by putting
the Sun behind the observer and measuring its shadow.

**Interactive:** two-point angle measurement — aim at the horizon, tap; aim at
the star, tap; the app gives the angle between. This is exactly what a gyroscope
does well, and it is the same gesture the instrument required.

### 6. The sextant

**Answers:** everything above, but properly.

Double reflection is the whole invention: the horizon and the star appear in one
field of view, and both move together when the ship rolls, so the reading holds
on a deck where an astrolabe is useless.

**The lesson is the corrections, not the instrument.** A raw sextant altitude is
wrong until you have subtracted index error, dip of the horizon, refraction,
semi-diameter and parallax. The app already computes the last three. The learner
applies them in order and watches the reading converge on the truth.

**Capstone exercise:** take altitudes of two stars, reduce both, plot the two
lines of position, and read a fix off the crossing. Compare with GPS. This is the
whole module in one task.

### 7. Longitude — the hard one

**Answers:** how far east or west am I? And for three centuries: nobody knows.

**Why it is hard, in one sentence:** latitude is a property of the sky where you
stand, but longitude is a *comparison* between here and somewhere else, so you
cannot find it without carrying that somewhere else with you — as a clock.

**The three answers:**

- **Dead reckoning** — course, speed, time. Interactive: the log line and the
  sandglass, a knot every 47 feet 3 inches, a 28-second glass. The app becomes
  the glass and the counter. Then a traverse board to record it, and a plot that
  shows the error compounding hour by hour.
- **Lunar distances** — the Moon moves against the stars about its own width
  every hour, so the sky is a clock if you can read it to an arcminute.
  Interactive: measure the angle from the Moon to a named star; the app inverts
  it for GMT and compares with the real GMT. This is where the phone's precision
  runs out in an instructive way — the learner discovers *why* the method needed
  an arcminute, by missing it.
- **The chronometer** — Harrison's H4, 1761. Interactive: a clock that drifts,
  and a map of where that drift puts you after six weeks at sea.

## Structure of a lesson

Every lesson uses the same five beats, so the shape becomes familiar:

1. **The question** it answers — one sentence.
2. **How it works** — a diagram, not a wall of text.
3. **Try it** — an interactive that runs in the browser or the app.
4. **Do it for real** — a field exercise with the phone, graded against GPS.
5. **What it cost to get wrong** — the historical anecdote. These are the hook,
   and they are why anyone finishes the lesson.

## Madeira

This is not a generic history section bolted onto a star atlas. Madeira is where
the story starts: found in 1419 by Zarco and Teixeira, one of the first results
of the programme run out of Sagres, and then the staging post and proving ground
for everything that went down the African coast afterwards. Funchal sits at
32° 38′ N — a number a 15th-century pilot could have found with an astrolabe to
within half a degree.

That gives the section a real reason to exist on a Madeira-facing site, and it
links outward to the trail content: walk up to Pico do Arieiro, 1,818 m and the
darkest easily reached sky on the island, and take the sight there.

## Website and app

**Website** — one static page per instrument, each with a canvas interactive
driven by mouse and touch, no sensors assumed. Strong search intent to serve:
*how to use an astrolabe*, *find latitude from Polaris*, *what is magnetic
declination*, *why was longitude so hard*. English and Portuguese.

**App** — the same lessons, but the interactives become the instruments, driven
by the sensors and graded against the truth. Plus a field mode: go outside, take
a sight, get a position.

The two share the astronomy. The site can be generated against the same core
compiled to WebAssembly, or against a small JSON export of the tables it needs;
that choice can wait until the app's instruments work.

## Build order

Each step ships something usable on its own.

1. **Latitude from Polaris.** Needs only altitude and the star catalogue, both
   done. Proves the whole grading loop end to end.
2. **The compass lesson.** Needs the world magnetic model, which the app wants
   anyway for the main sky view.
3. **The noon Sun and the astrolabe.** Needs solar declination, done, plus the
   shadow-sighting interaction.
4. **The sextant and the correction chain.** Needs refraction, dip, parallax and
   semi-diameter — all present in the core already.
5. **Two-star fix.** Needs line-of-position geometry, the one genuinely new
   piece of maths in the module.
6. **Longitude.** Dead reckoning first, lunar distances last, since that one is
   where the phone's accuracy becomes the lesson.

## Open questions

- **Historical declination.** The IGRF model reaches back to 1900. Going further
  needs the gufm1 model, which covers 1590 onwards. Worth the extra data for the
  century slider, or is 1900 enough?
- **Facsimile tables.** Reproducing a page of the 1509 regimento would be
  wonderful, and needs a source whose licensing is actually clear.
- **Portuguese first or English first?** The subject is Portuguese, the audience
  for the site is mixed, and the app store listings need both eventually.
