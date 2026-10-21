# v0.007 source verification

All engine processes serialized, hidden/headless, with isolated QA saves and no desktop input/focus. Every suite has a60second owned-process timeout. Script errors fail even on exit0.

| Suite | Actual result |
|---|---|
| damage | PASS · damage: all native tests passed |
| battle | PASS · battle: all native tests passed |
| navigation | PASS · Completed without error |
| economy | PASS · ALL NATIVE ECONOMY TESTS PASSED (73591 checks in 1917 ms) |
| construction | PASS · CONSTRUCTION PASS: 2827 checks in 14 ms |
| fleet_economy | PASS · fleet cash: 1190 checks, 0 failures, 2765 ms |
| campaign_cash | PASS · campaign cash: 418 checks, 0 failures, 1513 ms |
| save_validation | PASS · save validation: 89 checks, 0 failures, 436ms |
| runtime | PASS · runtime: 120 checks, 0 failures, 1963ms; background/headless only |
| voyage | PASS · voyage: 67 checks, 0 failures, 6478ms; largest fleet10 |
| tactics | PASS · tactics: 114 checks, 0 failures |
| refit | PASS · refit: 348 checks, 0 failures |
| fleet_points | PASS · fleet points: 98 checks, 0 failures, 702ms |
| commander | PASS · commander: 24 checks, 0 failures; background only |
| autovoyage | PASS · voyage: 67 checks, 0 failures, 6272ms; largest fleet10 |
| laboratory | PASS · LABORATORY: 81 checks, 0 failures |
| combat_events | PASS · combat_events: 10131 checks, 0 failures |
| audio | PASS · AUDIO: 1233 checks, 0 failures; decoding/scheduling only, no audition |
| map_revision | PASS · map revision: 361 checks, 0 failures, 2593ms |
| mount_layout | PASS · mount_layout: 1483 checks, 0 failures |
| presentation | PASS · PRESENTATION: 611 checks, 0 failures |
| feedback | PASS · FEEDBACK: 3952 checks, 0 failures |

The combined feedback suite has3952checks covering all24stern layouts/compatible engine packages, socket clearance, native cached meshes/repeated frames, bounded local scars, material effects, family/LOD/age budgets, rotated sinking, repaired hulls, final-kill completion and pause/Escape. Optional cosmetic save fields accept JSON round trips and reject nonfinite/unbounded data. Motors measured at most241close/42far primitives per hull; sampled effects at most25against a35limit.

The source-art sweep covered24hulls ×360headings ×threeLODs ×still/moving:12777222native polygons,0invalid. Fleet gallery93checks/33panels pass. The45-frame feedback capture uses actual runtime colored meshes for living hulls/weapons and the actual CombatArt sinking/effect functions. Root inspected PNGs and representative animation frames. Seven short fleet fixtures pass, including40boats at300DPper side and all physical weapon arcs.

Root measured actual Main CPU command-building work during a120frame/40boat fixture. The first naive detailed version had77.054ms median drawing and timed out a360frame/30second gate. The bounded colored-mesh implementation reduced median drawing to roughly5-6ms. The final360fixed-frame Main fixture then passes. These are headless CPU measurements, not GPU FPS or human foreground play. Raw final timings are in work/qa/v007-final-cached/cpu.log.

Actual old owner saves are copied only after clean release archives. Earlier releases, original saves/music and their hashes remain preserved. No crew animation, fluid simulation or numerical economy/balance change was introduced.

Raw evidence: work/qa/v007-final/*.log, work/qa/v007-fast/summary.json, work/qa/v007-motor-geometry/geometry.log, work/qa/v007-final-cached/*.log and work/qa/v007-final-visual/gallery.json. Raw helper reports plus root review are in docs/helper-reports.

Release export requires a clean exact-tag worktree, reruns all22suites, then verifies the Windows EXE itself for menu, campaign/save and battle plus its icon/PCK. Completed export identity and hashes are recorded in RELEASE.json; a source test record alone does not claim export or remote upload. No human listening or GPU frame-pacing claim.
