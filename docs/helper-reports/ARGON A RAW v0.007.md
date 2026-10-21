# v0.007 Helper Report — Stern Propulsion & Machinery Art (`motor_art.gd`)

## 1. Delivered Allowlist Files
- `game/scripts/motor_art.gd`
- `REPORT-V007-MOTORS.md`

No other files in `work/argon-a-boats` or the authoritative repository were modified, reset, or deleted.

## 2. Public API & Entry Points
`game/scripts/motor_art.gd` (`extends RefCounted`) exposes:
- `static func layout(spec: Dictionary, boat: Dictionary = {}) -> Dictionary`
  - Pure, deterministic layout query that never mutates `spec` or `boat`.
  - Reads the exact transom station `HullProfiles.stations(spec)[0].x` (`transomX`, negative boat-local `x`, with `+x` toward the bow) and half-beam `HullProfiles.stations(spec)[0].y` (`transomHalfBeam`).
- `static func draw(ctx: Dictionary, spec: Dictionary, boat: Dictionary = {}, palette: Dictionary = {}) -> void`
  - Renders all stern propulsion units, transom steering tie-bars/tillers, and aft machinery details onto `ctx.canvas` using `ctx.proj` and increments `ctx.n`, `ctx.npoly`, `ctx.nline`, and `ctx.ncirc`.
  - Reuses `WeaponArt._box`, `WeaponArt._face`, `WeaponArt._line`, and `WeaponArt._p` so every polygon face is emitted as a non-degenerate triangle culled when `absf((p[i] - p[0]).cross(p[i + 1] - p[0])) < 1.0`.

## 3. Exact Supported Metadata (`layout(spec, boat={})`)
### Top-Level Return Dictionary Keys
- `hullId` (`String`), `role` (`String`), `archetype` (`String`), `faction` (`String`), `tier` (`int`), `size` (`float`)
- `isSmallHull` (`bool`: `size <= 18.5`), `isCatamaran` (`bool`: `archetype == "catamaran"` or `role == "raider"`)
- `transomX` / `sternX` (`float`: exact `float(HullProfiles.stations(spec)[0].x)`)
- `transomHalfBeam` (`float`: exact `float(HullProfiles.stations(spec)[0].y)`)
- `engineId` (`String`: resolved from `boat.loadout.engine`, `spec.loadout.engine`, `engineModule`/`engineId`, or inferred from `spec.fuelUse`: `"stock_engine"`, `"economy_drive"`, `"boost_drive"`, `"heavy_drive"`)
- `engineHealth` (`float`: `0.0..1.0` from `boat.engine` or `spec.engineHealth`)
- `propulsion` / `family` (`String`: `"outboard"` on small hulls, `"stern_drive"` or `"nozzle"` on heavier hulls)
- `kind` (`String`: `"single_outboard"`, `"twin_outboard"`, `"twin_stern_drive"`, `"triple_stern_drive"`, `"twin_nozzle"`, `"triple_nozzle"`)
- `count` / `motorCount` (`int`: `1`, `2`, or `3`)
- `beyondStern` (`bool`: `true`, verifying `minX < transomX`)
- `minX` (`float`: aft-most local coordinate `< transomX`), `maxX` (`float`: forward-most bracket coordinate `<= transomX + 0.03`)
- `aftSocketClearance` (`float`: minimum clearance in boat-local units from `mount1` aft weapon socket via `Layout.footprint_clearance`), `minSocketClearance` (`float`: minimum clearance across all `Layout.hardpoints(spec)`), `clearsSockets` (`bool`)
- `units` / `motors` / `drives` (`Array[Dictionary]`): per-unit stern motor descriptors
- `machinery` (`Array[Dictionary]`): aft quarter transfer gearboxes (`kind = "transfer_gearbox"` on heavier hulls) and engine-bay exhaust manifolds (`kind = "exhaust_manifold"`)
- `components` (`Dictionary`): `{"cowling": true, "vents": true, "bands": true, "bracket": true, "lowerLeg": true, "propellerHousing": true, "exhaust": true}`

