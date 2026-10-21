# Argon B — v0.007 Combat Feedback & Staged Sinking Report (`combat_art.gd`)

## Scope & Allowlist Compliance
- Worktree: `C:/Users/bligh/Documents/Codex/2026-10-20/how/work/argon-b-combat`
- Authoritative source read: `C:/Users/bligh/Documents/Codex/2026-10-20/how/outputs/brass-tide` (`briefs/V0.007 TEAM CONTRACT.md`, `AGENTS.md`, `maps/PROJECT MAP.txt`, `HANDOFF.md`, `CODE MAP.md`, `maps/audio-effects.txt`, `game/scripts/combat_art.gd`, `game/scripts/combat_events.gd`, `game/scripts/chart.gd`, `game/scripts/boat_art.gd`, `game/scripts/weapon_art.gd`, `tools/boat_gallery.gd`, `tools/audit_boat_geometry.gd`).
- Files added in `work/argon-b-combat` (allowlist only):
  - `game/scripts/combat_art.gd`
  - `REPORT-V007-FX.md`
- All prior worktree files (`battle.gd`, `combat_events.gd`, `coast_migration.gd`, `mount_layout.gd`, `hull_profiles.gd`, tests, and prior reports) were left completely untouched.
- No engine or test processes were started.

---

## Exact Public API & Canvas Proxy

### `CombatArt` (`res://scripts/combat_art.gd`, `extends RefCounted`)
- **`const MAX_EFFECT_PRIMS: int = 35`**
- **`static func effect(chart, e: Dictionary) -> int`**
  - Preserves the `CombatArt.effect(self, effect)` call signature used by `chart.gd` while returning the emitted primitive count (`0..35`) for headless test/gallery inspection.
  - Purely visual and deterministic: reads numeric/string metadata from `e` without mutating `e`, gameplay state, RNG, camera, or audio.
  - Uses `_det_unit(seq, idx, salt)`, `_det_signed(seq, idx, salt)`, and `_det_angle(seq, idx, count, base, spread)` seeded from `e.seq` (fallback `e.id`) for deterministic spark, splinter, plume, and smoke angles.
  - Enforces a strict per-effect cap of `<= 35` primitives (`MAX_EFFECT_PRIMS = 35`) and validates every polygon via `Geometry2D.triangulate_polygon(pts)` before drawing.
- **`static func wreck(chart, w: Dictionary) -> int`**
  - Preserves the `CombatArt.wreck(self, wreck)` call signature used by `chart.gd` while returning the total emitted primitive count (`boat_prims + overlay_prims`).
  - Uses `chart.BoatArt` when present on `chart` (no circular `preload` of `Chart` or top-level `preload` of `BoatArt`), with a runtime `load("res://scripts/boat_art.gd")` fallback if invoked against a standalone `Recorder` mock.
- **`class FadeCanvas extends RefCounted`**
  - Recorder-compatible canvas proxy used to fade and water-tint sinking hull geometry in `wreck(chart, w)`.
  - Implements exact `CanvasItem` / `tools/boat_gallery.gd` `Recorder` methods and default arguments:
    - `draw_colored_polygon(points: PackedVector2Array, color: Color) -> void` (also skips degenerate polygons where `Geometry2D.triangulate_polygon(points).is_empty()`)
    - `draw_polyline(points: PackedVector2Array, color: Color, width: float = -1.0, _aa: bool = false) -> void`
    - `draw_line(from: Vector2, to: Vector2, color: Color, width: float = -1.0, _aa: bool = false) -> void`
    - `draw_circle(position: Vector2, radius: float, color: Color) -> void`
    - `draw_arc(center: Vector2, radius: float, start: float, end: float, point_count: int, color: Color, width: float = -1.0, _aa: bool = false) -> void`
    - `draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0) -> void`

---

## Supported Effect & Wreck Metadata Fields

