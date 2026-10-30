"""Regenerate short verified symbol maps and source size inventory."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
BUILD = int(re.search(r"BUILD: int\s*=\s*(\d+)", (ROOT / "game/scripts/version.gd").read_text()).group(1))
VERSION = f"{BUILD // 1000}.{BUILD % 1000:03d}"
GROUPS = {
    "voyage-work070": (["voyage_jobs","voyage_region070","campaign","contacts","voyage_ui","voyage_panel070"],
                       "Known physical work berths -> the existing funded job/escrow/manifest; private regional routes, selected current-fleet costs, return reserves and paid support roles. HOME service gates remain separate.",
                       "test_voyage_career070; current actual receipts in work/quality-v070 and docs/TEST RESULTS v0.070.md after native verification"),
    "equipment-lifecycle": (["equipment_lifecycle", "equipment_campaign", "equipment_recovery", "campaign", "save_validation", "harbor", "naval_replacements", "boarding_ops"],
                            "Constructors and saved careers -> immutable physical births, global custody checks and preserved equipment on capture. Multiple prizes stage without duplicate custody; source payload cannot forge condition or increase an actual donor hull's HP. Harbor merges paid service, commission journal compatibility and lifecycle purchases.",
                            "Custody75/7 before to75/0 after; commission/repair204/9 before to204/0 after. Merged life75/UI167/save89/naval227/service204/NPC140/campaigncoins458 all pass. Final-fitting order-stat refresh purity24/0. Exact evidence: docs/ROOT COMBINED EQUIPMENT VERIFICATION. Working live/tow union has Lab99/0, equipment voyage67/0 and salvage voyage14/0; MainUI167/save89/player204/owner140/coins458 pass; canonical40 performance and release remain open."),
    "equipment-interfaces": (["equipment_ui_controller", "equipment_picker", "equipment_ui", "workshop_ui", "refit_ui", "equipment_owner_service", "fleet_economy", "naval_combat"],
                             "Physical part condition and exact spare/new selection -> real refit/repair UI and96-hull drafts. NPC/company owners pay conserved coins, finite materials and workers; installed condition affects offscreen power. Canonical careers and saves are integrated; live battle is now a working integration candidate; remaining gates stay open.",
                             "Current merged actual Main/Interface UI167/0, NPC140/0 and naval AI227/0: docs/ROOT COMBINED EQUIPMENT VERIFICATION. Prior standalone UI168/0 and unchanged legacy fleet economy1266/0 are historical component evidence under ROOT EQUIPMENT INTERFACES INTEGRATION."),
    "equipment-service": (["equipment_service", "harbor"],
                          "Paid installed-part and hull restoration: detached quote/validation/staging, real kits/materials/purses/workers, in-place commit, stable UIDs and untouched locker spares. Combined career/save/UI service is integrated; live battle is now a working integration candidate; remaining gates stay open.",
                          "Current merged player service204/0, NPC/company140/0 and campaign_cash458/0: docs/ROOT COMBINED EQUIPMENT VERIFICATION. Prior enhanced fixture133/9 before to133/0 after: ROOT PAID HARBOR INTEGRATION."),
    "equipment-condition": (["equipment_condition", "equipment_records", "equipment_ui", "equipment_fitting", "equipment_damage", "damage", "equipment_campaign", "equipment_recovery"],
                            "Core/Records, paid physical fitting/damage and whole-campaign custody preflight feed integrated constructors/save migration/UI and paid Harbor/NPC service. Working live combat/tow has Lab99/0, equipment voyage67/0 and salvage voyage14/0; remaining gates stay open; legacy counts cannot create free perfect parts.",
                            "Core90, Records89, catalogue651/24hulls, panel49, fitting324/refit352/workshop85 and Damage174 are prior proof. Merged lifecycle75/UI167/save89/naval227/service204/NPC140/campaigncoins458: ROOT COMBINED EQUIPMENT VERIFICATION. Isolated weapons27/0, corrected AI-role16/0 (old16/1 retained),1800 exact private-prediction samples; performance open: ROOT ROLLOUT STATUS REUSE VERIFIED."),
    "equipment-live": (["equipment_combat", "equipment_rollout", "equipment_tow", "equipment_lifecycle", "fleet_lab", "salvage"],
                       "Working v0.031 integration candidate: copied numerical prediction, live machinery condition, preserved physical wrecks and paid tow, plus canonical title Lab boats. No release acceptance.",
                       "Root Lab99/0, equipment_voyage67/0, salvage_voyage14/0. Root accepted MainUI167/save89/player204/owner140/coins458, all0 failures. Canonical40 reached88/150 warmup ticks in40s; performance and release remain open. Kernel public/binary and R5 component proofs: docs/VERIFICATION INDEX.txt."),
    "development": (["main", "preferences", "interface", "version"],
                    "Main-thread lifetime/input/portable preferences -> saved careers and isolated laboratory. tools/check_game.py runs registered native suites; tools/advance_series.py records sequential source milestones/logs; tools/release_game.py requires separate clean exact-tag Windows proof.",
                    "test_runtime, test_commander, test_laboratory, test_workshop_ui; source evidence: docs/TEST RESULTS v0.029.md"),
    "shipping-companies": (["shipping_companies","company_ops","company_ui"],
                           "Actual player hulls, crews, purses and fixed physical routes -> shared-stock trade, material/hull basis, paid operation, real losses and physical recall.",
                           "test_shipping_companies, test_company_voyage"),
    "civilian-trade": (["regional_goods","civilian_goods_ops","regional_goods_ui"],
                       "Actual geography, remaining paid workers and ingredients -> regional lots; household savings, physical cargo/freight, dated markets and copied zero-column save migration.",
                       "test_regional_goods, test_civilian_voyage"),
    "worker-conditions": (["worker_conditions","worker_ops","worker_ui"],
                          "Actual paid jobs and purchased food -> harbor conditions; funded workplace shifts, material relief and elapsed negotiated recovery.",
                          "test_worker_conditions, test_conditions_voyage"),
    "industrial-development": (["industrial_tooling","tooling_ops","yard_development","tooling_ui"],
                               "Actual surveyed sources, crews, owned workshops and paid teams -> finite transported machinery, recipe labor bottlenecks and chartered drydock bays.",
                               "test_industrial_tooling, test_industrial_voyage"),
    "harbor-reserves": (["harbor_reserves","reserve_ops","supply_ui"],
                        "Actual consumption, route times and paid workers -> separate coverage, protected operating lots, feasible allocation floors and real public release.",
                        "test_harbor_reserves, test_supply_voyage"),
    "workforce-training": (["crew_training","training_ops","economic_ui"],
                          "Existing civilian people and funded course inputs -> reserved trainees, qualified recruits, paid wages and refund-safe cancellation.",
                          "test_crew_training, test_training_voyage"),
    "regional-goals": (["regional_campaigns","regional_rules","regional_orders","regional_ops","regional_ui"],
                       "Existing corridor fleets and paid supplies -> shared convoy/intercept/patrol plans, route-and-return readiness, observed stalls/resume and physical progress; other regional goals retained.",
                       "test_supplied_operations037, test_operation_flow037; earlier test_regional_campaigns, test_regional_voyage"),
    "home-harbors": (["home_harbor","home_ops","home_ui"],
                     "Physical local materials/staff/coins -> paid shore stock, business payroll and earned-only dividends, private/public berths and arrears.",
                     "test_home_harbor, test_home_voyage"),
    "coastal-stories": (["coastal_stories","story_ops","story_offers","story_ui"],
                       "Four original chains and actual survey/delivery/contact choices -> persistent branches, rights and finite funded opportunities.",
                       "test_coastal_stories, test_story_voyage"),
    "fleet-identity": (["fleet_identity","fleet_support","identity_ui","escort_ops","battle_objectives"],
                      "Actual crew berths, wages and fittings -> paid specialists/conversions, useful support reserves and real timed convoy protection.",
                      "test_fleet_identity, test_support_voyage"),
    "naval-activity": (["naval_ai","naval_orders","naval_combat","naval_replacements","naval_lifecycle","naval_ui"],
                      "Existing companies, spatial positions, stores and shipyards -> actual trade, escorts/intercepts, paid combat, recovery and replacements.",
                      "test_naval_ai, test_naval_voyage, test_naval_recovery"),
    "trade-intelligence": (["trade_intel","trade_flow","trade_ui"],
                           "Dated actual harbor observations and supplied fleets -> cargo-limited route estimates, physical shortages and blockades.",
                           "test_trade_intel, test_reactive_trade"),
    "politics": (["factions","politics","faction_ui"],
                 "Witnessed player actions, public standing, claims and faction pairs -> explained access, paid conduct and explicit commissions.",
                 "test_factions, test_political_voyage"),
    "voyage-jobs": (["voyage_jobs","civilian_work","passenger_transport","passenger_manifest","contacts","voyage_ui"],
                    "Real sponsors/stock/crew/time -> funded freight/fuel/charters, finite wild catch, actual carriers/people and witnessed captain memory.",
                    "test_civilian_work036, test_civilian_flow036; earlier test_voyage_jobs, test_voyage_flow"),
    "recovery": (["salvage","recovery_ui"],
                 "Actual destroyed hulls/site provenance -> persistent finite wrecks, selectable lots, paid tow and recovered blueprints.",
                 "test_salvage, test_salvage_voyage"),
    "expeditions": (["expedition","hold_manifest","economy_workers","campaign_ui","campaign_state_validation","exploration","island_site_art"],
                    "Traveling fleet/real stores -> cargo carriers, paid endurance, shore assignments, persistent discoveries and copied-port workers.",
                    "test_expedition, test_campaign_logistics, test_exploration, test_island_voyage"),
    "ocean-sector069": (["sector_world069","ocean_world064","ocean_travel066","shipping_flow068","sector_ui069","ocean_chart064","shipping_ui068"],
                         "Fresh seed -> saved 48-group geography/finite opening accounts; earned holdings, markets and surveys. Legacy voyages keep two regions. Pure spatial reads; player restore/transition prepares one generated grid alongside home and Glasswind.",
                         "test_sector_model069, test_sector_voyage069; native acceptance is recorded separately in docs/TEST RESULTS v0.069.md"),
    "campaign": (["main", "campaign", "contracts", "money", "campaign_guidance", "career_costs", "guidance_ui"],
                 "World/player orders and finished worker snapshots -> voyages, contracts, saves and purses; detached six-career cost/reward/entry guidance.",
                 "test_career_balance038, test_career_flow038; earlier test_campaign_cash, test_runtime, test_voyage"),
    "combat": (["battle", "damage", "deployment"],
               "Actual fleet hulls/captain orders -> persistent hull/crew/stores, shots, flooding, wrecks and result.",
               "test_damage, test_battle, test_tactics, test_runtime, test_voyage, test_commander"),
    "economy": (["economy", "industry_data", "goods", "fleet_economy"],
                "Fixed civilian pools/recipes/stock/ownership -> payroll, production, finite trade and resident/owner purses.",
                "test_economy, test_fleet_economy, test_campaign_cash"),
    "construction": (["construction", "harbor", "refit"],
                     "Physical bill/local prices/ordinary and expert workers/escrow -> paid hull building, repairs, stock and hires.",
                     "test_construction, test_refit, test_fleet_points, test_campaign_cash, test_voyage"),
    "navigation": (["navigation", "coast_migration"],
                   "Original island polygons/endpoints -> bounded precomputed water grid and safe water paths.",
                   "test_navigation, test_runtime, test_voyage"),
    "presentation": (["chart", "boat_art", "boat_portrait", "interface", "tactics_ui", "refit_ui", "finance_ui", "boat_deck_detail", "workshop_ui"],
                     "Campaign/battle telemetry -> main-thread canvas/UI. No fluid or animated crew.",
                     "test_runtime, test_art_workshop, test_workshop_ui; play questions in TO BE TESTED.md"),
    "workshop": (["fleet_workshop", "workshop_ui", "boat_portrait", "refit"],
                 "Owned living hull and knowledge-only draft -> physical-socket preview, finite stock/workforce/coin bill, stale-quote refusal and atomic main-thread publication preserving live hull/harbor references. Templates survive career restore; UI drafts never become equipment.",
                 "test_workshop, test_workshop_voyage, test_workshop_ui, test_art_workshop; unchanged test_refit, test_commander, test_save_validation, test_mount_layout"),
    "audio-effects": (["sound", "music", "combat_art", "combat_events", "weapon_art"],
                      "Typed bounded events -> recorded weapon voices, shaped effects, fitted weapon models and runtime music.",
                      "test_audio, test_combat_events; tools/audit_boat_geometry.gd and tools/boat_gallery.gd"),
    "equipment-options": (["mount_layout", "hull_profiles", "weapon_geometry", "preferences"],
                          "Shared physical chassis/equipment geometry and portable presentation preferences; canonical economic stats stay outside art.",
                          "test_mount_layout, test_presentation, test_refit"),
    "boat-feedback": (["motor_art", "hull_feedback", "boat_mesh_cache"],
                      "Actual transom / bounded hit records -> visible machinery, localized damage and cheap colored meshes; live weapons keep their firing plane.",
                      "test_feedback; tools/check_visuals.py, feedback_gallery.gd and presentation_bench.gd"),
    "laboratory": (["fleet_lab", "lab_ui", "dev_tools"],
                   "Title builder -> isolated normal300point battle, seeded replay/results and opt-in developer metrics.",
                   "test_laboratory, test_commander"),
}
EXCLUDED = {".git", ".godot", ".openai", "qa", "toolchain", "releases", "saves", "__pycache__"}


def main():
    folder = ROOT / "maps"
    folder.mkdir(exist_ok=True)
    for name, (scripts, state, tests) in GROUPS.items():
        lines = [f"BRASS TIDE — {name.upper()} MAP (generated; v{VERSION})", "", state, "", "FILES AND VERIFIED SYMBOLS"]
        for script in scripts:
            path = ROOT / "game" / "scripts" / f"{script}.gd"
            text = path.read_text(encoding="utf-8")
            lines.append(f"game/scripts/{script}.gd: {len(path.read_bytes())} bytes; {text.splitlines()[0]}")
            symbols = [(i, re.match(r"(?:static )?func (\w+)", line)) for i, line in enumerate(text.splitlines(), 1)]
            public = [(i, m[1]) for i, m in symbols if m and not m[1].startswith("_")]
            internal = [(i, m[1]) for i, m in symbols if m and m[1].startswith("_")]
            for i, symbol in (public + internal)[:6 if len(scripts)>5 else 12]:
                lines.append(f"  game/scripts/{script}.gd:{i} {symbol}()")
        lines += ["", "TESTS (game/tests/*.gd)", tests, "", "Full symbols: rg -n '^func |^static func ' on named files."]
        assert len(lines) < 80, name
        (folder / f"{name}.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    files = sorted(p for p in ROOT.rglob("*") if p.is_file()
                   and not any(part in EXCLUDED for part in p.relative_to(ROOT).parts)
                   and p != folder / "PROJECT MAP.txt" and p.suffix not in {".log", ".pyc"})
    lines = ["BRASS TIDE — SOURCE INVENTORY", "Generated by tools/update_maps.py; bytes. >40KB: read in parts. Code near60KB: split.", ""]
    for path in files:
        size = path.stat().st_size
        flag = " [READ IN PARTS]" if size > 40000 else ""
        if path.suffix in {".gd", ".py", ".js", ".cjs"} and size > 60000:
            flag += " [SPLIT REQUIRED]"
        lines.append(f"{size:8d}  {path.relative_to(ROOT).as_posix()}{flag}")
    lines.append(f"\nTOTAL: {len(files)} files, {sum(p.stat().st_size for p in files)} bytes; generated inventory excluded.")
    (folder / "PROJECT MAP.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Generated {len(GROUPS)} maps and {len(files)}-file inventory.")


if __name__ == "__main__":
    main()
