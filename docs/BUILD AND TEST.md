<!-- brass-tide-series:29:start -->
# v0.029 source checks and release gates

SOURCE CHECKS RECORDED: 70 native suites recorded from supplied logs. Feature acceptance requires lead review.

Registered native suites: 70. Stage-specific minimum: workshop, art_workshop, workshop_voyage, workshop_ui.
Use tools/check_game.py with an explicit existing Godot 4.7.2 path and isolated logs. One hidden/headless/silent engine at a time; no desktop input or owner saves.

Record actual complete native logs with tools/advance_series.py --build 29 --accept-logs <logs>. This records evidence; it never runs Godot or exports. Refresh static maps separately with tools/update_maps.py.

Continue only after lead acceptance, preserved annotated tag and a separately verified clean exact-tag Windows release. Later stages remain pending; do not reuse tags or overwrite older releases.

Exact-tag Windows export/startup/save/battle, archive hashes, launcher, remote publication, visual/motion review and listening require their own evidence. Source logs establish none of those outcomes.
Earlier build instructions follow as historical records.
<!-- brass-tide-series:29:end -->

# Build and test — current v0.028 source

Godot 4.7.2 Windows x64; project game/project.godot. Existing console engine:
`C:/Users/bligh/Documents/Codex/2026-09-25/we-x20/work/engine/Godot_v4.7.2-stable_win64_console.exe`.
Use the existing matching export template. The portable game requires no editor,
Python or Node. No global installation or system setting changes.

Read VERIFICATION INDEX.txt before running anything. Current .028 has 66 accepted
native suites and independent release evidence. Reuse unchanged-input proof;
context/scratch cleanup needs static/hash checks, not another campaign run.

From source root, for an actual relevant game change:

    python tools/check_game.py --engine "<existing Godot console path>" --only damage battle --logs "<task>/work/qa/current-damage"
    python tools/check_game.py --engine "<existing Godot console path>" --logs "<task>/work/qa/current-source-final"
    python tools/qa_brass.py --scenario full_300 --engine "<existing Godot console path>" --logs "<task>/work/qa/current-battle"
    python tools/update_maps.py

The first example is targeted; omit --only for all 66 required native suites.
Checker serializes isolated hidden/headless processes, isolates APPDATA and bounds
each suite to 60 seconds. Nonzero exit, fatal script/parse errors or FAIL count as
failure even if the engine exits zero. Never run two engines or change assertion
strength to get a pass. Only owned explicit PID cleanup. No mouse/keyboard/focus.

For changed art: tools/check_visuals.py --engine <path> --logs <scratch> --only
feedback --preview-dir <scratch previews> is one targeted example. Gallery/render
and geometry tools can inspect actual drawing calls, headings and animation.
Read FAST DEV TOOLS.txt for scopes. CPU/software evidence is distinct from rendered
frame pacing, listening or subjective quality. Keep foreground testing prohibited.
Read-only legacy-save tool takes a copy and needs separately scoped migration proof.

For a real playable release, review named files, update current notes/maps, commit
and create the annotated next 0.001 tag. Add a separate clean checkout at that tag.
From that checkout:

    python tools/release_game.py --engine "<existing Godot console path>" --release-dir "<task>/outputs/Brass Tide vX.XXX" --logs "<task>/work/qa/export-vXXX"

The exporter refuses dirty/non-tagged source or verified-release overwrite. It
imports/exports hidden, verifies icon/PCK/native menu/campaign-save/battle and
writes RELEASE.json plus Windows/source ZIP identities. Runtime PCK excludes tests,
dev tools and saves. Owner saves are copied separately after clean checks; preserve
all originals, old releases and music. Launcher/publication are separate actions.

Retain docs/helper-reports/, docs/legal/, docs/audio/, current CHANGES and TEST RESULTS,
core root records and maps: release tooling copies those inputs. The two small
completed-economy document pointers preserve historical delivery-tool inputs.
Helper reports
may be cold archived with a current pointer; never falsely mark advice as tests.
Separate rendering remains the game default; Stable Rendering.vbs is a per-launch
fallback already supplied for the documented engine font issue.

Origin: Oddsprig/BRASS-TIDE--THE-SHATTERED-COAST. tools/publish_github.* preflights
clean main/annotated tag/ancestry, pushes normally/atomically and checks remote refs.
Current .028 publication is pending Windows credential access; no upload is implied
by local delivery. Do not force, retag or repeatedly retry unchanged authentication.
