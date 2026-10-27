# Brass Tide v0.043 - Real rendered performance

This pass measures actual exported battles and reduces repeated equipment,
traffic and drawing preparation. It keeps the full300-point fleets,60Hz
physics, original combat rules and existing economy workers.

The experimental separate graphics mode raised engine texture errors. A matched
same-build comparison removed those errors in safe graphics mode, now default.
The performance targets remain open; read docs/PERFORMANCE v0.043.txt for actual
numbers and the distinction between complete measurement and smooth play.

Final combined correction passed419focused checks and portable verification.
Rendered mixed-fleet FPS improved16.903 to28.686; light3.749 to4.330. The
light-fleet case remains unacceptable; smoothness acceptance is OPEN.

Verification: 419 focused assertions/0 failures, Windows export and portable menu/campaign/battle startup. Whole selected batch plus setup 58.004s. Preserved earlier failures; no broad acceptance claim.
