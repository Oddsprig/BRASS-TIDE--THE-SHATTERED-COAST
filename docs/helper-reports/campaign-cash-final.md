# Bronze-cash campaign integration — final bounded task

Added only `game/tests/test_campaign_cash.gd`; previous campaign tests/reports remain unchanged. Actual Godot4.7.2 headless run against currently copied dependencies: **410checks,0failures,1030ms,exit0**. No UI, foreground/focus, mouse or keyboard control used.

Verified:

- One starter/five sailors,15000captain cash and5000crew cash.
- Real priced hull/minimum crew funded by transfers from existing port purses; ship stock/workforce/recruits consumed; no free working stores. One ammo case buys50ready rounds.
- Commission cash split into real wage escrow/materials/tax/business income; actual work pays household/expert purses, completes with zero escrow, collects once. No deletion of unpaid escrow.
-100cash per sailor/day enters shared purse. Arrears reduce morale/actual speed; repayment transfers cash to crew and clears liability. Harbor-loan repayment restores the actual lending treasury.
- Sponsor-funded escrow and physical freight; abandonment refunds sponsor/stock. All eight story protocols pay exactly escrow plus captured operating-purse cash, advance once and reject duplicate rewards.
- Capture conserves owner/player money. Salvage requires a pending wreck and only one claim, yielding damaged/uncrewed/unstored hull.
- Rescue consumes finite ready stock and civilian sailors, borrows existing treasury money, refuses an empty yard and refits within the eight-hull cap.
- Used hull sale requires business cash and returns crew/workforce, savings and stores. Corrupt save refusal leaves live voyage unchanged; valid JSON preserves world/purses/NPC ownership/damage/stocks.
-100days of actual core+NPC+yards preserve exact total coins every day, including a real funded job that advances labor, and maintain finite physical stocks/purses.

No new failure found in this copied integration. Root should independently rerun after final Economy/Construction refresh, which was still pending when assigned. No source edits, deletion or commits.