### `effect(chart, e)` Fields Read
- **Timing & Placement**: `age` (`float`), `life` (`float`), `x` (`float`), `y` (`float`), `position` (`Vector2`), `height` (`float`, default `0.0`), `angle` (`float`, radians), `seq` / `id` (`int`).
- **Classification**: `kind` (`"fire"`, `"hit"`, `"miss"`, `"sink"`, `"engine"`), `type` (`"muzzle"`, `"hit"`, `"explosion"`, `"splash"`), `subtype` (`String`), `reason` / `cause` (`String`), `family` / `weaponFamily` (`"gun"`, `"cannon"`, `"rocket"`, `"torpedo"`), `material` (`"wood"`, `"armor"`, `"metal"`, `"engine"`, `"water"`, `"land"`), `hullMaterial` (`"wood"`, `"armor"`, `"metal"`).
- **Dimensions & Flags**: `magnitude` (`float`), `radius` (`float`), `length` (`float`), `width` (`float`), `splash` (`bool`), `land` (`bool`), `breach` (`bool`), `incendiary` (`bool`), `engineDamaged` (`bool`), `lod` (`int`, optional `0..2` override; otherwise derived from `chart.scale_factor` and `chart.tactical`).

### Visual Behavior by Effect Category & LOD Primitive Counts
1. **Muzzle Flashes & Weapon Launches (`kind == "fire"` or `type == "muzzle"`)**:
   - `gun`: Directional amber-orange muzzle spear polygon, inner white-hot core polygon + lance line, muzzle glow orb, angled muzzle-brake side prongs, cordite smoke puff, and deterministic forward powder sparks (`13 / 9 / 4` primitives at `LOD 0 / 1 / 2`).
   - `cannon`: Broad cannon blast cone, white-gold core, lateral concussion brake jets, shockwave arc, 4..1 billowing gun-smoke puffs, and burning powder ember streaks (`17 / 11 / 7` primitives at `LOD 0 / 1 / 2`).
   - `rocket`: Forward rack ignition cone plus rear venturi backblast cone (`-screen_dir`), propellant smoke clouds behind the launcher, and fiery propellant sparks (`15 / 9 / 6` primitives at `LOD 0 / 1 / 2`).
   - `torpedo`: Compressed-air mist cone at the waterline (`ground`), central air-slug streak, V-shaped water entry spray jets, entry ripple arc, and cavitation bubble beads (`11 / 7 / 5` primitives at `LOD 0 / 1 / 2`).
2. **Impact Sparks (`metal` AND `armor`) & Engine Hits**:
   - Triggered whenever `material` or `hullMaterial` is `"armor"`, `"metal"`, or `"engine"`, or `kind == "engine"` / `engineDamaged`.
   - Draws a 4-point metallic strike glint star polygon, white-hot core flash, deflection shock arc, angled ricochet slash, and `8 / 5 / 3` high-contrast gold-amber and white-steel spark streaks with glowing white-hot bead tips and sheared steel plate shards (`18..25 / 9..15 / 5..8` primitives at `LOD 0 / 1 / 2`).
   - Engine hits (`kind == "engine"` or `material == "engine"` or `engineDamaged`) add rising dark oily machinery smoke puffs and an internal orange short-circuit flare.
3. **Wood Splinters (`material == "wood"` when not armor/metal)**:
   - Draws a warm ochre splinter burst star, sawdust/breach smoke cloud, `3 / 2 / 1` spinning polygonal plank shards (`_shard_poly`), and `7 / 4 / 2` two-tone split-timber splinter streaks (`12..15 / 8..11 / 4..5` primitives at `LOD 0 / 1 / 2`).
   - Cannon/breach hits on wood or armor add an HE shell burst star, gunsmoke puffs, and hot friction embers.
4. **Rocket & Torpedo Blasts (`family in ["rocket", "torpedo"]` or `type == "explosion"`)**:
   - `rocket`: Dual-layer counter-rotating starburst fireball polygons, expanding blast wave arc, rising dark soot clouds, and incendiary spark streaks (`17..18 / 10..11 / 5..6` primitives at `LOD 0 / 1 / 2`).
   - `torpedo`: Sub-surface orange cavitation flash at the hull waterline, dual concentric foam shock rings, towering tapered whitewater geyser polygon, `6 / 4 / 2` vertical spray jets with foam caps, and upward-thrown hull fragments (`20 / 14 / 6` primitives at `LOD 0 / 1 / 2`).
