# Argon B — v0.006 Hull Chassis & Interchangeable Mount Socket Layout Report

## Allowlist & Isolation
Only the three allowlisted v0.006 files were created in `C:/Users/bligh/Documents/Codex/2026-10-20/how/work/argon-b-combat`:
1. `game/scripts/mount_layout.gd` (new, 234 lines — under the 300-line cap)
2. `game/tests/test_mount_layout.gd` (new, 134 lines)
3. `REPORT-MOUNTS.md` (new)

All prior v0.004 and v0.005 files (`game/scripts/battle.gd`, `game/scripts/combat_events.gd`, `game/tests/test_combat_events.gd`, `REPORT.md`, `game/scripts/coast_migration.gd`, `game/tests/test_map_revision.gd`, `REPORT-MAP.md`) and all Root-owned files (`refit.gd`, `boat_art.gd`, `main.gd`, `world.json`) remain untouched. No Godot engine or test processes were launched.

---

## Module API (`game/scripts/mount_layout.gd`)

`mount_layout.gd` (`extends RefCounted`) has zero external script dependencies and operates purely on dictionaries:

- **`hardpoints(spec: Dictionary) -> Array`**:
  Returns the hull's physical mount sockets (`2` for `size < 20.0`, `3` for `20.0 <= size < 28.0`, `4` for `size >= 28.0`), preserving `Refit.hardpoints(spec)` slot count, stable IDs (`mount0`..`mount3`), labels (`Main deck`, `Aft deck`, `Port deck`, `Starboard deck`), size thresholds (`_size(spec)` on `mount0`, `maxi(1, _size(spec) - 1)` on `mount1..3`), normal gun firing arcs (`TAU` on `mount0`/`mount1`, `PI * 1.25` on `mount2`/`mount3`), and socket outward angles (`0.0` bow, `PI` aft, `-PI / 2.0` port, `PI / 2.0` starboard).
  Each socket dictionary contains:
  - `id`: `"mount0"` | `"mount1"` | `"mount2"` | `"mount3"`
  - `label`: `"Main deck"` | `"Aft deck"` | `"Port deck"` | `"Starboard deck"`
  - `slot`: `"bow"` | `"aft"` | `"port"` | `"starboard"`
  - `size`: `int` (`1..3`)
  - `x`, `y`: world-unit socket center (`localX * hull_size(spec)`, `localY * hull_size(spec)`)
  - `localX`, `localY`: normalized deck-local coordinates (`x / size`, `y / size`)
  - `arc`: `TAU` (`mount0`, `mount1`) or `PI * 1.25` (`mount2`, `mount3`)
  - `angle`, `outwardAngle`: `0.0` (`mount0`), `PI` (`mount1`), `-PI / 2.0` (`mount2`), `PI / 2.0` (`mount3`)
  - `fixedArc`: `0.9`
  - `footprintRadius`, `worldFootprintRadius`: deck-local (`0.14..0.20`) and world-unit socket collar radius
  - `elevation`: deck plinth height hint (`11.0..13.5`)
  - `muzzleOffset`, `worldMuzzleOffset`: normalized (`0.36..0.52`) and world-unit barrel/tube origin offset
  - `originX`, `originY`, `worldOriginX`, `worldOriginY`: normalized and world-unit weapon origin hints along `angle`

- **`structure(spec: Dictionary) -> Dictionary`**:
  Returns normalized superstructure positions, dimensions, and non-overlapping footprints for `BoatArt`:
  - `hullId`, `role`, `archetype`, `faction`, `tier`, `size`, `fittingBudget`
  - `bounds`: `{sternX, bowX, halfBeam, minX: -1.80, maxX: 2.20, maxAbsY: 0.60|0.95, isCatamaran, catamaranOffset, demiBeam}`
  - `cabin` (and alias `bridge`): `{id: "cabin", kind: "rect", x: -0.32..-0.28, y: 0.0, length: 0.68..0.76, width: 0.48..0.60, len, wid, height, style, glass, upperLength, upperWidth, upperHeight, footprintRadius}`
  - `engine`: `{id: "engine", kind: "rect", x: -1.03..-0.98, y: 0.0, length: 0.32..0.38, width: 0.38..0.56, len, wid, height, style, stacks, vents, pods, footprintRadius}`
  - `stacks`: array of `{id, kind: "circle", x, y, radius, height}` inside the `x ~ -1.0` engine zone
  - `vents`: array of `{id, kind: "rect", x, y, length, width, len, wid, height, slats}` inside the `x ~ -1.0` engine zone
  - `masts`: array of `{x, y, height, pennant}`
  - `helm`: `{x, y, height}`
  - `footprints`: `[cabin, engine] + stacks + vents` for direct overlap checks
  - `sockets`: normalized socket array matching `hardpoints(spec)`

