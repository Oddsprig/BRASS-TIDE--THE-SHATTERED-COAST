"""Fast isolated Brass Tide battle checks. Never opens a window or reads a career save."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
SCENARIOS = ROOT / 'tools/bench_scenarios.json'


def existing_game():
    if os.name != 'nt':
        return []
    query = "Get-Process | Where-Object { $_.ProcessName -match '^(Brass Tide|Godot)' } | Select-Object Id,ProcessName | ConvertTo-Json -Compress"
    result = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', query],
                            capture_output=True, text=True, timeout=10, creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode:
        raise RuntimeError('Unable to check for an existing game; no engine was launched.')
    value = json.loads(result.stdout) if result.stdout.strip() else []
    return value if isinstance(value, list) else [value]


def main():
    definitions = json.loads(SCENARIOS.read_text(encoding='utf-8'))['scenarios']
    world = json.loads((ROOT / 'game/data/world.json').read_text(encoding='utf-8'))
    ids = {hull['id'] for hull in world['HULLS']}
    for key, scenario in definitions.items():
        if not set(scenario['player'] + scenario['enemy']) <= ids:
            raise ValueError('Unknown hull in scenario ' + key)
    parser = argparse.ArgumentParser(description=__doc__)
    select = parser.add_mutually_exclusive_group(required=True)
    select.add_argument('--list', action='store_true')
    select.add_argument('--scenario', choices=list(definitions))
    select.add_argument('--suite', choices=['smoke', 'all'])
    parser.add_argument('--engine', type=Path)
    parser.add_argument('--seed', type=int, default=83)
    parser.add_argument('--seconds', type=float)
    parser.add_argument('--logs', type=Path, default=ROOT.parents[1] / 'work/qa/fast-battles')
    args = parser.parse_args()
    if args.list:
        for key, scenario in definitions.items():
            print(f"{key:20} {scenario['label']} ({scenario['seconds']} simulation seconds)")
        return 0
    if args.engine is None or not args.engine.is_file():
        parser.error('Supply --engine with the existing Godot console executable; nothing is installed automatically.')
    if args.seconds is not None and not 0 < args.seconds <= 180:
        parser.error('--seconds must be in (0,180].')
    args.logs.mkdir(parents=True, exist_ok=True)
    selected = [args.scenario] if args.scenario else ['duel','all_weapons','reserve_boundary'] if args.suite == 'smoke' else list(definitions)
    environment = os.environ.copy()
    environment['APPDATA'] = str((args.logs / 'appdata').resolve())
    summaries = []
    for name in selected:
        running = existing_game()
        if running:
            print('No test launched: a Brass Tide or Godot process is already running. Close it before a serialized test.')
            return 2
        report_path = (args.logs / (name + '.json')).resolve()
        run_id = uuid4().hex
        seconds = args.seconds if args.seconds is not None else definitions[name]['seconds']
        command = [str(args.engine.resolve()), '--headless', '--path', str(ROOT / 'game'),
                   '--script', str(ROOT / 'tools/fleet_bench.gd'), '--', '--scenario=' + name,
                   '--seed=' + str(args.seed), '--seconds=' + str(seconds), '--out=' + str(report_path),
                   '--runid=' + run_id]
        try:
            result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace',
                                    env=environment, timeout=20, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
            output = result.stdout + result.stderr
            ok = result.returncode == 0 and not re.search(r'SCRIPT ERROR:|(?m:^ERROR:)|Parse Error|\bFAIL\b', output)
        except subprocess.TimeoutExpired:
            output = 'Owned test process exceeded 20 seconds and was terminated by its timeout.'
            ok = False
        (args.logs / (name + '.log')).write_text(output, encoding='utf-8')
        summary = json.loads(report_path.read_text(encoding='utf-8')) if ok and report_path.is_file() else {}
        ok = (ok and bool(summary) and not summary.get('failures')
              and summary.get('runId') == run_id and summary.get('scenario') == name
              and summary.get('seed') == args.seed and summary.get('requestedSeconds') == seconds
              and summary.get('checks', 0) > 0 and summary.get('frames', 0) > 0)
        print(('PASS ' if ok else 'FAIL ') + name)
        if summary:
            print(f"  {summary['deployedBoats']} boats; {summary['simulatedSeconds']:.1f}s simulated; "
                  f"{summary['wallMs']}ms work; simulation tick p95 {summary['simulationTickP95us']}us")
        if not ok:
            print(output[-5000:])
        summaries.append({'scenario':name,'ok':ok,'report':summary})
        if not ok:
            break
    (args.logs / 'summary.json').write_text(json.dumps({'rendered':False,'audioAuditioned':False,'cases':summaries},indent=2),encoding='utf-8')
    return 0 if len(summaries) == len(selected) and all(item['ok'] for item in summaries) else 1


if __name__ == '__main__':
    raise SystemExit(main())
