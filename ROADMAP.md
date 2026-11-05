# Current step: v0.093 - Music transitions and weapon sound review

- Scene music responds to the latest requested role without waiting behind a full crossfade.
- When both music voices are audible, retire the quieter voice over40ms before reusing it; keep the other at its existing gain and retain the two-second musical fade.
- Keep the two reusable players, all18 supplied tracks, owner volume/mute, same-role Next, finite weapon voices and existing licensed weapon banks.

Finish this scope, run focused checks under120seconds, package, then advance
to the next saved scope. No speculative fine-tuning or full-game gate.
