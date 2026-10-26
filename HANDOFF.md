# Brass Tide v0.034 delivered

BRASS TIDE v0.034 - Coastal geography and navigation
DELIVERED SCOPED WINDOWS BUILD
Source/tag: a38c972ad9ad38088d64da307ac41d4db21fd748 / v0.034
Test Bridge: 8d8c9384f1244baba94fa0c2a50688a5
56 focused checks, 0 failures; menu/campaign/battle startup passed.
Selected batch plus setup: 37.275s; owned cleanup verified.

- Campaign routes and their caches account for the largest actual sailing hull, keeping stored reserves separate from the traveling fleet.
- Harbor arrivals use safe approach water within service range and explain unavailable clearance instead of sending large boats through shore.
- Campaign battles use the original coast near the encounter; open water stays open, with safe fleet formations and physical convoy exits.
- Tactical route planning allows conservative turning room, and charted trade routes follow cached water paths.

Later roadmap scopes remain separate. No full-game/rendered/audio acceptance claim.

Retained coastal-navigation034:58 checks/0 failures in TestBridge d967fda5362149cfa2bc4aa49a148a8e; all9 starting NPC courses usable. Production source hashes matched the final candidate; only the coastal encounter fixture changed. The final batch runs that remaining fixture, export and portable startups.

Continue with the next saved version scope after v0.034; preserve the shared lane and120-second limit.
