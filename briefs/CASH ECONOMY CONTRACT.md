# Current finite-economy contract — v0.028 base

Native code/data/tests are authoritative; this replaces the old migration brief.
The original brief is preserved verbatim in the consolidation context addendum.

Use integer **coins** in purses and player-visible currency. A sailor-day earns
100 coins; physical goods may be fractional. No credits, arbitrary boat prices,
regenerated coin balances or free production workforce. Current goods/catalogue:
Goods.definitions(), industry_data.gd and game/data/world.json (20 goods, 24 hulls).
Historical brief counts are not current limits. Port internal `cash` remains the
aggregate business purse; renaming visible currency does not justify a schema break.

Economy/Construction/FleetEconomy must transfer existing coins/stock, reserve actual
workers/experts, pay input labor, assembly, supervision and overhead, and preserve
liabilities separately. Owners buy real supplies, pay crew purses and wages, suffer
actual damage/loss and fund replacements. Seeding happens once on world creation;
no automatic purse reset. Capital, cost basis, sale revenue and earned profit are
distinct. Schooling, workshops, customs, boarding and passenger cohorts conserve
existing people and their qualifications, berths, property and money.

Read actual economy.gd, goods.gd, construction.gd, fleet_economy.gd, money.gd and the
system being changed; use generated maps. Pure worker tasks own disjoint copied
ports and publish after main-thread join. Atomic live transactions preserve the
identity of held port/business/hull references. Save preflight must include every
new cohort/purse/store before any live mutation.

Relevant native suites: economy, construction, fleet_economy, campaign_cash,
save_validation and the affected module/voyage pair. See VERIFICATION INDEX before
reruns and DEVELOPER LESSONS for known regressions. A helper needs a fresh narrow
allowlist; this contract does not grant ownership of all listed modules or start
an implementation task.
