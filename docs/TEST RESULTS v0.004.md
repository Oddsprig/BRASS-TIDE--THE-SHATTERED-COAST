# v0.004 source verification

All engine processes serialized, hidden/headless, no input/focus or owner-save access. Script errors fail even on exit0; each test has a60second owned-process timeout.

| Suite | Actual result |
|---|---|
| damage | PASS · damage: all native tests passed |
| battle | PASS · battle: all native tests passed |
| navigation | PASS · Completed without error |
| economy | PASS · ALL NATIVE ECONOMY TESTS PASSED (73591 checks in 1944 ms) |
| construction | PASS · CONSTRUCTION PASS: 2827 checks in 17 ms |
| fleet_economy | PASS · fleet cash: 1190 checks, 0 failures, 2613 ms |
| campaign_cash | PASS · campaign cash: 418 checks, 0 failures, 1192 ms |
| save_validation | PASS · save validation: 83 checks, 0 failures, 391ms |
| runtime | PASS · runtime: 120 checks, 0 failures, 2021ms; background/headless only |
| voyage | PASS · voyage: 67 checks, 0 failures, 5380ms; largest fleet10 |
| tactics | PASS · tactics: 114 checks, 0 failures |
| refit | PASS · refit: 347 checks, 0 failures |
| fleet_points | PASS · fleet points: 98 checks, 0 failures, 496ms |
| commander | PASS · commander: 24 checks, 0 failures; background only |
| autovoyage | PASS · voyage: 67 checks, 0 failures, 5646ms; largest fleet10 |
| laboratory | PASS · LABORATORY: 67 checks, 0 failures |
| combat_events | PASS · combat_events: 10153 checks, 0 failures |
| audio | PASS · AUDIO: 1085 checks, 0 failures; decoding/scheduling only, no audition |

Exact geometry audit:6466029 polygons across24hulls,360headings,threeLODs and stationary/moving cases; zero invalid. Headless actual battle startup180frames passed. Background raster capture inspected; no listening or GPU FPS claim.

Raw evidence:
- work/qa/v004-final/damage.log
- work/qa/v004-final/battle.log
- work/qa/v004-final/navigation.log
- work/qa/v004-final/economy.log
- work/qa/v004-final/construction.log
- work/qa/v004-final/fleet_economy.log
- work/qa/v004-final/campaign_cash.log
- work/qa/v004-final/save_validation.log
- work/qa/v004-final/runtime.log
- work/qa/v004-final/voyage.log
- work/qa/v004-final/tactics.log
- work/qa/v004-final/refit.log
- work/qa/v004-final/fleet_points.log
- work/qa/v004-final/commander.log
- work/qa/v004-final/autovoyage.log
- work/qa/v004-final/laboratory.log
- work/qa/v004-final/combat_events.log
- work/qa/v004-final/audio.log

Release export runs from an exact-tag clean separate worktree, rechecks native suites and tests the resulting Windows EXE for menu, campaign/save and battle. See RELEASE.json for completed export facts; this document does not infer completion from a plan. No rendered FPS or human listening claim.
