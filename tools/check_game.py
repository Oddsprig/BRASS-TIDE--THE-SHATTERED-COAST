"""Bounded, sequential Godot checks. Never opens a window or controls input."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import time
from qa_brass import existing_game

ROOT = Path(__file__).resolve().parents[1]
SUITES = ["damage", "battle", "navigation", "economy", "construction",
          "fleet_economy", "campaign_cash", "save_validation", "runtime", "voyage",
          "tactics", "refit", "fleet_points", "commander", "autovoyage", "laboratory", "combat_events", "audio", "map_revision", "mount_layout", "presentation", "feedback", "expedition", "campaign_logistics"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--project", type=Path, default=ROOT / "game")
    parser.add_argument("--logs", type=Path, default=ROOT.parent.parent / "work" / "qa" / "final")
    parser.add_argument("--only", nargs="+", choices=SUITES)
    args = parser.parse_args()
    args.logs = args.logs.resolve()
    args.logs.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["APPDATA"] = str(args.logs / "appdata")
    if (args.project / 'assets/sfx').is_dir() and not list((args.project / '.godot/imported').glob('gun-1.wav-*.sample')):
        if existing_game(): raise RuntimeError('Another game/editor is running; no import launched.')
        result=subprocess.run([str(args.engine.resolve()),'--headless','--path',str(args.project.resolve()),'--editor','--import','--quit'],capture_output=True,text=True,encoding='utf-8',errors='replace',env=env,timeout=60,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        output=result.stdout+result.stderr
        (args.logs/'asset-import.log').write_text(output,encoding='utf-8')
        if result.returncode or re.search(r'SCRIPT ERROR:|(?m:^ERROR:)|Parse Error',output):
            print('FAIL asset import; inspect asset-import.log')
            return 1
    bad = []
    for suite in args.only or SUITES:
        if existing_game():
            raise RuntimeError("Another Brass Tide/Godot process is running; no test launched.")
        started = time.monotonic()
        command = [str(args.engine.resolve()), "--headless", "--path", str(args.project.resolve()),
                   "--script", f"res://tests/test_{suite}.gd"]
        try:
            result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8",
                                    errors="replace", env=env, timeout=60,
                                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            output = result.stdout + result.stderr
            ok = result.returncode == 0 and not re.search(r"SCRIPT ERROR:|(?m:^ERROR:)|Parse Error|\bFAIL(?:URE)?\b", output)
        except subprocess.TimeoutExpired as error:
            partial=(error.stdout or b'')+(error.stderr or b'')
            output = (partial.decode('utf-8',errors='replace') if isinstance(partial,bytes) else partial)
            output += f"\nTIMEOUT after 60 seconds; this owned process was terminated. {error}"
            ok = False
        (args.logs / f"{suite}.log").write_text(output, encoding="utf-8")
        print(f"{'PASS' if ok else 'FAIL'} {suite}: {time.monotonic() - started:.2f}s", flush=True)
        shown=set()
        for line in output.splitlines():
            if re.search(r"checks|failures|assertions|^FAIL|^SCRIPT ERROR|^ERROR|voyage leg", line, re.I):
                if line in shown or len(shown)>=24: continue
                shown.add(line)
                print("  " + line, flush=True)
        if not ok:
            bad.append(suite)
    print(f"{len(args.only or SUITES) - len(bad)} suites passed; {len(bad)} failed. Logs: {args.logs}")
    return bool(bad)


if __name__ == "__main__":
    raise SystemExit(main())
