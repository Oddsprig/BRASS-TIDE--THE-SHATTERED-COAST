"""Exercise actual queue functions with synthetic process discovery, no engines."""
import argparse
import ast
import json
from pathlib import Path
from types import SimpleNamespace


def check_runner(path):
    source = path.read_text(encoding='utf-8')
    tree = ast.parse(source, filename=str(path))
    nodes = [node for node in tree.body if isinstance(node, ast.FunctionDef)
             and node.name in {'classify', 'inventory'}]
    assert len(nodes) == 2, path
    calls = []
    reply = SimpleNamespace(returncode=0, stdout='', stderr='')

    def fake_discovery(command, **kwargs):
        assert command[0] == 'powershell.exe'
        assert '%godot%' in command[-1].lower() and '%unity%' in command[-1].lower()
        assert kwargs['timeout'] <= 10 and kwargs['capture_output']
        calls.append(command)
        return reply

    namespace = {'json': json, 'subprocess': SimpleNamespace(run=fake_discovery, CREATE_NO_WINDOW=0)}
    exec(compile(ast.Module(body=nodes, type_ignores=[]), str(path), 'exec'), namespace)
    classify, inventory = namespace['classify'], namespace['inventory']
    # Former exact/known/headless exemptions must be overridden, including stale
    # injected allowed fields. No fixture depends on another real user's project.
    base = {'Id': 123, 'StartUtc': '2026-10-24T00:00:00Z',
            'Path': 'C:/synthetic/Godot.exe', 'MainWindowHandle': 0,
            'CommandLine': 'Godot.exe --headless --path C:/synthetic/project',
            'permittedUnrelated': True}
    rows = [base, dict(base, Path='C:/synthetic/Unity.exe'),
            dict(base, Path='C:/synthetic/UnityHub.exe'),
            dict(base, MainWindowHandle=42), dict(base, Id=456),
            dict(base, Path=''), dict(base, StartUtc=''), {},
            dict(base, Path='C:/synthetic/Brass Tide.exe')]
    for row in rows:
        actual = classify(row)
        assert actual['permittedUnrelated'] is False and actual.get('blockReason'), actual
        assert row.get('permittedUnrelated', True), 'Classifier changed supplied process data'
    assert inventory() == []
    reply.stdout = json.dumps(rows[:3])
    found = inventory()
    assert len(found) == 3 and all(not row['permittedUnrelated'] for row in found)
    checks = len(rows) + 2
    for output, error, code in [('garbage', '', 0), ('null', '', 0), ('[null]', '', 0),
                                ('', 'Access denied', 0), ('', '', 1)]:
        reply.stdout, reply.stderr, reply.returncode = output, error, code
        try:
            inventory()
        except RuntimeError:
            checks += 1
        else:
            raise AssertionError('Unreadable discovery did not keep the queue closed')
    return {'runner': str(path), 'checks': checks, 'failures': 0,
            'discoveryCallsMocked': len(calls), 'engineLaunched': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', type=Path, action='append')
    args = parser.parse_args()
    paths = args.runner or [Path(__file__).with_name('resume_game_checks.py')]
    print(json.dumps([check_runner(path) for path in paths], indent=2))
