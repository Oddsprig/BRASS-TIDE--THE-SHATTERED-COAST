# Brass Tide v0.002 — fleet command and fitting

Owner: “PLEASE CALL IT COINS NOT CASH, WASD FOR CAMERA CONTROL. BETTER QUALITY BOATS.” Battle should work as an autobattler with flagship autopilot by default, boat fitting, four weapon families, wakes and 300 deployment points per side.

- Every boat starts on autopilot. Click/drag selects boats; right-click water, enemies or allies gives move, attack or escort orders. Space pauses; Tab toggles a paused tactical overview and restores the prior pause state. U toggles manual flagship; X changes flagship. Manual steering uses arrows; WASD always pans the camera.
- Fleet acquisitions and battle deployment use 300 points. Different hulls/fittings cost different points. Existing over-cap saves keep every boat; undeployed boats remain safe reserves.
- Dock to change compatible machine guns, cannons, rockets, torpedoes, engines and armor within fitting budgets. Review actual materials, shipwrights, engineers, yard margin and duty. Removed modules stay in the boat's locker. Owned parts still need paid work. Fitting never heals damage or refills stores.
- Independent weapon timers, finite shared ammunition, leading/arcs, armor penetration, waterline torpedo damage and rocket fire/blast. Mixed-battery AI closes to useful secondary range. Larger magazines require purchased ammunition.
- All24 original hulls now use richer shaded boat art with seven silhouettes, armor plates/rivets, cabins/glazing, rails, vents and fitting-aware weapons. Wakes curve, widen and fade behind boats; torpedoes and rockets have trails. Water remains inexpensive decorative rendering. Crew remain numerical, with static helm/gunner details.
- Current currency labels say coins. Existing saved purse keys remain compatible. v0.001 voyages migrate without altering the original file.

Testing found and corrected camera reset after panning, wrong mount coordinate scale, empty fittings regenerating a gun, stale references after atomic fitting, weak success-test fixtures, locker bounds, loaded-save input aliasing and mixed-weapon AI standing too far away. A text edit briefly changed an internal NPC purse key; the full financial suite caught it and the key was restored.

All15 native suites passed in the integrated candidate, plus93 art capture checks and23 checks against the real v0.001 voyage. Both eight-contract voyages win using earned money, actual stock/workers and purchased hulls/refits; the autobattle voyage uses zero battle input. It grows from one boat to ten and finishes with three afloat. Original v0.001 remains preserved. Export verification is recorded by RELEASE.json; detailed automated evidence and remaining human play questions accompany the build. No foreground tests or GPU FPS claim.
