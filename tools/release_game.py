"""Export and verify a tagged Windows game from a separate clean Git worktree."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def run(command, log, env, timeout=120):
    result = subprocess.run([str(x) for x in command], cwd=ROOT, env=env, capture_output=True,
                            text=True, encoding="utf-8", errors="replace", timeout=timeout,
                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    output = result.stdout + result.stderr
    log.write_text(output, encoding="utf-8")
    if result.returncode or re.search(r"SCRIPT ERROR:|(?m:^ERROR:)|Parse Error", output):
        raise RuntimeError(f"Failed ({result.returncode}); inspect {log}")
    return output.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--release-dir", required=True, type=Path)
    parser.add_argument("--logs", required=True, type=Path)
    args = parser.parse_args()
    dest = args.release_dir.resolve()
    logs = args.logs.resolve()
    logs.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["APPDATA"] = str(logs / "appdata")
    commit = run(["git", "rev-parse", "HEAD"], logs / "commit.log", env)
    tag = run(["git", "rev-parse", "v0.001^{commit}"], logs / "tag.log", env)
    if commit != tag:
        raise RuntimeError("Export checkout must be the exact v0.001 tag.")
    dirty = run(["git", "status", "--porcelain"], logs / "source-status.log", env)
    if dirty:
        raise RuntimeError("Release worktree must be clean before export.")
    if dest.exists() and (dest / "RELEASE.json").exists():
        raise RuntimeError("A verified release already exists here; preserve it and use a new version.")
    dest.mkdir(parents=True, exist_ok=True)
    engine = args.engine.resolve()
    executable = dest / "Brass Tide.exe"
    print("Importing the clean release worktree in the background.", flush=True)
    run([engine, "--headless", "--path", ROOT / "game", "--editor", "--import", "--quit"], logs / "import.log", env)
    print("Exporting native Windows executable and PCK.", flush=True)
    run([engine, "--headless", "--path", ROOT / "game", "--export-release", "Windows Portable", executable], logs / "export.log", env)
    assert executable.is_file() and executable.with_suffix(".pck").is_file()
    if os.name == "nt":
        extract = ctypes.windll.shell32.ExtractIconExW
        extract.argtypes = [ctypes.c_wchar_p,ctypes.c_int,ctypes.c_void_p,ctypes.c_void_p,ctypes.c_uint]
        extract.restype = ctypes.c_uint
        count = extract(str(executable), -1, None, None, 0)
        assert count > 0, "Native executable has no Windows icon resource"
    shutil.copy2(ROOT / "game/assets/Brass Tide.ico", dest / "Brass Tide.ico")
    print("Checking the exported game itself: menu, campaign/save and battle; no window/input.", flush=True)
    for name, hook in [("menu", []), ("campaign", ["--", "--qa-campaign"]), ("battle", ["--", "--qa-battle"])]:
        output = run([executable, "--headless", "--quit-after", "30", *hook], logs / f"portable-{name}.log", env, 30)
        assert "BRASS TIDE v0.001" in output, f"No verified game startup in {name}"
    # Preserve the newly generated test save outside the shipped game. Never delete user saves.
    saves = dest / "saves"
    if saves.exists():
        assert saves.resolve().parent == dest
        assert dest.is_relative_to(ROOT.parents[1]) and logs.is_relative_to(ROOT.parents[1])
        shutil.move(str(saves), str(logs / f"portable-test-saves-{time.time_ns()}"))
    docs = dest / "docs"
    docs.mkdir(exist_ok=True)
    for name in ["ECONOMY.md", "ORIGINALITY AND CREDITS.md", "BUILD AND TEST.md", "CODEX PORTABLE BUILD RULES.txt"]:
        shutil.copy2(ROOT / "docs" / name, docs / name)
    shutil.copytree(ROOT / "docs/legal", docs / "legal", dirs_exist_ok=True)
    for name in ["AGENTS.md", "CODE MAP.md", "HANDOFF.md", "ROADMAP.md", "VERSION MAP.txt", "DEV LOG.txt", "TO BE TESTED.md", "CHANGES v0.001.md"]:
        shutil.copy2(ROOT / name, docs / name)
    shutil.copytree(ROOT / "maps", dest / "maps", dirs_exist_ok=True)
    tests = dest / "tests"
    tests.mkdir(exist_ok=True)
    shutil.copy2(ROOT / "docs/TEST RESULTS v0.001.md", tests / "TEST RESULTS v0.001.md")
    shutil.copytree(ROOT / "docs/helper-reports", tests / "helper-reports", dirs_exist_ok=True)
    (dest / "START HERE.txt").write_text(START, encoding="utf-8")
    (dest / "Stable Rendering.vbs").write_text(STABLE, encoding="utf-8")
    hashes = {p.relative_to(dest).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted(dest.rglob("*")) if p.is_file()}
    manifest = {"game":"Brass Tide: The Shatter Coast", "version":"0.001", "build":1,
                "source_commit":commit, "source_tag":"v0.001", "platform":"Windows x86_64",
                "engine":run([engine,"--version"],logs / "engine-version.log",env),
                "exported_background_smoke":["menu","campaign and portable save","battle"],
                "sha256":hashes}
    (dest / "RELEASE.json").write_text(json.dumps(manifest,indent=2),encoding="utf-8")
    archive = dest.with_name(dest.name + " Windows x64.zip")
    with zipfile.ZipFile(archive,"w",zipfile.ZIP_DEFLATED,compresslevel=6) as package:
        for path in sorted(dest.rglob("*")):
            if path.is_file(): package.write(path,Path(dest.name)/path.relative_to(dest))
    print(f"Verified release: {dest}\nArchive: {archive}\nSource: {commit}", flush=True)


START = """BRASS TIDE: THE SHATTER COAST — v0.001

