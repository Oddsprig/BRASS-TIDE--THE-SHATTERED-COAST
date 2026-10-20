# v0.002 verification — 20 October2026

All tests are sequential headless Godot processes with no foreground window, focus, mouse, keyboard or desktop control. Each native suite is capped at60seconds; logged script errors fail the runner even when exit0. Helpers wrote source/tests and did not launch game processes; root reviewed and ran them independently.

| Suite | Passing checks / coverage |
|---|---|
| damage / battle / navigation | Numerical damage/stores, combat/collision/withdrawal and original water routes |
| economy |73,591; finite paid production, labor, prices and365-day conservation |
| construction |2,827; all24 bills, machinery, labor/supervision escrow and shared yard capacity |
| fleet economy |1,190; owner/crew purses, finite paid stores/repair/trade and365days |
| campaign finance |418; actual purchases/crew/salvage/loans/contracts/shared workers/coins |
| save validation |83; valid and malformed JSON, bounds, identities and atomic refusal |
| runtime |120; actual scene/UI, worker publication, battle transitions and save/load |
| tactics |114; default AI/manual opt-in, selection orders,300-point deployment/reserves, four weapon families, lead/arcs/shore, independent timers and useful mixed-range behavior |
| refit |347;24 default hulls, fitting limits, families, exact paid parts/labor/duty, finite stocks/workers/lockers, no healing/refill and failed-install atomicity |
| fleet points |98; more than8 light hulls,300-point acquisitions, retained over-cap legacy rosters, canonical fitted saves, tampering and required successful/failed fitting paths |
| commander |23; actual Main controller, camera while paused, tactical pause restore, AI toggle/flagship, selection, coins/DP HUD and real fitting UI |
| voyage |67; all8 real contracts with optional programmatic manual captain |
| autovoyage |67; all8 real contracts with zero battle input |

Full integrated result:15/15 suites pass; raw output work/qa/v002-final-corrected. Both real voyages use earned payouts, actual stock/crew, purchases, paid weapon/armor refits and legal Wait workdays with wages/rations. No money/stock/crew is injected and no campaign result is forced. Deterministic random contacts are avoided through the same sailing/grace actions available in the game. Late purchases can replace weak hulls within300points; final result is3survivors. Pure financial unit fixtures explicitly set stock/workforce or move existing treasury funds; they are not evidence for earned campaign progression.

Additional evidence: tools/boat_gallery.gd captured exact BoatArt primitives for33panels, with93checks and0failures. Root software-rasterized and inspected24hulls, fitting/damage/projectiles and wake frames. This validates generated art, not an actual GPU screenshot/FPS. Full detail uses bounded primitives and cheaper LODs; trails/wakes have fixed caps. Read-only tools/verify_legacy_save.gd ran on the owner's actual v0.001 voyage:23checks,0failures; boat health/crew/stores and total coins survive, supplied dictionary and original file bytes remain unchanged.

The release tool imports a clean exact-tag worktree, exports native Windows x64 and tests the exported EXE itself headless for menu, campaign/save and battle. RELEASE.json records the exact commit/tag, engine and passing standalone checks; the final delivery receipt records package inspection, PE/icon and hashes. Test saves are preserved outside the shipped build. User saves are copied only after executable tests and are excluded from the clean distribution ZIP.

Failures fixed during development are recorded in CHANGES and the separate root verdict; raw helper reports remain unchanged. Current human feel, display scaling, GPU frame pacing and audio remain unmeasured under the owner's background-only rule. Separate rendering stays default; the engine's documented experimental/font issue remains and Stable Rendering.vbs offers the per-launch Safe fallback. No Android release or commercial quality parity is claimed. See TO BE TESTED.md.


Release verification completed: exact game commit 6c0e81b69684b7c1eebaa6430d2eebd190bf7b72 / annotated v0.002, separate clean worktree. All15suites passed again there (refit347, commander23); each suite under6seconds, including full autonomous campaign. Source import passed. Exported native EXE independently passed menu, campaign/save and battle startup; native icon and PE versions0.0.2.0 verified. Matching-engine --main-pack audit found0failures for13required modules, data/icon, version/coins/Separate settings and excluded test/tool/save files. Generated QA saves are outside the delivered folder. Desktop launcher target/workdir/icon and byte hash were verified after copying, without launching it. Root also reframed/rasterized the exact art capture (73–125full-detail primitives/hull; largest hull LOD123/81/51) and viewed the wake frames. Hashes and source identity are in RELEASE.json and the final delivery receipt.

The last release-tool text substitution changed the old-version migration sentence along with its header. Root narrowed the template substitution and corrected the delivered START HERE; native game files and immutable release tag are unchanged. This is included with the post-export records on main.
