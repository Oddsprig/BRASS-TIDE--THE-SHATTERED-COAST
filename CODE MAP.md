# Brass Tide working source map — toward v0.031

Native project: game/. Canonical catalogue/geography: game/data/world.json. See
maps/PROJECT MAP.txt for sizes and targeted maps/ files for actual symbols/lines.
Historical JS prototype is archived. Planned modules do not exist until implemented.

LIVE-FRAME CANDIDATE CHECKPOINT - 25 OCTOBER 2026
The five live-frame modules remain isolated; Main still contains only the two
accepted private-copy changes. Original weapons-cadence job58762011 passes27/0
on exact R3B inputs3f89395f. Root checked native logs, all499 inputs, tool and
engine receipts, hidden/profile/lane settings and the empty ownership ledger.
The two isolation64/1 receipts remain: repair reached the jury cap, then ongoing
fire reduced final engine HP. Corrected fixture549f uses a separate canonical
engine at0.50 with no fire and retains strict HP gain plus actual supply debit.
Its new499-input stage92f012d3 preserves all other source and23 import files.
Native isolation3cf177bd and OLD recorderf1300c87 are QUEUED at this checkpoint.
Cold cost52a013 remains conditional on a verified isolation pass and exit audit.
R2 recorder source reverses all521 originals through112 edits. Preserved CPU
checks67/0 validate lossless bounded gzip; native feasibility is still pending.
The isolated NEW source overlay is not battle equivalence. Its actual adapted
builder hash needs a separately reviewed provenance verifier; never fake shared
builder identity or rewrite OLD evidence to satisfy the frozen comparator.
Root proof files: ROOT FRAME WEAPONS R3B VERIFIED.json and
ROOT BATTLE OBSERVER R2 SOURCE VERIFIED.json. No performance/release acceptance.


| Area | Current files under game/scripts/ | Targeted map |
| --- | --- | --- |
| Lifetime, input, save/options | main, campaign, preferences, interface | development, campaign |
| Fleet ownership, voyage budgets, cargo | expedition, deployment, hold_manifest, fleet_support, fleet_identity | expeditions, fleet-identity |
| Tactical planning and physical gates | tactical_planner, tactical_role_plans, tactical_stations, tactical_runtime, tactical_routes, tactical_certification, tactical_fire_control, tactics_ui | tactical |
| Damage and combat | damage, battle, combat_events, combat_boarding, battle_objectives | combat, boat-feedback |
| Equipment custody, career migration and numerical part damage | equipment_condition, equipment_records, equipment_ui, equipment_fitting, equipment_damage, equipment_campaign, equipment_recovery, equipment_combat, equipment_rollout, equipment_tow | equipment-condition |
| Paid Harbor part restoration and material/worker bills | equipment_service, harbor | equipment-service |
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

Main has the verified14-module R4 union: equipment_combat, equipment_rollout,
equipment_tow plus11 updated existing modules. Lab99/voyage67/salvage14 and
MainUI167/save89/player204/NPC140/coins458 pass. Canonical40 warmup reached
88/150 in40s; performance remains open. See current BUILD STATUS, exact proof
ROOT COMBINED R4 GATES VERIFIED and ROOT CANONICAL40 PARTIAL VERIFIED.
Current tests:
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

Current verified copy changes: equipment_condition delays internal backups;
equipment_damage uses a small private repair guard. Shared math/status/publish
remain. See docs/MAIN PRIVATE OPTIMIZATION INTEGRATION.json for exact scope.
