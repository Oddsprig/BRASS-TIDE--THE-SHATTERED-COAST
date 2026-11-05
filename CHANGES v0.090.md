# Brass Tide v0.090 - Boat separation and steering

Owner: "stick to the scope of each one".

- Use authored heading-aware hull capsules for boat-to-boat contact and spawn clearance; preserve the existing terrain and weapon hit radius.
- Keep compact side-by-side passage and existing tactical steering/escort slots. Increase spawn column spacing only for longer hulls.
- Preserve intentional ram/boarding contact; manual takeover revokes automatic boarding clearance exemptions. Retain all36 boats and actual stores/owners.

See docs/TEST RESULTS v0.090.md for actual focused checks and remaining limits.

Verification: 427 focused assertions/0 failures, Windows export and portable menu startup. Whole selected batch plus setup 54.743s. Preserved earlier failures; no broad acceptance claim.
