# Native damage model — v0.028

Authority: game/scripts/damage.gd and game/tests/test_damage.gd. APIs include
create_ship, apply_hit, get_status, tick_ship and repair_at_port. Campaign harbor
service adds the actual economy/material/worker checks; do not bypass it with a
standalone numerical service call. The former JS guide is cold archived.

Water/capacity use liters; breach area uses cm². Current constants: inflowPerArea
0.055, bailing 1.65 L/s per allocated able sailor, powered pump 2.3 L/s scaled by
engine condition while fueled, patching 1.8 cm²/s per allocated repair sailor.
Capacity is max(200, 4 × maxHp). get_status is read-only; tick_ship substeps and
returns measured flow/repair telemetry. Hull destruction or flooding can sink.

Crew includes wounded; able labor excludes them. Balanced/bail/repair/fight policies
allocate numerical labor between weapons, bailing and repair; idle tasks return
labor to weapons. No animated crew is required. Patching consumes0.018 supply/cm²;
after breaches close, repair policy restores0.22 HP per repair sailor-second at
0.35 supply/HP, with existing repair factors. Fire and engine damage affect survival.
No free crew replacement or resurrection of sunk boats.

Visual impacts, sparks/fire/smoke, wake, staged sinking and bounded events are in
hull_feedback, combat_art, combat_events and motor_art. Stable mount geometry
connects weapon presentation to actual combat. More detailed damageable equipment
is planned for .031; it is not delivered by this document update.
