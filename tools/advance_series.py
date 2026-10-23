"""Record one .029-.038 source milestone; never run, export, tag or publish a game.

Examples (run only after lead review in the integrated source checkout):
  python tools/advance_series.py --build 29 --previous-release <v028/RELEASE.json> --dry-run
  python tools/advance_series.py --build 29 --previous-release <v028/RELEASE.json>
  python tools/advance_series.py --build 29 --accept-logs <serialized-native-log-dir>

Advancing requires the predecessor source report and its existing Windows release
receipt. Re-recording the current build needs no predecessor receipt. Every
registered native suite must have a nonempty, positive, error-free log to import
source evidence. Log/source correspondence and feature acceptance remain the
lead's responsibility. Export, visuals, motion, audio and publication are separate.
"""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD_RE = r"(?m)^(const BUILD: int\s*=\s*)(\d+)(\s*)$"
BAD_LOG = re.compile(
    r"SCRIPT\s+ERROR|Parse\s+Error|(?:^|\n)\s*(?:ERROR|FATAL)\b|"
    r"\bFAIL(?:URE|ED)?\b|\bTIMEOUT\b|\btimed\s+out\b|Traceback|"
    r"\b[1-9]\d*\s+(?:failures|failed|errors)\b", re.I
)
# Two retained native fixtures use these exact completion markers rather than
# the usual checks/PASS summary. Keep this tied to their actual suite names.
NATIVE_COMPLETIONS = {
    "regional_goods": r"^REGIONAL_GOODS_TESTS_PASS$",
    "shipping_companies": r"^shipping:\s*0 failures$",
}
SEPARATE = (
    "Exact-tag Windows export/startup/save/battle, archive hashes, launcher, "
    "remote publication, visual/motion review and listening require their own "
    "evidence. Source logs establish none of those outcomes."
)


def read(path):
    """Keep existing line endings/history intact and refuse invalid UTF-8."""
    return path.read_bytes().decode("utf-8")


def version(build):
    return f"{build // 1000}.{build % 1000:03d}"


def replace_one(text, pattern, value, label):
    result, count = re.subn(pattern, value, text)
    if count != 1:
        raise ValueError(f"Expected exactly one {label}; found {count}.")
    return result


def managed(before, build, body):
    """Replace this milestone's block, preserving all unowned/historical text."""
    start = f"<!-- brass-tide-series:{build}:start -->"
    end = f"<!-- brass-tide-series:{build}:end -->"
    block = f"{start}\n{body.rstrip()}\n{end}"
    if start in before or end in before:
        if before.count(start) != 1 or before.count(end) != 1:
            raise ValueError("Ambiguous series record markers; no files written.")
        left, rest = before.split(start)
        old, right = rest.split(end)
        if start in old or end in left:
            raise ValueError("Reversed series record markers; no files written.")
        return left + block + right
    return block + "\n\n" + before


def stage_for(root, build):
    config = json.loads(read(root / "tools/series_steps.json"))
    if config.get("schema_version") != 1:
        raise ValueError("Unsupported series_steps schema.")
    steps = config["steps"]
    expected = list(range(config["base_build"] + 1, config["last_build"] + 1))
    if [step["build"] for step in steps] != expected or expected != list(range(29, 39)):
        raise ValueError("The stage manifest must describe .029-.038 exactly, in order.")
    for step in steps:
        if not step.get("title") or not step.get("outcome") or not step.get("features"):
            raise ValueError("Each stage needs its own title, outcome and features.")
        if not isinstance(step.get("required_suites"), list) or not step["required_suites"]:
            raise ValueError("Each stage needs explicit native suite requirements.")
    if build not in expected:
        raise ValueError("Only integer builds 29 through 38 belong to this series.")
    return steps[build - 29]


