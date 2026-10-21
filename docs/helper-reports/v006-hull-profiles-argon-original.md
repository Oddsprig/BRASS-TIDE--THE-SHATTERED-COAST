# Argon B — v0.006 Hull Identity Profiles Report (`hull_profiles.gd`)

## Allowlist & Isolation
Only the two allowlisted files for this follow-up were created in `C:/Users/bligh/Documents/Codex/2026-10-20/how/work/argon-b-combat`:
1. `game/scripts/hull_profiles.gd` (new, 208 lines — under the 250-line limit)
2. `REPORT-HULL-PROFILES.md` (new)

All prior v0.004, v0.005, and v0.006 files (`game/scripts/battle.gd`, `game/scripts/combat_events.gd`, `game/tests/test_combat_events.gd`, `REPORT.md`, `game/scripts/coast_migration.gd`, `game/tests/test_map_revision.gd`, `REPORT-MAP.md`, `game/scripts/mount_layout.gd`, `game/tests/test_mount_layout.gd`, `REPORT-MOUNTS.md`) and all Root-owned files (`boat_art.gd`, `refit.gd`, `main.gd`, `world.json`) remain untouched. No Godot engine or test processes were launched, and no tests are claimed executed.

---

## Exact Code API (`game/scripts/hull_profiles.gd`)

`hull_profiles.gd` (`extends RefCounted`) is a pure static module with **zero external script dependencies** (no `BoatArt`, `MountLayout`, or `Refit` preload or cycle):

### Constants
- `CAT_OFFSET: float = 0.62` (matches `BoatArt.CAT_OFFSET` and `MountLayout.CAT_OFFSET`)
- `_ROLE_ARCH: Dictionary` (`skiff -> speedboat`, `cutter -> hydrofoil`, `torpedo -> hydrofoil`, `raider -> catamaran`, `corvette -> patrol`, `gunboat -> armored`, `rocket -> monitor`, `cruiser -> command`)
- `_ROLE_DEFAULT_ID: Dictionary` (fallback canonical hull ID per role when an unknown hull ID is passed)
- `_HULL_ORDER: Array` (all 24 canonical hull IDs in `world.json` order)
- `_PROFILES: Dictionary` (keyed by all 24 canonical hull IDs)

### Static Functions
- **`hull_ids() -> Array`**:
  Returns a duplicate array of the 24 canonical hull IDs in `world.json` order.
- **`has_hull(id: String) -> bool`**:
  Returns `true` if `id` is one of the 24 canonical hull IDs in `_PROFILES`.
- **`archetype(spec) -> String`**:
  Accepts either a `spec: Dictionary` or a hull ID `String`. Returns the exact archetype string (`speedboat`, `hydrofoil`, `catamaran`, `patrol`, `armored`, `monitor`, `command`) matching `BoatArt.archetype(spec)` and `MountLayout.archetype(spec)`.
- **`stations(spec) -> Array`**:
  Accepts either a `spec: Dictionary` or a hull ID `String`. Returns a duplicated `Array` of 8 `Vector2(x, half_beam)` points ordered strictly stern-to-bow (`stations[0].x < ... < stations[7].x`, `stations[7].y == 0.0`).
- **`width_at(stations_or_spec, x: float) -> float`**:
  Accepts either a `stations: Array` or a `spec` (`Dictionary` / `String`) and linearly interpolates `half_beam` at longitudinal coordinate `x` (matching `BoatArt._width_at`).
- **`deck_half_width_at(spec, x: float, inset: float = 1.0) -> float`**:
  Returns `width_at(spec, x) * inset` for monohulls, or `CAT_OFFSET + width_at(spec, x) * inset` for catamarans (`archetype(spec) == "catamaran"`).
