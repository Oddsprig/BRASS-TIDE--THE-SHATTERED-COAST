# Sol fleet cash review — dependency validation pending

Implemented `game/scripts/fleet_economy.gd` as a pure static RefCounted module. API: create_owners, tick, total_coins, upkeep; narrow helpers dock and subsidize. Nine patrol-ID owners match existing chart routes and names. Boats own independent deep-copied specs; physical starting fuel/ammo/kits are zero. Initial owner capital transfers existing home business/government coins only. Seeded sailors leave the fixed civilian workforce/recruit pool.

Each living sailor earns100bronze cash/day, transferred into crewPurse; fractional-day pay accrues without lost coins. Unpaid amounts remain liabilities and reduce morale, actual boat speed and firing cadence via preserved base specs. Sunk boats never erase purses. Food is paid by crew; physical fuel, repair kits and50-round ammo cases by the owner. Merchant tradeCargo distinguishes business lots from crew-funded rations. Finite repairs transfer100ordinary/150mechanic wages to household/expert purses and require idle workers/kits. Subsidies require explicit affordable government transfers.

Root movement must clear atPort while sailing and call dock on arrival. tick also services owners whose atPort remains set. Root must not multiply economyFactor again, since spec speed/fireRate already reflect it. No GUI, Nodes, input, focus, filesystem simulation access, deletion or commits.

Current staged headless Godot4.7.2 run:655checks in282ms;648pass,7dependency/purchase/trade failures because copied economy still expects credits rather than coins. Strict assertions retained. Capital/wages/subsidies/arrears, deep-copy isolation, sinking purse retention, all365daily exact total-conservation checks including escrow, no-capital bankruptcy and finite stocks pass. Additional real16good economy+fleet365day test will run after refreshed economy input. Old campaign report preserved unchanged. Final combined validation pending dependency refresh.

