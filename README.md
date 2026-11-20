# Lorem Arcade

Four small puzzle and arcade games in one Android app, in one dark glass
style. Stars from every game add up and unlock color themes for all of them.

<p>
  <img src="docs/screenshots/hub.png" width="200" alt="Game hub">
  <img src="docs/screenshots/color_flow.png" width="200" alt="Color Flow">
  <img src="docs/screenshots/bead_belt.png" width="200" alt="Bead Belt">
  <img src="docs/screenshots/cog_clash.png" width="200" alt="Cog Clash">
  <img src="docs/screenshots/gate_drop.png" width="200" alt="Gate Drop">
</p>

## Games

### Color Flow
Tubes of colored blocks around a looping belt. Tap a tube to send its top run
onto the belt; blocks drop into the tube that fits them best. Sort every tube.

Seven modes: **Levels**, **Move limit**, **Timed**, **Daily puzzle** (with a
streak), **Endless**, **Belt full** (the belt starts full) and **Rush** (new
blocks keep arriving; clear full tubes before the belt overflows). Later
levels add locked blocks, hidden blocks and wild rainbow blocks.

### Bead Belt
A belt full of colored beads. Tap a bucket to put it in a free dock; it
scoops up beads of its color until it is full and leaves. Clear the belt
before it jams.

### Cog Clash
Buy gears and place them on a grid so they link to your weapon. Number gears
add power, 2x and 3x gears multiply it, and equal gears next to each other
merge. Then press Fight and watch your fighter take on the wave.

### Gate Drop
Hold and drag to pour balls from a cup through x2, x3 and x5 gates and past
lock bars. Every ball that reaches the pipe fires at the horde. Stop it
before it breaks through.

## Features

- 1 to 3 stars per level in every level-based mode; stars unlock themes
  (Neon, Pastel, Mono + shapes) and there is a color-blind palette.
- Progress is saved per game and per mode; an unfinished Color Flow level is
  restored after the app is closed.
- Sound effects and haptics, both can be turned off.
- Pause when the app goes to the background, and a confirm before leaving a
  level in progress.
- Screen reader labels in the menus and in Color Flow, scalable text and
  large touch targets.
- Works offline. No ads, no tracking, no accounts.

## Install

Download the latest APK from the
[Releases](https://github.com/KobeBrandt/lorem-arcade/releases) page and open
it on your Android phone (you may need to allow installs from your browser or
file manager). Needs Android 7.0 (API 24) or newer.

## Build from source

Needs [Flutter](https://docs.flutter.dev/get-started/install) 3.47 or newer
and the Android SDK.

```bash
flutter pub get
flutter run
```

Run the tests and the analyzer:

```bash
flutter test
flutter analyze
```

Build a release APK:

```bash
flutter build apk --release
```

### Release signing

Release builds are signed with the key described in `android/key.properties`
(not in git). It holds `storeFile`, `storePassword`, `keyAlias` and
`keyPassword`. Without that file, release builds fall back to the debug key
and Gradle prints a warning; such a build must not be published.

## Project layout

| Path | What |
|---|---|
| `lib/game/` | Color Flow: board rules, level generator and solver, the Flame game |
| `lib/games/bead_belt/`, `cog_clash/`, `gate_drop/` | The other three games |
| `lib/arcade/` | Shared level screen and game catalog for the hub games |
| `lib/ui/` | Hub, Color Flow screens, stats, themes, settings, shared widgets |
| `lib/audio/` | Sound effects, synthesized in Dart (`tool/make_sounds.dart`) |
| `test/` | Unit, game and widget tests |

## License

Copyright (C) 2026 KBrandt.dev

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the [LICENSE](LICENSE) file for details.
