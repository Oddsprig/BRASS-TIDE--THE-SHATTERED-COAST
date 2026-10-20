# v0.002 helper report — Boat art/camera (Muse Wonder Full)

Scope delivered, nothing outside the allowlist. No game/Godot/test launches were run by this helper (root serializes); nothing graphical is claimed as tested. All art is original code geometry; no shipped-game assets, maps or names were reproduced.

## Files

- `game/scripts/boat_art.gd` (new, ~750 lines): all boat/wake/trail/projectile drawing.
- `game/scripts/boat_portrait.gd` (new): `BoatPortrait` Control for the refit panel.
- `game/scripts/chart.gd` (edited): camera controls, wake/trail recording, culling/LOD, selection + order indicators; boat rendering delegated to BoatArt.
- `tools/boat_gallery.gd` (new): headless primitive recorder + focused art check (this is the maintained test collateral for this slice; the allowlist has no test-file slot). Unexecuted — root to run.
- No files under `game/assets/boats/` were needed (pure code art, cached station geometry per hull id).

## BoatArt API (canvas-like, untyped — built for background QA)

- `BoatArt.draw_boat(canvas, projector: Callable, boat: Dictionary, opts := {}) -> Dictionary{primitives, polygons, lines, circles, archetype, mounts, lod}`. `canvas` is any object with `draw_colored_polygon/draw_polyline/draw_line/draw_circle`; `projector.call(world_pos, height) -> Vector2`. opts: `accent, enemy, lod 0..2, clock, px` (screen px per local unit), `enlargement`.
- `BoatArt.draw_wake(canvas, projector, samples, opts)`, `draw_trail(...)`, `draw_projectile(...)`, `stern_of(boat)`, `preview_boat(spec, angle)`, `mounts_of(spec)`, `archetype(spec)`, `palette(spec, accent, enemy)`.

Silhouettes by role (all 24 hulls): skiff→speedboat (open cockpit, windshield, twin outboards), cutter/torpedo→hydrofoil (foil wings, struts, hull lift at speed, strut spray), raider→twin-hull catamaran (two demi-hulls, bridge deck, cargo crates), corvette→patrol monohull, gunboat→armored gunboat (casemate, vision slit, twin stacks), rocket→broad monitor (sponsons, low deckhouse), cruiser→command cruiser (stepped two-tier glazed bridge, funnel pair, signal masts). Per-faction palettes (compact/forge/reed/raiders) plus enemy warming; per-hull seed varies crate placement.

Detail at LOD0: water shadow + contact-foam outline, shaded side/rim/deck layers, deck plank seams + centerline, segmented armor plates with seams and corner rivets (armored/monitor/command and armor≥10), gunwale rivet rows elsewhere, bow rails with stanchions, cabins with forward glazing bands + mullions, vents/grilles, exhaust stacks, life rings, rope coils, masts with accent pennants, static helm/gunner figures (never animated), breach scars, flood overlay by `water/capacity`, fire + smoke. Estimated LOD0 primitives per hull ≈70–160 (v0.001 drew ≈15); the gallery asserts ≥55 for every hull and prints exact counts. LOD1 drops rivets/rings/ropes and halves planks; LOD2 is hull/deck/cabin/mount silhouettes only. Chart picks LOD from on-screen length (>78px→0, >36px→1, else 2; tactical forces ≥1) and culls boats whose centre is outside the viewport grown by hull margin.

Weapons reflect the fitted spec: `spec.weaponMounts` (kind gun/cannon/rocket/torpedo + synonyms, x/y in local units or world units — auto-normalized by spec.size when out of local range, angle, size string/number → scale, max 6 mounts) with the v0.001 single `spec.weapon` as fallback (incl. aft mounts on cruiser/gunboat/high-tier hulls). Guns = shield + twin barrels + gunner; cannons = turret box + heavy barrel + muzzle; rockets = 4-tube rack with frames; torpedoes = paired side tubes with caps/bands. Turreted gun/cannon follow `boat.turretAngle`; tubes/racks keep fitted local angle. Projectiles are distinct per family (bullet tracer, shell + glow, rocket body + flame, torpedo foam body) from `shot.kind` (gun→bullet, cannon→shell accepted).

