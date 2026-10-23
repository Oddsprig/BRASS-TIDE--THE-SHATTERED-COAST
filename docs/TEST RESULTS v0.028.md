# v0.028 source verification

All 66 native suites passed in isolated background/headless processes, serialized by tools/check_game.py. No owner save, desktop input or focus was used.

| Suite | Actual log result |
| --- | --- |
| damage | damage: all native tests passed |
| battle | battle: all native tests passed |
| navigation | navigation: direct, island detour, blocked targets, barriers, diagonal corners, shore connections, bounded finite graph, 10 ports and 19 routes passed |
| economy | ALL NATIVE ECONOMY TESTS PASSED (86831 checks in 2841 ms) |
| construction | CONSTRUCTION PASS: 2827 checks in 16 ms |
| fleet_economy | fleet cash: 1266 checks, 0 failures, 3726 ms |
| campaign_cash | campaign cash: 458 checks, 0 failures, 8802 ms |
| save_validation | save validation: 89 checks, 0 failures, 897ms |
| runtime | runtime: 124 checks, 0 failures, 2270ms; background/headless only |
| voyage | voyage: 68 checks, 0 failures, 9524ms; largest fleet14 |
| tactics | tactics: 114 checks, 0 failures |
| refit | refit: 348 checks, 0 failures |
| fleet_points | fleet points: 99 checks, 0 failures, 2102ms |
| commander | commander: 24 checks, 0 failures; background only |
| autovoyage | voyage: 68 checks, 0 failures, 10467ms; largest fleet13 |
| laboratory | LABORATORY: 81 checks, 0 failures |
| combat_events | combat_events: 10131 checks, 0 failures |
| audio | AUDIO: 1233 checks, 0 failures; decoding/scheduling only, no audition |
| map_revision | map revision: 361 checks, 0 failures, 3044ms |
| mount_layout | mount_layout: 1483 checks, 0 failures |
| presentation | PRESENTATION: 611 checks, 0 failures |
| feedback | FEEDBACK: 3952 checks, 0 failures |
| expedition | expedition: 23 checks, 0 failures |
| campaign_logistics | campaign logistics: 16 checks, 0 failures |
| exploration | exploration: 270 checks, 0 failures |
| island_voyage | island voyage: 12 checks, 0 failures |
| salvage | salvage: 70 checks, 0 failures |
| salvage_voyage | salvage voyage: 14 checks, 0 failures |
| voyage_jobs | voyage_jobs: 69 checks, 0 failures |
| voyage_flow | voyage flow: 12 checks, 0 failures |
| factions | ALL FACTION TESTS PASSED (193 checks in 5 ms) |
| political_voyage | political voyage: 16 checks, 0 failures |
| naval_ai | naval_ai: 227 checks, 0 failures, 2376 ms |
| naval_voyage | naval voyage: 8 checks, 0 failures |
| trade_intel | ALL TRADE INTEL TESTS PASSED (67 checks in 15 ms) |
| reactive_trade | reactive trade: 9 checks, 0 failures |
| fleet_identity | fleet_identity: 55 checks, 0 failures |
| support_voyage | support voyage: 17 checks, 0 failures |
| naval_recovery | naval recovery: 11 checks, 0 failures |
| coastal_stories | coastal_stories: 109 checks, 0 failures |
| story_voyage | story voyage: 18 checks, 0 failures |
| home_harbor | home_harbor: 74 checks, 0 failures |
| home_voyage | home voyage: 17 checks, 0 failures |
| regional_campaigns | regional campaigns: 64 checks, 0 failures |
| regional_voyage | regional voyage: 24 checks, 0 failures |
| campaign_endurance | campaign endurance: 2168 checks, 0 failures, 14631 ms, 8 worker lanes |
| crew_training | crew training: 20 checks, 0 failures |
| training_voyage | training voyage: 14 checks, 0 failures |
| harbor_reserves | Native suite completed |
| supply_voyage | supply voyage: 12 checks, 0 failures |
| industrial_tooling | Native suite completed |
| industrial_voyage | industrial voyage: 35 checks, 0 failures |
| worker_conditions | worker_conditions: 54 checks, 0 failures |
| conditions_voyage | conditions voyage: 21 checks, 0 failures |
| regional_goods | Native suite completed |
| civilian_voyage | civilian voyage: 53 checks, 0 failures |
| shipping_companies | Native suite completed |
| company_voyage | company voyage: 30 checks, 0 failures |
| trade_law | trade law: 49 checks, 0 failures; native candidate |
| customs_voyage | customs voyage: 25 checks, 0 failures |
| boarding | boarding: 115 checks, 0 failures |
| boarding_voyage | boarding voyage: 28 checks, 0 failures |
| regional_crises | regional_crises: 103 checks; 0 failures |
| crisis_voyage | crisis voyage: 30 checks, 0 failures |
| campaign_guidance | campaign guidance: 287 checks, 0 failures |
| campaign_systems | campaign systems: 97 checks, 0 failures |

This report establishes source checks. Exact tagged export identity, native Windows startup/save/battle and file hashes are recorded separately in portable RELEASE.json. No human listening, subjective fun or GPU frame-pacing claim is made.
