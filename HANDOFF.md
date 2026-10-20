# Current state — v0.001 in development

Owner chose Godot4 native Windows after an initial browser technical prototype. Source under game/ is authoritative; dist/ contains tested JavaScript reference modules only. No web build will be released. Separate render thread configured in game/project.godot. Current code is incomplete; no playable release has been claimed.

One Sol6.1 specialist built the JS damage/battle/navigation reference. Two Argon High Bridge helpers built economy and original24boat/10port/8mission world. Native ports now use isolated Git worktrees. Root builds campaign/UI/art, verifies all integration, documents and exports.

Immediate next step: finish native module ports, campaign/render/UI, import and headless checks, actual Windows playtest, release docs and export in a separate worktree, then desktop icon and verified GitHub push if host access permits.
