"""Read-only advisory API check. Native Godot remains authoritative.

Checks direct calls on scripts named by const/preload, never dynamic objects.
No engine launch, imports, writes, owner data or automatic source fixes.
"""
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('game', type=Path)
parser.add_argument('files', nargs='+')
args = parser.parse_args()
preload = re.compile(r'const\s+(\w+)\s*(?::\s*\w+)?\s*=\s*preload\(\s*["\']res://([^"\']+\.gd)["\']\s*\)')
function = re.compile(r'^\s*(?:static\s+)?func\s+(\w+)\s*\(', re.M)
script_methods = {'new', 'get', 'set', 'get_script', 'has_method', 'get_method_list', 'get_property_list'}
issues = []
for relative in args.files:
    path = args.game / relative
    source = path.read_text(encoding='utf-8')
    for match in re.finditer(r'\b(?:var|const)\s+namespace\b|\bnamespace\s*:', source):
        issues.append({'file': relative, 'line': source.count('\n', 0, match.start()) + 1,
                       'issue': 'namespace is reserved in the current Godot parser; review the declaration'})
    for alias, target in preload.findall(source):
        dependency = args.game / target
        if not dependency.is_file():
            issues.append({'file': relative, 'preload': target, 'issue': 'Missing preload file'})
            continue
        methods = set(function.findall(dependency.read_text(encoding='utf-8'))) | script_methods
        for match in re.finditer(r'\b' + re.escape(alias) + r'\.(\w+)\s*\(', source):
            if match.group(1) not in methods:
                issues.append({'file': relative, 'line': source.count('\n', 0, match.start()) + 1,
                               'call': alias + '.' + match.group(1), 'preload': target,
                               'issue': 'No matching method declared; review inheritance/dynamic API before changing'})
print(json.dumps({'advisoryOnly': True, 'engineInvoked': False, 'issues': issues}, indent=2))
