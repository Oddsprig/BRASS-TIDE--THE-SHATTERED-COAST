"""Regenerate short verified symbol maps and source size inventory."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
BUILD = int(re.search(r"BUILD: int\s*=\s*(\d+)", (ROOT / "game/scripts/version.gd").read_text()).group(1))
VERSION = f"{BUILD // 1000}.{BUILD % 1000:03d}"
GROUPS = {
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
    "presentation": (["chart", "boat_art", "boat_portrait", "interface", "tactics_ui", "refit_ui", "finance_ui"],
                     "Campaign/battle telemetry -> main-thread canvas/UI. No fluid or animated crew.",
                     "test_runtime; play questions in TO BE TESTED.md"),
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
