# v0.006 source verification

All engine processes serialized, hidden/headless, no input/focus or owner-save access. Script errors fail even on exit0; each test has a60second owned-process timeout.

| Suite | Actual result |
|---|---|
| damage | PASS · damage: all native tests passed |
| battle | PASS · battle: all native tests passed |
| navigation | PASS · Completed without error |
| economy | PASS · ALL NATIVE ECONOMY TESTS PASSED (73591 checks in 1964 ms) |
| construction | PASS · CONSTRUCTION PASS: 2827 checks in 16 ms |
| fleet_economy | PASS · fleet cash: 1190 checks, 0 failures, 2677 ms |
| campaign_cash | PASS · campaign cash: 418 checks, 0 failures, 1370 ms |
| save_validation | PASS · save validation: 83 checks, 0 failures, 424ms |
| runtime | PASS · runtime: 120 checks, 0 failures, 1865ms; background/headless only |
| voyage | PASS · voyage: 67 checks, 0 failures, 6499ms; largest fleet10 |
| tactics | PASS · tactics: 114 checks, 0 failures |
| refit | PASS · refit: 348 checks, 0 failures |
| fleet_points | PASS · fleet points: 98 checks, 0 failures, 690ms |
| commander | PASS · commander: 24 checks, 0 failures; background only |
| autovoyage | PASS · voyage: 67 checks, 0 failures, 6279ms; largest fleet10 |
| laboratory | PASS · LABORATORY: 81 checks, 0 failures |
| combat_events | PASS · combat_events: 10131 checks, 0 failures |
| audio | PASS · AUDIO: 1233 checks, 0 failures; decoding/scheduling only, no audition |
| map_revision | PASS · map revision: 361 checks, 0 failures, 2566ms |
| mount_layout | PASS · mount_layout: 1483 checks, 0 failures |
| presentation | PASS · PRESENTATION: 611 checks, 0 failures |

Seven short fleet fixtures pass, including four surrounding threats exercising all4physical weapon arcs and40boats at300DP per side. Final native geometry audit:8128182polygons,0invalid;93gallery checks and33captured panels. Native Main full_300 ran360fixed frames without script/drawing errors. Actual owner saves remain byte-identical; no human audition or GPU FPS claim.

Raw evidence:
- work/qa/v006-final/damage.log
- work/qa/v006-final/battle.log
- work/qa/v006-final/navigation.log
- work/qa/v006-final/economy.log
- work/qa/v006-final/construction.log
- work/qa/v006-final/fleet_economy.log
- work/qa/v006-final/campaign_cash.log
- work/qa/v006-final/save_validation.log
- work/qa/v006-final/runtime.log
- work/qa/v006-final/voyage.log
- work/qa/v006-final/tactics.log
- work/qa/v006-final/refit.log
- work/qa/v006-final/fleet_points.log
- work/qa/v006-final/commander.log
- work/qa/v006-final/autovoyage.log
- work/qa/v006-final/laboratory.log
- work/qa/v006-final/combat_events.log
- work/qa/v006-final/audio.log
- work/qa/v006-final/map_revision.log
- work/qa/v006-final/mount_layout.log
- work/qa/v006-final/presentation.log

Release export runs from an exact-tag clean separate worktree, rechecks native suites and tests the resulting Windows EXE for menu, campaign/save and battle. See RELEASE.json for completed export facts; this document does not infer completion from a plan. No rendered FPS or human listening claim.
