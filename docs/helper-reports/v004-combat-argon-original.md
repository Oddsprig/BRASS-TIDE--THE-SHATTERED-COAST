# Argon B — v0.004 Typed Combat Events & Effect Source Report

## Summary
Implemented the v0.004 typed combat event queue, enriched effect descriptors, persistent wreck records, and per-mount shot timestamps in isolation within `C:/Users/bligh/Documents/Codex/2026-10-20/how/work/argon-b-combat`, strictly adhering to the file allowlist and preserving all v0.001–v0.003 battle, tactics, campaign, and numerical APIs.

## Files Modified / Created (Allowlist Only)
1. `game/scripts/combat_events.gd` (**New**) — Bounded combat event emitter, effect builder, wreck lifecycle helper, and per-mount shot timestamp tracker (`CombatEvents`).
2. `game/scripts/battle.gd` (**Modified**) — Integrated `CombatEvents` into `Battle.create`, `Battle.step`, `_fire`, `_projectiles`, `_blast`, `_record_wreck`, and `_cleanup_dead`; added `Battle.pop_events(st)`, `Battle.mount_shot_time(ship, mount_id)`, `Battle.mount_shot_age(ship, mount_id, now)`, `Battle.hull_material(ship)`, and `Battle.weapon_family(weapon_id)`.
3. `game/tests/test_combat_events.gd` (**New**) — Self-contained SceneTree headless test script validating event emission, `pop_events(st)` drain semantics, weapon families/variants, hit/miss/land/water materials, engine failure transitions, hull/flooding sink events, wreck sinking progression, per-mount shot timestamps, and 40-boat `300 v 300` queue/effect/wreck bounds.
4. `REPORT.md` (**New**) — This implementation report.

---

## Implemented APIs & Schemas

### 1. Event Queue & `Battle.pop_events(st)`
- **State fields in `Battle.create()`**:
  - `st.events`: `Array` of queued event dictionaries (hard-capped at `CombatEvents.MAX_EVENTS = 256`; oldest dropped if unpopped).
  - `st.stepEvents`: `Array` of events emitted during the most recent `Battle.step(st, ...)` call (hard-capped at `CombatEvents.MAX_STEP_EVENTS = 128`).
  - `st.eventSeq`: Monotonically increasing integer sequence counter (`1, 2, 3, ...`).
  - `st.eventCounts`: Cumulative dictionary `{"fire": int, "hit": int, "miss": int, "sink": int, "engine": int}`.
- **`Battle.pop_events(st: Dictionary) -> Array`**:
  - Returns a shallow copy (`duplicate()`) of `st.events` and clears `st.events` so each event is consumed once by sound/visual systems.
- **Common Event Schema** (all 5 event types: `"fire"`, `"hit"`, `"miss"`, `"sink"`, `"engine"`):
  - `id`, `seq`, `sequence`: Strictly increasing monotonic `int` (`>= 1`).
  - `type`, `kind`: `"fire" | "hit" | "miss" | "sink" | "engine"`.
  - `subtype`: Specific event subtype (`"light_gun"`, `"heavy_cannon"`, `"direct"`, `"blast"`, `"water"`, `"land"`, `"hull"`, `"flooding"`, `"engine_out"`, etc.).
  - `time`: Battle timestamp (`float`, `st.time`).
  - `team`, `side`: `"player"` or `"enemy"` (emitted for **all** deployed boats on both teams).
  - `family`, `weaponFamily`: `"gun" | "cannon" | "rocket" | "torpedo"`.
  - `projectileKind`: `"bullet" | "shell" | "rocket" | "torpedo"`.
  - `weapon`, `weaponId`: Weapon identifier (`"machine_gun"`, `"heavy_cannon"`, `"torpedo_launcher"`, etc.).
  - `tier`: `"light" | "heavy"`.
  - `source`, `sourceId`, `sourceHull`, `sourceRole`, `sourceFaction`: Firing/attacker boat metadata.
  - `target`, `targetId`, `targetHull`, `targetRole`, `targetFaction`, `targetTeam`: Target/victim boat metadata (`""` when N/A).
  - `mount`, `mountId`, `slot`, `mountArc`: Mount slot (`"bow"`, `"port"`, `"starboard"`, `"stern"`, `"turret"`, or `"hull"`/`"engine"`).
  - `position`: `Vector2(x, y)` plus scalar `x` and `y` (`float`).
  - `direction`: Normalized `Vector2` plus `angle` (`float` radians).
  - `magnitude`: Normalized intensity `float` (`0.15` to `2.5`) for audio/camera/particle scaling.
  - `material`: Surface/medium material (`"wood" | "armor" | "water" | "land" | "engine" | "metal"`).
