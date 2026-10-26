# Brass Tide v0.031 - Damageable equipment

Owner: "stick to the fucking scope".

- Individual weapon, engine, armor and pump condition, with physical effects.
- Crew repair priorities, real supply use and paid harbor fitting/service.
- Equipment identity and condition through refits, saves, salvage and recovery.
- Fixed newly acquired boats gaining bookkeeping/morale fields only after load.

Seven focused equipment fixtures passed1,677 checks with zero failures. Windows
export and portable menu/campaign/battle startup passed in the background. The
batch plus charged setup took81.464 seconds. Campaign/publication also passed637/0.
The wrapper's final raw-byte check rejected editor-generated `.import` line
ending changes; independent review confirmed only23 CRLF/LF metadata changes,
with runtime, tests, data and raw assets unchanged. The wrapper failure remains
recorded. The first builder attempt also remains failed at its512MiB cap; the
successful builder used1GiB while gameplay tests retained512MiB.

Full-game regression, target frame times and human visual/audio play checks are
deferred. This release completes the equipment scope, not the complete game.