5. **Water Plumes & Shoreline Impacts (`kind == "miss"` / `type == "splash"`)**:
   - Water misses scale column height by weapon family (`gun < cannon < rocket < torpedo`) with base foam collar, outer ripple ring, central tapered plume polygon, arched spray fan with droplet caps, and falling mist beads (`18..19 / 11..12 / 4..5` primitives at `LOD 0 / 1 / 2`).
   - Land/shoreline misses (`land == true` or `material == "land"`) draw sandy-ochre dust clouds, HE flash (for cannon/rocket), and flying stone clods + ricochet sparks (`9..10 / 6..7 / 3..4` primitives at `LOD 0 / 1 / 2`).
6. **Sink Effect (`kind == "sink"` or `subtype == "hull_down"`)**:
   - **Flooding (`reason == "flooding"` and not `incendiary`)**: **No fireball**; draws concentric water-surge rings, central engulfing water-swell polygon, radial spray jets, rising air-escape bubbles, and floating timber splinters (`19 / 12 / 7` primitives at `LOD 0 / 1 / 2`).
   - **Hull / Fire destruction (`reason != "flooding"` or `incendiary`)**: Draws water shockwave rings, jagged orange-red hull blast star + white-gold core, billowing dark smoke clouds, and flying hull shards/sparks (`17 / 11 / 7` primitives at `LOD 0 / 1 / 2`).

### `wreck(chart, w)` Fields Read & Staged Sinking Behavior
- **Fields read**: `x`, `y`, `angle`, `turretAngle`, `localAimAngles`, `size`, `spec`, `sinkProgress` (`0..1`), `age`, `listAngle`, `cause` / `reason` (`"hull"`, `"fire"`, `"flooding"`), `onFire`, `id` / `hull` / `seq`, and optional `lod`.
- **No Second Reflected Outline**:
  - Instead of shifting the boat to negative height (`h * (1 - t) - t * 12`) or allowing the submerged `h = 0` keel contact plate / `h = -3` hydrofoil foils to show through translucent upper decks, `wreck()` keeps the boat anchored at `w_pos`, advances the waterline upward (`waterline = lerpf(1.2, 16.0, clampf(t * 1.18, 0.0, 1.0))`), clamps `h_above = maxf(0.0, h - waterline) * v_scale`, tilts elevated geometry by `roll` (`listAngle`) and `pitch`, and sets `FadeCanvas.suppress_submerged_base = true` (`last_h <= 0.5` skipped) while fading `hull_alpha` and blending colors toward `WATER_TINT`.
- **Staged Sinking Overlays**:
  - **Hull / Fire Sinking (`cause != "flooding"` or `onFire`)**: Early hull-break blast star (`t < 0.36`), active deck flames (`t < 0.78`), rising dark smoke column transitioning to quenching steam (`t > 0.58`), gunwale foam surges, rising air bubbles, and drifting plank debris.
  - **Flooding Sinking (`cause == "flooding"` and not `onFire`)**: Omit fireballs and deck flames; draws waterline breach spray jets, expanding foam rings, dense escaping air-bubble streams, and floating timber flotsam.

---

## Verification & Untested Limits
- **Static & Structural Verification Performed**:
  - Verified all method signatures, parameter defaults, polygon non-degeneracy guards (`Geometry2D.triangulate_polygon`), primitive cap (`MAX_EFFECT_PRIMS = 35`), LOD monotonicity (`LOD 0 > LOD 1 > LOD 2`), and absence of circular preloads against authoritative `chart.gd`, `combat_events.gd`, `boat_art.gd`, `tools/boat_gallery.gd`, and `tools/audit_boat_geometry.gd`.
- **Tests Not Run (Per Contract)**:
  - Per `briefs/V0.007 TEAM CONTRACT.md` ("No engine starts... Root integrates and tests"), no Godot engine, headless test suite (`tools/check_game.py`), or gallery capture (`tools/boat_gallery.gd`) was executed in this helper turn.
  - Cosmetic battle-end visual tail progression after final kill remains owned by Root (`main.gd` / `battle.gd`).
