# Brass Tide v0.093

Current candidate: Music transitions and weapon sound review.

- Scene music responds to the latest requested role without waiting behind a full crossfade.
- When both music voices are audible, retire the quieter voice over40ms before reusing it; keep the other at its existing gain and retain the two-second musical fade.
- Keep the two reusable players, all18 supplied tracks, owner volume/mute, same-role Next, finite weapon voices and existing licensed weapon banks.

Focused native checks/export are pending. Root owns all TestBridge work;
helpers stay in source-only roles. Continue this version before the next.
