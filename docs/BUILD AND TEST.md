# Build and test — v0.007

Native Godot4.7.2 Windows x64, existing matching export template, no global install. Project: game/project.godot. BUILD7 displays0.007; each release advances the integer by1. The shipped game needs no editor, Node or Python.

From this source root:

    python tools/check_game.py --engine "C:/path/to/Godot_v4.7.2-stable_win64_console.exe"
    python tools/update_maps.py

The checker runs22current suites sequentially, headless and hidden,60s each maximum. --only selects suites; --project points at an isolated helper candidate. Tests include actual scene/menu/laboratory/fitting flow, finite economy, eight-contract voyages, saved presentation preferences, physical socket/projectile alignment, localized damage and completion of sinking after the final kill. Test logs/caches/saves stay out of Git.

Art QA: python tools/check_visuals.py --engine <existing console engine> --logs <scratch folder> --only fleet feedback geometry native --preview-dir <preview folder>. This serially captures actual BoatArt/CombatArt commands, rasterizes PNG/GIF previews, audits every hull at360headings/threeLODs and runs Main's full300point fixture. --only feedback is a short targeted animation check. A60/120second owned-process bound prevents stalled scripts. No desktop window or input is used. tools/verify_legacy_save.gd --save=<portablevoyage.json> checks real migration read-only.

Commit named reviewed files, create annotated v0.007 tag, and add a separate clean release worktree at that tag. In that checkout:

    python tools/release_game.py --engine "C:/path/to/Godot_v4.7.2-stable_win64_console.exe" --release-dir "C:/absolute/Brass Tide v0.007" --logs "C:/absolute/work/qa/v007-release-export"

It refuses dirty/non-tagged checkouts and verified-release overwrite, imports/exports headless, checks native icon and standalone menu/campaign/save/battle, preserves generated test saves outside the release, and writes a manifest/ZIP. Runtime PCK excludes tests, dev tools and saves. User saves live beside the EXE and are copied separately after checks; original releases stay intact.

Owner rule: background only, no focus/mouse/keyboard/desktop control, no simultaneous game instances. Pure simulation does not prove GPU performance, display scaling or human feel. Separate rendering remains default, with a Stable Rendering.vbs per-launch Safe fallback for the documented engine font issue. Economy jobs own copied state and main-thread transactions first publish finished snapshots.

Origin is the verified owner repository Oddsprig/BRASS-TIDE--THE-SHATTERED-COAST. v0.001 upload was independently verified. tools/publish_github.cmd derives the current version, checks clean main/current annotated tag/game and original v0.001 history, then pushes main/tag atomically without force and verifies remote refs. --check-only is local preflight. The sandbox's Windows credential manager previously denied vault access; use the user's existing supported authentication context if still necessary. Never claim a new upload without remote hashes. Do not treat a chat file link as an executable launch action.
