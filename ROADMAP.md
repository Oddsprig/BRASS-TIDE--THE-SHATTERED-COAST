# Current step: v0.043 - Real rendered performance and runtime budget

- Measure actual exported mixed and light300point battles through the real renderer with active combat and declared hardware/resolution.
- Attribute simulation and draw costs through opt-in counters, then apply bounded fixes to demonstrated bottlenecks while preserving actors,60Hz and authoritative state.
- Keep real rendered background profiling separate from capped headless checks, and preserve actual limits and unmet targets.

Finish this scope, run focused checks under120seconds, package, then advance
to the next saved scope. No speculative fine-tuning or full-game gate.