- **`profile(spec) -> Dictionary`**:
  Accepts either a `spec: Dictionary` or a hull ID `String`. Returns a fresh deep-copied profile dictionary containing:
  - `id: String` (`spec.get("id", hid)`)
  - `hullId: String` (resolved canonical ID in `_PROFILES`)
  - `name: String`
  - `faction: String` (`compact` | `forge` | `reed` | `raiders`)
  - `role: String` (`skiff` | `cutter` | `torpedo` | `raider` | `corvette` | `gunboat` | `rocket` | `cruiser`)
  - `archetype: String` (`speedboat` | `hydrofoil` | `catamaran` | `patrol` | `armored` | `monitor` | `command`)
  - `tier: int` (`1..4`, preserving `spec.get("tier")`)
  - `size: float` (`8.0..48.0`, preserving `spec.get("size")`)
  - `mountTier: int` (`1` if `size < 19.0`, `2` if `size < 27.0`, else `3`)
  - `fittingBudget: int` (`clampi(8 + maxi(0, tier - 1) * 3 + int(maxf(0.0, size - 13.0) * 0.75), 8, 36)`)
  - `isCatamaran: bool` (`archetype == "catamaran"`)
  - `catamaranOffset: float` (`0.62` if `isCatamaran` else `0.0`)
  - `sternX: float` (`stations[0].x`, in `[-2.10, -1.86]`)
  - `bowX: float` (`stations[-1].x`, in `[2.00, 2.30]`)
  - `halfBeam: float` and `maxHalfBeam: float` (maximum station `y`: `0.58..0.88` for monohulls, `0.24..0.27` demi-hull half-beam for catamarans)
  - `outerHalfBeam: float` (`CAT_OFFSET + maxHalfBeam` for catamarans, `maxHalfBeam` for monohulls)
  - `beam: float` (`outerHalfBeam * 2.0`)
  - `stations: Array` (fresh duplicate of 8 `Vector2(x, half_beam)` stations, stern-to-bow)
  - `bridgeStyle: String` and `cabinStyle: String` (unique per-hull bridge style identifier across all 24 hulls)
  - `bridge: Dictionary` and `bridgeShape: Dictionary` (`{x, len, wid, h, glass, visor}` kept inside the central bridge zone `x in [-0.31, -0.28]`, `len in [0.66, 0.76]`, `wid in [0.46, 0.60]`)
  - `deckAccents: Array` and `accents: Array` (2 hull-specific accent dicts `{kind, x, y, len, wid, h}` per hull)
  - `cargoDetails: Array` and `cargo: Array` (2 hull-specific cargo/locker dicts `{kind, x, y, len, wid, h}` per hull)
  - `spanDeck: Dictionary` (`{"minX": -1.72, "maxX": 1.38, "halfWidth": 0.62}` for catamarans, `{}` for monohulls)

---

## All 24 Canonical Hull Profiles & Geometric Bounds

| # | Hull ID | Name | Role / Archetype | Tier / Size | `sternX` | `bowX` | `maxHalfBeam` | `bridgeStyle` |
|---|---|---|---|---|---|---|---|---|
| 1 | `tin_skiff` | Tinwake Skiff | `skiff` / `speedboat` | T1 / 14 | `-1.86` | `2.02` | `0.60` | `open_windscreen` |
| 2 | `bilge_punt` | Bilgewater Punt | `skiff` / `speedboat` | T1 / 13 | `-1.90` | `2.14` | `0.62` | `scout_cowl` |
| 3 | `lantern_skiff` | Lantern Ward Skiff | `skiff` / `speedboat` | T2 / 15 | `-1.96` | `2.08` | `0.65` | `customs_canopy` |
| 4 | `marsh_dart` | Marsh Dart Hydro | `cutter` / `hydrofoil` | T1 / 14 | `-1.86` | `2.16` | `0.60` | `stepped_cockpit` |
| 5 | `scab_cutter` | Scabfin Cutter | `cutter` / `hydrofoil` | T2 / 17 | `-1.92` | `2.06` | `0.63` | `sawtooth_cowl` |
| 6 | `gale_cutter` | Galeblade Interceptor | `cutter` / `hydrofoil` | T3 / 18 | `-2.02` | `2.24` | `0.65` | `interceptor_canopy` |
| 7 | `silt_lugger` | Silt Runner Lugger | `raider` / `catamaran` | T1 / 17 | `-1.88` | `2.02` | `0.25` (demi) | `estuary_span` |
| 8 | `hook_raider` | Grapnel Blockade Runner | `raider` / `catamaran` | T2 / 20 | `-1.96` | `2.15` | `0.24` (demi) | `runner_gantry` |
| 9 | `mercantile_clipper` | Sovereign Armed Packet | `raider` / `catamaran` | T3 / 23 | `-2.06` | `2.26` | `0.27` (demi) | `packet_house` |
| 10 | `harbor_sloop` | Breakwater Patrol Sloop | `corvette` / `patrol` | T1 / 17 | `-1.86` | `2.04` | `0.62` | `brass_wheelhouse` |
| 11 | `ash_corvette` | Ashwake Escort Corvette | `corvette` / `patrol` | T2 / 21 | `-1.94` | `2.10` | `0.68` | `turtleback_conning` |
| 12 | `aegis_corvette` | Vanguard Line Corvette | `corvette` / `patrol` | T3 / 24 | `-2.02` | `2.22` | `0.66` | `rangefinder_bridge` |
| 13 | `reed_stinger` | Fen Stinger Torpedo Launch | `torpedo` / `hydrofoil` | T2 / 17 | `-1.88` | `2.14` | `0.62` | `low_stinger_hood` |
| 14 | `krill_torpedo` | Tallowfin Torpedo Boat | `torpedo` / `hydrofoil` | T3 / 20 | `-1.96` | `2.18` | `0.65` | `wolfpack_hood` |
| 15 | `manta_strike` | Manta Flotilla Leader | `torpedo` / `hydrofoil` | T4 / 24 | `-2.05` | `2.28` | `0.70` | `manta_command_fin` |
| 16 | `slag_gunboat` | Slagclast River Gunboat | `gunboat` / `armored` | T2 / 22 | `-1.87` | `2.01` | `0.75` | `ironclad_casemate` |
| 17 | `bellows_gunboat` | Bellows Siege Gunboat | `gunboat` / `armored` | T3 / 26 | `-1.96` | `2.08` | `0.78` | `siege_citadel` |
| 18 | `furnace_turret` | Furnace Sovereign Monitor | `gunboat` / `armored` | T4 / 30 | `-2.06` | `2.16` | `0.85` | `bastion_cupola` |
| 19 | `barbed_lance` | Sparkrack Rocket Scow | `rocket` / `monitor` | T2 / 20 | `-1.86` | `2.00` | `0.80` | `scow_blast_cab` |
| 20 | `cinder_monitor` | Pyreclast Rocket Monitor | `rocket` / `monitor` | T3 / 25 | `-1.95` | `2.06` | `0.88` | `pyre_bunker` |
| 21 | `wraith_rocket` | Hellbore Salvo Cruiser | `rocket` / `monitor` | T4 / 29 | `-2.04` | `2.18` | `0.84` | `hellbore_fire_tower` |
| 22 | `cobalt_frigate` | Cobalt Commodore Frigate | `cruiser` / `command` | T2 / 24 | `-1.96` | `2.18` | `0.66` | `commodore_tower` |
| 23 | `iron_bastion` | Bastion Armored Cruiser | `cruiser` / `command` | T3 / 31 | `-2.04` | `2.24` | `0.73` | `flagship_citadel` |
| 24 | `maiden_dreadnought` | Shatter Throne Dreadnought | `cruiser` / `command` | T4 / 36 | `-2.10` | `2.30` | `0.81` | `throne_pagoda` |