def registered_suites(root):
    """Read the real registry without importing runner modules or starting tools."""
    tree = ast.parse(read(root / "tools/check_game.py"))
    values = [ast.literal_eval(node.value) for node in tree.body
              if isinstance(node, ast.Assign)
              and any(isinstance(t, ast.Name) and t.id == "SUITES" for t in node.targets)]
    if len(values) != 1 or not isinstance(values[0], list) or not values[0]:
        raise ValueError("Expected one nonempty literal SUITES registry.")
    suites = values[0]
    if any(not isinstance(s, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", s) for s in suites):
        raise ValueError("Malformed native suite registry.")
    if len(set(suites)) != len(suites):
        raise ValueError("Duplicate native suites.")
    for suite in suites:
        if not (root / f"game/tests/test_{suite}.gd").is_file():
            raise ValueError(f"Registered native suite has no actual file: {suite}")
    return suites


def log_summary(text, suite=None):
    if not text.strip() or BAD_LOG.search(text):
        raise ValueError("empty/error/fail/timeout log")
    for line in reversed(text.splitlines()):
        if suite in NATIVE_COMPLETIONS and re.fullmatch(NATIVE_COMPLETIONS[suite], line.strip()):
            return line.strip()
        if re.search(r"\b(?:0 checks|0 assertions)\b", line, re.I):
            continue
        count = re.search(r"\b([1-9]\d*)\s+(?:checks|assertions)\b", line, re.I)
        if count and (re.search(r"\b0 failures\b", line, re.I)
                      or re.search(r"\bpass(?:ed)?\b", line, re.I)):
            return line.strip()
        if re.search(r"\bpass(?:ed)?\b", line, re.I) and not re.search(r"\bchecks|assertions\b", line, re.I):
            return line.strip()
    raise ValueError("no positive native completion summary")


def accept_logs(root, directory, suites, required):
    missing = sorted(set(required) - set(suites))
    if missing:
        raise ValueError("Stage suites must be implemented and registered before acceptance: " + ", ".join(missing))
    rows, bad = [], []
    for suite in suites:
        path = directory / f"{suite}.log"
        try:
            raw = path.read_bytes()
            summary = log_summary(raw.decode("utf-8"), suite)
            script_hash = hashlib.sha256((root / f"game/tests/test_{suite}.gd").read_bytes()).hexdigest()
            rows.append((suite, summary, hashlib.sha256(raw).hexdigest(), script_hash))
        except (OSError, UnicodeError, ValueError) as error:
            bad.append(f"{suite}: {error}")
    if bad:
        raise ValueError("Native logs refused; no files written:\n" + "\n".join(bad))
    return rows


def predecessor(root, receipt_path, old):
    if receipt_path is None:
        raise ValueError("Advancing requires --previous-release <predecessor RELEASE.json>; export is a separate step.")
    receipt = json.loads(read(receipt_path))
    if (receipt.get("build") != old or receipt.get("version") != version(old)
            or receipt.get("source_tag") != "v" + version(old)
            or not re.fullmatch(r"[0-9a-f]{40}", str(receipt.get("source_commit", "")))
            or receipt.get("platform") != "Windows x86_64"
            or not str(receipt.get("engine", "")).startswith("4.7.2")):
        raise ValueError("Predecessor receipt does not identify the exact preceding Windows build/engine/tag.")
    required_smokes = {"menu", "campaign and portable save", "battle"}
    if not required_smokes.issubset(set(receipt.get("exported_background_smoke", []))):
        raise ValueError("Predecessor receipt lacks native Windows smoke evidence.")
    hashes = receipt.get("sha256", {})
    for name in ["Brass Tide.exe", "Brass Tide.pck"]:
        expected = hashes.get(name, "")
        path = receipt_path.parent / name
        if not re.fullmatch(r"[0-9a-f]{64}", expected) or not path.is_file():
            raise ValueError(f"Predecessor release is missing its hashed {name}.")
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f"Predecessor release hash mismatch: {name}")
    report = root / f"docs/TEST RESULTS v{version(old)}.md"
    if not report.is_file() or not re.search(r"native suites (?:passed|recorded)|Native log evidence", read(report), re.I):
        raise ValueError("Preserve the predecessor source-check report before advancing.")


def developer_notes(before, build, body):
    header = "BRASS TIDE — DEVELOPMENT NOTES\n"
    divider = "\n\nPREVIOUS BUILD NOTES\n"
    normalized = before.replace("\r\n", "\n")
    if normalized.startswith(header + f"v{version(build)} — "):
        marker = re.search(r"\r?\n\r?\nPREVIOUS BUILD NOTES\r?\n", before)
        if marker is None:
            raise ValueError("Current notes lack their historical divider; refusing to discard history.")
        # A generated LF header may precede historical CRLF text. Slice at the
        # first actual divider without normalizing any historical bytes.
        previous = before[marker.end():]
    else:
        previous = before
    return header + body.rstrip() + divider + previous


def plan(root, build, logs=None, previous_release=None):
    stage = stage_for(root, build)
    version_path = root / "game/scripts/version.gd"
    script = read(version_path)
    matches = re.findall(BUILD_RE, script)
    if len(matches) != 1:
        raise ValueError("Expected exactly one current integer BUILD.")
    old = int(matches[0][1])
    if build not in (old, old + 1):
        raise ValueError(f"Sequence refused: current BUILD {old}; requested {build}. Use current or immediate successor only.")
    project = read(root / "game/project.godot")
    presets = read(root / "game/export_presets.cfg")
    world = read(root / "game/data/world.json")
    values = re.findall(r'(?m)^config/version="([^"]+)"\r?$', project)
    exports = re.findall(r'(?m)^application/(?:file_version|product_version)="([^"]+)"\r?$', presets)
    descriptions = re.findall(r'(?m)^application/file_description="([^"]+)"\r?$', presets)
    if (values != [version(old)] or exports != [f"0.0.{old}.0"] * 2
            or descriptions != [f"Brass Tide v{version(old)}"]
            or json.loads(world).get("VERSION") != version(old)):
        raise ValueError("Current BUILD/world/project/export versions disagree; no files written.")
    if build != old:
        predecessor(root, previous_release, old)
    suites = registered_suites(root)
    rows = accept_logs(root, logs, suites, stage["required_suites"]) if logs is not None else []
    report_path = root / f"docs/TEST RESULTS v{version(build)}.md"
    old_report = read(report_path) if report_path.exists() else ""
    if not rows and f"<!-- series-source-logs:{build} -->" in old_report:
        raise ValueError("Source logs already recorded; provide --accept-logs to refresh without downgrading evidence.")
    status = (f"SOURCE CHECKS RECORDED: {len(rows)} native suites recorded from supplied logs. Feature acceptance requires lead review."
              if rows else "SOURCE CANDIDATE: no native validation, export or delivery is claimed.")
    ver = version(build)
    title = stage["title"]
    features = "\n".join("- " + item for item in stage["features"])
    scope = "Implemented behavior to review" if rows else "Current stage scope; pending implementation and verification"
    detail = f"v{ver} — {title}\n{status}\n\n{stage['outcome']}\n\n{scope}:\n{features}"
    gate = ("Continue only after lead acceptance, preserved annotated tag and a separately verified clean exact-tag Windows release. "
            "Later stages remain pending; do not reuse tags or overwrite older releases.")
    updates = {}

    def record(relative, body):
        path = root / relative
        before = read(path) if path.exists() else ""
        updates[path] = managed(before, build, body)

    updates[version_path] = replace_one(script, BUILD_RE, lambda m: m[1] + str(build) + m[3], "BUILD")
    updates[root / "game/project.godot"] = replace_one(project, r'(?m)^(config/version=")[^"]+("\r?)$', lambda m: m[1] + ver + m[2], "project version")
    for key in ["file_version", "product_version"]:
        presets = replace_one(presets, rf'(?m)^(application/{key}=")[^"]+("\r?)$', lambda m: m[1] + f"0.0.{build}.0" + m[2], key)
    updates[root / "game/export_presets.cfg"] = replace_one(presets, r'(?m)^(application/file_description=")[^"]+("\r?)$', lambda m: m[1] + f"Brass Tide v{ver}" + m[2], "export description")
    updates[root / "game/data/world.json"] = replace_one(world, r'("VERSION"\s*:\s*")[^"]+(")', lambda m: m[1] + ver + m[2], "world VERSION")
    notes_path = root / "game/data/DEVELOPER NOTES.txt"
    notes = detail + "\n\nFinite coins, equipment and people; 100 coins per sailor-day. Templates contain knowledge only.\n" + SEPARATE
    updates[notes_path] = developer_notes(read(notes_path), build, notes)
    record(f"CHANGES v{ver}.md", f"# Brass Tide v{ver} — {title}\n\n{detail}\n\n{SEPARATE}")
    report = f"# v{ver} source verification\n\n{status}\n\n"
    if rows:
        report += f"<!-- series-source-logs:{build} -->\nNative log evidence: all {len(rows)} registered suites have positive completion summaries and no fatal/error/fail/timeout marker.\n\n"
        report += "| Suite | Actual completion summary | Log SHA256 | Fixture SHA256 |\n| --- | --- | --- | --- |\n"
        report += "\n".join(f"| {s} | {summary.replace('|', '/')} | {log_hash} | {script_hash} |" for s, summary, log_hash, script_hash in rows)
        report += "\n\nThese are imported native logs, not a fresh run by this tool. Lead must verify they match the integrated source and authorized serialized headless/silent run.\n"
    else:
        report += "Native execution is pending. Required stage suites: " + ", ".join(stage["required_suites"]) + ".\n"
    record(f"docs/TEST RESULTS v{ver}.md", report + "\n" + SEPARATE)
    for relative, heading in [
        ("HANDOFF.md", "# Current source milestone"),
        ("BUILD STATUS.txt", "BRASS TIDE — CURRENT SOURCE BUILD STATUS"),
        ("BUILD PLAN.txt", "CURRENT AUTHORIZED SERIES STAGE"),
        ("ROADMAP.md", "# Current authorized sequential stage"),
        ("VERSION MAP.txt", "CURRENT SOURCE VERSION"),
        ("VERSIONS.md", "## Current source milestone"),
        ("DEV LOG.txt", "CURRENT SERIES RECORD"),
    ]:
        record(relative, f"{heading}\n\n{detail}\n\n{gate}\n\n{SEPARATE}\n\nRoadmap: docs/FLEET CAMPAIGN VERSION MAP v0.029-v0.038.txt\nEarlier records follow unchanged.")
    record("docs/BUILD AND TEST.md", f"# v{ver} source checks and release gates\n\n{status}\n\nRegistered native suites: {len(suites)}. Stage-specific minimum: {', '.join(stage['required_suites'])}.\nUse tools/check_game.py with an explicit existing Godot 4.7.2 path and isolated logs. One hidden/headless/silent engine at a time; no desktop input or owner saves.\n\nRecord actual complete native logs with tools/advance_series.py --build {build} --accept-logs <logs>. This records evidence; it never runs Godot or exports. Refresh static maps separately with tools/update_maps.py.\n\n{gate}\n\n{SEPARATE}\nEarlier build instructions follow as historical records.")
    code_path = root / "CODE MAP.md"
    updates[code_path] = replace_one(read(code_path), r"(?m)^(# Brass Tide v)[\d.]+( source map\r?)$", lambda m: m[1] + ver + m[2], "code-map heading")
    return {path: text for path, text in updates.items()
            if not path.exists() or read(path) != text}, status


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--build", required=True, type=int)
    parser.add_argument("--previous-release", type=Path, help="Existing immediate predecessor RELEASE.json; required only when advancing")
    parser.add_argument("--accept-logs", type=Path, help="Complete actual tools/check_game.py suite logs; never runs native checks")
    parser.add_argument("--dry-run", action="store_true", help="Validate and list planned files without writing")
    args = parser.parse_args(argv)
    try:
        updates, status = plan(ROOT, args.build, args.accept_logs, args.previous_release)
    except (OSError, UnicodeError, ValueError, KeyError, SyntaxError) as error:
        parser.exit(2, f"Refused: {error}\n")
    print(f"{'DRY RUN' if args.dry_run else 'Recording'} v{version(args.build)}: {status}")
    for path, content in updates.items():
        print(path.relative_to(ROOT).as_posix())
        if not args.dry_run:
            path.write_bytes(content.encode("utf-8"))
    print(f"{len(updates)} {'planned' if args.dry_run else 'updated'} files. {SEPARATE}")
    return 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    raise SystemExit(main())