- **`weapon_aim(point: Dictionary, kind: String, original: bool = false) -> Dictionary`**:
  Returns `{arc, angle, fixed}` for `Refit.effective_spec` integration:
  - Normal turreted weapons (`gun`, `cannon`) and `original` (`stock_primary`) keep `point.arc` (`TAU` on bow/aft, `PI * 1.25` on sides) and `0.0 if original else point.angle`.
  - Fixed launchers (`not original and kind in ["rocket", "torpedo"]`) get `arc = minf(point.arc, 0.9)` and the socket's outward angle `point.outwardAngle` (`0.0` bow, `PI` aft, `-PI / 2.0` port, `PI / 2.0` starboard).

- **`mounts_of(spec: Dictionary) -> Array`**:
  Normalizes fitted `spec.weaponMounts` (world-unit `x, y` divided by `size`) or bare-hull primary weapon on `mount0` into boat-local mount dicts with `id, kind, x, y, worldX, worldY, angle, arc, scale, footprintRadius, elevation, muzzleOffset, originX, originY` so `BoatArt` needs no hidden legacy mount coordinates.

- **`footprint_clearance(socket: Dictionary, item: Dictionary) -> float`**:
  Signed deck-local clearance between a circular socket footprint and a rectangular or circular structure footprint (`> 0.0` means strictly disjoint).

- **`hull_size(spec)`**, **`_size(spec)` / `mount_tier(spec)`**, **`_budget(spec)` / `fitting_budget(spec)`**, **`archetype(spec)`**:
  Exact size-threshold and fitting-budget helpers matching `Refit`.

---

## Deck Zone Separation (All 24 Hulls)
Longitudinal deck zones ( stern `-x` -> bow `+x` ) are strictly disjoint across all 8 roles and all 24 canonical hulls:
1. **Aft socket (`mount1`)**: center `localX in [-1.53, -1.46]`, `localY = 0.0`, `footprintRadius in [0.16, 0.18]` -> spans `[-1.71, -1.28]` (inside `-1.80` stern bound).
2. **Engine / stacks / vents (`engine`)**: center `x in [-1.03, -0.98]`, `length in [0.32, 0.38]` -> spans `[-1.22, -0.79]` (clear of `mount1` aft and `cabin` forward).
3. **Compact bridge (`cabin`)**: center `x in [-0.32, -0.28]`, `length in [0.68, 0.76]`, `width in [0.48, 0.60]` -> spans `[-0.70, +0.10]`.
4. **Side sockets (`mount2` port, `mount3` starboard)**: center `localX in [0.47, 0.53]`, `localY in ∓[0.42, 0.445]` (monohull) or `∓[0.54, 0.58]` (catamaran), `footprintRadius in [0.14, 0.15]` -> spans `x in [0.32, 0.68]` and `|y| + r <= 0.60` (monohull) / `<= 0.73 <= 0.95` (catamaran).
5. **Main / bow socket (`mount0`)**: center `localX in [0.96, 1.08]`, `localY = 0.0`, `footprintRadius in [0.16, 0.20]` -> spans `[0.76, 1.28]` (inside `+2.20` bow bound).

---

## Root Integration Notes
- In `game/scripts/refit.gd`:
  - `const Layout = preload("res://scripts/mount_layout.gd")`
  - `static func hardpoints(spec: Dictionary) -> Array: return Layout.hardpoints(spec)`
  - In `effective_spec`: use `var aim: Dictionary = Layout.weapon_aim(point, module.kind, original)` (or `"angle": 0.0 if original else point.angle`) so fixed launchers on `mount1..3` use the socket outward angle (`0.0` bow, `PI` aft, `±PI / 2.0` sides) while normal guns retain their full `point.arc`.
- In `game/scripts/boat_art.gd`:
  - `mounts_of(spec)` can delegate to `Layout.mounts_of(spec)`, and `_superstructure` / socket ring rendering can read `Layout.structure(spec)` (`cabin`, `engine`, `stacks`, `vents`, `masts`, `helm`, `sockets`).

---

## Test Suite (`game/tests/test_mount_layout.gd`)
Ready for Root to run headlessly:
- Loads `res://data/world.json` and checks all 24 canonical hulls in `world.HULLS`.
- Verifies exact hardpoint counts, `mount0..3` IDs, labels, size thresholds, fitting budgets, normal gun arcs, and outward angles against `Refit`.
- Verifies every socket (including `footprintRadius`) lies inside `x in [-1.8, 2.2]`, `|y| <= 0.60` (monohulls) / `0.95` (catamarans), and hull-specific `bounds`.
- Verifies zero overlap (`footprint_clearance > 0.04`) between every socket and `cabin`, `engine`, `stacks`, and `vents`, plus non-overlap between `cabin` and `engine` and between every socket pair.
- Verifies `weapon_aim` fixed-launcher outward angles (`0`, `PI`, `±PI/2`), `mounts_of` bare/fitted normalization without hidden coordinates, caller immutability, and `Deployment.cost` preservation.
