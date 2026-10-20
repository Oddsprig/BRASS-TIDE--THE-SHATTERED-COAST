# Sol6.1 followup — save preflight

Goal: validate malformed saved dictionaries before Campaign.restore counts coins or replaces the live voyage. Existing Sol specialist only, in its isolated worktree. No extra helpers, commits, deletion or unrelated edits.

Read current cash contract, campaign restore, money counters and actual new-game JSON. Own only new save_validation.gd, test_save_validation.gd and a new raw report. Pure static validate(saved,world) returns useful ok/message, accepts JSON whole-valued floats, permits additional metadata and preserves input. Validate ports/IDs/purses/stocks, construction escrow, player/NPC boats, crew/stores/geometry, cargo and funded sponsors before indexing.

Tests cover actual new/damaged/contract saves plus malformed types, nonfinite values, duplicate IDs, negative or fractional coins and bad hulls. Root reserved the single-instance background test slot; the helper must not run Godot until granted. Root independently wires live-state atomicity and runs the tests. Report stated no execution claim, correctly; root later verified 83 checks and campaign rejection without mutation.
