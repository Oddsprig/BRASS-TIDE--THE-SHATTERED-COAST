# Argon B — v0.005 Coast Migration & Save Revision Report (`REPORT-MAP.md`)

## 1. Summary & Scope Compliance
Implemented the v0.005 save revision validation and legacy coast migration module in isolation inside `C:/Users/bligh/Documents/Codex/2026-10-20/how/work/argon-b-combat`.

- **Allowlist strictly respected**:
  - `game/scripts/coast_migration.gd` (**New**)
  - `game/tests/test_map_revision.gd` (**New**)
  - `REPORT-MAP.md` (**New**)
- **Prior v0.004 files untouched**: `game/scripts/battle.gd`, `game/scripts/combat_events.gd`, `game/tests/test_combat_events.gd`, and `REPORT.md` were not modified.
- **No engine/test processes launched**: Zero Godot, Python, or Node processes were started; Root serializes all execution.
- **No `Campaign` dependency in module**: `game/scripts/coast_migration.gd` preloads only `res://scripts/save_validation.gd`, `res://scripts/navigation.gd`, and `res://scripts/money.gd`.

---

## 2. Public Interface & Exact Symbols (`game/scripts/coast_migration.gd`)

### Entry Point
- `static func prepare(saved: Dictionary, world: Dictionary, nav: Dictionary) -> Dictionary`
  - Returns `{"ok": bool, "state": Dictionary, "message": String}`.
  - Never mutates caller `saved`, `world`, or `nav` dictionaries.
  - On refusal, returns `{"ok": false, "state": {}, "message": "<detailed reason>"}`.

### Constants
- `LEGACY_MAP_REVISION: int = 1`
- `CURRENT_MAP_REVISION: int = 2`
- `DEFAULT_CAMPAIGN_SCALE: float = 4.0`
- `DOCK_RADIUS: float = 65.0`
- `MIN_SNAP_RADIUS: float = 180.0`
- `MAX_SNAP_RADIUS: float = 360.0`
- `SNAP_CELL_FACTOR: float = 2.25`
- `FALLBACK_LEGACY_MAP: Dictionary` (used only if `world` does not yet contain the `"LEGACY_MAP"` key; when `world.has("LEGACY_MAP")`, `world["LEGACY_MAP"]` is strictly validated and used).

### Internal Static Helpers
- `_parse_save_revision(saved: Dictionary) -> Dictionary`: Treats missing `saved.mapRevision` as `1`; requires any present `mapRevision` to be a finite whole number (`int` or whole-valued `float`, rejecting `bool`, `String`, `null`, `Array`, `Dictionary`, `NAN`, `INF`, and fractional floats).
- `_parse_world_revision(world: Dictionary) -> Dictionary`: Reads `world.get("MAP_REVISION", 2)` and requires a finite integer matching `CURRENT_MAP_REVISION` (`2`).
- `_parse_campaign_scale(world: Dictionary) -> Dictionary`: Reads `world.get("CAMPAIGN_SCALE", 4.0)` and requires a positive finite number.
- `_build_legacy_world(world: Dictionary) -> Dictionary`: Deep-copies `world` and replaces `WORLD`, `PORTS`, and `ISLANDS` with deep copies from `world["LEGACY_MAP"]`.
- `_find_docked_port_id(pos: Dictionary, legacy_ports: Dictionary, preferred_id: String = "") -> String`: Finds the closest legacy port within `DOCK_RADIUS` (`<= 65.0` units), tie-breaking in favor of `preferred_id` (`save.lastPort`).
- `_nearest_valid_nav_node(nav: Dictionary, x: float, y: float) -> Dictionary`: Searches `nav["nodes"]` for the closest connected water node (`Navigation.is_water(nav, nx, ny)` and non-empty `nav["edges"][i]`) within `clampf(cell * 2.25, 180.0, 360.0)`.
- `_resolve_at_sea_position(old_pos: Dictionary, scale: float, nav: Dictionary) -> Dictionary`: Scales `old_pos` by `scale` (`x * 4.0, y * 4.0`), verifies `Navigation.is_water(nav, sx, sy)` and graph connectivity via `Navigation._connectors`, or snaps to `_nearest_valid_nav_node` if reasonably close; otherwise refuses with distance details.

---

## 3. Migration & Validation Pipeline

1. **Revision Preflight**:
   - Missing `save.mapRevision` defaults to `1`.
   - Non-finite, fractional, non-numeric, unknown (`<= 0`), or future (`> 2`) revisions are rejected immediately before any state copy or transformation.
2. **Current Revision (`mapRevision == 2`)**:
   - Validated against `world` via `SaveValidation.validate(saved, world)`.
   - Verifies `Money.total(saved) == int(saved.get("coinSupply", -1))`.
   - Returns a deep copy of `saved` with `state["mapRevision"] = 2` without re-scaling coordinates or routes (idempotent).
