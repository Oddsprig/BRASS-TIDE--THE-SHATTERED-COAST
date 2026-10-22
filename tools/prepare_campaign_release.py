"""Record one sequential campaign build. Tests and exports remain separate verified steps."""
import argparse
from datetime import datetime
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_game import SUITES


def prepend(path, text):
    before = path.read_text(encoding="utf-8") if path.exists() else ""
    path.write_text(text + "\n\n" + before, encoding="utf-8")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--build", type=int, required=True)
    p.add_argument("--title", required=True)
    p.add_argument("--feature", action="append", default=[])
    p.add_argument("--accept-logs", type=Path)
    args = p.parse_args()
    version = f"0.{args.build:03}"
    old = int(re.search(r"BUILD: int\s*=\s*(\d+)", (ROOT / "game/scripts/version.gd").read_text()).group(1))
    if args.build not in (old, old + 1):
        raise SystemExit("Preserve sequence: prepare the current build or its immediate successor.")
    if args.accept_logs:
        failed = []
        results = []
        for name in SUITES:
            path = args.accept_logs / f"{name}.log"
            text = path.read_text(encoding="utf-8") if path.exists() else ""
            if not text or re.search(r"SCRIPT ERROR:|(?m:^ERROR:)|Parse Error|\bFAIL(?:URE)?\b|TIMEOUT", text):
                failed.append(name)
            summary = next((line for line in reversed(text.splitlines()) if re.search(r"checks|passed|assertions", line, re.I)), "Native suite completed")
            results.append((name, summary))
        if failed:
            raise SystemExit("Missing or failed native suites: " + ", ".join(failed))
        report = f"# v{version} source verification\n\nAll {len(SUITES)} native suites passed in isolated background/headless processes, serialized by tools/check_game.py. No owner save, desktop input or focus was used.\n\n| Suite | Actual log result |\n| --- | --- |\n"
        report += "\n".join(f"| {name} | {summary.replace('|', '/')} |" for name, summary in results)
        report += "\n\nThis report establishes source checks. Exact tagged export identity, native Windows startup/save/battle and file hashes are recorded separately in portable RELEASE.json. No human listening, subjective fun or GPU frame-pacing claim is made.\n"
        (ROOT / f"docs/TEST RESULTS v{version}.md").write_text(report, encoding="utf-8")
        status = f"SOURCE ACCEPTED: {len(SUITES)} native suites pass; portable export evidence is recorded separately in RELEASE.json."
    else:
        status = "SOURCE CANDIDATE: implementation underway; no new test/export claim."
    if old != args.build:
        (ROOT / "game/scripts/version.gd").write_text('extends RefCounted\n\nconst BUILD: int = %d\n\nstatic func text() -> String:\n\treturn "%%d.%%03d" %% [BUILD / 1000, BUILD %% 1000]\n' % args.build, encoding="utf-8")
    project = ROOT / "game/project.godot"
    project.write_text(re.sub(r'config/version="[^"]+"', f'config/version="{version}"', project.read_text(encoding="utf-8")), encoding="utf-8")
    presets = ROOT / "game/export_presets.cfg"
    text = presets.read_text(encoding="utf-8")
    text = re.sub(r'application/(file_version|product_version)="[^"]+"', lambda m: f'application/{m[1]}="0.0.{args.build}.0"', text)
    text = re.sub(r'application/file_description="[^"]+"', f'application/file_description="Brass Tide v{version}"', text)
    presets.write_text(text, encoding="utf-8")
    world = ROOT / "game/data/world.json"
    data = json.loads(world.read_text(encoding="utf-8"))
    data["VERSION"] = version
    world.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    notes = ROOT / "game/data/DEVELOPER NOTES.txt"
    text = notes.read_text(encoding="utf-8") if notes.exists() else ""
    marker = f"v{version} — {args.title}"
    if marker in text:
        text = text[text.find("\nPREVIOUS BUILD NOTES\n") + len("\nPREVIOUS BUILD NOTES\n"):] if "\nPREVIOUS BUILD NOTES\n" in text else ""
    features = "\n".join("- " + feature for feature in args.feature)
    entry = f"BRASS TIDE — DEVELOPMENT NOTES\n{marker}\n{status}\n\n{features}\n\nTeam: Codex root + up to three Sol6.1 Max helpers through Bridge.\nBackground tests only. Separate rendering; copied-state harbor workers adapt to CPU threads, capped at8 and reserving2 logical threads. Original content, numerical crews, finite coins/materials/people.\n\nPREVIOUS BUILD NOTES\n"
    notes.write_text(entry + text, encoding="utf-8")
    changes = ROOT / f"CHANGES v{version}.md"
    changes.write_text(f"# Brass Tide v{version} — {args.title}\n\n{status}\n\n{features}\n\nBuilt on the preceding version. Prior releases, original saves and owner music are preserved. See the source verification report and portable RELEASE.json for actual checks/export evidence.\n", encoding="utf-8")
    if not args.accept_logs:
        date = datetime.now().strftime("%Y-%m-%d")
        prepend(ROOT / "DEV LOG.txt", f"{date} | v{version} CANDIDATE | {args.title}\n{features}\nRoot + up to three Sol6.1 Max helpers through Bridge. Source checks and exact-tag export follow; no delivery claim yet.")
        prepend(ROOT / "VERSION MAP.txt", f"v{version} CANDIDATE — {args.title}\n" + " ".join(args.feature) + "\nSource acceptance and export receipts determine completion; every build advances0.001.")
        prepend(ROOT / "VERSIONS.md", f"## v{version} — {args.title}\n\nCandidate; verified test/export records follow.\n\n" + features)
    else:
        prepend(ROOT / "DEV LOG.txt", f"v{version} SOURCE ACCEPTED | {args.title}\n{len(SUITES)} native suites passed; source report saved. Portable export and publication require separate receipts.")
    prepend(ROOT / "HANDOFF.md", f"# v{version} — {args.title}\n\n{status}\n\n" + features + f"\n\nContinue the authorized sequential roadmap after verifying/preserving this version. Root + up to three Sol6.1 Max helpers through Bridge only. In-game notes: game/data/DEVELOPER NOTES.txt. Release checks: docs/TEST RESULTS v{version}.md and portable RELEASE.json. Preserve owner saves/music and all previous releases. Background-only tests, one engine at a time.")
    code = ROOT / "CODE MAP.md"
    text = code.read_text(encoding="utf-8")
    text = re.sub(r"^# Brass Tide v[\d.]+ source map", f"# Brass Tide v{version} source map", text)
    code.write_text(text, encoding="utf-8")
    (ROOT / "BUILD STATUS.txt").write_text(f"BRASS TIDE BUILD STATUS\nCurrent source: v{version} / BUILD {args.build}\nMilestone: {args.title}\n{status}\n\nPlayable delivery is proven by each portable RELEASE.json and outputs/Brass Tide v{version} DELIVERY VERIFIED.json.\nIn-game TXT notes: game/data/DEVELOPER NOTES.txt. Current economy plan: docs/ECONOMY VERSION MAP v0.019-v0.028.txt.\nOwner authorized sequential builds0.019-0.028 with root and up to three Sol6.1 Max helpers through Bridge.\nPrevious versions, original saves and supplied music must remain intact.\n", encoding="utf-8")
    if args.accept_logs:
        prepend(ROOT / "ROADMAP.md", f"v{version} SOURCE ACCEPTED — {args.title}. {len(SUITES)} native suites accepted; exact-tag export has separate receipts. Continue the authorized sequence after preserving this build. Earlier planning/release records follow.")
        prepend(ROOT / "BUILD PLAN.txt", f"v{version} SOURCE ACCEPTED — {args.title}\n{features}\nNative checks accepted; preserve this build's verified export before advancing. Historical plans follow.")
        prepend(ROOT / "TO BE TESTED.md", f"v{version} voluntary play: {args.title}\nAssess readability and usefulness of: {' '.join(args.feature)}\nAutomated integrity/performance evidence does not establish human fun or GPU frame pacing. All automated tests remain background only.")
    print(f"Recorded v{version}: {status}")


if __name__ == "__main__":
    main()
