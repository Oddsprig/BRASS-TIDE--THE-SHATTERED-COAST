# Current save preflight contract — v0.028 base

Read actual save_validation.gd, campaign_state_validation.gd, coast_migration.gd
and Campaign.restore. SaveValidation.validate(saved, world) returns a Dictionary;
Campaign accepts the validated/migrated state only after success. Use current keys
and full native schemas rather than old example counts or ad-hoc JSON assumptions.

Preflight malformed types, nonfinite values, negative/fractional coins, IDs and
ownership before counting/indexing/replacing live state. Accept legitimate JSON
whole-valued numeric floats. Preserve input; migrate copies. Validate all goods,
actual carrier cargo, working stores, crew/qualification subsets, shore employees,
tooling, company charters, escrow, boarding/captives, passengers and liabilities.
Reject inconsistent custody and capacity. Failure must leave live state intact.

Adding a good/cohort/owner requires the same addition to wreck/restore accounting.
Installed tooling and workshop staff cannot disappear. Sunk flagship references
must resolve to an actual surviving hull. See DEVELOPER LESSONS for .021/.028 fixes.
Use isolated synthetic fixtures and read-only copies for legacy migration; keep
owner originals/settings/backups untouched. Source test_save_validation.gd and
actual module/voyage tests remain authoritative. Existing evidence is indexed;
rerun affected schemas/flows only when changed, plus required release regressions.