3. **Legacy Revision (`mapRevision == 1`)**:
   - Builds `legacy_world` from `world` + `world.LEGACY_MAP` (`2600 x 1800` bounds, original 10 ports, original 8 islands) and runs `SaveValidation.validate(saved, legacy_world)` **before** any coordinate transformation.
   - Verifies `Money.total(saved) == int(saved.get("coinSupply", -1))`.
   - Deep-copies `saved` into `state`. All purses (`coins`, `crewPurse`, `wageArrears`, `debt`, `coinSupply`, port `cash`/`householdPurse`/`expertPurse`/`governmentPurse`, `buildQueue` `escrow`, `fleetOwners` purses, `activeContract` `escrow`), workforce, stocks, cargo, boats, loadouts, refit lockers, crew, stores, contracts, and logs remain untouched.
   - **Port Mapping**: Maps each entry in `state["ports"]` (`x`, `y`) by stable `id` to `world.PORTS` and verifies `Navigation.is_water(nav, px, py)`.
   - **Position Transform**:
     - If `old_pos` is within `65.0` units of a legacy port, moves `state["position"]` to the matching new port's `(x, y)` and verifies water.
     - Otherwise scales `old_pos` by `world.CAMPAIGN_SCALE` (`4.0`), verifies `Navigation.is_water(nav, sx, sy)`, or snaps to the nearest valid connected `nav` node within `clampf(cell * 2.25, 180.0, 360.0)`, failing with a detailed refusal message if no valid water node is reasonably close.
   - **Route Intent Rebuild**:
     - If `state["destination"]` is non-empty, charts `Navigation.find_path(nav, state["position"], new_dest_port)`, removes the start node (`pop_front()`), assigns `state["path"]`, and retains `state["destination"]`.
     - Else if `state["path"]` is non-empty, scales the final old waypoint `(x * scale, y * scale)`, charts `Navigation.find_path(nav, state["position"], scaled_target)`, removes the start node (`pop_front()`), assigns `state["path"]`, and keeps `state["destination"] = ""`.
     - If `Navigation.find_path` fails (`size() < 2`), refuses with a detailed routing failure message.
   - **Patrols**: Preserves `patrol.progress`, `patrol.from`, `patrol.to`, and all patrol fields for `Campaign.restore` to recompute patrol courses.
   - **Post-Transform Checks**: Sets `state["mapRevision"] = 2`, runs `SaveValidation.validate(state, world)`, and enforces `Money.total(state) == initial_money == int(state["coinSupply"])`.

---

## 4. Test Coverage (`game/tests/test_map_revision.gd`)

`game/tests/test_map_revision.gd` builds authentic legacy campaign saves via `Campaign.new(legacy_world)` using `world.LEGACY_MAP` and real harbor trade/contract operations (no synthetic coin/stock/crew gifts):
1. **Missing & Explicit Legacy Revision (`1 -> 2`)**: Docked save migration, caller non-mutation, and `mapRevision = 2` assignment.
2. **Deep-Copy & Full Economic Conservation**: Verifies `Money.total`, `coinSupply`, all 10 port coordinates on water, and exact preservation of all port purses, stocks, workforce, build queues, player/NPC fleets, active contracts, and patrol `id`/`from`/`to`/`progress`. Mutates the returned dictionary to verify deep-copy isolation.
3. **Docked Offset (`<= 65.0`)**: Verifies an offset position within 65 units of legacy `kelp_reach` moves to the new `kelp_reach` coordinates.
4. **Idempotence & Current Revision (`mapRevision == 2`)**: Re-runs `CoastMigration.prepare` on the migrated state and on a native `mapRevision = 2` save to verify zero double-scaling and exact state preservation.
5. **At-Sea Scaling & Harbor Route Intent**: Steps a real legacy voyage past 65 units from port toward `kelp_reach`, migrates, and verifies 4x scaling, `Navigation.is_water` along every rebuilt path segment, start-node removal, terminal waypoint at new `kelp_reach`, and retained `destination = "kelp_reach"`.
6. **Open-Water Route Intent**: Charts an open-water course (`destination == ""`), migrates, and verifies the rebuilt path ends at the scaled final old pathpoint with `destination == ""`.
7. **Nearest Valid Nav Node Snap vs Deep-Land Refusal**: Verifies near-shore obstacle snapping to the nearest valid `nav` node within threshold and refusal when buried inside a large landmass far from any valid `nav` node.
8. **Routing Failure Refusal**: Verifies detailed refusal when an open-water target scales into an island or when a destination harbor is cordoned off by barriers.
9. **Malformed / Unknown / Future Revisions & Out-of-Legacy-Bounds**: Rejects `0`, `-1`, `-99`, `3`, `4`, `999`, `1.5`, `-0.5`, `NAN`, `INF`, `-INF`, `"1"`, `"2"`, `null`, `true`, `false`, `[]`, `{}`, legacy positions outside `2600 x 1800`, and tampered `coinSupply` ledgers.

### Suggested Verification Command (for Root)
```powershell
& "<Godot_console_exe>" --headless --path game --script res://tests/test_map_revision.gd
```
