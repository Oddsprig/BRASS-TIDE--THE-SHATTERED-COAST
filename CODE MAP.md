# Current source map

game/project.godot: Godot4 native project, separate rendering thread, 1600x1000 reference layout.
game/scripts/version.gd: integer build counter and exact three-decimal version.
game/scripts/damage.gd: damage, breaches, crew tasks, supplies, pumps and sinking (native port in progress).
game/scripts/battle.gd: fixed-step fleet combat, steering, weapons, AI and retreat (native port in progress).
game/scripts/economy.gd: port workers, production, stocks, trade, wages (native port in progress).
game/scripts/navigation.gd: water-only campaign pathfinding (native port in progress).
game/scripts/main.gd: main scene/controller (in progress).
game/data/world.json: original factions, hulls, islands, ports and story (generated from reviewed data).
dist/*.js and tests/*.cjs: original module reference and fast tests, not shipped as a browser game.
