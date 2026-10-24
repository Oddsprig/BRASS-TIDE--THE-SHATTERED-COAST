"""Exact-input, serialized resume checks; no UI or live profile access."""
import argparse
import ctypes
from datetime import datetime, timezone
import hashlib
import json
import msvcrt
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from check_game import SUITES as ORIGINAL_SUITES

# Original 70 stay separate. Only completed tactical suites enter this registry.
TACTICAL_SUITES = ["tactical_planner", "tactical_memory", "tactical_dt",
                   "tactical_orders", "tactical_ui"]
DETACHED_SUITES = ["equipment_condition", "equipment_records", "equipment_ui", "equipment_catalog", "equipment_fitting", "equipment_damage", "equipment_campaign", "equipment_service"]
from hidden_check import run_hidden

DEFAULT_ENGINE = Path("C:/Users/bligh/Documents/Codex/2026-09-25/we-x20/work/engine/Godot_v4.7.2-stable_win64_console.exe")
DEFAULT_ENGINE_SHA = "c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643"
# Historical identity constants retained for diagnostic-tool compatibility.
# They authorize no launch: all Godot/Unity apps now block, even headless.
LATE_BARGE_ENGINE = Path("C:/Users/bligh/Documents/Codex/2026-09-17/referenced-chatgpt-conversation-this-is-an/work/tools/godot/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64.exe")
GUARD_POLICY = "Owner24Oct: queue behind ANY other Godot/Unity app, including known headless jobs/editors; unreadable discovery queues"
BRASS_ROOT = next((parent for parent in [ROOT, *ROOT.parents]
                   if (parent / "work/resume-v030-v038").is_dir()), ROOT)
LATE_BARGE_ROOT = Path("C:/Users/bligh/Desktop/The Late Barge")


def normalized(path):
    return str(path).replace("\\", "/").rstrip("/").casefold()


def within(path, root):
    path, root = normalized(path), normalized(root)
    return path == root or path.startswith(root + "/")


def command_args(command):
    # Native Windows tokenization; no shell execution and no guessed substrings.
    parser = ctypes.windll.shell32.CommandLineToArgvW
    parser.argtypes = [ctypes.c_wchar_p, ctypes.POINTER(ctypes.c_int)]
    parser.restype = ctypes.POINTER(ctypes.c_wchar_p)
    count = ctypes.c_int()
    pointer = parser(command, ctypes.byref(count))
    if not pointer:
        raise ValueError("Unreadable Windows command line")
    try:
        return [pointer[index] for index in range(count.value)]
    finally:
        free = ctypes.windll.kernel32.LocalFree
        free.argtypes = [ctypes.c_void_p]
        free.restype = ctypes.c_void_p
        free(ctypes.cast(pointer, ctypes.c_void_p))


def classify(row):
    # Owner24Oct: every other Godot/Unity app blocks, even a known headless job.
    # Keep the old field for receipt/runner compatibility; it is never an exemption.
    row = dict(row)
    row.update(permittedUnrelated=False,
               projectClassification="QUEUED_OTHER_ENGINE_APP",
               backgroundProof="",
               blockReason="Other Godot/Unity app running; wait before the next Brass engine launch")
    if not all(row.get(key) for key in ["Id", "StartUtc", "Path"]):
        row["blockReason"] = "Engine app identity unreadable; keep tests queued"
    return row


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def inventory():
    # Read current command lines on EVERY launch, so PID churn cannot turn an old
    # exception into a blanket Godot exemption. Host query needs approved access.
    query = "Get-CimInstance Win32_Process -Filter \"Name LIKE '%godot%' OR Name LIKE '%unity%' OR Name LIKE '%Brass%' OR ExecutablePath LIKE '%Godot%' OR ExecutablePath LIKE '%Unity%'\" | ForEach-Object { $row = $_; $p = Get-Process -Id $row.ProcessId -ErrorAction Stop; [pscustomobject]@{Id=$p.Id;ProcessName=$p.ProcessName;Path=$p.Path;MainWindowHandle=$p.MainWindowHandle;StartUtc=$p.StartTime.ToUniversalTime().ToString('o');CommandLine=$row.CommandLine} } | ConvertTo-Json -Compress"
    result = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", query],
        capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=10,
        creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode or result.stderr.strip():
        raise RuntimeError("Process guard unreadable; no engine launched: " + result.stderr)
    try:
        rows = json.loads(result.stdout) if result.stdout.strip() else []
    except (ValueError, TypeError) as error:
        raise RuntimeError("Process discovery unreadable; keep tests queued") from error
    rows = rows if isinstance(rows, list) else [rows]
    if not all(isinstance(row, dict) for row in rows):
        raise RuntimeError("Process identities unreadable; keep tests queued")
    return [classify(row) for row in rows]