---

## Deck Clearance & Structural Alignment with `MountLayout` and `BoatArt`
- **Longitudinal bounds**: Every hull satisfies `sternX in [-2.10, -1.85]` (`-2.10..-1.86`) and `bowX in [2.00, 2.30]` (`2.00..2.30`). Even after `BoatArt`'s `0.94` inset-deck x-scaling (`[-1.974..-1.748, +1.880..+2.162]`), both `mount1` (`x ~ -1.50, r <= 0.18`, aft edge `-1.71`) and `mount0` (`x ~ +1.02, r <= 0.20`, fore edge `+1.28`) lie strictly inside the clear deck.
- **Lateral beam at side sockets (`x in [0.47, 0.53]`)**:
  - On all 21 monohulls, `width_at(spec, 0.50) >= 0.58` (and on all `size >= 20` monohulls with `mount2`/`mount3`, `width_at(spec, 0.50) >= 0.63 > 0.445 + 0.15 = 0.595`), so side socket centers (`|y| <= 0.445`) sit inside the `0.84` inset deck and full socket collars (`|y| + r <= 0.595`) sit inside the hull beam.
  - On all 3 catamarans (`silt_lugger`, `hook_raider`, `mercantile_clipper`), `stations` stay demi-hull width (`0.16..0.27`), centered at `±CAT_OFFSET` (`±0.62`), giving outer half-beam `0.85..0.88 > 0.56 + 0.14 = 0.70` at `x = 0.52`, with `spanDeck` covering `x in [-1.72, 1.38], y in [-0.62, 0.62]`.
- **Non-overlapping accents and cargo details**:
  - Foredeck accents are placed at `x in [1.48, 1.68]` (forward of `mount0` at `x <= 1.28`).
  - Quarterdeck cargo/lockers are placed at `x in [-1.32, -1.25], |y| in [0.25, 0.42]` (laterally and longitudinally clear of `mount1` at `x = -1.50, y = 0` and `engine` at `x = -1.00, y = 0`).
  - Waist strakes/sponsons/belts are placed at `x in [-0.30, 0.18], |y| in [0.42, 0.64]` (outboard of `bridge` half-width `<= 0.30` and aft of `mount2`/`mount3` at `x >= 0.32`).

---

## Untested Limits (Root Owns Numerical / Engine Verification)
Per instructions, **no Godot process or headless test was run** in this worktree. Root owns numerical verification and integration:
1. **GDScript parse & headless test execution**: `game/scripts/hull_profiles.gd` has not been loaded by the Godot binary yet.
2. **`BoatArt` triangulation audit (`--qa-geometry`)**: Station arrays are strictly increasing in `x` with positive `y` up to `stations[7].y == 0.0`, designed for `BoatArt._outline`, but actual `Geometry2D.triangulate_polygon` checks across all headings/skews remain for Root's test runner.
3. **`MountLayout. sternX` synchronization**: `MountLayout._ROLE_TABLE` in `game/scripts/mount_layout.gd` (which is off-allowlist in this turn) still lists role-level `sternX` values `-1.74..-1.80` for `bounds.sternX`, whereas `HullProfiles.profile(spec).sternX` uses the new per-hull `-1.86..-2.10` range; Root should read `HullProfiles.stations(spec)` / `HullProfiles.profile(spec)` in `BoatArt` (and optionally align `MountLayout` bounds if desired during integration).
