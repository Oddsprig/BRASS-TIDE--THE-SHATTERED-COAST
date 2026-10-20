# Cash integration review — read-only snapshot

Reviewed root campaign.gd, harbor.gd, contracts.gd and money.gd during conversion. No root files or previous reports changed; no GUI/focus interaction.

Findings sent to root:

1. **Owner schema mismatch** — campaign.gd:74 creates story owners without wageRemainder/daysOperated/tradeGood and sets tradeCargo to a Dictionary rather than the fleet API's number. Fleet.tick accesses missing fields. Use the complete owner schema.
2. **Rescue creates hulls** — campaign.gd:468 pays the yard but neither requires/decrements shipStock nor consumes construction materials. Empty yards can repeatedly create instant replacement hulls. Consume a real ready hull or commission/refit through production.
3. **Rescue creates workers** — campaign.gd:468–471 assigns five/minimum sailors without reducing workforce/recruits. Harbor.sell returns them into workforce (harbor.gd:128), inflating the fixed civilian pool. Allocate rescue sailors from actual availability and keep workforce/availableWorkers coherent.
4. **Repair double-books labor** — harbor.gd:158 checks total workforce/experts>0, then instantly completes repairs without reserving worker-days. Fully employed workers can repair repeatedly the same day. Require free civilian/specialist capacity and consume paid work over time.
5. **Failed restore mutates voyage** — campaign.gd:514–529 installs saved state before rejecting its inconsistent coin ledger. Validate a temporary candidate or rollback.

Normal Money transfers/totals include all four port purses, order escrow, fleet/crew purses and contract escrow; no normal-path coin mint/drain found. Collection removes completed orders, so Construction must guarantee zero remaining escrow or refund residue before removal. Pure battle settlement remains replay-sensitive; preserve main's once-only settlement/salvage guards. Incoming Economy/Construction still require combined executable validation; no pending integration pass is claimed.
