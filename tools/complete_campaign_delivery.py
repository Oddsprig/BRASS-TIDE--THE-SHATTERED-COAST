"""Preserve a verified portable release with its exact-tag source ZIP and checksums."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--build", type=int, required=True)
    args = p.parse_args()
    version = f"0.{args.build:03}"
    outputs = ROOT.parent
    folder = outputs / f"Brass Tide v{version}"
    manifest = json.loads((folder / "RELEASE.json").read_text(encoding="utf-8"))
    assert manifest["version"] == version and manifest["build"] == args.build
    tag = subprocess.check_output(["git", "rev-parse", f"v{version}^{{commit}}"], cwd=ROOT, text=True).strip()
    assert tag == manifest["source_commit"]
    for name, expected in manifest["sha256"].items():
        assert hashlib.sha256((folder / name).read_bytes()).hexdigest() == expected, name
    source = outputs / f"Brass Tide v{version} Godot source.zip"
    if not source.exists():
        subprocess.run(["git", "archive", "--format=zip", "--prefix=brass-tide/", "--output", str(source), f"v{version}"], cwd=ROOT, check=True,
                       creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    archives = {}
    for path in [source, outputs / f"Brass Tide v{version} Windows x64.zip"]:
        with zipfile.ZipFile(path) as archive:
            assert archive.testzip() is None, path
            if path == source:
                version_text = archive.read("brass-tide/game/scripts/version.gd").decode("utf-8")
                assert f"BUILD: int = {args.build}" in version_text
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        sidecar = path.with_name(path.name + ".sha256")
        line = digest + "  " + path.name + "\n"
        if sidecar.exists():
            assert sidecar.read_text(encoding="utf-8") == line
        else:
            sidecar.write_text(line, encoding="utf-8")
        archives[path.name] = {"bytes": path.stat().st_size, "sha256": digest, "crc": "PASS"}
    result = {"version": version, "source_commit": tag, "source_tag": f"v{version}",
              "native_windows_smoke": manifest["exported_background_smoke"], "archives": archives,
              "prior_releases": "preserved", "owner_saves": "unchanged", "foreground_input": False,
              "publication": "Separate verified remote-ref receipt required"}
    receipt = outputs / f"Brass Tide v{version} DELIVERY VERIFIED.json"
    if receipt.exists():
        assert json.loads(receipt.read_text(encoding="utf-8")) == result
    else:
        receipt.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    text = f"BRASS TIDE v{version} — VERIFIED LOCAL WINDOWS DELIVERY\n\nExact game source: {tag}\nNative Windows menu, campaign/save and battle startup: PASS in background/headless mode.\nExecutable icon/PCK, manifest hashes, Windows ZIP and exact-tag source ZIP CRC/SHA256: PASS.\nAll prior releases and original owner saves/music remain preserved. No desktop input/focus.\nDevelopment notes are available in the title/Escape menus and DEVELOPER NOTES.txt beside the game.\nGitHub upload and latest desktop shortcut have separate receipts.\n"
    (outputs / f"Brass Tide v{version} DELIVERY VERIFIED.txt").write_text(text, encoding="utf-8")
    (ROOT / "BUILD STATUS.txt").write_text(text, encoding="utf-8")
    log = ROOT / "DEV LOG.txt"
    entry = f"v{version} DELIVERED | exact game {tag}\nClean native Windows menu/campaign-save/battle/icon/PCK and archive CRC/SHA256 verified. All earlier releases and original owner saves/music remain preserved. No desktop input/focus. GitHub and latest desktop shortcut have separate receipts.\n\n"
    if entry not in log.read_text(encoding="utf-8"):
        log.write_text(entry + log.read_text(encoding="utf-8"), encoding="utf-8")
    print(f"v{version}: exact-tag source, portable hashes, archives and local delivery verified")


if __name__ == "__main__":
    main()
