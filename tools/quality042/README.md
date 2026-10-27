# Original hull source candidate for 0.042

Status: **source only, no bake or test executed by SolArt**. A source commit is
not finished art. Root owns native execution, visual review, bake results and
the actual battle/refit acceptance. No future version scope is implemented.

`models.py` authors three distinct models from new geometry. It does not reuse
the old BoatArt polygon mesh: Tinwake has a smooth rolled aluminum launch,
open cockpit and twin sculpted outboards; Ashwake has a round-bilge steel hull,
individual bevelled armor courses, a turtleback bridge and copper exhaust;
Brasswind has two long timber demi-hulls, a two-level packet house, a walkaround
balcony, bound cargo and two articulated-looking cargo derricks. All models
include rounded material edges, a cambered deck, propulsion and real empty
mounting wells. Guns are separate SolWeapons assets.

`bake.py` is a CPU software renderer using existing NumPy and Pillow. It has a
3D depth buffer, explicit smooth normals, linear-light diffuse and specular
materials, a world-space shadow map with a soft kernel, procedural deck grain,
and transparent antialiasing. No engine, Blender or other process is started.
`blender_hulls.py` adapts the exact same authored surfaces to Blender meshes,
custom vertex normals and physical materials. `blender_scene.py` supplies
SolWeapons with the shared transparent Cycles CPU scene and exact camera.

## Contract

Manifest: `game/assets/boats042/asset-manifest.json`, schema
`brass-tide-boats042-v1`. Its hull entries are consumed by SolWeapons'
`boat_sprite_art.gd`; no changes to economy, navigation, combat or weapon stats.

- Model physical XY = hull-local XY multiplied by size14/21/28. +X is the bow,
  +Y is starboard. Z is physical world height, **never** size-scaled.
- Pixel pivot is the waterline origin `[0,0,0]`, not the alpha bounding-box center.
- Exact screen projection at density1 is `[(x-y)*.82,(x+y)*.41-z]`.
- Heading `i` rotates model XY by `i*TAU/32` before projection. Positive heading
  turns +X toward +Y. Index0 points +worldX; index28 equals -PI/4.
- CPU hull cells: skiff/escort384×320, pivot192,200; merchant400×320,
  pivot200,200. All use density2 and atlas8columns×4rows, with no rotation or
  trimming of cells. Portraits use density4: skiff/escort768×640, pivot384,400;
  merchant800×640, pivot400,400. The requested heading is recorded explicitly.
- World sun direction toward the light is normalized`[-.55,-.65,1]`. Camera and
  light do not rotate with hull. Sky is cool, direct light is warm and restrained.
- Mounts use current `MountLayout` role/tier/faction/hash formulas. `sockets_for`
  preserves mount0..3, physical XY, footprints, tiers, directions and elevation.
  Rings terminate at the socket plane; well interiors contain **no guns**.
  `WeaponGeometry` remains authoritative for the9.7 weapon base and muzzle height.
- Baker fills actual `frame_bounds_px` and `portrait_bounds_px` as `[x,y,w,h]`;
  empty arrays in this source manifest mean **not measured**, not an empty hull.
- Three atlas base levels occupy47,841,280bytes total (45.625MiB). Three portraits
  add5,980,160bytes (5.703125MiB). Mipmaps add about one third. Compressed PNG sizes
  and actual bake durations are unknown until Root runs the candidate.

## Root's first small bake

Use the machine-wide Test Bridge lane and existing process detector. Do not
wrap these commands in a second lane lease. Keep the whole selected native job
under120seconds including setup and cleanup. Run one first frame and inspect
it before scheduling atlas production. These commands are instructions for
Root's automated adapter, not requests for the owner to run a terminal.

With the existing Python that already has NumPy and Pillow:

```text
python tools/quality042/bake.py --hull tin_skiff --mode preview --heading 28 --aa 2 --seconds 95 --out <NEW_REVIEW_DIRECTORY> --cache <NEW_CACHE_DIRECTORY>
```

If the normal Python lacks NumPy, do not install it. Blender's bundled Python
normally has NumPy, but may lack Pillow; check installed interpreters only.
Otherwise use the Blender native path below. Do not claim an unrun path works.

