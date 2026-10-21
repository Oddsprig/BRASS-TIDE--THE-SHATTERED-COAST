"""Finalize one reviewed build with explicit paths, clean-tag tests and a preserved Windows delivery."""
import argparse
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path(r"C:\Users\bligh\Documents\Codex\2026-09-25\we-x20\work\engine\Godot_v4.7.2-stable_win64_console.exe")


def run(args, cwd=ROOT):
    print("Running " + " ".join(str(x) for x in args[:3]),flush=True)
    result = subprocess.run([str(x) for x in args], cwd=cwd, text=True, encoding="utf-8", errors="replace",
                            capture_output=True,
                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    if result.stdout:print(result.stdout,flush=True)
    if result.stderr and result.returncode:print(result.stderr,flush=True)
    if result.returncode:
        raise SystemExit(f"Step failed ({result.returncode}): {args[0:3]}")


def output(args, cwd=ROOT):
    return subprocess.check_output(args, cwd=cwd, text=True, encoding="utf-8", errors="replace").strip()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--build", type=int, required=True)
    p.add_argument("--title", required=True)
    p.add_argument("--feature", action="append", default=[])
    p.add_argument("--approved-files", type=Path, required=True)
    p.add_argument("--source-logs", type=Path, required=True)
    args = p.parse_args()
    version = f"0.{args.build:03}"
    work = ROOT.parents[1] / "work"
    approved = [line.strip() for line in args.approved_files.read_text(encoding="utf-8").splitlines() if line.strip()]
    for name in approved:
        path = (ROOT / name).resolve()
        if not path.is_relative_to(ROOT) or ".git" in path.relative_to(ROOT).parts:
            raise SystemExit("Invalid reviewed path: " + name)
    command = ["python", "tools/prepare_campaign_release.py", "--build", str(args.build), "--title", args.title, "--accept-logs", str(args.source_logs.resolve())]
    for feature in args.feature:
        command += ["--feature", feature]
    run(command)
    run(["python", "tools/import_game.py", "--engine", ENGINE, "--log", work / "qa" / f"v{args.build:03}-pretag-import.log"])
    run(["python", "tools/update_maps.py"])
    # Every staged source path was reviewed by root; generated identities/maps are an explicit bounded set.
    identities = [name for name in output(["git", "ls-files", "--others", "--exclude-standard"]).splitlines()
                  if re.fullmatch(r"game/(scripts|tests)/[^/]+\.gd\.uid", name)]
    maps = [p.relative_to(ROOT).as_posix() for p in (ROOT / "maps").glob("*.txt")]
    files = sorted(set(approved + identities + maps))
    run(["git", "add", "--", *files])
    run(["git", "diff", "--cached", "--check", "--", ".", ":(exclude)docs/helper-reports/*"])
    run(["git", "commit", "-m", f"Build v{version} {args.title.lower()}"])
    if output(["git", "status", "--porcelain"]):
        raise SystemExit("Unreviewed files remain after explicit commit; no tag or export created.")
    run(["git", "tag", "-a", f"v{version}", "-m", f"v{version} {args.title}"])
    checkout = work / f"release-v{version}"
    run(["git", "worktree", "add", "--detach", checkout, f"v{version}"])
    run(["python", "tools/check_game.py", "--engine", ENGINE, "--logs", work / "qa" / f"release-v{args.build:03}"], cwd=checkout)
    # Godot may normalize CRLF in import sidecars. Require no content diff before refreshing their index.
    run(["git", "diff", "--exit-code", "--", "game/assets"], cwd=checkout)
    run(["git", "add", "-u", "--", "game/assets"], cwd=checkout)
    if output(["git", "status", "--porcelain"], cwd=checkout):
        raise SystemExit("Clean-tag checkout changed unexpectedly; no export created.")
    run(["python", "tools/release_game.py", "--engine", ENGINE, "--release-dir", ROOT.parent / f"Brass Tide v{version}", "--logs", work / "qa" / f"export-v{args.build:03}"], cwd=checkout)
    run(["python", "tools/complete_campaign_delivery.py", "--build", str(args.build)])
    run(["python", "tools/update_launcher.py", "--build", str(args.build)])
    print(f"v{version} completed sequentially; prior releases retained.", flush=True)


if __name__ == "__main__":
    main()
