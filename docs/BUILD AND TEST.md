# Build and test

Use the existing Godot 4.7.2 Windows console executable and its matching Windows export template. No global installation is required. The project is game/project.godot; source art and the Windows ICO are in game/assets. Build number 1 displays 0.001. Advance BUILD by one for each subsequent release.

Run bounded native checks from this source root:

    python tools/check_game.py --engine "C:/path/to/Godot_v4.7.2-stable_win64_console.exe"

Every process is headless, sequential, hidden and limited to 60 seconds. The checker rejects script errors even when Godot returns exit 0. Raw logs go to the task's work/qa/final directory by default. Current suites cover damage, battle, water navigation, paid production, physical construction, NPC finances, cash campaign protocols, the actual scene/controller and an eight-contract voyage. The old test_campaign.gd retains superseded pre-cash fixtures; test_campaign_cash.gd replaces its financial contract. It is not a valid test of the new currency requirements.

Regenerate the source map with:

    python tools/update_maps.py

The owner's final constraint is background testing only: no mouse/keyboard/focus, no desktop UI automation, no foreground windows. Do not start another instance while one test/game is running. Pure headless simulation does not prove current graphical appearance, FPS or human gameplay feel.

For release, review named changes, commit them, tag v0.001, create a separate Git worktree of that exact release commit and export from its game/ folder:

    Godot... --headless --path game --export-release "Windows Portable" "C:/absolute/release/Brass Tide.exe"

Ship the executable, matching PCK, original ICO, START HERE, current docs/maps and test notes. Exclude editor caches, Python/Node, tests, development scripts, credentials, logs and browser prototypes from the PCK. Saves are created beside the exported executable, not in a developer-specific location. Test the exported executable headless without the editor to verify portability.

Rendering is Separate by default as requested. The engine help confirms --render-thread safe as an optional per-launch fallback for the documented Godot glyph-atlas race; this does not change the saved default. Economy uses copied WorkerThreadPool jobs; main-thread actions synchronize before modifying any purse or inventory.

Engine notices in docs/legal are extracted by the development-only game/scripts/build_notices.gd from the exact engine. Read docs/ORIGINALITY AND CREDITS.md. The owner supplied https://github.com/Oddsprig/BRASS-TIDE--THE-SHATTERED-COAST, verified empty with write access and configured as origin. Windows denied the sandboxed Git credential manager access to saved credentials, so upload remains pending. tools/publish_github.cmd checks clean main, the exact original annotated tag, unchanged game files and the intended destination before a non-force atomic main/tag push, then verifies both remote hashes. Run it under the user's normal Windows account; --check-only performs local read-only preflight without uploading or opening a window.
