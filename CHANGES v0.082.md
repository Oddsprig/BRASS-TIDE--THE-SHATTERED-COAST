# Brass Tide v0.082 - Weapon sound and music transitions

Owner: "stick to the scope of each one".

- Finish the existing two-player music fade before accepting a queued scene or Next change.
- Overlap natural cue endings by two seconds and preserve mute/headless behavior.
- Supply bounded offline gunfire, heavy-shot, rocket/torpedo, impact and music transition clips; hearing remains a separate quality gate.

See docs/TEST RESULTS v0.082.md for actual focused checks and remaining limits.

Verification: 35 focused assertions/0 failures, Windows export and portable menu startup. Whole selected batch plus setup 63.769s. Preserved earlier failures; no broad acceptance claim.
