"""Update only Brass Tide's desktop link and copy a voyage after clean archives exist."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
from win32com.client.dynamic import Dispatch

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--build", type=int, required=True)
    args = p.parse_args()
    version = f"0.{args.build:03}"
    outputs = ROOT.parent
    folder = outputs / f"Brass Tide v{version}"
    manifest = json.loads((folder / "RELEASE.json").read_text(encoding="utf-8"))
    proof = outputs / f"Brass Tide v{version} DELIVERY VERIFIED.json"
    assert proof.is_file() and manifest["version"] == version
    target = folder / "Brass Tide.exe"
    assert sha(target) == manifest["sha256"][target.name]
    link_path = Path.home() / "Desktop" / "Brass Tide.lnk"
    shell = Dispatch("WScript.Shell")
    link = shell.CreateShortcut(str(link_path))
    link.TargetPath = str(target)
    link.WorkingDirectory = str(folder)
    link.IconLocation = str(folder / "Brass Tide.ico") + ",0"
    link.Description = f"Brass Tide v{version}"
    link.Save()
    readback = shell.CreateShortcut(str(link_path))
    assert Path(readback.TargetPath) == target
    receipt = {"version": version, "target": str(target), "icon": readback.IconLocation,
               "launched": False, "ownerSaveCopied": False}
    destination = folder / "saves"
    if not (destination / "voyage.json").exists():
        candidates = [child / "saves/voyage.json" for child in outputs.iterdir()
                      if child.is_dir() and child != folder and re.fullmatch(r"Brass Tide v0\.\d{3}", child.name)
                      and (child / "saves/voyage.json").is_file()]
        if candidates:
            source = max(candidates, key=lambda path: path.stat().st_mtime_ns)
            original = sha(source)
            destination.mkdir(exist_ok=True)
            for name in ["voyage.json", "voyage.backup.json"]:
                old = source.parent / name
                new = destination / name
                if old.is_file() and not new.exists():
                    shutil.copy2(old, new)
            assert sha(source) == original and sha(destination / "voyage.json") == original
            receipt.update(ownerSaveCopied=True, ownerSaveSource=str(source), ownerSaveSHA256=original)
            settings = source.parent.parent / "settings.json"
            if settings.is_file() and not (folder / "settings.json").exists():
                shutil.copy2(settings, folder / "settings.json")
    (outputs / f"Brass Tide v{version} LAUNCHER VERIFIED.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"Desktop icon targets verified v{version}; no game was launched. Original voyages remain intact.")


if __name__ == "__main__":
    main()