PLAY
Double-click Brass Tide.exe. No editor, installer, Node or Python is needed.
Keep the EXE and matching PCK together. You can move this whole portable folder.
Your voyage and backup are saved in saves/ beside the EXE after you start playing.

FIRST VOYAGE
Start a new campaign with one inherited Tinwake skiff and five sailors.
Enter Brass Haven, open Contracts, and accept the first story job.
Choose its destination on the chart, sail there, then resolve the contract.
Battles begin paused: inspect your boats, then press Space to start.
Victory releases the sponsor's escrow. Recover a wreck, hire sailors, repair it,
or buy a stronger hull to grow your fleet. You can field up to eight boats.
Use Voyage stores for an affordable short trip; Full stores fills long-range tanks.
Keep rations and wages paid. Inspect the Hold and Economy screens for real purses.

CONTROLS
Chart: click a harbor/open water to sail; right-click cancels the course.
Space pauses. Mouse wheel zooms. E harbor, F fleet, C hold, J contracts, H guide.
Battle: W/S throttle, A/D steer (or arrows), Shift boost; aim and hold left click.
R toggles automatic gunners. Tab changes flagship. 1 engage, 2 escort, 3 hold.
Fleet withdrawal is available in the battle controls; it takes twelve seconds.
Escape opens the captain's desk. F11 toggles fullscreen.

RENDERING
The normal launch uses separate rendering and background economy jobs.
If changing text flickers/disappears or the renderer becomes unstable, close the
game and launch Stable Rendering.vbs. This changes rendering for that launch only.
Godot's separate-thread font issue is documented in the test notes. Current final
graphics/FPS and human feel have not been tested in the foreground, as requested.

FOLDERS
docs/   Economy, credits/licenses, portable build rules and current source records.
maps/   Verified source/system maps for continuing development.
tests/  Actual automated evidence, helper reports and independent root verdict.
RELEASE.json  Exact source commit/tag and hashes of the delivered files.

This is the first playable version. Future releases advance by exactly 0.001.
The editable Godot source is delivered separately in the brass-tide source folder.
"""

STABLE = '''Set files = CreateObject("Scripting.FileSystemObject")
Set runner = CreateObject("WScript.Shell")
folder = files.GetParentFolderName(WScript.ScriptFullName)
runner.CurrentDirectory = folder
runner.Run Chr(34) & folder & "\\Brass Tide.exe" & Chr(34) & " --render-thread safe", 1, False
'''

if __name__ == "__main__":
    main()
