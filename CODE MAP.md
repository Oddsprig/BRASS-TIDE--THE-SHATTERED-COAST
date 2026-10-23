# Brass Tide v0.029 source map

Native project: game/. Canonical catalogue/geography: game/data/world.json. See
maps/PROJECT MAP.txt for sizes and targeted maps/ files for actual symbols/lines.
Historical JS prototype is archived. Planned modules do not exist until implemented.

| Area | Current files under game/scripts/ | Targeted map |
| --- | --- | --- |
| Lifetime, input, save/options | main, campaign, preferences, interface | development, campaign |
| Fleet ownership, voyage budgets, cargo | expedition, deployment, hold_manifest, fleet_support, fleet_identity | expeditions, fleet-identity |
| Damage and combat | damage, battle, combat_events, combat_boarding, battle_objectives | combat, boat-feedback |
| Paid fitting, knowledge templates and physical sockets | fleet_workshop, workshop_ui, refit, refit_ui, mount_layout, weapon_geometry | workshop, equipment-options |
| Boat/weapon/motor visuals | hull_profiles, boat_art, boat_deck_detail, weapon_art, motor_art, hull_feedback, boat_mesh_cache, combat_art | presentation, boat-feedback |
| Chart and routing | chart, navigation, route_cache, coast_migration | navigation |
| Economy and construction | economy, economy_workers, goods, industry_data, construction, harbor, fleet_economy, money | economy, construction |
| Labor/reserves/industry/wellbeing | crew_training, training_ops, harbor_reserves, reserve_ops, industrial_tooling, tooling_ops, yard_development, worker_conditions, worker_ops | workforce-training, harbor-reserves, industrial-development, worker-conditions |
| Civilian goods and companies | regional_goods, civilian_goods_ops, shipping_companies, company_ops | civilian-trade, shipping-companies |
| Exploration, wrecks and jobs | exploration, salvage, contacts, voyage_jobs, contracts | expeditions, recovery, voyage-jobs |
| Factions, NPC fleets and trade | factions, politics, naval_ai, naval_orders, naval_combat, naval_lifecycle, naval_replacements, trade_flow, trade_intel | politics, naval-activity, trade-intelligence |
| Customs, boarding and crises | trade_law, law_ops, boarding, boarding_ops, regional_crises, crisis_ops, passenger_manifest, passenger_transport | campaign |
| Stories, home harbor and goals | coastal_stories, story_ops, home_harbor, home_ops, regional_campaigns, regional_ops, campaign_guidance | coastal-stories, home-harbors, regional-goals |
| Restore preflight | save_validation, campaign_state_validation, coast_migration | campaign |
| Sound/music and test lab | sound, music, fleet_lab, lab_ui, dev_tools | audio-effects, laboratory |

Related *_ui scripts present module results on main. Worker tasks own copies;
join before publishing. Mount IDs/arcs/geometry are shared by fitting and combat.

Delivered source: v0.029; .030 tactical implementation is isolated in helpers. Current tests:
game/tests/ (70 named suites in tools/check_game.py; native results are recorded in
docs/TEST RESULTS v0.029.md). The original 66 fixtures retain their assertions;
workshop, art_workshop, workshop_voyage and workshop_ui cover the new milestone.
Tools:
check_game.py (native regression), qa_brass.py/fleet_bench.gd (seven CPU fixtures),
check_visuals.py and gallery/render/geometry tools (exact drawing/animation audits),
verify_legacy_save.gd (read-only migration), sync_music.py (owner audio manifests),
update_maps.py (static maps), advance_series.py (sequential source metadata and
actual-log recording), release_game.py (clean exact-tag Windows packaging),
update_launcher.* and publish_github.* (separately evidenced delivery actions).
Use docs/BUILD AND TEST.md and FAST DEV TOOLS.txt for current source/release scopes.

Current proof: docs/VERIFICATION INDEX.txt. Integration pitfalls: DEVELOPER LESSONS.
Future scope: ROADMAP.md and the .029-.038 main/AI/civilian contracts. Current simple
battle/NPC logic is not proof of future coordinated or multi-party AI behavior.
Recovery and retired context: docs/ARCHIVE INDEX.txt. Keep raw advisory reports
separate from code acceptance and actual run evidence.