Wakes/trails (chart-owned state, BoatArt-drawn): stern-path samples recorded in `chart.step` (battle ships and campaign fleet), capped at 26 samples/boat, 64 boats, 6 s life; drawn as ≤4 age bands × 3 polylines (two widening V edges + centre churn), so the curve and fade come from the actual path. Torpedo/rocket trail dots capped at 700 points, stamped at ≤33 Hz, 1.1–1.4 s life. No fluid simulation.

## Chart changes (public APIs preserved)

`setup/project/world_at/step/zoom/camera/fonts/draw_boat(boat,color,selected,enemy,enlargement,no_bars)/boat_shape/draw_turret` all keep their signatures; `draw_boat` now culls, rings selected boats, delegates to BoatArt, and draws the same HP/water bars. The v0.001 bodies remain as unused `_step_v001`/`_draw_boat_v001` (the file's CRLF endings made surgical whole-body replacement impractical from this environment; root may delete them — they are never called).

New: `pan_camera(screen_direction, dt, fast=false)` (screen-axis pan at 540 px/s, 1150 fast, disables follow, clamped to world+450), `center_camera()` (battle: snap+follow flagship; campaign: snap+follow player position), `set_tactical(enabled)` (battle scale ×0.52, campaign ×0.75, user `zoom` untouched, mirrors `host.tactical_mode` only if that property exists), plus public `follow_camera`/`tactical` vars. `step` no longer resets the camera per frame: defaults are applied only on mode entry, follow only in battle (or campaign after `center_camera()`), so WASD panning works while paused in both modes. Root still owns all input.

Battle selection/orders: selected ids come from `host.selected_battle_ids` if present/non-empty, else per-ship `selected`, else the flagship. Selected player boats with a Dictionary `boat.order` (`{x,y}` / `{target:{x,y}}` / `{targetId}`, kind in `kind` or `type`) get a dashed order line + X/ring marker, coloured by kind (attack/engage red, escort friendly, else gold).

Known integration notes for root: (1) current `main.gd` sets `chart.camera`/`zoom` on battle start — still works; on return to campaign the chart now resets to the (1300,900) overview only on mode entry, matching old framing. (2) Campaign fleet boats in `draw_campaign` still pass `vx=45` heading-east; only speed magnitude is read. (3) Five leftover `pass` lines in the old projectile loop are inert.

## BoatPortrait

`class_name BoatPortrait extends Control`, `custom_minimum_size = 360×230`, public `boat: Dictionary` (redraws on assignment), `accent`, `enemy`, `display_angle`, and `set_spec(spec)` for a live-campaign-free preview of any hull/fitted spec. Draws panel water + chart rings, the same BoatArt LOD0 geometry fitted to the rect, and name/role/archetype text when a theme font exists.

## Background visual QA hook

`tools/boat_gallery.gd` (SceneTree script) loads `game/data/world.json`, draws through a dummy `Recorder` canvas, and writes JSON panels (640×420, background `#183e4b`, primitives as `{t: poly|line|seg|circle, pts:[[x,y]…], c:[r,g,b,a], w?, r?}` in panel pixels): all 24 hulls at LOD0 underway, LOD 0/1/2 of the largest hull, one fitted hull carrying all four weapon families (5 mounts), a damaged hull (breaches+flood+fire), 3 curved-wake frames, and a projectile/trail panel. It also runs ~90 assertions (24 hulls, all archetypes present, ≥55 primitives/hull, recorder count == stats count, LOD strictly decreasing, mount normalization incl. world-unit coordinates, damage adds primitives, wake/projectile emission) and exits 0/1 with a one-line summary. Suggested root run (headless, no window):

```
<godot-console> --headless --path game --script <abs path to tools/boat_gallery.gd> -- --out=<abs path>/qa/boat_gallery.json
```

Root can rasterise each panel's primitives in order (filled polygons, polylines/segs with width w, filled circles) to PNG, and the three `wake_frame_*` panels to GIF — identical primitives to what the game draws, no live window needed.

## Verification status

Not run: no Godot import, tests, gallery execution or screenshots were performed (per contract, root serializes; this environment's shell sandbox was also unavailable). Files were static-reviewed after writing (signatures, call sites in `main.gd`/`interface.gd`, mount/spec field names against `world.json`/`battle.gd`). Primitive counts above are hand-estimated from the geometry code; exact counts come from the gallery summary when root runs it. Risks root should check on first import: GDScript parse of the three new files, `BoatPortrait` setter redraw behaviour in the fitting panel, and wake feel at battle zoom.
