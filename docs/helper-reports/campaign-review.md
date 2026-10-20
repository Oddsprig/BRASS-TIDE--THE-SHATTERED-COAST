# Campaign integration review

Created `game/tests/test_campaign.gd`; campaign/economy/navigation/world inputs remain read-only. Refreshed inputs pass all original299 checks unchanged. Added12 focused recovery checks: final actual Godot4.7.2 headless result is311 checks,0failures, exit0 in about1second.

Coverage: exactly one cheapest starter/five crew/1800credits; second hull plus minimum crew/payment/pools; recruitment limits; commission materials/time/collection; repairs consume existing kits then harbor supplies and credits; finite resupply; capacity and fractional-food conservation; sealed freight capacity/unsellability/abandonment; full eight-story protocol/rewards/completion/no duplicate contract claim; damaged uncrewed salvage, rescue/debt; JSON world/crew/damage/stocks; ten economy days with exact wages/rations and finite stocks.

Actual first-story navigation steps stay on water. Real inherited-skiff battle wins at19.57seconds with88.26/150HP,45/80ammo,19.73/20supplies. Settlement preserves these stores/damage and advances story. Save comparison recursively checks every field while treating JSON's int-to-float conversion semantically.

`test_campaign.gd:303` proves an outcome retaining only uncrewed salvage returns `fleetLost=true`; rescue preserves the tow and provides an active boat. With eight uncrewed owned hulls, rescue retains exactly eight, crews/repairs/supplies an existing flagship, and charges one1200-credit debt.

Static UI review of root `main.gd`/`interface.gd`: result_handled is set before deferred settlement; successful salvage sets salvage_claimed; closing outcomes selects rescue/return/title. `_enter_battle` clears the previous outcome marker before modal closure, preventing quick-fight replay from closing the new battle. These caller guards cover normal UI replay paths; pure campaign settlement/recovery methods themselves remain non-idempotent and should continue to be called only through those guards. No new unresolved cross-system failures. Actual Windows interaction/playtest remains root's responsibility. No commits or unowned source edits.
