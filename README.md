# Brass Tide: The Shatter Coast — v0.021

An original Windows motorboat fleet campaign built in Godot. Start with a Tinwake skiff, earn bronze coins, pay sailors and build a fleet of 24 boat designs. Fit interchangeable guns, cannons, rockets, torpedoes, engines and armor. Numerical crews fight fires, patch breaches, bail water and keep damaged boats afloat.

v0.019 adds paid harbor training: existing workers and an instructor leave ordinary work, prepaid material lots are consumed, and daily wages move from held coins to trainee and instructor purses. Harbor controls show the full bill, eligibility and refund rules. Existing sailors keep their competence.

v0.020 adds route-scale reserve reports, physically protected operating stock, feasible essential-production floors and actual public granary releases. Market and NPC purchases share the same finite export availability.

v0.021 adds finite surveyed machinery, paid recovery crews, physical equipment cargo, staffed restoration, actual workshop recipes and maintenance, and funded drydock expansion. Private workshop inputs and public shipyard stocks retain separate ownership.

The campaign now includes expedition reserves, island surveys, persistent wreck recovery, compatible jobs and remembered contacts, faction relationships, independent convoys/patrols/raiders, reactive inventories and blockades, support conversions and paid specialists, four original exploration stories, staffed home-harbor businesses and sustained regional goals.

All eleven requested increments v0.008–v0.018 were built sequentially and preserved as individual tagged Windows/source deliveries. Each later portable version has its own exact-tag verification receipt; the Desktop launcher is updated only after verification. Prior releases, original saves and owner music remain intact. Local portable binaries live in the task's outputs folders; this repository contains the Godot source and version tags.

WASD pans, Shift pans faster, scroll zooms, M shows the coast and Home follows your fleet. Battles default to autopilot; select boats and right-click orders, Space pauses, Tab opens tactical view. I opens island surveys, K jobs/contacts and L regional goals. Ownership and support reserves are separate from the 300-point battle deployment limit. The title-screen fleet laboratory tests boats and fittings without spending career coins.

Read [the captain's guide](docs/CAPTAINS%20CAMPAIGN%20GUIDE.txt) for the full loop and [delivery notes](docs/CAMPAIGN%20DELIVERY%20v0.008-v0.018.txt) for exact per-version records. Bronze-coin wages, materials, real inventories and finite worker/business/government/fleet purses underpin the economy. Original assets, names, coast and stories take broad genre inspiration; no reference-game assets or map were copied.

Rendering uses Separate threading, inexpensive decorative 2D water and cached boat geometry. Pure harbor production runs on copied state using a hardware-aware worker group capped at 8; the main thread publishes joined results before advancing fleet decisions. The native Windows portable game needs no editor, Node or Python installation.

Development starts at game/project.godot. Read AGENTS.md, maps/PROJECT MAP.txt, HANDOFF.md and CODE MAP.md before editing. All 52 native suites run sequentially via tools/check_game.py with the existing Godot 4.7.2 console executable. Tests remain hidden/headless, with no desktop input. The 180-day campaign, real-save migration and the 300-versus-300 CPU fixture passed; these measurements do not claim rendered FPS or human listening. Keep each version's exact export/source archives and advance playable versions by 0.001.
