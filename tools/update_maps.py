"""Regenerate short verified symbol maps and source size inventory."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
BUILD = int(re.search(r"BUILD: int\s*=\s*(\d+)", (ROOT / "game/scripts/version.gd").read_text()).group(1))
VERSION = f"{BUILD // 1000}.{BUILD % 1000:03d}"
GROUPS = {
    "equipment-condition": (["equipment_condition"],
                            "Unused numerical component: exact physical item custody, condition, bounded jury repair and legacy projection. Live damage, paid fitting, harbor, save and recovery adapters remain pending.",
                            "test_equipment_condition (90 native checks on recorded inputs); docs/QA EQUIPMENT CORE v0.031.txt. No live feature acceptance."),
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
                       "Chosen real ports/factions and physical receipts -> sustained watches, paid development, survey achievements, optional finite treaties and bounded history.",
                       "test_regional_campaigns, test_regional_voyage, test_campaign_endurance"),
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
    "voyage-jobs": (["voyage_jobs","contacts","voyage_ui"],
                    "Real sponsors/stock/crew-based quotes -> several funded jobs, physical sealed lots, remembered contacts and dated observations.",
                    "test_voyage_jobs, test_voyage_flow"),
    "recovery": (["salvage","recovery_ui"],
                 "Actual destroyed hulls/site provenance -> persistent finite wrecks, selectable lots, paid tow and recovered blueprints.",
                 "test_salvage, test_salvage_voyage"),
    "expeditions": (["expedition","hold_manifest","economy_workers","campaign_ui","campaign_state_validation","exploration","island_site_art"],
                    "Traveling fleet/real stores -> cargo carriers, paid endurance, shore assignments, persistent discoveries and copied-port workers.",
                    "test_expedition, test_campaign_logistics, test_exploration, test_island_voyage"),
    "campaign": (["main", "campaign", "contracts", "money"],
                 "World/player orders and finished worker snapshots -> voyages, contracts, saves and purses.",
                 "test_campaign_cash, test_runtime, test_voyage"),
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
