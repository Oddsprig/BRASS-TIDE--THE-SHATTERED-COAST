"""Serial background rendering captures, geometry audit and actual Main fleet smoke check."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
from qa_brass import existing_game

ROOT = Path(__file__).resolve().parents[1]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--engine', required=True, type=Path)
    ap.add_argument('--logs', required=True, type=Path)
    ap.add_argument('--only', nargs='+', choices=['fleet', 'feedback', 'geometry', 'native', 'cpu'])
    ap.add_argument('--preview-dir', type=Path)
    args = ap.parse_args()
    args.logs.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env['APPDATA'] = str(args.logs.resolve()/'appdata')
    commands = {
        'fleet': (['--quit-after', '2', '--script', str(ROOT/'tools/boat_gallery.gd'), '--', '--out='+str(args.logs.resolve()/'gallery.json')], 30),
        'feedback': (['--quit-after', '2', '--script', str(ROOT/'tools/feedback_gallery.gd'), '--', '--out='+str(args.logs.resolve()/'feedback.json')], 30),
        'geometry': (['--script', str(ROOT/'tools/audit_boat_geometry.gd')], 120),
        'native': (['--fixed-fps', '60', '--quit-after', '360', '--', '--qa-lab=full_300', '--qa-geometry'], 30),
        'cpu': (['--fixed-fps', '60', '--quit-after', '125', '--script', str(ROOT/'tools/presentation_bench.gd')], 30),
    }
    for name in args.only or commands:
        assert not existing_game(), 'Another game/editor is running; no engine launched.'
        command, timeout = commands[name]
        try:
            result = subprocess.run([str(args.engine.resolve()), '--headless', '--path', str(ROOT/'game'), *command],
                                    cwd=ROOT, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace',
                                    timeout=timeout, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
            output = result.stdout+result.stderr
        except subprocess.TimeoutExpired as error:
            output = (error.stdout or b'')+(error.stderr or b'')
            if isinstance(output, bytes):
                output = output.decode('utf-8', errors='replace')
            (args.logs/f'{name}.log').write_text(output+'\nOwned process timed out and was terminated.', encoding='utf-8')
            print(output[-3000:])
            return 1
        (args.logs/f'{name}.log').write_text(output, encoding='utf-8')
        marker = {'fleet': 'boat_gallery:', 'feedback': 'FEEDBACK GALLERY:', 'geometry': 'GEOMETRY:', 'native': 'BRASS TIDE v', 'cpu': 'PRESENTATION CPU:'}[name]
        ok = result.returncode == 0 and marker in output and not re.search(r'SCRIPT ERROR:|(?m:^ERROR:)|Parse Error|BAD BOAT|\bFAIL', output)
        print(name, 'PASS' if ok else 'FAIL', flush=True)
        for line in output.splitlines():
            if any(key in line for key in ['GEOMETRY:', 'checks,', 'FEEDBACK GALLERY:', 'BRASS TIDE v', 'PRESENTATION CPU:']):
                print(line, flush=True)
        if not ok:
            print(output[-3000:])
            return 1
    if args.preview_dir:
        build = int(re.search(r'BUILD: int\s*=\s*(\d+)', (ROOT/'game/scripts/version.gd').read_text()).group(1))
        version = f'v{build//1000}.{build%1000:03}'
        for name, script, capture in [('fleet', 'render_boat_gallery.py', 'gallery.json'), ('feedback', 'render_feedback_gallery.py', 'feedback.json')]:
            if name in (args.only or commands):
                subprocess.run([sys.executable, str(ROOT/'tools'/script), str(args.logs/capture), '--out', str(args.preview_dir), '--label', version], check=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
