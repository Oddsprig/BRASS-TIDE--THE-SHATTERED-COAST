# Brass Tide v0.028 source map

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
- game/tests/:66 native suites. tools/check_game.py serializes them with isolated APPDATA and per-suite timeouts; script errors fail even on exit0.
- tools/qa_brass.py, fleet_bench.gd, bench_scenarios.json: seven short isolated CPU benchmarks including40boats at300DPper side and physical outward-arc coverage.
- tools/check_visuals.py, feedback_gallery.gd, render_feedback_gallery.py, presentation_bench.gd: short cached-render animation captures, mesh/impact/sinking geometry checks and actual Main CPU timings.
- tools/boat_gallery.gd, render_boat_gallery.py, audit_boat_geometry.gd: exact code drawing capture/software PNG/GIF and360heading native polygon checks.
- tools/sync_music.py, verify_legacy_save.gd: owner audio copy/hash manifest and read-only real-save migration verification.
- tools/release_game.py: clean exact-tag native Windows export, icon/PCK/menu/campaign/save/battle checks, RELEASE.json and portable ZIP.
- tools/publish_github.py: verified exact repository, clean main/tag ancestry, atomic non-forced publish of all playable tags and exact remote verification. No interactive sign-in UI.

Read BUILD PLAN.txt, version notes/verdicts and delivery receipts for actual changes and verification. ROADMAP.md and docs/FLEET CAMPAIGN VERSION MAP v0.029-v0.038.txt record the next ten PLANNED versions; game remains v0.028. The completed economy-stage record is docs/ECONOMY DEVELOPMENT v0.019-v0.028.txt. Original planning/code-map snapshots are retained in docs/history/2026-10-23 before v0.029-v0.038 planning/. New future modules do not exist merely because this plan names them. Source captures and numerical/codec checks do not substitute for actual visual review, voluntary play or listening.

- v0.011: voyage_jobs.gd owns finite side-job escrow and freight; contacts.gd owns harbor trust and dated observations; voyage_ui.gd presents these books. Campaign wrappers allocate sealed cargo and record actual visits/settlements. test_voyage_flow.gd covers lost cargo, once-only payment and the real menu.

- v0.012: factions.gd is the political ledger; politics.gd enforces services and records real events; faction_ui.gd presents standing, claims, safe conduct and explicit commission terms. test_political_voyage.gd exercises actual access, purses and menus.

- v0.013: naval_ai.gd coordinates naval_orders.gd, naval_combat.gd and naval_replacements.gd; naval_lifecycle.gd publishes travel, harbor recovery and finite wrecks into the campaign. naval_ui.gd shows nearby objectives. Per-port economy workers remain independent snapshots.

- v0.014: trade_intel.gd owns dated quotes and living-fleet blockade assessment; trade_flow.gd connects physical authored stations and daily port flags; trade_ui.gd shows finite buyer/route estimates. Main publishes one economic day before taking the next copied snapshot.

- v0.015: fleet_identity.gd owns paid interior/specialist records; fleet_support.gd handles reserve policy, discharge, losses and support accounting; identity_ui.gd exposes them. battle_objectives.gd and escort_ops.gd connect real timed convoy protection to the same battle/deployment engine. naval_recovery regressions cover the independent Argon audit.

- v0.016: coastal_stories.gd plus data/coastal_stories.json define original chains; story_ops.gd applies choices/rights and physical public salvage; story_offers.gd creates finite ordinary freight opportunities; story_ui.gd presents narratives, gates and next locations.

- v0.017: home_harbor.gd owns paid shore businesses, employees, local inventories and standard material basis; home_ops.gd owns private/public berths and arrears; home_ui.gd presents establishment, stock, capital and earned-only dividends. Canonical money and save validation include business purses and staff.

- v0.018: regional_campaigns.gd owns optional goal/grant/treaty records; regional_rules.gd owns distinct-day progress, physical locality, diplomatic conditions and expiry; regional_orders.gd assigns actual corridor patrol routes beneath normal recovery priorities; regional_ops.gd records actual paid deliveries/combat and publishes daily progress; regional_ui.gd presents the selected goals (L). test_campaign_endurance runs 180 published economic days with the real worker pool.

- v0.019: crew_training.gd owns finite qualification subsets, reserved trainee/instructor cohorts, paid material and wage escrow, completion and cancel rules. training_ops.gd enforces harbor access; economic_ui.gd shows full quotes and course accounts. Economy ticks copied local jobs; Money.port_total counts their escrow once and SaveValidation preflights it before restore.

- v0.020: harbor_reserves.gd computes read-only demand/coverage/export availability and feasible priority floors; reserve_ops.gd publishes actual recipe/convoy observations and route horizons, enforces policy authority and transfers real granary lots; supply_ui.gd presents it. Economy/Fleets purchases use the same availability, and copied local production reserves essential work within the shared paid workforce.

Industrial development: industrial_tooling.gd owns finite item identities and commissioning; tooling_ops.gd binds actual surveys, crews, physical recovery and paid workshop staffing/recipes; yard_development.gd owns five-day staffed bay escrow; tooling_ui.gd exposes those actions. Hold manifests carry equipment once; Money totals count only held bay wages. Tests: industrial_tooling and industrial_voyage.

Worker conditions: worker_conditions.gd owns bounded food/pay facts and workplace shifts; worker_ops.gd binds actual permissions, public registry foremen, material basis and the completed-day stamp; worker_ui.gd exposes owned policies and restart costs. Economy snapshots record actual food and fully funded employment; Home payroll feeds the same workers once. Tests: worker_conditions, conditions_voyage.

Civilian goods: regional_goods.gd owns bounded geographic paid production and actual household consumption; civilian_goods_ops.gd combines real wage/occupation telemetry and copied legacy zero-column migration; regional_goods_ui.gd shows full bills and actual supply/use. Existing regional_ops.gd still owns regional campaigns. Goods/IndustryData/save registries now contain20 items. Tests: regional_goods, civilian_voyage. tools/hidden_check.py stops fatal compiler failures through only the exact child it launched.

Shipping companies: shipping_companies.gd owns bounded company metadata, commercial basis and same-reference roster/purse transfers; company_ops.gd binds actual hulls, master wages, working/hull capital basis, fixed route policy and physical meetings; company_ui.gd exposes charter/route/account controls and water-route payroll estimates. Fleet economy records real trade/pay/repair events. Naval lifecycle/orders keep physical travel and emergency repair; private replacements/subsidies are blocked. Tests: shipping_companies, company_voyage.