For the actual Blender quality path, one frame only:

```text
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -t 6 --python tools/quality042/blender_hulls.py -- --hull tin_skiff --heading 28 --samples 16 --out <NEW_REVIEW_DIRECTORY>
```

`--save-model` writes an inspectable .blend as part of that Root job. `--portrait`
selects the double-density cell. The common scene uses Cycles **CPU**,6threads,
16samples, deterministic seed42 and denoising. Camera origin, XY basis and
height are asserted against the actual Blender camera before rendering.
Blender render itself is bounded by Root's outer owned-process119second job;
there is no automatic retry or background monitor in these scripts.

CPU previews produce a single real transparent PNG and a cached receipt with
source hash, PNG hash, alpha bounds, parts/vertices/triangles and elapsed time.
`--hull all --mode preview` is available, but start with a single hull so that
Root learns actual per-frame cost before choosing a larger batch.

## Incremental CPU atlas production after visual acceptance

Choose the number of frames per call from the measured first-frame duration.
Default is **one** frame; maximum8. The internal deadline defaults95seconds and
cannot exceed105, leaving outer job cleanup time. Deadline exit3 means
`INCOMPLETE_BOUNDED`, not success. Completed cached frames survive; partial
frames never enter the atlas. No shell retry loop is supplied.

```text
python tools/quality042/bake.py --hull tin_skiff --mode frames --start 0 --frames 1 --aa 2 --seconds 95
python tools/quality042/bake.py --hull tin_skiff --mode pack --aa 2 --seconds 95
python tools/quality042/bake.py --hull tin_skiff --mode portrait --heading 28 --aa 2 --seconds 95
```

The first line is one bounded slice; Root schedules remaining directions0..31
using the same cache and AA setting. Pack refuses any missing frame. It writes
the atlas, real alpha bounds and a bake receipt only after all32 cached frames
exist. `portrait` writes the second-density PNG and its true bounds. Repeat for
the other two hull IDs. Default output is the game's boats042 directory; use
`--out` and `--cache` consistently when isolating review candidates. Source
changes invalidate the entire cache key; do not mix old/new pixels. Root should
preserve failed evidence and choose new review directories for new candidates.

The merchant-only CPU canvas correction selects its cell/pivot before model
construction or packing, including when using `--hull all`. It preserves the
exact projection, densities and model geometry. Across all32 source headings,
merchant vertex bounds are x9.17456..390.82544 and y85.45518..293.96575 at
density2 on the400×320 canvas; this is arithmetic, not rendered acceptance.
New frame/atlas receipts contain `canvas_config`; manifest updates publish the
cell, pivot and portrait configuration only for the hull being baked. Portrait
updates record `portrait_source_sha256` without replacing an existing atlas's
`source_sha256` or alpha bounds. Completed skiff/escort atlases retain their old
source receipts; only the merchant atlas needs a new bake. Root owns semantic
manifest merging so existing runtime-baked bounds/provenance stay intact.

For reproducibility, cache keys include SHA256 of both model and CPU bake
sources plus hull ID, heading, density and AA. Models have no random state,
network access, downloaded textures or third-party art. Generated cached PNGs
are not committed by this source-only helper.

## Required Root verification

1. Existing Python imports or Blender5.2 API/camera acceptance; no installs.
2. One hero frame, then actual normal-size battle and refit views for all three.
   Inspect smooth silhouettes, material value separation, readable machinery,
   rail thickness, hull contact, shadow direction and details after downsampling.
3. Actual MountLayout socket/size comparison, including signed32 Godot String
   hash interpretation; compare rings/markers at headings0,8,16,24 and28.
4. Separate fitted weapons rotate, unequip and recoil without leaving a ghost
   gun in the hull. Check base height and clipping on the large merchant's side
   sockets; weapon base9.7 and socket elevation are distinct existing contracts.
5. Confirm alpha edges, actual atlas dimensions, pivots, source/PNG hashes,
   per-frame bounds and high-resolution portrait selection in the public Lab.

No FPS, rendered quality, fun or release completion follows from this source
candidate or its code size. Root's actual assets and focused native fixture
decide whether this042 increment is acceptable.
