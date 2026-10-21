# Shared fitting and hull art integration verdict

Root accepted Argon B's physical socket/structure module after complete source review and1483 native assertions. IDs, counts, fitting budgets, size thresholds and normal gun arcs remain stable. Fixed launchers now use their socket's outward angle. The unchanged helper report is v006-mounts-argon-original.md.

Root accepted the24 explicit silhouette station arrays and identity/deck details from Argon B's later profile module. Root trimmed the public API to hull_ids(), has_hull(), profile(Dictionary) and stations(Dictionary), and kept all numerical stats in canonical world/Refit data. Layout remains the single source for bridge/machinery/socket positions. Some purely decorative details are omitted if they collide with sockets. Catamaran center decking extends far enough aft to support its rear socket. The unchanged original report is v006-hull-profiles-argon-original.md; its broader draft API does not describe the trimmed integration.

The two requested Argon High projects were started in isolated worktrees. Argon A stalled without delivering a usable art change; none of its code was accepted. Root implemented the weapon models, solid connected hull corrections, superstructure integration, presentation, music, UI and tests. No additional GPT or other helpers were started.

Root replaced forward-only secondary-weapon test assumptions with genuine outward-arc fixtures. Tests retain actual four-family firing and exact ammunition/cooldown assertions, and now reject side launchers firing inward. The all-weapons laboratory/fast fixture uses four surrounding threats. Per-mount target choice respects explicit attack priority when that target is in its firing arc, and can choose another valid threat for an otherwise idle side/rear weapon.

WeaponGeometry supplies the physical barrel/tube distances shared by Refit, WeaponArt and Battle. Each mount records its own local aim and shot time. Torpedoes release into the water at their tube's horizontal position; their visible track stays at the waterline. No new weapon damage, wage anchor or free career goods were introduced for these checks.

Root verified actual hull support, distinct silhouettes, all four weapon projectile origins on all24 hulls, retained numerical specs, camera bounds, portable preferences and eight supplied music roles. Exact native suite results and geometry captures are recorded with this version. Decoder/scheduler tests and software raster captures do not claim human listening, rendered GPU FPS or foreground control feel.
