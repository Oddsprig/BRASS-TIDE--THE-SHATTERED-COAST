"""Compile/export and package an UNTESTED Windows build. Never launches the game."""
import argparse
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
FLAGS = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def git(*args):
    hooks = ROOT / "qa/build-only-empty-hooks"
    hooks.mkdir(parents=True, exist_ok=True)
    return subprocess.check_output(["git", "-c", "core.hooksPath=" + str(hooks), *args], cwd=ROOT, text=True,
                                   encoding="utf-8", creationflags=FLAGS).strip()


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def clean_tag(tag):
    commit = git("rev-parse", "HEAD")
    if git("rev-parse", tag + "^{commit}") != commit:
        raise RuntimeError("Build checkout must equal the named immutable source tag.")
    if git("status", "--porcelain"):
        raise RuntimeError("Build checkout must be clean.")
    return commit


def export(args):
    commit = clean_tag(args.tag)
    if args.stage.exists():
        raise RuntimeError("Preserve the earlier stage; select a new empty stage directory.")
    args.stage.mkdir(parents=True)
    args.logs.mkdir(parents=True, exist_ok=True)
    executable = args.stage / "Brass Tide.exe"
    env = os.environ.copy()
    env["APPDATA"] = str(args.logs / "appdata")
    calls = []
    # These are editor/compiler/export commands only. No game, script, smoke or test.
    commands = [
        ("import", [args.engine, "--headless", "--audio-driver", "Dummy", "--path", ROOT / "game", "--editor", "--import", "--quit"]),
        ("export", [args.engine, "--headless", "--audio-driver", "Dummy", "--path", ROOT / "game", "--export-release", "Windows Portable", executable]),
    ]
    for name, command in commands:
        started = time.time()
        child = subprocess.Popen([str(x) for x in command], cwd=ROOT, env=env,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 creationflags=FLAGS | (subprocess.BELOW_NORMAL_PRIORITY_CLASS if os.name == "nt" else 0))
        timed_out = False
        try:
            output, _ = child.communicate(timeout=180)
        except subprocess.TimeoutExpired:
            timed_out = True
            child.kill()  # Exact owned compiler child only.
            output, _ = child.communicate()
        log = args.logs / (name + ".log")
        log.write_bytes(output)
        calls.append({"purpose": "build " + name, "command": [str(x) for x in command],
                      "pid": child.pid, "exit_code": child.returncode,
                      "seconds": time.time() - started, "timed_out": timed_out,
                      "log": str(log), "log_sha256": digest(log)})
        text = output.decode("utf-8", errors="replace")
        write_json(args.stage / "BUILD COMMANDS.json", calls)
        if timed_out or child.returncode or re.search(r"SCRIPT ERROR:|(?m:^ERROR:)|Parse Error", text):
            raise RuntimeError("Compiler/export failed; retained log: " + str(log))
        print("Completed build " + name + "; no game or tests launched.", flush=True)
    if not executable.is_file() or not executable.with_suffix(".pck").is_file():
        raise RuntimeError("Export did not produce the executable and matching PCK.")
    shutil.copy2(ROOT / "game/assets/Brass Tide.ico", args.stage / "Brass Tide.ico")
    write_json(args.stage / "BUILD EXPORT.json", {
        "status": "COMPILED/EXPORTED ONLY; UNTESTED", "source_commit": commit,
        "source_tag_at_export": args.tag, "engine": "Godot 4.7.2.stable.official.ed1daf0bf",
        "engine_sha256": digest(args.engine), "commands": calls,
        "game_launched": False, "tests_run": False,
        "files": {p.name: digest(p) for p in args.stage.iterdir() if p.suffix in [".exe", ".pck", ".ico"]}})


