# Brass Tide: The Shatter Coast — v0.007

Original Windows motorboat fleet campaign in Godot. Begin with a Tinwake skiff, earn bronze coins, hire sailors, fit interchangeable weapons/engines/armor and grow a fleet. Eight funded contracts lead through the original coast; trade and building continue afterward.

Play the portable Windows release using Brass Tide.exe beside its PCK. WASD moves the camera; M opens the territory overview; Home follows your fleet. Battles default to autopilot. Select boats and right-click orders; Space pauses, Tab opens tactical view, U offers optional manual flagship control. Dock and click numbered fittings in the boat preview to install equipment.

Stern motors and drives, local impact scars, engine smoke, deck fires, material sparks and cause-aware sinking provide battle feedback. Static boat/equipment shapes use a bounded colored-mesh cache; weapons still aim independently and the final wreck finishes sinking after victory.

The title menu's fleet laboratory supports all24hulls, compatible fittings,300points per side, seeds and replay. Options exposes opt-in developer tools and persistent audio/video settings. Drop owner music into music/ beside the game or Desktop/Brass Tide Music. Keep the supplied music/provenance manifest with redistribution.

Source: game/project.godot, game/scripts/, game/data/. Separate rendering is configured; water is decorative2D and crew are numerical. The PC game needs no Python/Node/editor installation. Development tools use the existing runtimes described in docs/FAST DEV TOOLS.txt.

Read AGENTS.md, maps/PROJECT MAP.txt, HANDOFF.md and CODE MAP.md before editing. All tests must remain background/headless, one engine at a time, with no desktop input/focus. Tests: tools/check_game.py --engine <Godot console path>. Preserve older releases and private saves. Each build advances0.001. Exact exports and tests are documented in RELEASE.json and docs/TEST RESULTS v0.007.md.
