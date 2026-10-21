# Argon B combat integration verdict

The unchanged helper report is v004-combat-argon-original.md. Root reviewed the complete implementation and independently ran the numerical suites, actual eight-contract autopilot campaign, event test and audio integration test. Accepted: bounded typed all-team events, retained event ordering, per-mount shot times, enriched visual effects and persistent sinking hull data.

The report contains speculative API/schema names that the delivered code does not implement. The accepted API is Battle.pop_events(), mount_shot_time(), mount_shot_age(), hull_material() and weapon_family(); combat_events.gd defines the actual schema. The report is evidence of the helper's claims, not a public API specification.

The helper's mixed-hull large-fleet test could not actually deploy its claimed 30+ boats under300DP. Root corrected that fixture to21vs20 Tinwake hulls, verifying exactly40 active boats at300DP per side and one reserve. Four-weapon coverage remains a separate fixture. The corrected test passes10153 assertions. No combat RNG or damage rules were changed to force the test or campaign outcome.

Root owns recorded sound acquisition/editing/provenance, consume-once spatial audio, shaped combat drawing, replacement weapon geometry and native geometry verification. All six weapon/impact sources are CC0 recordings. The quiet engine bed is an original procedural asset, explicitly identified in the manifest. Decoder checks are not a listening audition.
