# Voyage progression — read-only review

No Godot/test process launched; only current sources and root's existing voyage.log read. No source or prior report edits.

**P1 async atomicity:** main.gd snapshots ports for background Economy, then campaign.apply_economy replaces ports wholesale. Contract acceptance/completion and collection mutate purses/escrow/orders before save_game synchronizes. Interface directly abandons contracts/repays loans without pre-sync. Pending snapshots can restore sponsor cash after escrow funding, lose repayments, or resurrect collected orders. Synchronize before every port mutation or validate publication revisions; synchronization after mutation is too late.

**First-three-leg roster:** voyage.prepare requests optimal crew atomically. A Punt needs3minimum/4optimal: requesting4 with3volunteers recruits nobody. Hire minimum first, then optional top-up. Preparation occurs only at departure; the player can also hire/repair at Sawtooth before starting leg2. Root's existing log confirms the uncrewed Punt stayed mothballed and the lone starter lost leg2.

**Stores absorb capital:** full refill prioritizes60fuel before ammo. Recipe-base cost is18000cash fuel plus5150cash for20kits, excluding price spread. Campaign fuel consumption is roughly0.014/second and upkeep~0.1/day. Offer explicit quantities/short-voyage stores; resupply success can mean fuel bought while ammunition remains empty.

**Finite repairs:** a35%-HP salvaged135HP Punt needs7.02ordinary repair-days, rounded to8idle workers, and17.55kits before working stores. Multiple repairs share finite daily labor. Failed preparation should wait/re-route/repair partially instead of deploying a47HP hull.

**Combat prerequisite:** ideal hull-only starter shots are approximately74hits for leg2 and110 for leg3 versus80ready rounds, before misses/flooding. Expansion is necessary. Later, always salvaging enemySpecs[0] and retaining early weak hulls fills eight slots without upgrades; the voyage captain needs budget-aware purchase/sale decisions before broad enemy/reward buffs. These are static balance assessments, not completed-voyage validation.