- **Per-Event Extra Fields**:
  - `"fire"`: `salvoCount`, `muzzleSpeed`, `recoil`, `smokeRadius`, `flashLength`, `flashWidth`, `wakeWidth`.
  - `"hit"`: `damage`, `Direct` (`bool`), `breachAdded` (`bool`), `fireAdded` (`bool`), `engineFailed` (`bool`), `hullRatio` (`0..1`), `armorTier` (`int`), `armorId` (`String`), `woodChips` (`bool`), `sparks` (`bool`).
  - `"miss"`: `reason` (`"water" | "land" | "expired"`), `splash` (`bool`), `land` (`bool`), `splashRadius` (`float`), `columnHeight` (`float`).
  - `"engine"`: `reason` (`"damage"`), `engineRatio` (`0.0`), `smokeRadius` (`float`), `sparks` (`bool`).
  - `"sink"`: `cause` (`"hull" | "flooding"`), `killerId` (`String`), `sinkDuration` (`float`), `foamRadius` (`float`).

### 2. Enriched Visual Effect Records (`st.effects`)
- Preserves existing keys (`x`, `y`, `type` in `{"muzzle", "hit", "explosion", "splash"}`, `age`, `life`) for full backward compatibility with v0.001–v0.003 rendering and tests, while adding:
  - `position` (`Vector2`), `direction` (`Vector2`), `angle` (`float`)
  - `family` (`"gun" | "cannon" | "rocket" | "torpedo"`), `weapon`, `tier` (`"light" | "heavy"`), `kind`, `subtype`
  - `team`, `source`, `sourceId`, `target`, `targetId`, `mount`, `mountId`
  - `material` (`"wood" | "armor" | "water" | "land" | "engine" | "metal"`), `magnitude`
  - Geometry/style hints for Argon A / Root renderer: `radius`, `length`, `width`, `height`, `recoil`, `smoke`, `fragments`, `reason`, `splash`, `land`, `expired`
- Capped at `CombatEvents.MAX_EFFECTS = 200`.

### 3. Persistent Wreck & Sinking Metadata (`st.wrecks`)
- Preserves existing keys (`x`, `y`, `angle`, `radius`, `length`, `beam`, `color`, `team`) and adds:
  - `id`, `uid`, `type`, `hull`, `role`, `faction`, `archetype`, `spec`, `turretAngle`, `material`
  - `cause` (`"hull"` vs `"flooding"`), `killerId`, `killerFamily`, `killerMount`, `sunkAt`
  - `age`, `sinkDuration` (`2.2s`), `sinkProgress` (`0.0 -> 1.0`), `sinking` (`bool`, transitions to `false` when settled), `listAngle`, `foamRadius`, `breaches`, `onFire`
- `CombatEvents.tick_wrecks(st, dt)` advances `age`, `sinkProgress`, and `sinking` each `Battle.step`.
- Capped at `CombatEvents.MAX_WRECKS = 64`.

### 4. Per-Mount Shot Timestamps
- Firing updates each deployed ship's mount timestamp tracking:
  - `ship.mountShotTimes[mount_id] = st.time` (also indexed under `mount_index` and `"slot_<i>"`).
  - `ship.weaponShotTimes[weapon_id] = st.time` and `ship.weaponShotTimes[family] = st.time`.
  - `ship.lastShotTime = st.time`, `ship.lastShotMount = mount_id`, `ship.lastShotFamily = family`, `ship.battleTime = st.time`.
  - `mount_entry.lastShotTime = st.time`, `mount_entry.shotCount += 1`, `mount_entry.lastShotFamily = family`, `mount_entry.lastWeaponId = weapon_id`.
- Helper queries on both `Battle` and `CombatEvents`:
  - `Battle.mount_shot_time(ship, mount_id) -> float` (`-1.0` if never fired).
  - `Battle.mount_shot_age(ship, mount_id, now) -> float` (`INF` if never fired).

### 5. Shoreline vs Open-Water Miss Distinction & RNG Integrity
- Separated `_island_blocked(st, start, end)` from `_blocked(st, start, end)` in `battle.gd` so projectiles intersecting an island record their exact shoreline impact position `start + delta * land_t` with `material = "land"` and `reason = "land"`, whereas projectiles reaching `p.life <= 0.0` or map bounds emit a water splash (`material = "water"`, `reason = "expired"`, `splash = true`).
- Zero changes to `st.rng` call count or order in `Battle` or `Damage`, ensuring deterministic parity with existing campaign/tactics/combat tests.
- Ephemeral engine/hit trackers (`_engineTracker`, `_hitTracker`) live on `st` rather than mutating campaign boat dictionaries, keeping `st.reserves` and campaign saves clean for `SaveValidation`.

---

## Verification & Execution Note
- **No Godot engine or test processes were launched** per the owner/lead background-serialization rule (`NO engine/test launches; root serializes tests`).
- Root can run the new test suite directly via:
  - `<godot_console_exe> --headless --path C:/Users/bligh/Documents/Codex/2026-10-20/how/work/argon-b-combat/game -s res://tests/test_combat_events.gd`
  - `<godot_console_exe> --headless --path C:/Users/bligh/Documents/Codex/2026-10-20/how/work/argon-b-combat/game -s res://tests/test_battle.gd`
  - `<godot_console_exe> --headless --path C:/Users/bligh/Documents/Codex/2026-10-20/how/work/argon-b-combat/game -s res://tests/test_tactics.gd`