def package(args):
    commit = clean_tag(args.tag)
    proof = json.loads((args.stage / "BUILD EXPORT.json").read_text(encoding="utf-8"))
    if proof["source_commit"] != commit:
        raise RuntimeError("Package source differs from the compiled source.")
    build = int(re.search(r"BUILD: int\s*=\s*(\d+)", (ROOT / "game/scripts/version.gd").read_text()).group(1))
    version = f"{build // 1000}.{build % 1000:03d}"
    if args.tag != "v" + version:
        raise RuntimeError("Final tag must match the game version.")
    dest = args.destination
    source_zip = dest.with_name(dest.name + " Godot source.zip")
    windows_zip = dest.with_name(dest.name + " Windows x64.zip")
    if any(p.exists() for p in [dest, source_zip, windows_zip]):
        raise RuntimeError("Preserve existing deliveries; destination must be new.")
    dest.mkdir(parents=True)
    for name in ["Brass Tide.exe", "Brass Tide.pck", "Brass Tide.ico", "BUILD EXPORT.json", "BUILD COMMANDS.json"]:
        shutil.copy2(args.stage / name, dest / name)
    docs = dest / "docs"
    docs.mkdir()
    for name in ["AGENTS.md", "CODE MAP.md", "HANDOFF.md", "ROADMAP.md", "VERSION MAP.txt", "DEV LOG.txt", "TO BE TESTED.md", "VERSIONS.md", "BUILD STATUS.txt", f"CHANGES v{version}.md"]:
        path = ROOT / name
        if path.is_file():
            shutil.copy2(path, docs / name)
    for name in ["ECONOMY.md", "ORIGINALITY AND CREDITS.md", "BUILD AND TEST.md", "CODEX PORTABLE BUILD RULES.txt", "CAPTAINS CAMPAIGN GUIDE.txt", "ECONOMY QUICK START.txt", "CAMPAIGN ROADMAP.txt", f"DEFERRED TEST QUEUE v{version}.txt", f"ROOT REVIEW v{version}.txt", f"TEST RESULTS v{version}.md", f"SOURCE INTEGRATION v{version}.txt", f"SOURCE MANIFEST v{version}.json"]:
        path = ROOT / "docs" / name
        if path.is_file():
            shutil.copy2(path, docs / name)
    for name in ["legal", "audio", "helper-reports"]:
        if (ROOT / "docs" / name).is_dir():
            shutil.copytree(ROOT / "docs" / name, docs / name)
    for name in ["maps", "music"]:
        if (ROOT / name).is_dir():
            shutil.copytree(ROOT / name, dest / name)
    shutil.copy2(ROOT / "game/data/DEVELOPER NOTES.txt", dest / "DEVELOPER NOTES.txt")
    (dest / "UNTESTED - READ FIRST.txt").write_text(
        f"BRASS TIDE v{version} - UNTESTED BUILD\n\n"
        "Built at the owner's request with all testing deferred. No game launch,\n"
        "smoke, battle, save, performance or UI test was run for this package.\n"
        "An earlier planner component run failed one screen-priority assertion;\n"
        "a source correction is included but has not been rerun.\n"
        "The previous verified v0.029 delivery remains available.\n"
        "Work stops after this version; all later version work is stopped.\n\n"
        "Play: open Brass Tide.exe and keep the PCK beside it.\n"
        "WASD: camera. Space: pause. Tab: tactical overview. U: autopilot.\n"
        "Tactical options select role, doctrine, formation, protected ally and fire rules.\n"
        "No owner voyage is included in the clean archives. Preserve originals.\n"
        "See the deferred test queue in docs/ and DEVELOPER NOTES.txt.\n", encoding="utf-8")
    shutil.copy2(dest / "UNTESTED - READ FIRST.txt", dest / "START HERE.txt")
    (dest / "Stable Rendering.vbs").write_text(
        'Set files = CreateObject("Scripting.FileSystemObject")\n'
        'Set runner = CreateObject("WScript.Shell")\n'
        'folder = files.GetParentFolderName(WScript.ScriptFullName)\n'
        'runner.CurrentDirectory = folder\n'
        'runner.Run Chr(34) & folder & "\\Brass Tide.exe" & Chr(34) & " --render-thread safe", 1, False\n', encoding="utf-8")
    manifest = {"game": "Brass Tide: The Shatter Coast", "version": version, "build": build,
                "source_commit": commit, "source_tag": args.tag, "platform": "Windows x86_64",
                "status": "UNTESTED BUILD", "tests": "DEFERRED AT OWNER REQUEST",
                "game_launched": False, "exported_background_smoke": [],
                "engine": proof["engine"], "engine_sha256": proof["engine_sha256"],
                "sha256": {p.relative_to(dest).as_posix(): digest(p) for p in sorted(dest.rglob("*")) if p.is_file()}}
    write_json(dest / "RELEASE.json", manifest)
    subprocess.run(["git", "archive", "--format=zip", "--prefix=brass-tide/", "--output", str(source_zip), args.tag], cwd=ROOT, check=True, creationflags=FLAGS)
    with zipfile.ZipFile(windows_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=1) as archive:
        for path in sorted(dest.rglob("*")):
            if path.is_file():
                archive.write(path, Path(dest.name) / path.relative_to(dest))
    archives = {}
    for path in [source_zip, windows_zip]:
        value = digest(path)
        path.with_name(path.name + ".sha256").write_text(value + "  " + path.name + "\n", encoding="utf-8")
        archives[path.name] = {"bytes": path.stat().st_size, "sha256": value}
    receipt = {"version": version, "source_commit": commit, "source_tag": args.tag,
               "status": "BUILD ONLY - UNTESTED", "tests": "DEFERRED AT OWNER REQUEST",
               "game_launched": False, "archives": archives, "build": proof,
               "owner_saves": "not included or changed by packaging", "later_versions": "STOPPED"}
    write_json(dest.with_name(dest.name + " BUILD ONLY.json"), receipt)
    print(f"Packaged UNTESTED build: {dest}\nNo tests or game launches. Stop after this version.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["export", "package"])
    parser.add_argument("--tag", required=True)
    parser.add_argument("--stage", required=True, type=Path)
    parser.add_argument("--engine", type=Path)
    parser.add_argument("--logs", type=Path)
    parser.add_argument("--destination", type=Path)
    args = parser.parse_args()
    if args.phase == "export":
        if not args.engine or not args.logs:
            parser.error("export needs --engine and --logs")
        export(args)
    else:
        if not args.destination:
            parser.error("package needs --destination")
        package(args)


if __name__ == "__main__":
    main()
