# Native Navigation Port & Content Name Review (`v0.001`)

## What Changed
- `game/scripts/navigation.gd:1-298`: Ported `dist/navigation.js:1-37` to pure `RefCounted` static GDScript (`create`, `is_water`, `find_path`, plus `isWater`/`findPath` aliases). Keeps dictionary keys camelCase (`width`, `height`, `cell`, `clearance`, `cols`, `rows`, `islands`, `nodes`, `edges`) and island vertices as `[x, y]` float arrays (`navigation.gd:145-167`). Precomputes island AABBs (`minX`, `minY`, `maxX`, `maxY`) and 8-way neighbor edges with diagonal corner-cut protection (`navigation.gd:206-208`). Tightened line-of-sight clearance sampling (`_clear`, `navigation.gd:96-129`) from 8-unit steps (`dist/navigation.js:8`) to 2-unit steps (`CLEAR_STEP = 2.0`) with AABB broadphase so long smoothed segments cannot clip sharp polygon vertices between samples.
- `game/tests/test_navigation.gd:1-162`: Added `SceneTree` headless test suite covering direct open-water routing, island detours, blocked/non-finite (`NAN`/`INF`) coordinates, solid barriers, diagonal corner-cut rejection, 3-cell shore attachment, `<5000` node bound (`cell=1` -> 3410 nodes), and full 8-island / 10-port / 19-route / 45-port-pair Shatter Coast world verification (`world.json` with fallback).
- `game/assets/chart-mark.svg:1` & `game/assets/compass.svg:1`: Created two original vector chart icons matching the brass-and-teal palette.

## What Ran
- `Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/test_navigation.gd`: Passed all generic checks, 10 ports, 19 routes, and 45 port pairs in ~1.8s (exit code 0).

## Content Name Overlap Review (Blood Wake)
- Audited all 4 factions, 24 hulls, 8 islands, 10 ports, and 8 missions against Blood Wake's roster.
- `krill_torpedo.name` (`content.js:353`): `"Razorback Torpedo Boat"` overlapped Blood Wake's `"Razorback"` gunboat. Recommended original replacements (Root edits data only): **`"Tallowfin Torpedo Boat"`** (already adopted in `outputs/brass-tide/game/data/world.json:341`), **`"Krillspine Torpedo Boat"`**, or **`"Brinebarb Torpedo Boat"`**.
- `marsh_dart.name` (`world.json:111`): `"Marsh Dart Hydro"` is distinct, though Blood Wake had a boat named `"Hydro"`; if zero token overlap is desired, **`"Marsh Dart Planer"`** is a clean alternative.
