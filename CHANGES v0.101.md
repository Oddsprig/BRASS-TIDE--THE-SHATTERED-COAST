# Brass Tide v0.101 — Battle worker payloads

v0.101 — Accepted scoped worker-payload change
Native1446 checks/0failures: identical payload values and read-only flags, nested worker isolation, and fresh targets on both sides. Twelve paired constructions per side on42 boats/294DP per side: player median14.328 ->13.446ms; enemy17.221 ->16.362ms (about6.2%/5.0%). This measures capsule construction only, with variable samples; it does not establish overall FPS or eliminate the historical36.154ms workerP95/183.333ms lag.
Job5384f742f5204de6a13169238938d9f1 attempt003 passed native/export/isolated101menu. First two attempts remain failures in fixture wiring (static-call parse, then missing initial live index); production was not accepted from those attempts. Successful queued command25.969s, native body2.321s; no watchdog kill. No additional native tests for this change.
