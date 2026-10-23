# Current native-module contract — v0.028 base

Godot 4.7.2 GDScript. Use actual native source APIs and data, not the archived JS
prototype or CONTRACT.md. Historical migration assignments are in the cold archive.
This contract supplies boundaries, not an authorization to rewrite systems.

Pure simulation modules use RefCounted/static methods with explicit Dictionary,
Array and numeric types where inference is ambiguous. Do not use scene/UI Nodes,
rendering, resource loading, audio, filesystem or mutable shared globals inside
worker-owned pure tasks. Copy state, join and publish once on main. Static world
catalogues are read-only. Preserve stable IDs and current camelCase save keys.

Read the targeted generated map and module/test source before editing. Damage:
damage.gd/test_damage.gd; combat: battle.gd/test_battle.gd; economy/construction:
corresponding modules/tests and CASH ECONOMY CONTRACT. Routes: navigation.gd,
route_cache.gd, coast_migration.gd and their native tests. Canonical current world:
game/data/world.json. No legacy generator overwrites.

Keep native regression sources and strict assertions. Use hidden serialized bounded
checks via existing tools; no competing engine runs, desktop control or owner-save
mutation. Source passes do not prove export, rendered FPS, audio or advanced AI.
Helpers receive a separate current brief/worktree/file allowlist and return an
unchanged raw report; lead independently reviews diffs and records acceptance.
No helper deletion, unscheduled helpers or broad source rewrites.
