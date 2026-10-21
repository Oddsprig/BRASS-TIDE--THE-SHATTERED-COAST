"""Import a source candidate headlessly before committing its generated Godot identities."""
import argparse
import os
from pathlib import Path
import re
import subprocess
from qa_brass import existing_game

ROOT = Path(__file__).resolve().parents[1]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--engine", type=Path, required=True)
    p.add_argument("--log", type=Path, required=True)
    args = p.parse_args()
    if existing_game():
        raise SystemExit("Another game/editor is running; no import launched.")
    args.log.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["APPDATA"] = str((args.log.parent / "appdata").resolve())
    result = subprocess.run([str(args.engine.resolve()), "--headless", "--path", str(ROOT / "game"), "--editor", "--import", "--quit"],
                            env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60,
                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    output = result.stdout + result.stderr
    args.log.write_text(output, encoding="utf-8")
    if result.returncode or re.search(r"SCRIPT ERROR:|(?m:^ERROR:)|Parse Error", output):
        raise SystemExit("Import failed; inspect " + str(args.log))
    print("Headless source import passed; generated script identities are ready for explicit commit.")


if __name__ == "__main__":
    main()