def inputs():
    files = {}
    for path in sorted((ROOT / "game").rglob("*")):
        if path.is_file() and ".godot" not in path.relative_to(ROOT / "game").parts:
            files[path.relative_to(ROOT).as_posix()] = sha(path)
    raw = json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
    return {"sha256": hashlib.sha256(raw).hexdigest(), "files": files}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--import-only", action="store_true")
    parser.add_argument("--only", nargs="+", choices=ORIGINAL_SUITES + TACTICAL_SUITES + DETACHED_SUITES)
    parser.add_argument("--script", type=Path, help="Unregistered work-in-progress fixture in game/tests")
    parser.add_argument("--engine", type=Path, default=DEFAULT_ENGINE)
    parser.add_argument("--engine-sha256", default=DEFAULT_ENGINE_SHA)
    parser.add_argument("--timeout", type=int, choices=range(1, 61), default=60)
    parser.add_argument("--original-all", action="store_true", help="Explicit original 70 only; never includes unfinished tactical suites")
    parser.add_argument("--name", required=True)
    args = parser.parse_args()
    if sum([args.import_only, bool(args.only), args.original_all, bool(args.script)]) != 1:
        parser.error("Choose exactly one import-only, only, original-all or script mode")
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", args.name):
        parser.error("Simple unique evidence directory name required")
    engine = args.engine.resolve(strict=True)
    if not re.fullmatch(r"[0-9a-fA-F]{64}", args.engine_sha256):
        parser.error("Exact engine SHA256 required")
    script = args.script.resolve(strict=True) if args.script else None
    if script and (script.parent != ROOT / "game/tests" or not re.fullmatch(r"test_tactical_[a-z_]+\.gd", script.name)):
        parser.error("WIP script must be a direct game/tests/test_tactical_*.gd fixture")
    directory = ROOT / "qa" / args.name
    directory.mkdir(exist_ok=False)
    if sha(engine) != args.engine_sha256.lower():
        raise RuntimeError("Engine SHA mismatch; nothing launched")
    lease = (ROOT / "qa/ENGINE-QA.lease").open("a+b")
    if lease.tell() == 0:
        lease.write(b"0")
        lease.flush()
    lease.seek(0)
    msvcrt.locking(lease.fileno(), msvcrt.LK_NBLCK, 1)
    initial = inputs()
    write_json(directory / "inputs-before.json", initial)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    records = []
    preferred = ["battle", "tactics", "refit", "commander", "boarding", "boarding_voyage",
                 "runtime", "workshop_ui", "combat_events", "voyage_flow"]
    ordered = preferred + [name for name in ORIGINAL_SUITES if name not in preferred]
    suites = ["asset-import"] if args.import_only else [script.stem.removeprefix("test_")] if script else args.only or ordered
    for suite in suites:
        if inputs()["sha256"] != initial["sha256"]:
            raise RuntimeError("Frozen game input changed between cases; no next child launched")
        try:
            before = inventory()
        except RuntimeError as error:
            write_json(directory / "guard-blocked.json", {"error": str(error), "suiteNotLaunched": suite})
            print("BLOCKED: process identity unreadable; no new child launched", flush=True)
            break
        if any(not row["permittedUnrelated"] for row in before):
            write_json(directory / "guard-blocked.json", {"before": before, "suiteNotLaunched": suite})
            print("BLOCKED: unknown/owner engine; no new child launched", flush=True)
            break
        environment = os.environ.copy()
        environment["APPDATA"] = str(directory / "profiles" / suite / "roaming")
        environment["LOCALAPPDATA"] = str(directory / "profiles" / suite / "local")
        environment["GODOT_SILENCE_ROOT_WARNING"] = "1"
        command = [str(engine), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game")]
        command += (["--editor", "--import", "--quit"] if args.import_only else
                    ["--script", f"res://tests/test_{suite}.gd", "--",
                     "--out=" + str(directory / (suite + "-observations.json"))])
        record = {"suite": suite, "head": head, "gameInputSha256": initial["sha256"],
            "engineSha256": sha(engine), "runnerSha256": sha(Path(__file__)),
            "originalRegistrySha256": sha(ROOT / "tools/check_game.py"),
            "scriptSha256": sha(ROOT / f"game/tests/test_{suite}.gd") if not args.import_only else None,
            "hiddenRunnerSha256": sha(ROOT / "tools/hidden_check.py"), "command": command,
            "timeoutSeconds": args.timeout, "priority": "BELOW_NORMAL", "audio": "Dummy",
            "profile": environment["APPDATA"], "externalBefore": before,
            "guardPolicy": GUARD_POLICY, "contention": "CONTENDED" if before else "No external engine observed; idle host not established",
            "startedUtc": datetime.now(timezone.utc).isoformat()}
        receipt = directory / (suite + ".json")

        def started(pid):
            record["pid"] = pid
            record["status"] = "running"
            write_json(receipt, record)

        clock = time.monotonic()
        try:
            result = run_hidden(command, env=environment, timeout=args.timeout, on_started=started)
            output = result.stdout + result.stderr
            record["exitCode"] = result.returncode
            record["timeout"] = False
        except subprocess.TimeoutExpired as error:
            output = error.stdout or b""
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
            output += "\nTIMEOUT: exact owned child terminated by hidden runner.\n"
            record["exitCode"] = None
            record["timeout"] = True
        record["wallSeconds"] = time.monotonic() - clock
        record["finishedUtc"] = datetime.now(timezone.utc).isoformat()
        record["passed"] = (record["exitCode"] == 0 and not record["timeout"]
            and not re.search(r"SCRIPT ERROR:|(?m:^ERROR:)|Parse Error|\bFAIL(?:URE)?\b", output))
        record["status"] = "finished"
        record["gameInputAfterSha256"] = inputs()["sha256"]
        record["inputChanged"] = record["gameInputAfterSha256"] != initial["sha256"]
        if record["inputChanged"] and not args.import_only:
            record["passed"] = False
        logfile = directory / (suite + ".log")
        logfile.write_text(output, encoding="utf-8")
        record["logSha256"] = sha(logfile)
        observations = directory / (suite + "-observations.json")
        if observations.is_file():record["observationsSha256"] = sha(observations)
        record["ownedChildExited"] = True  # run_hidden has waited on this exact owned handle.
        try:
            record["externalAfter"] = inventory()
            if record["externalAfter"]:record["contention"] = "CONTENDED"
            record["guardBlocksNext"] = any(not row["permittedUnrelated"] for row in record["externalAfter"])
        except RuntimeError as error:
            record["externalAfterError"] = str(error)
            record["guardBlocksNext"] = True
        write_json(receipt, record)
        records.append(record)
        save_summary(directory, head, script, records, suites)
        print(f"{'PASS' if record['passed'] else 'FAIL'} {suite}: pid={record['pid']} {record['wallSeconds']:.2f}s", flush=True)
        for line in output.splitlines():
            if re.search(r"checks|failures|^FAIL|^SCRIPT ERROR|^ERROR", line, re.I):
                print("  " + line, flush=True)
        if record["inputChanged"] or record["guardBlocksNext"]:
            break
    write_json(directory / "inputs-after.json", inputs())
    save_summary(directory, head, script, records, suites)
    lease.seek(0)
    msvcrt.locking(lease.fileno(), msvcrt.LK_UNLCK, 1)
    lease.close()
    return int(len(records) != len(suites) or any(not r["passed"] for r in records))


def save_summary(directory, head, script, records, suites):
    write_json(directory / "summary.json", {"sourceHead": head,
        "scope": "native source assertions and numerical outcomes only; no rendered/GPU/listening/human-motion/parity claim",
        "originalRegistryCount": len(ORIGINAL_SUITES), "tacticalRegistry": TACTICAL_SUITES,
        "unregisteredScript": str(script) if script else None,
        "cases": records, "passed": sum(r["passed"] for r in records),
        "failed": sum(not r["passed"] for r in records), "expected": len(suites),
        "complete": len(records) == len(suites),
        "blocked": (directory / "guard-blocked.json").exists()})


if __name__ == "__main__":
    raise SystemExit(main())
