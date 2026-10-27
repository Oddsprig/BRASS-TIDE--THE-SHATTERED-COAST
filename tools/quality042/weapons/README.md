# Brass Tide 0.042 weapon source candidate

Root executes all baking and native checks. This seat ran no tests, engines,
Blender, renderers, GPU jobs, downloads or helpers. Source review does not establish
visual or native acceptance. Merge both Weapons commits and SolArt's shared model
and baker sources before execution.

`weapon_models.py` authors seven mechanisms in real 3D: single/twin belt-fed MG,
cradled cannon, three/six-cell rocket rack, single/twin torpedo tube. Curved
cooling jackets, receivers, breech blocks, recoil cylinders, loading tray,
ammunition chests, feed links, saddle straps, air lines, bolts and open annular
mouths are geometry. No stock models, downloaded art, black front discs or
runtime 3D rendering. Model materials and exact projection/light come from
SolArt's `models.py` / `bake.py`.

Coordinates are canonical physical units: +X toward the muzzle, +Y starboard,
+Z up; index `h` has world bearing `h * TAU / 32`. XY rotates before projecting
`u=.82*(x-y), v=.41*(x+y)-z`. No hull-size multiplication of model heights.
The model origin is the mount pivot at deck elevation 9.7. Runtime scales all
weapon dimensions by the existing `WeaponGeometry.unit(hull_size, fitting_size)`.
Canonical muzzle stations remain gun `(8.8,0,4.8)`, cannon `(14.2,0,5.8)`, rocket
`(5.9,0,6.0)`, torpedo `(7.9,0,2.8)`. Torpedo gameplay projectile height remains
waterline zero; the visual launcher stays on deck as in the original renderer.

The hull contains no installed weapons. `BoatArt.draw_boat` calls
`BoatSpriteArt.draw_hull`, then actual installed mounts from `mounts_of`, then
existing damage/equipment feedback. Existing motor motion remains live.
Weapons retain physical fitting IDs, sizes, local aiming angles and shot times;
removing a fit removes every weapon layer. Economy, stats, AI, projectiles,
mount layout, remaining 33 hulls and saves are unchanged. The nautical chart,
nonstandard projectors, legacy enlargement and missing assets use existing art.

Each weapon atlas has 32 cells, eight columns/four rows, cell256x192,
pivot128x128, density6 pixels per canonical unit. The pivot is the deck mounting
origin. MGs/cannon have separate base and moving-assembly atlases; other weapons
have one base atlas. Ten atlases total2048x768px, RGBA8 base memory60MiB. Both
recoil layers use the assembled model's world shadow map. The receiver/barrel
layer moves back1.1units and recovers over the existing0.16seconds, only after
that mount's actual shot timestamp. Subframe heading correction uses the
existing ISO affine basis about the firing plane. No per-frame asset renders,
image transformations or material generation; textures/manifests load once.

`BoatSpriteArt.hull_entry`, `frame_info`, `bounds`, `weapon_variant`, `audit`
and `clear_cache` are inspectable. Actual Battle and BoatPortrait use the same
BoatArt entry. The Recorder must implement native CanvasItem argument order
`draw_texture_rect_region(texture, rect, source, modulate, transpose, clip_uv)`
and `draw_set_transform_matrix`. Showcase owns that actual texture adapter.
Portrait selects Art's real density4 image at exact heading28/-PI/4. Bounds use
actual offline `frame_bounds_px` / `portrait_bounds_px` metadata if supplied.

Root-only focused execution after shared-lane claim by Test Bridge:

1. Preview cannon and gun_single first, both layers at heading28. Invoke existing
   Python with `tools/quality042/weapons/bake_weapons.py --variant cannon
   --mode preview --heading 28 --aa 2 --seconds 90 --cache <NEW_CACHE>
   --out <NEW_PREVIEW_DIRECTORY>`. Review the real assembled layers at normal
   battle/refit scale before committing to all directions. No result here claims
   those previews were produced or approved.
2. For accepted source, `--mode frames --start 0 --frames 4` produces bounded
   reusable chunks. Repeat start4,8,...28 only as Root chooses; no automatic
   engine retry or batch beyond100active seconds. Each call shares that deadline
   across both layers. `--mode pack` refuses any missing/changed frame receipt
   and writes the real variant atlases into `game/assets/boats042/weapons/`.
   Run all seven variants as needed for fitting coverage. Do not publish a
   single-layer partial pack. The checked-in manifest is a source contract,
   never a claim that its PNG files exist.
3. Native import plus Showcase's one `test_art042.gd` fixture should prove three
   actual Battle hull images; real normal390x245 refit portraits; unchanged
   waterline and physical socket positions; separate aiming/recoil; empty fits
   have no gun textures; loaded image dimensions/regions are valid; fallback
   hulls retain art; complete boat state stays unchanged. Preserve failed or
   interrupted native evidence. Root reviews normal zoom and motion separately.

Optional Cycles preview uses `blender_weapons.py` with the same pure authored
mesh source and shared Blender camera/material adapter. It renders one layer
and direction per background invocation, with other layers as shadow casters.
Root owns outer119second timeout/cleanup and must verify Blender API/camera.
CPU and Blender frames have different shading; use one accepted pipeline for
the complete final atlases rather than mixing rendering styles.