### Per-Unit Dictionary Keys (`units[i]`)
- `id` (`"motor0"`, `"motor1"`, ...), `index` (`int`), `kind` (`"outboard" | "stern_drive" | "nozzle"`), `configuration` (`String`)
- `x`, `y`, `z`, `transomX`, `minX`, `maxX`, `length`/`len`, `width`/`wid`, `height`, `scale`, `steerAngle`, `worldX`, `worldY`
- `aftSocketClearance`, `socketClearance`
- Sub-component dictionaries:
  - `cowling`: `{"x", "y", "zMin", "zMax", "length", "width", "height", "style"}`
  - `vents`: `{"x", "y", "z", "slats", "length", "width"}`
  - `bands`: `{"x", "y", "z", "count", "width"}`
  - `bracket`: `{"x", "y", "zMin", "zMax", "length", "width"}`
  - `lowerLeg`: `{"x", "y", "zMin", "zMax", "length", "width", "plateZ"}`
  - `propellerHousing`: `{"x", "y", "zMin", "zMax", "length", "width", "radius", "blades", "shrouded"}`
  - `exhaust`: `{"x", "y", "z", "ports", "radius"}`

## 4. Hull Roster Coverage & Socket Clearance
- **Small Hulls (`size < 19.0`, 9 hulls)**:
  - `bilge_punt` (13.0) and `marsh_dart` (14.0): single centerline outboard (`single_outboard`, upgraded to twin when fitted with `heavy_drive`).
  - `tin_skiff` (14.0), `lantern_skiff` (15.0), `scab_cutter` (17.0), `gale_cutter` (18.0), `harbor_sloop` (17.0), `reed_stinger` (17.0): twin outboards (`twin_outboard`).
  - `silt_lugger` (17.0 catamaran): twin outboards centered on the port/starboard demi-hull transoms (`y = ±0.62`).
- **Heavier Hulls (`size >= 19.0`, 15 hulls)**:
  - `hook_raider` (20.0) and `mercantile_clipper` (23.0): catamaran demi-hull twin nozzles / stern drives (`y = ±0.62`) plus aft machinery.
  - `ash_corvette` (21.0), `aegis_corvette` (24.0), `krill_torpedo` (20.0), `slag_gunboat` (22.0), `bellows_gunboat` (26.0), `barbed_lance` (20.0), `cinder_monitor` (25.0), `cobalt_frigate` (24.0): twin stern drives or shrouded nozzles (`count = 2`) plus port/starboard stern-quarter transfer gearboxes and engine-bay exhaust manifolds.
  - `manta_strike` (24.0, tier 4), `wraith_rocket` (29.0, tier 4), `furnace_turret` (30.0, tier 4), `iron_bastion` (31.0, tier 3), `maiden_dreadnought` (36.0, tier 4): triple stern drives / shrouded Kort nozzles (`count = 3`) plus stern-quarter transfer gearboxes and engine-bay exhaust manifolds.
- **Socket Clearance**:
  - Transom brackets end at `transomX + 0.03` (`<= -1.83`), well aft of `mount1` (`localX in [-1.53, -1.46]`, `footprintRadius in [0.16, 0.18]`, aft edge `>= -1.71`).
  - Stern-quarter transfer gearboxes sit at `|y| >= 0.28` (`±0.62` on catamarans) and are filtered through `Layout.footprint_clearance(socket, item) >= 0.05`.
  - No weapon sockets are moved and no working weapons are added.

## 5. LOD Scaling & Primitive Budget
- **LOD 0 (Close)**: Full 3D cowling + hood cap + intake scoop, wrap bands + brass pinstripes, 4 louver vents, transom bracket + clamp bolts/hydraulic trim rams, lower leg + cavitation plate, gearcase/nozzle shroud + 3 rotating propeller blades, exhaust housing + speed wash, tie-bar, and aft machinery (~60–196 primitives across 1–3 motor hulls; strictly `<= 250`).
- **LOD 1 (Medium)**: Simplified cowling + cap, wrap band, 2 louver slats, bracket, lower leg + cavitation plate, gearcase/nozzle + 2 blades, exhaust housing, tie-bar, and simplified aft machinery (~34–110 primitives).
- **LOD 2 (Far)**: 2 boxes + 2 lines per propulsion unit, omitting small deck machinery (~14–42 primitives across 1–3 motor hulls; strictly `<= 50`).
- Primitive count strictly decreases (`LOD 0 > LOD 1 > LOD 2`) on every hull.

## 6. Limitations & Untested Items
- Per contract instructions, no Godot engine instances, headless test suites, or GPU/software captures were launched in this helper worktree (`work/argon-a-boats` is on an older baseline and root owns integration into `boat_art.gd` and all native test/geometry/gallery runs).
- Root integration into `boat_art.gd` should call `MotorArt.draw(ctx, spec, boat, c)` inside `BoatArt.draw_boat` and remove the legacy `for pod in engine.pods:` loop in `BoatArt._superstructure` as noted in the brief.
