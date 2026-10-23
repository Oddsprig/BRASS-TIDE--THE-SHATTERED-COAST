# Open review and future verification

Current v0.028 already has accepted 66-suite native regression, seven battle CPU
fixtures and separate exact-tag Windows smoke/export/hash evidence. See
[VERIFICATION INDEX](docs/VERIFICATION%20INDEX.txt). Reusing this unchanged baseline
avoids repeating settled checks merely because old scratch output was removed.
No engine tests are required for this context-only consolidation.

Unresolved human review: perceived boat/weapon detail, sustained combat readability,
SFX/music balance, tactical enjoyment, UI scaling and actual rendered frame pacing
on the owner’s display. Background numerical/codec/software-art checks do not
answer those questions. Owner prohibits foreground/input takeover; respect that.

Future .029-.038 work must satisfy the detailed gates in the main version map,
AI BEHAVIOR STANDARD and CIVILIAN FLEET PLAN. In particular: executable harassment
and escape, coordinated encirclement with counters, independent pirate/faction
encounters with one custody record per hull, sighting-based decisions, near/distant
outcome calibration, large-hull route/dock geometry, reachable civilian costs and
actual fishing/cargo/fuel/guest/piracy loops. None is marked delivered by .028 tests.

For an actual change, run relevant native suites and one concrete flow exercising
the new behavior; keep useful failing diagnostics until resolved. For a playable
release, run required regressions and independent clean-tag Windows export checks.
Retain originals and use isolated save copies for migration. Don’t rerun expensive
whole campaigns for wording, maps, or removal of inactive scratch directories.

GitHub source/tags: awaiting a changed supported authentication context; retained
local publication failure evidence remains authoritative until remote hashes prove
success. This cleanup neither retries publishing nor changes the launcher.
