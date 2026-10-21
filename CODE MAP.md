# Active source v0.004

Implemented additions: fleet_lab.gd and lab_ui.gd own normal300point fixtures/builder/results; dev_tools.gd is explicit opt-in lab tooling; music.gd loads portable/Desktop music at runtime. Main isolates/restores career objects. Release/check runners serialize engine processes. Read generated maps and maps/development.txt for older-tool context. Later system additions are recorded below.

# Active source v0.003

Implemented additions: fleet_lab.gd and lab_ui.gd own normal300point fixtures/builder/results; dev_tools.gd is explicit opt-in lab tooling; music.gd loads portable/Desktop music at runtime. Main isolates/restores career objects. Release/check runners serialize engine processes. Read generated maps and maps/development.txt for older-tool context. Later system additions are recorded below.

# Native source map — v0.002

The playable game is game/. dist/ and root tests/*.cjs preserve the historical browser prototype. Runtime scripts below are in game/scripts/. Generated maps contain verified file/line symbols; tools/update_maps.py refreshes them.

- project.godot/main.tscn: native Windows entry, Separate rendering and fixed 60Hz physics.
- main.gd: scene/input, WASD camera, AI/manual modes, selection/orders, tactical pause, worker publication and portable saves.
- campaign.gd: voyages, canonical fitted boats, 300-point ownership, morale, real hull/crew/salvage/loan transactions and read-only-input restore.
- contracts.gd/money.gd: funded escrow, freight/rewards, integer purse transfers and complete coin counts.
- damage.gd: numerical crew allocation, breaches, water inflow/bailing/pumps, finite patching, wounds/fire/engines and sinking.
- battle.gd/deployment.gd: 300 points/side with preserved reserves, default autopilot, orders, optional manual flagship, independent weapon mounts, led swept projectiles, arcs, shore collision and DPS-aware engagement spacing.
- refit.gd: hardpoints, fitting budgets, four weapon families, engines/armor, exact itemized costs, real stocks/shared workers, atomic installation and finite module lockers.
- goods.gd/industry_data.gd/economy.gd: sixteen paid input chains, 100 coins per sailor-day, finite resident/business/expert/government purses and workforce.
- fleet_economy.gd: NPC owned boats, operating/crew purses, payroll, cargo/trade, finite stores/repairs and morale.
- construction.gd/harbor.gd: physical hull bills, whole machinery, labor/supervision escrow, shared yard capacity, hires, repairs, stores and sales. Fitted magazines buy ammunition; fitting supplies none.
- navigation.gd: bounded water-only routes around the original coast.
- chart.gd/boat_art.gd: isometric coast/boats, seven hull silhouettes, fitting-aware mounts, damage marks, bounded fading wakes and trails, culling and three LODs. Flat decorative water.
- boat_portrait.gd: same BoatArt geometry in fleet/fitting previews.
- interface.gd/finance_ui.gd/tactics_ui.gd/refit_ui.gd: current title/harbor/fleet/finance/guide/command/fitting UI. Currency labels say coins; internal saved cash keys remain compatible.
- sound.gd and game/assets/: original generated sound and original icon/vector art; no animated crew.
- game/data/world.json: 24 original hulls, 10 ports, 4 factions, 8 story contracts and islands. tools/build_data.cjs regenerates current build/currency metadata.
- version.gd: integer BUILD2 displays0.002. export_presets.cfg: native x86_64, dev tests/tools/saves excluded.
- game/tests/:15 current bounded native suites; superseded pre-economy campaign fixture is retained as history.
- tools/check_game.py: sequential hidden/headless runner, 60s process limit, rejects script errors even on exit0.
- tools/boat_gallery.gd + render_boat_gallery.py: capture exact BoatArt primitives, software raster PNG/GIF preview; no GPU/FPS claim.
- tools/verify_legacy_save.gd: read-only real portable save migration check.
- tools/release_game.py: clean exact-tag export, native standalone smoke checks, icon, manifests and Windows ZIP.
- tools/publish_github.cmd: verified origin, preserved v0.001 tag, current annotated tag, clean main/tagged game check; non-force atomic main/tag push and remote verification.

Maps: campaign, combat, economy, construction, navigation, presentation (each under80lines). Current evidence: docs/TEST RESULTS v0.002.md and separate raw/helper verdict. Human play questions: TO BE TESTED.md.


Current development additions (playable game remains v0.002): BUILD PLAN.txt and VERSION MAP.txt define planned stages; docs/audio holds text music prompts and recorded-SFX research. tools/qa_brass.py runs tools/fleet_bench.gd against shared tools/bench_scenarios.json in isolated headless fixtures; tools/plan_territory.py emits a concept/draft without changing world data. See maps/development.txt and docs/FAST DEV TOOLS.txt. In-game lab/dev/menu improvements remain planned v0.003 work, not existing runtime APIs.
