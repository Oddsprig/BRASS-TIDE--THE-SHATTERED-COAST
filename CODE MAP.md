# Brass Tide working source map — toward v0.031

Native project: game/. Canonical catalogue/geography: game/data/world.json. See
maps/PROJECT MAP.txt for sizes and targeted maps/ files for actual symbols/lines.
Historical JS prototype is archived. Planned modules do not exist until implemented.

LIVE-FRAME CANDIDATE CHECKPOINT - 25 OCTOBER 2026
The five live-frame modules remain isolated; Main keeps only the two accepted
private-copy changes. Weapons-cadence58762011 passes27/0. Corrected repair
3cf177bd produced native67/0 with unchanged inputs and exited original children.
Its outer supervisor FAILED after native completion; that failure and unknown
cause remain separate. Original isolation64/1 records are preserved.
Cold diagnostic734be351 passes51/0:24 actual updates,40 canonical boats afloat,
300DP per side. Mean whole274.9235ms / AI179.2996ms / other95.6239ms; prior R4
cold means407.8069/295.3393/112.4676ms. Same last work4rollouts/240samples/3077
clearance tests and normalLimit7. This is cold data, not FPS or capacity.
Full R2 recorder463f9bac hit60s with12777415B partial trace and no terminal
manifest/count. Preserve it; no unchanged retry, raised bound or NEW full-family
run. Corrected metadata followed an earlier pre-launch rejection, not a test pass.
A smaller complete integration-fixture plan and finer hotspot measurement are
source work. Original battle regressions remain intact. Physical motion adapter
work uses original legacy-only scenarios and does not certify canonical gear.
Proofs: ROOT FRAME REPAIR R1 NATIVE VERIFIED OUTER FAILED.json,
ROOT FRAME COST R3B NATIVE VERIFIED.json and
ROOT BATTLE OBSERVER R2 INCOMPLETE VERIFIED.json. No performance/release acceptance.


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
