# Brass Tide v0.043

Current candidate: Real rendered performance and runtime budget.

- Measure actual exported mixed and light300point battles through the real renderer with active combat and declared hardware/resolution.
- Attribute simulation and draw costs through opt-in counters, then apply bounded fixes to demonstrated bottlenecks while preserving actors,60Hz and authoritative state.
- Keep real rendered background profiling separate from capped headless checks, and preserve actual limits and unmet targets.

Focused native checks/export are pending. Root owns all TestBridge work;
helpers stay in source-only roles. Continue this version before the next.
