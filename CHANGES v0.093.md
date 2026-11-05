# Brass Tide v0.093 - Music transitions and weapon sound review

Owner: "stick to the scope of each one".

- Scene music responds to the latest requested role without waiting behind a full crossfade.
- When both music voices are audible, retire the quieter voice over40ms before reusing it; keep the other at its existing gain and retain the two-second musical fade.
- Keep the two reusable players, all18 supplied tracks, owner volume/mute, same-role Next, finite weapon voices and existing licensed weapon banks.

See docs/TEST RESULTS v0.093.md for actual focused checks and remaining limits.

Verification: 42 focused assertions/0 failures, Windows export and portable menu startup. Whole selected batch plus setup 63.799s. Preserved earlier failures; no broad acceptance claim.
