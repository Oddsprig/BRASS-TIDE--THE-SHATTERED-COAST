"""Copy supplied music into the portable source library, without overwriting old takes."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inbox',type=Path,required=True)
    args=parser.parse_args()
    dest=ROOT/'music';dest.mkdir(exist_ok=True)
    records=[]
    for source in sorted(args.inbox.rglob('*')):
        if not source.is_file() or source.suffix.lower() not in {'.mp3','.ogg','.wav'}:continue
        if not 0<source.stat().st_size<=67108864:continue
        digest=hashlib.sha256(source.read_bytes()).hexdigest()
        relative=source.relative_to(args.inbox)
        target=dest/relative
        target.parent.mkdir(parents=True,exist_ok=True)
        if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest()!=digest:
            target=target.with_name(target.stem+'-'+digest[:8]+target.suffix)
        if not target.exists():shutil.copy2(source,target)
        assert hashlib.sha256(target.read_bytes()).hexdigest()==digest
    for path in sorted(dest.rglob('*')):
        if path.is_file() and path.suffix.lower() in {'.mp3','.ogg','.wav'}:
            records.append({'file':path.relative_to(dest).as_posix(),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'source':'Owner supplied Lyria output','usage':'Owner requested integration; retain generation provenance with original output.'})
    (dest/'MANIFEST.json').write_text(json.dumps({'tracks':records},indent=2)+'\n',encoding='utf-8')
    print(f'{len(records)} music tracks verified. Originals preserved; no playback.')

if __name__=='__main__':main()
