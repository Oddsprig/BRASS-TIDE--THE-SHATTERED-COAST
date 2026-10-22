"""Emit explicit changed source paths for root review; never stages anything."""
from pathlib import Path
import argparse, subprocess
ROOT=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args()
    changed=subprocess.check_output(["git","diff","--name-only","-z"],cwd=ROOT).decode("utf-8").split("\0")
    untracked=subprocess.check_output(["git","ls-files","--others","--exclude-standard","-z"],cwd=ROOT).decode("utf-8").split("\0")
    paths=sorted(set(p for p in changed+untracked if p))
    for name in paths:
        path=(ROOT/name).resolve()
        assert path.is_relative_to(ROOT) and ".git" not in path.relative_to(ROOT).parts
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text("\n".join(paths)+"\n",encoding="utf-8")
    print(f"{len(paths)} explicit changed paths written for lead review.")
if __name__=="__main__":main()
