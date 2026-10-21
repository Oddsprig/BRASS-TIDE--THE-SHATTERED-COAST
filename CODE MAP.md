# Brass Tide v0.008 source map

The native Godot game is game/. Generated maps/ contains current symbols/line numbers and the source inventory. The historical browser prototype remains in dist/ and root tests/. Older maps are archived under docs/archive/.

- expedition.gd, hold_manifest.gd, campaign_ui.gd: read-only voyage costs/endurance, actual carrier cargo allocations/sinking losses, preparation window and in-game TXT notes; stored hulls stay at their harbor.
- economy_workers.gd: disjoint copied-harbor group jobs, hardware-aware bounded workers, explicit joins and main-thread once-only publication. tools/prepare_campaign_release.py records sequential build/source-acceptance notes without claiming exports.

- main.gd: title/career/lab lifetime, WASD camera and commander input, fixed-step battle, worker publication, portable saves/options and music context.
- campaign.gd, contracts.gd, money.gd: voyages, finite real purses, funded contracts, canonical fleets, ownership budget and restore.
- economy.gd, industry_data.gd, goods.gd, construction.gd, harbor.gd, fleet_economy.gd:100coin wage anchor, paid input chains/experts/construction, NPC budgets, crew savings and actual material/stores trades.
- damage.gd: numerical crew jobs, breaches/flooding/pumps/bailing, finite supplies/repairs, fire/wounds/engines and sinking.
- battle.gd, deployment.gd, combat_events.gd: normal300DP, preserved reserves, autopilot/orders, independent mount targets/aim, swept impacts and bounded all-team events/effects/wrecks.
- refit.gd: compatible paid weapon/engine/armor installations, exact bill, stable IDs and finite lockers. mount_layout.gd owns shared sockets/structure; weapon_geometry.gd owns barrel/tube dimensions.
- hull_profiles.gd, boat_art.gd, weapon_art.gd:24original silhouettes, solid hull contact, separate detailed weapon models, threeLODs and bounded cheap wakes/trails. Numerical specs are never replaced by art data.
- motor_art.gd, hull_feedback.gd, boat_mesh_cache.gd: actual-transom machinery, bounded localized damage records/fire/smoke, and a512-entry texture-free mesh cache. Static meshes use64heading buckets with continuous small-angle transforms; the firing plane stays anchored. Live prop wash, damage and weapon aim remain independent.
- chart.gd, navigation.gd, coast_migration.gd:10400x7200coast, regional/territory camera/priority labels, bounded water routes, copy-first revision migration with original port IDs and unchanged purses.
- interface.gd, tactics_ui.gd, finance_ui.gd, refit_ui.gd, boat_portrait.gd: title/Escape, wages/markets, fleet orders, clickable numbered physical mounts and the same fitted boat geometry.
- fleet_lab.gd, lab_ui.gd, dev_tools.gd:24hulls/compatible fittings,300DPbuilder, deterministic fixtures/replay/results, career isolation and explicit opt-in short-test tools.
- sound.gd, combat_art.gd: six CC0 recording families/three cuts each, bounded32voice spatial pool, short distinct muzzle/impact/water effects and staged sinking. Quiet engine bed is original/procedural.
- music.gd, preferences.gd:18owner-supplied Lyria tracks in eight roles, complete variation cycles, live portable/Desktop scan and separate persistent presentation settings.
- game/tests/:22native suites. tools/check_game.py serializes them with isolated APPDATA and per-suite timeouts; script errors fail even on exit0.
- tools/qa_brass.py, fleet_bench.gd, bench_scenarios.json: seven short isolated CPU benchmarks including40boats at300DPper side and physical outward-arc coverage.
- tools/check_visuals.py, feedback_gallery.gd, render_feedback_gallery.py, presentation_bench.gd: short cached-render animation captures, mesh/impact/sinking geometry checks and actual Main CPU timings.
- tools/boat_gallery.gd, render_boat_gallery.py, audit_boat_geometry.gd: exact code drawing capture/software PNG/GIF and360heading native polygon checks.
- tools/sync_music.py, verify_legacy_save.gd: owner audio copy/hash manifest and read-only real-save migration verification.
- tools/release_game.py: clean exact-tag native Windows export, icon/PCK/menu/campaign/save/battle checks, RELEASE.json and portable ZIP.
- tools/publish_github.py: verified exact repository, clean main/tag ancestry, atomic non-forced publish of all playable tags and exact remote verification. No interactive sign-in UI.

Read BUILD PLAN.txt for original acceptance and version notes/verdicts for actual changes/corrections. ROADMAP.md and docs/CAMPAIGN ROADMAP.txt describe proposed campaign milestones, actual v0.007 gaps, integration seams and future acceptance; none of those proposed systems is claimed as delivered. Source captures and numerical/codec checks do not substitute for voluntary foreground play or listening.
