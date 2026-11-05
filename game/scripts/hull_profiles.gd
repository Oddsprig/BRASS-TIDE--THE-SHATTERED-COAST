extends RefCounted
## Pure static hull identity profiles for the 36 canonical Brass Tide hulls.
## Provides name-specific stern-to-bow silhouette stations Vector2(x, half_beam),
## bridgeStyle, deckAccents, and cargoDetails while preserving archetypes,
## sizes/stats/budgets, and clear deck zones for shared sockets, central bridge, and engine.

const CAT_OFFSET: float = 0.62

const _ROLE_ARCH: Dictionary = {
	"skiff": "speedboat", "cutter": "hydrofoil", "torpedo": "hydrofoil", "raider": "catamaran",
	"corvette": "patrol", "gunboat": "armored", "rocket": "monitor", "cruiser": "command"
}

const _ROLE_DEFAULT_ID: Dictionary = {
	"skiff": "tin_skiff", "cutter": "marsh_dart", "torpedo": "reed_stinger", "raider": "silt_lugger",
	"corvette": "harbor_sloop", "gunboat": "slag_gunboat", "rocket": "barbed_lance", "cruiser": "cobalt_frigate"
}

const _HULL_ORDER: Array = [
	"tin_skiff", "bilge_punt", "lantern_skiff", "marsh_dart", "scab_cutter", "gale_cutter",
	"silt_lugger", "hook_raider", "mercantile_clipper", "harbor_sloop", "ash_corvette", "aegis_corvette",
	"reed_stinger", "krill_torpedo", "manta_strike", "slag_gunboat", "bellows_gunboat", "furnace_turret",
	"barbed_lance", "cinder_monitor", "wraith_rocket", "cobalt_frigate", "iron_bastion", "maiden_dreadnought",
	"kelpnet_dory", "brinehook_longliner", "mother_gull_trawler", "fenhopper_lighter",
	"tideledger_coaster", "fourport_packet", "brasswind_motor_galleon", "seepoil_tanker",
	"blackwater_fleet_tanker", "gullwing_daysailer", "osprey_cabin_cruiser", "aurelian_court_yacht"
]

const _PROFILES: Dictionary = {
	"tin_skiff": {"name": "Tinwake Skiff", "faction": "compact", "role": "skiff", "tier": 1, "size": 14.0, "bridgeStyle": "open_windscreen", "bridge": {"x": -0.30, "len": 0.68, "wid": 0.48, "h": 17.5, "glass": false, "visor": "raked_screen"},
		"stations": [Vector2(-1.86, 0.42), Vector2(-1.62, 0.52), Vector2(-0.95, 0.58), Vector2(-0.15, 0.60), Vector2(0.55, 0.58), Vector2(1.22, 0.46), Vector2(1.78, 0.22), Vector2(2.02, 0.0)],
		"accents": [{"kind": "bow_fender", "x": 1.56, "y": 0.0, "len": 0.26, "wid": 0.34, "h": 10.5}, {"kind": "outboard_pair", "x": -1.80, "y": 0.22, "len": 0.22, "wid": 0.14, "h": 12.5}],
		"cargo": [{"kind": "rope_coil", "x": 1.44, "y": 0.14, "len": 0.16, "wid": 0.16, "h": 10.0}, {"kind": "tool_locker", "x": -1.26, "y": -0.26, "len": 0.20, "wid": 0.16, "h": 11.0}]},
	"bilge_punt": {"name": "Bilgewater Punt", "faction": "raiders", "role": "skiff", "tier": 1, "size": 13.0, "bridgeStyle": "scout_cowl", "bridge": {"x": -0.31, "len": 0.66, "wid": 0.46, "h": 16.8, "glass": false, "visor": "scrap_shield"},
		"stations": [Vector2(-1.90, 0.34), Vector2(-1.60, 0.48), Vector2(-0.85, 0.62), Vector2(-0.05, 0.61), Vector2(0.58, 0.58), Vector2(1.20, 0.40), Vector2(1.82, 0.12), Vector2(2.14, 0.0)],
		"accents": [{"kind": "pike_sprit", "x": 1.66, "y": 0.0, "len": 0.34, "wid": 0.18, "h": 10.5}, {"kind": "patch_strake", "x": -0.30, "y": 0.42, "len": 0.48, "wid": 0.10, "h": 9.8}],
		"cargo": [{"kind": "salvage_drum", "x": -1.26, "y": 0.26, "len": 0.18, "wid": 0.18, "h": 11.2}, {"kind": "grapnel_reel", "x": 1.46, "y": -0.12, "len": 0.16, "wid": 0.16, "h": 10.2}]},
	"lantern_skiff": {"name": "Lantern Ward Skiff", "faction": "compact", "role": "skiff", "tier": 2, "size": 15.0, "bridgeStyle": "customs_canopy", "bridge": {"x": -0.29, "len": 0.71, "wid": 0.51, "h": 18.6, "glass": true, "visor": "searchlight_brow"},
		"stations": [Vector2(-1.96, 0.48), Vector2(-1.68, 0.58), Vector2(-0.90, 0.64), Vector2(0.05, 0.65), Vector2(0.66, 0.61), Vector2(1.30, 0.48), Vector2(1.84, 0.20), Vector2(2.08, 0.0)],
		"accents": [{"kind": "searchlight_post", "x": 1.54, "y": 0.0, "len": 0.18, "wid": 0.18, "h": 15.0}, {"kind": "bilge_sponson", "x": -0.28, "y": 0.46, "len": 0.56, "wid": 0.12, "h": 10.2}],
		"cargo": [{"kind": "customs_chest", "x": -1.28, "y": -0.28, "len": 0.24, "wid": 0.18, "h": 11.5}, {"kind": "buoy_rack", "x": -1.28, "y": 0.28, "len": 0.22, "wid": 0.16, "h": 11.5}]},
	"marsh_dart": {"name": "Marsh Dart Hydro", "faction": "reed", "role": "cutter", "tier": 1, "size": 14.0, "bridgeStyle": "stepped_cockpit", "bridge": {"x": -0.31, "len": 0.70, "wid": 0.48, "h": 18.8, "glass": true, "visor": "bubble_canopy"},
		"stations": [Vector2(-1.86, 0.35), Vector2(-1.60, 0.48), Vector2(-0.92, 0.55), Vector2(-0.10, 0.59), Vector2(0.52, 0.60), Vector2(1.18, 0.42), Vector2(1.86, 0.11), Vector2(2.16, 0.0)],
		"accents": [{"kind": "planing_step", "x": 0.18, "y": 0.44, "len": 0.22, "wid": 0.14, "h": 9.6}, {"kind": "bow_vane", "x": 1.62, "y": 0.0, "len": 0.30, "wid": 0.20, "h": 10.4}],
		"cargo": [{"kind": "reed_pannier", "x": -1.25, "y": -0.25, "len": 0.22, "wid": 0.16, "h": 11.2}, {"kind": "shoal_poles", "x": -1.25, "y": 0.25, "len": 0.28, "wid": 0.12, "h": 10.8}]},
	"scab_cutter": {"name": "Scabfin Cutter", "faction": "raiders", "role": "cutter", "tier": 2, "size": 17.0, "bridgeStyle": "sawtooth_cowl", "bridge": {"x": -0.31, "len": 0.72, "wid": 0.50, "h": 19.6, "glass": true, "visor": "slit_casemate"},
		"stations": [Vector2(-1.92, 0.44), Vector2(-1.64, 0.54), Vector2(-0.88, 0.58), Vector2(0.00, 0.62), Vector2(0.60, 0.63), Vector2(1.28, 0.52), Vector2(1.80, 0.24), Vector2(2.06, 0.0)],
		"accents": [{"kind": "sawtooth_fender", "x": 1.52, "y": 0.22, "len": 0.32, "wid": 0.14, "h": 10.8}, {"kind": "fin_strake", "x": -0.30, "y": 0.44, "len": 0.50, "wid": 0.12, "h": 11.0}],
		"cargo": [{"kind": "ammo_hoppers", "x": -1.27, "y": 0.28, "len": 0.24, "wid": 0.18, "h": 11.8}, {"kind": "boarding_hooks", "x": 1.44, "y": -0.16, "len": 0.22, "wid": 0.14, "h": 10.5}]},
	"gale_cutter": {"name": "Galeblade Interceptor", "faction": "reed", "role": "cutter", "tier": 3, "size": 18.0, "bridgeStyle": "interceptor_canopy", "bridge": {"x": -0.30, "len": 0.74, "wid": 0.51, "h": 20.4, "glass": true, "visor": "swept_aero"},
		"stations": [Vector2(-2.02, 0.38), Vector2(-1.70, 0.52), Vector2(-0.95, 0.55), Vector2(-0.05, 0.63), Vector2(0.58, 0.65), Vector2(1.32, 0.45), Vector2(1.96, 0.14), Vector2(2.24, 0.0)],
		"accents": [{"kind": "supercharger_scoop", "x": -0.78, "y": 0.0, "len": 0.18, "wid": 0.26, "h": 15.2}, {"kind": "blade_strake", "x": 1.66, "y": 0.0, "len": 0.36, "wid": 0.20, "h": 10.8}],
		"cargo": [{"kind": "trim_cells", "x": -1.28, "y": -0.27, "len": 0.24, "wid": 0.16, "h": 11.6}, {"kind": "signal_tube", "x": -1.28, "y": 0.27, "len": 0.24, "wid": 0.16, "h": 11.6}]},
	"silt_lugger": {"name": "Silt Runner Lugger", "faction": "reed", "role": "raider", "tier": 1, "size": 17.0, "bridgeStyle": "estuary_span", "bridge": {"x": -0.28, "len": 0.71, "wid": 0.56, "h": 19.6, "glass": true, "visor": "wide_pilothouse"},
		"stations": [Vector2(-1.88, 0.20), Vector2(-1.60, 0.24), Vector2(-0.75, 0.25), Vector2(0.25, 0.25), Vector2(0.95, 0.22), Vector2(1.52, 0.16), Vector2(1.88, 0.08), Vector2(2.02, 0.0)],
		"accents": [{"kind": "pontoon_fender", "x": 1.48, "y": 0.62, "len": 0.28, "wid": 0.14, "h": 10.5}, {"kind": "cross_beam", "x": 0.18, "y": 0.0, "len": 0.16, "wid": 0.96, "h": 10.2}],
		"cargo": [{"kind": "grain_tarp", "x": -1.26, "y": -0.34, "len": 0.28, "wid": 0.24, "h": 12.4}, {"kind": "bale_stack", "x": -1.26, "y": 0.34, "len": 0.28, "wid": 0.24, "h": 12.4}]},
	"hook_raider": {"name": "Grapnel Blockade Runner", "faction": "raiders", "role": "raider", "tier": 2, "size": 20.0, "bridgeStyle": "runner_gantry", "bridge": {"x": -0.28, "len": 0.73, "wid": 0.58, "h": 20.4, "glass": true, "visor": "armored_gantry"},
		"stations": [Vector2(-1.96, 0.16), Vector2(-1.66, 0.21), Vector2(-0.80, 0.22), Vector2(0.20, 0.24), Vector2(0.88, 0.23), Vector2(1.50, 0.14), Vector2(1.94, 0.05), Vector2(2.15, 0.0)],
		"accents": [{"kind": "grapnel_davit", "x": 1.54, "y": 0.62, "len": 0.30, "wid": 0.14, "h": 12.0}, {"kind": "chain_catwalk", "x": 0.18, "y": 0.0, "len": 0.18, "wid": 1.02, "h": 10.6}],
		"cargo": [{"kind": "smuggler_locker", "x": -1.28, "y": -0.36, "len": 0.28, "wid": 0.22, "h": 12.6}, {"kind": "contraband_cask", "x": -1.28, "y": 0.36, "len": 0.28, "wid": 0.22, "h": 12.6}]},
	"mercantile_clipper": {"name": "Sovereign Armed Packet", "faction": "compact", "role": "raider", "tier": 3, "size": 23.0, "bridgeStyle": "packet_house", "bridge": {"x": -0.28, "len": 0.75, "wid": 0.59, "h": 21.4, "glass": true, "visor": "treasury_cupola"},
		"stations": [Vector2(-2.06, 0.19), Vector2(-1.74, 0.25), Vector2(-0.85, 0.27), Vector2(0.25, 0.27), Vector2(1.02, 0.24), Vector2(1.66, 0.16), Vector2(2.06, 0.06), Vector2(2.26, 0.0)],
		"accents": [{"kind": "bullion_coaming", "x": 0.18, "y": 0.0, "len": 0.20, "wid": 1.06, "h": 11.2}, {"kind": "packet_prow_crest", "x": 1.62, "y": 0.62, "len": 0.32, "wid": 0.16, "h": 11.0}],
		"cargo": [{"kind": "bonded_strongbox", "x": -1.30, "y": -0.36, "len": 0.30, "wid": 0.24, "h": 13.0}, {"kind": "bonded_strongbox", "x": -1.30, "y": 0.36, "len": 0.30, "wid": 0.24, "h": 13.0}]},
	"harbor_sloop": {"name": "Breakwater Patrol Sloop", "faction": "compact", "role": "corvette", "tier": 1, "size": 17.0, "bridgeStyle": "brass_wheelhouse", "bridge": {"x": -0.31, "len": 0.71, "wid": 0.53, "h": 19.8, "glass": true, "visor": "brass_binnacle"},
		"stations": [Vector2(-1.86, 0.45), Vector2(-1.60, 0.56), Vector2(-0.82, 0.62), Vector2(0.05, 0.62), Vector2(0.65, 0.59), Vector2(1.26, 0.46), Vector2(1.78, 0.18), Vector2(2.04, 0.0)],
		"accents": [{"kind": "breakwater_coaming", "x": 1.48, "y": 0.0, "len": 0.22, "wid": 0.42, "h": 11.2}, {"kind": "capstan_post", "x": 1.64, "y": 0.0, "len": 0.14, "wid": 0.14, "h": 11.8}],
		"cargo": [{"kind": "convoy_stores", "x": -1.27, "y": -0.28, "len": 0.24, "wid": 0.18, "h": 11.6}, {"kind": "hawser_reel", "x": 1.42, "y": -0.18, "len": 0.18, "wid": 0.18, "h": 10.4}]},
	"ash_corvette": {"name": "Ashwake Escort Corvette", "faction": "forge", "role": "corvette", "tier": 2, "size": 21.0, "bridgeStyle": "turtleback_conning", "bridge": {"x": -0.31, "len": 0.73, "wid": 0.55, "h": 20.6, "glass": true, "visor": "foundry_hood"},
		"stations": [Vector2(-1.94, 0.52), Vector2(-1.66, 0.64), Vector2(-0.88, 0.68), Vector2(0.10, 0.68), Vector2(0.72, 0.65), Vector2(1.36, 0.52), Vector2(1.86, 0.24), Vector2(2.10, 0.0)],
		"accents": [{"kind": "turtleback_glacis", "x": 1.54, "y": 0.0, "len": 0.34, "wid": 0.48, "h": 11.8}, {"kind": "welded_belt", "x": -0.30, "y": 0.50, "len": 0.58, "wid": 0.12, "h": 10.8}],
		"cargo": [{"kind": "shell_caisson", "x": -1.28, "y": -0.32, "len": 0.24, "wid": 0.20, "h": 12.0}, {"kind": "cinder_drum", "x": -1.28, "y": 0.32, "len": 0.22, "wid": 0.20, "h": 12.0}]},
	"aegis_corvette": {"name": "Vanguard Line Corvette", "faction": "compact", "role": "corvette", "tier": 3, "size": 24.0, "bridgeStyle": "rangefinder_bridge", "bridge": {"x": -0.31, "len": 0.75, "wid": 0.56, "h": 21.8, "glass": true, "visor": "optical_director"},
		"stations": [Vector2(-2.02, 0.48), Vector2(-1.72, 0.60), Vector2(-0.90, 0.66), Vector2(0.10, 0.66), Vector2(0.76, 0.62), Vector2(1.42, 0.44), Vector2(1.96, 0.16), Vector2(2.22, 0.0)],
		"accents": [{"kind": "rangefinder_wing", "x": -0.28, "y": 0.46, "len": 0.32, "wid": 0.14, "h": 16.0}, {"kind": "clipper_breakwater", "x": 1.58, "y": 0.0, "len": 0.28, "wid": 0.40, "h": 11.5}],
		"cargo": [{"kind": "damage_control_locker", "x": -1.29, "y": -0.30, "len": 0.26, "wid": 0.20, "h": 12.2}, {"kind": "damage_control_locker", "x": -1.29, "y": 0.30, "len": 0.26, "wid": 0.20, "h": 12.2}]},
	"reed_stinger": {"name": "Fen Stinger Torpedo Launch", "faction": "reed", "role": "torpedo", "tier": 2, "size": 17.0, "bridgeStyle": "low_stinger_hood", "bridge": {"x": -0.31, "len": 0.71, "wid": 0.50, "h": 19.2, "glass": true, "visor": "torpedo_sight"},
		"stations": [Vector2(-1.88, 0.36), Vector2(-1.60, 0.48), Vector2(-0.88, 0.56), Vector2(0.12, 0.62), Vector2(0.62, 0.60), Vector2(1.24, 0.42), Vector2(1.84, 0.12), Vector2(2.14, 0.0)],
		"accents": [{"kind": "drop_collar_cheek", "x": 0.18, "y": 0.46, "len": 0.26, "wid": 0.14, "h": 11.4}, {"kind": "air_flask_manifold", "x": 1.54, "y": 0.0, "len": 0.28, "wid": 0.22, "h": 10.8}],
		"cargo": [{"kind": "air_bottle_rack", "x": -1.26, "y": -0.26, "len": 0.24, "wid": 0.16, "h": 11.6}, {"kind": "warhead_cradle", "x": -1.26, "y": 0.26, "len": 0.24, "wid": 0.16, "h": 11.6}]},
	"krill_torpedo": {"name": "Tallowfin Torpedo Boat", "faction": "raiders", "role": "torpedo", "tier": 3, "size": 20.0, "bridgeStyle": "wolfpack_hood", "bridge": {"x": -0.31, "len": 0.72, "wid": 0.52, "h": 20.2, "glass": true, "visor": "wolfpack_vane"},
		"stations": [Vector2(-1.96, 0.44), Vector2(-1.68, 0.56), Vector2(-0.86, 0.63), Vector2(0.10, 0.65), Vector2(0.68, 0.63), Vector2(1.34, 0.46), Vector2(1.90, 0.16), Vector2(2.18, 0.0)],
		"accents": [{"kind": "reload_skid", "x": 1.54, "y": 0.0, "len": 0.34, "wid": 0.24, "h": 11.2}, {"kind": "tallow_fin", "x": -0.30, "y": 0.48, "len": 0.46, "wid": 0.14, "h": 11.8}],
		"cargo": [{"kind": "torpedo_canister", "x": -1.28, "y": 0.30, "len": 0.28, "wid": 0.18, "h": 12.0}, {"kind": "grease_drums", "x": -1.28, "y": -0.30, "len": 0.24, "wid": 0.18, "h": 11.8}]},
	"manta_strike": {"name": "Manta Flotilla Leader", "faction": "reed", "role": "torpedo", "tier": 4, "size": 24.0, "bridgeStyle": "manta_command_fin", "bridge": {"x": -0.31, "len": 0.74, "wid": 0.54, "h": 21.6, "glass": true, "visor": "manta_crest"},
		"stations": [Vector2(-2.05, 0.40), Vector2(-1.72, 0.52), Vector2(-0.92, 0.58), Vector2(0.05, 0.68), Vector2(0.64, 0.70), Vector2(1.36, 0.48), Vector2(1.98, 0.15), Vector2(2.28, 0.0)],
		"accents": [{"kind": "manta_chine_wing", "x": 0.16, "y": 0.52, "len": 0.34, "wid": 0.18, "h": 11.6}, {"kind": "spear_hydro_prow", "x": 1.66, "y": 0.0, "len": 0.38, "wid": 0.22, "h": 11.0}],
		"cargo": [{"kind": "reload_tube_case", "x": -1.30, "y": -0.30, "len": 0.28, "wid": 0.18, "h": 12.2}, {"kind": "reload_tube_case", "x": -1.30, "y": 0.30, "len": 0.28, "wid": 0.18, "h": 12.2}]},
	"slag_gunboat": {"name": "Slagclast River Gunboat", "faction": "forge", "role": "gunboat", "tier": 2, "size": 22.0, "bridgeStyle": "ironclad_casemate", "bridge": {"x": -0.31, "len": 0.73, "wid": 0.57, "h": 21.0, "glass": false, "visor": "armored_slit"},
		"stations": [Vector2(-1.87, 0.58), Vector2(-1.60, 0.70), Vector2(-0.82, 0.75), Vector2(0.10, 0.75), Vector2(0.75, 0.68), Vector2(1.36, 0.52), Vector2(1.80, 0.25), Vector2(2.01, 0.0)],
		"accents": [{"kind": "casemate_knuckle", "x": -0.28, "y": 0.56, "len": 0.64, "wid": 0.16, "h": 12.8}, {"kind": "river_ram_plate", "x": 1.54, "y": 0.0, "len": 0.28, "wid": 0.48, "h": 11.5}],
		"cargo": [{"kind": "slag_ballast_bin", "x": -1.28, "y": 0.36, "len": 0.26, "wid": 0.22, "h": 12.2}, {"kind": "shell_hoist", "x": -1.28, "y": -0.36, "len": 0.26, "wid": 0.22, "h": 12.2}]},
	"bellows_gunboat": {"name": "Bellows Siege Gunboat", "faction": "forge", "role": "gunboat", "tier": 3, "size": 26.0, "bridgeStyle": "siege_citadel", "bridge": {"x": -0.31, "len": 0.74, "wid": 0.58, "h": 22.0, "glass": false, "visor": "twin_slit_cupola"},
		"stations": [Vector2(-1.96, 0.62), Vector2(-1.68, 0.74), Vector2(-0.90, 0.78), Vector2(0.18, 0.78), Vector2(0.84, 0.72), Vector2(1.46, 0.55), Vector2(1.88, 0.26), Vector2(2.08, 0.0)],
		"accents": [{"kind": "bellows_manifold", "x": -0.30, "y": 0.58, "len": 0.68, "wid": 0.16, "h": 13.2}, {"kind": "siege_glacis", "x": 1.58, "y": 0.0, "len": 0.30, "wid": 0.52, "h": 12.0}],
		"cargo": [{"kind": "siege_powder_safe", "x": -1.29, "y": -0.38, "len": 0.28, "wid": 0.22, "h": 12.6}, {"kind": "siege_powder_safe", "x": -1.29, "y": 0.38, "len": 0.28, "wid": 0.22, "h": 12.6}]},
	"furnace_turret": {"name": "Furnace Sovereign Monitor", "faction": "forge", "role": "gunboat", "tier": 4, "size": 30.0, "bridgeStyle": "bastion_cupola", "bridge": {"x": -0.31, "len": 0.75, "wid": 0.59, "h": 23.2, "glass": false, "visor": "forged_barbette"},
		"stations": [Vector2(-2.06, 0.66), Vector2(-1.76, 0.79), Vector2(-0.95, 0.85), Vector2(0.20, 0.85), Vector2(0.92, 0.78), Vector2(1.54, 0.60), Vector2(1.94, 0.28), Vector2(2.16, 0.0)],
		"accents": [{"kind": "torpedo_blister", "x": -0.28, "y": 0.64, "len": 0.76, "wid": 0.18, "h": 12.4}, {"kind": "steam_ejector_bank", "x": 1.62, "y": 0.0, "len": 0.32, "wid": 0.56, "h": 12.4}],
		"cargo": [{"kind": "heavy_shell_pallet", "x": -1.30, "y": -0.42, "len": 0.30, "wid": 0.24, "h": 13.0}, {"kind": "heavy_shell_pallet", "x": -1.30, "y": 0.42, "len": 0.30, "wid": 0.24, "h": 13.0}]},
	"barbed_lance": {"name": "Sparkrack Rocket Scow", "faction": "raiders", "role": "rocket", "tier": 2, "size": 20.0, "bridgeStyle": "scow_blast_cab", "bridge": {"x": -0.31, "len": 0.72, "wid": 0.56, "h": 19.8, "glass": true, "visor": "blast_shutters"},
		"stations": [Vector2(-1.86, 0.66), Vector2(-1.58, 0.78), Vector2(-0.80, 0.80), Vector2(0.20, 0.80), Vector2(0.88, 0.76), Vector2(1.50, 0.62), Vector2(1.84, 0.34), Vector2(2.00, 0.0)],
		"accents": [{"kind": "blast_deflector", "x": 1.52, "y": 0.0, "len": 0.26, "wid": 0.64, "h": 11.4}, {"kind": "scow_bumper", "x": -0.28, "y": 0.60, "len": 0.62, "wid": 0.16, "h": 11.2}],
		"cargo": [{"kind": "rocket_crate", "x": -1.26, "y": -0.40, "len": 0.28, "wid": 0.22, "h": 12.2}, {"kind": "igniter_casks", "x": -1.26, "y": 0.40, "len": 0.26, "wid": 0.22, "h": 12.2}]},
	"cinder_monitor": {"name": "Pyreclast Rocket Monitor", "faction": "forge", "role": "rocket", "tier": 3, "size": 25.0, "bridgeStyle": "pyre_bunker", "bridge": {"x": -0.31, "len": 0.74, "wid": 0.58, "h": 20.8, "glass": false, "visor": "thermite_hood"},
		"stations": [Vector2(-1.95, 0.62), Vector2(-1.66, 0.76), Vector2(-0.78, 0.86), Vector2(0.25, 0.88), Vector2(0.90, 0.80), Vector2(1.48, 0.58), Vector2(1.88, 0.26), Vector2(2.06, 0.0)],
		"accents": [{"kind": "sponson_box", "x": -0.25, "y": 0.64, "len": 0.70, "wid": 0.20, "h": 12.0}, {"kind": "flame_apron", "x": 1.56, "y": 0.0, "len": 0.28, "wid": 0.56, "h": 11.6}],
		"cargo": [{"kind": "thermite_cassette", "x": -1.28, "y": -0.40, "len": 0.28, "wid": 0.24, "h": 12.6}, {"kind": "thermite_cassette", "x": -1.28, "y": 0.40, "len": 0.28, "wid": 0.24, "h": 12.6}]},
	"wraith_rocket": {"name": "Hellbore Salvo Cruiser", "faction": "raiders", "role": "rocket", "tier": 4, "size": 29.0, "bridgeStyle": "hellbore_fire_tower", "bridge": {"x": -0.31, "len": 0.75, "wid": 0.59, "h": 22.2, "glass": true, "visor": "salvo_director"},
		"stations": [Vector2(-2.04, 0.58), Vector2(-1.74, 0.72), Vector2(-0.88, 0.82), Vector2(0.20, 0.84), Vector2(0.94, 0.74), Vector2(1.56, 0.52), Vector2(1.96, 0.22), Vector2(2.18, 0.0)],
		"accents": [{"kind": "salvo_outrigger", "x": -0.28, "y": 0.62, "len": 0.72, "wid": 0.18, "h": 12.4}, {"kind": "hellbore_prow", "x": 1.62, "y": 0.0, "len": 0.34, "wid": 0.48, "h": 11.8}],
		"cargo": [{"kind": "salvo_magazine", "x": -1.30, "y": -0.38, "len": 0.30, "wid": 0.24, "h": 13.0}, {"kind": "salvo_magazine", "x": -1.30, "y": 0.38, "len": 0.30, "wid": 0.24, "h": 13.0}]},
	"cobalt_frigate": {"name": "Cobalt Commodore Frigate", "faction": "compact", "role": "cruiser", "tier": 2, "size": 24.0, "bridgeStyle": "commodore_tower", "bridge": {"x": -0.31, "len": 0.74, "wid": 0.57, "h": 24.2, "glass": true, "visor": "stepped_flag_bridge"},
		"stations": [Vector2(-1.96, 0.48), Vector2(-1.68, 0.60), Vector2(-0.88, 0.66), Vector2(0.12, 0.66), Vector2(0.82, 0.61), Vector2(1.48, 0.45), Vector2(1.94, 0.18), Vector2(2.18, 0.0)],
		"accents": [{"kind": "signal_wings", "x": -0.28, "y": 0.46, "len": 0.34, "wid": 0.16, "h": 18.0}, {"kind": "commodore_crest", "x": 1.60, "y": 0.0, "len": 0.30, "wid": 0.38, "h": 12.0}],
		"cargo": [{"kind": "brigade_pump_unit", "x": -1.28, "y": -0.30, "len": 0.26, "wid": 0.20, "h": 12.4}, {"kind": "turbine_spares", "x": -1.28, "y": 0.30, "len": 0.26, "wid": 0.20, "h": 12.4}]},
	"iron_bastion": {"name": "Bastion Armored Cruiser", "faction": "compact", "role": "cruiser", "tier": 3, "size": 31.0, "bridgeStyle": "flagship_citadel", "bridge": {"x": -0.31, "len": 0.75, "wid": 0.59, "h": 25.8, "glass": true, "visor": "armored_admiral_walk"},
		"stations": [Vector2(-2.04, 0.54), Vector2(-1.76, 0.67), Vector2(-0.92, 0.73), Vector2(0.16, 0.73), Vector2(0.90, 0.67), Vector2(1.56, 0.50), Vector2(2.02, 0.21), Vector2(2.24, 0.0)],
		"accents": [{"kind": "flagship_belt", "x": -0.28, "y": 0.54, "len": 0.74, "wid": 0.16, "h": 13.5}, {"kind": "ram_spur_crest", "x": 1.66, "y": 0.0, "len": 0.34, "wid": 0.44, "h": 12.5}],
		"cargo": [{"kind": "armored_ammunition_hoist", "x": -1.30, "y": -0.34, "len": 0.28, "wid": 0.22, "h": 13.0}, {"kind": "armored_ammunition_hoist", "x": -1.30, "y": 0.34, "len": 0.28, "wid": 0.22, "h": 13.0}]},
	"maiden_dreadnought": {"name": "Shatter Throne Dreadnought", "faction": "forge", "role": "cruiser", "tier": 4, "size": 36.0, "bridgeStyle": "throne_pagoda", "bridge": {"x": -0.31, "len": 0.76, "wid": 0.60, "h": 27.6, "glass": true, "visor": "triple_command_pagoda"},
		"stations": [Vector2(-2.10, 0.62), Vector2(-1.82, 0.75), Vector2(-0.98, 0.81), Vector2(0.22, 0.81), Vector2(0.98, 0.74), Vector2(1.64, 0.56), Vector2(2.08, 0.25), Vector2(2.30, 0.0)],
		"accents": [{"kind": "forged_triple_belt", "x": -0.28, "y": 0.60, "len": 0.82, "wid": 0.18, "h": 14.2}, {"kind": "throne_forecastle", "x": 1.68, "y": 0.0, "len": 0.38, "wid": 0.50, "h": 13.0}],
		"cargo": [{"kind": "bilge_manifold_bank", "x": -1.32, "y": -0.38, "len": 0.30, "wid": 0.24, "h": 13.4}, {"kind": "siege_magazine_cap", "x": -1.32, "y": 0.38, "len": 0.30, "wid": 0.24, "h": 13.4}]},
	"kelpnet_dory": {"name": "Kelpnet Dory", "faction": "reed", "role": "skiff", "tier": 1, "size": 13.0, "bridgeStyle": "open_windscreen", "bridge": {"x": -0.30, "len": 0.68, "wid": 0.48, "h": 16.5, "glass": false},
		"stations": [Vector2(-2.06, 0.56), Vector2(-1.78, 0.60), Vector2(-1.0, 0.59), Vector2(0.0, 0.56), Vector2(0.70, 0.52), Vector2(1.40, 0.38), Vector2(1.92, 0.15), Vector2(2.08, 0.0)],
		"accents": [{"kind": "net_reel", "x": -1.65, "y": -0.32, "len": 0.24, "wid": 0.17, "h": 13.0}],
		"cargo": [{"kind": "salvage_drum", "x": -1.05, "y": 0.38, "len": 0.24, "wid": 0.16, "h": 12.3}, {"kind": "rope_coil", "x": 1.50, "y": 0.0, "len": 0.28, "wid": 0.24, "h": 10.0}]},
	"brinehook_longliner": {"name": "Brinehook Longliner", "faction": "compact", "role": "skiff", "tier": 2, "size": 15.0, "bridgeStyle": "customs_canopy", "bridge": {"x": -0.30, "len": 0.71, "wid": 0.51, "h": 18.5, "glass": true},
		"stations": [Vector2(-2.32, 0.50), Vector2(-2.0, 0.59), Vector2(-1.15, 0.62), Vector2(-0.10, 0.58), Vector2(0.66, 0.54), Vector2(1.42, 0.36), Vector2(1.98, 0.14), Vector2(2.18, 0.0)],
		"accents": [{"kind": "stern_davit", "x": -1.85, "y": -0.30, "len": 0.42, "wid": 0.14, "h": 20.0}],
		"cargo": [{"kind": "line_drum", "x": -1.25, "y": -0.40, "len": 0.22, "wid": 0.16, "h": 13.0}, {"kind": "line_drum", "x": -1.25, "y": 0.40, "len": 0.22, "wid": 0.16, "h": 13.0}]},
	"mother_gull_trawler": {"name": "Mother Gull Trawler", "faction": "reed", "role": "raider", "tier": 2, "size": 19.0, "bridgeStyle": "estuary_span", "bridge": {"x": -0.28, "len": 0.73, "wid": 0.58, "h": 20.0, "glass": true},
		"stations": [Vector2(-2.20, 0.25), Vector2(-1.80, 0.30), Vector2(-0.80, 0.32), Vector2(0.20, 0.32), Vector2(1.10, 0.27), Vector2(1.70, 0.20), Vector2(2.12, 0.06), Vector2(2.28, 0.0)],
		"accents": [{"kind": "cross_beam", "x": 0.56, "y": 0.0, "len": 0.16, "wid": 0.95, "h": 11.4}, {"kind": "trawl_reel", "x": -1.48, "y": -0.48, "len": 0.34, "wid": 0.24, "h": 15.0}, {"kind": "trawl_reel", "x": -1.48, "y": 0.48, "len": 0.34, "wid": 0.24, "h": 15.0}],
		"cargo": [{"kind": "net_tarp_stack", "x": 0.0, "y": -0.48, "len": 0.26, "wid": 0.18, "h": 12.4}, {"kind": "net_tarp_stack", "x": 0.0, "y": 0.48, "len": 0.26, "wid": 0.18, "h": 12.4}]},
	"fenhopper_lighter": {"name": "Fenhopper Lighter", "faction": "reed", "role": "raider", "tier": 1, "size": 17.0, "bridgeStyle": "estuary_span", "bridge": {"x": -0.28, "len": 0.71, "wid": 0.56, "h": 18.4, "glass": true},
		"stations": [Vector2(-2.20, 0.31), Vector2(-1.85, 0.32), Vector2(-0.85, 0.33), Vector2(0.35, 0.33), Vector2(1.20, 0.30), Vector2(1.72, 0.24), Vector2(2.05, 0.13), Vector2(2.18, 0.0)],
		"accents": [{"kind": "cross_beam", "x": 0.25, "y": 0.0, "len": 0.16, "wid": 1.0, "h": 11.0}],
		"cargo": [{"kind": "bale_stack", "x": -1.48, "y": -0.48, "len": 0.38, "wid": 0.24, "h": 15.0}, {"kind": "bale_stack", "x": -1.48, "y": 0.48, "len": 0.38, "wid": 0.24, "h": 15.0}, {"kind": "cargo_hatch", "x": 1.10, "y": -0.63, "len": 0.34, "wid": 0.22, "h": 10.2}, {"kind": "cargo_hatch", "x": 1.10, "y": 0.63, "len": 0.34, "wid": 0.22, "h": 10.2}]},
	"tideledger_coaster": {"name": "Tideledger Coaster", "faction": "compact", "role": "raider", "tier": 2, "size": 21.0, "bridgeStyle": "estuary_span", "bridge": {"x": -0.28, "len": 0.73, "wid": 0.58, "h": 20.4, "glass": true},
		"stations": [Vector2(-2.38, 0.28), Vector2(-1.95, 0.32), Vector2(-0.85, 0.34), Vector2(0.35, 0.34), Vector2(1.22, 0.29), Vector2(1.86, 0.20), Vector2(2.28, 0.08), Vector2(2.45, 0.0)],
		"accents": [{"kind": "packet_prow_crest", "x": 1.82, "y": 0.62, "len": 0.32, "wid": 0.16, "h": 12.3}],
		"cargo": [{"kind": "bonded_strongbox", "x": -1.60, "y": -0.48, "len": 0.44, "wid": 0.24, "h": 15.0}, {"kind": "bonded_strongbox", "x": -1.60, "y": 0.48, "len": 0.44, "wid": 0.24, "h": 15.0}, {"kind": "cargo_hatch", "x": 1.08, "y": -0.63, "len": 0.42, "wid": 0.24, "h": 10.4}, {"kind": "cargo_hatch", "x": 1.08, "y": 0.63, "len": 0.42, "wid": 0.24, "h": 10.4}]},
	"fourport_packet": {"name": "Fourport Packet", "faction": "compact", "role": "raider", "tier": 3, "size": 24.0, "bridgeStyle": "packet_house", "bridge": {"x": -0.28, "len": 0.75, "wid": 0.59, "h": 22.0, "glass": true},
		"stations": [Vector2(-2.30, 0.30), Vector2(-1.92, 0.35), Vector2(-0.90, 0.36), Vector2(0.40, 0.35), Vector2(1.20, 0.29), Vector2(1.86, 0.18), Vector2(2.32, 0.06), Vector2(2.52, 0.0)],
		"accents": [{"kind": "cross_beam", "x": 0.25, "y": 0.0, "len": 0.14, "wid": 1.0, "h": 11.2}],
		"cargo": [{"kind": "packet_tarp_stack", "x": -1.65, "y": -0.50, "len": 0.46, "wid": 0.28, "h": 15.4}, {"kind": "bonded_strongbox", "x": -1.65, "y": 0.50, "len": 0.46, "wid": 0.28, "h": 14.0}, {"kind": "cargo_hatch", "x": 1.10, "y": -0.63, "len": 0.48, "wid": 0.28, "h": 10.6}, {"kind": "cargo_hatch", "x": 1.10, "y": 0.63, "len": 0.48, "wid": 0.28, "h": 10.6}]},
	"brasswind_motor_galleon": {"name": "Brasswind Motor-Galleon", "faction": "compact", "role": "raider", "tier": 3, "size": 28.0, "bridgeStyle": "packet_house", "bridge": {"x": -0.28, "len": 0.75, "wid": 0.59, "h": 23.0, "glass": true},
		"stations": [Vector2(-2.50, 0.36), Vector2(-2.06, 0.38), Vector2(-0.90, 0.38), Vector2(0.45, 0.38), Vector2(1.30, 0.33), Vector2(1.94, 0.23), Vector2(2.44, 0.09), Vector2(2.65, 0.0)],
		"accents": [{"kind": "merchant_mast", "x": -0.28, "y": -0.50, "len": 0.16, "wid": 0.13, "h": 36.0}, {"kind": "merchant_mast", "x": -0.28, "y": 0.50, "len": 0.16, "wid": 0.13, "h": 30.0}],
		"cargo": [{"kind": "bale_tarp_stack", "x": -1.92, "y": -0.60, "len": 0.50, "wid": 0.30, "h": 17.0}, {"kind": "bale_tarp_stack", "x": -1.92, "y": 0.60, "len": 0.50, "wid": 0.30, "h": 17.0}, {"kind": "cargo_hatch", "x": 1.18, "y": -0.63, "len": 0.52, "wid": 0.30, "h": 10.6}, {"kind": "cargo_hatch", "x": 1.18, "y": 0.63, "len": 0.52, "wid": 0.30, "h": 10.6}]},
	"seepoil_tanker": {"name": "Seepoil Tanker Barge", "faction": "forge", "role": "corvette", "tier": 2, "size": 20.0, "bridgeStyle": "turtleback_conning", "bridge": {"x": -0.31, "len": 0.73, "wid": 0.55, "h": 19.0, "glass": true},
		"stations": [Vector2(-2.16, 0.62), Vector2(-1.80, 0.72), Vector2(-0.80, 0.78), Vector2(0.25, 0.78), Vector2(1.18, 0.71), Vector2(1.78, 0.48), Vector2(2.12, 0.28), Vector2(2.30, 0.0)],
		"accents": [{"kind": "oil_manifold_bank", "x": -0.42, "y": -0.52, "len": 0.66, "wid": 0.18, "h": 13.0}, {"kind": "oil_manifold_bank", "x": -0.42, "y": 0.52, "len": 0.66, "wid": 0.18, "h": 13.0}],
		"cargo": [{"kind": "oil_cask", "x": -1.58, "y": -0.46, "len": 0.30, "wid": 0.20, "h": 14.4}, {"kind": "oil_cask", "x": -1.58, "y": 0.46, "len": 0.30, "wid": 0.20, "h": 14.4}, {"kind": "cargo_drum", "x": 1.56, "y": 0.0, "len": 0.42, "wid": 0.42, "h": 16.0}]},
	"blackwater_fleet_tanker": {"name": "Blackwater Fleet Tanker", "faction": "forge", "role": "corvette", "tier": 3, "size": 27.0, "bridgeStyle": "brass_wheelhouse", "bridge": {"x": -0.31, "len": 0.75, "wid": 0.56, "h": 22.0, "glass": true},
		"stations": [Vector2(-2.48, 0.63), Vector2(-2.08, 0.76), Vector2(-1.0, 0.83), Vector2(0.40, 0.83), Vector2(1.35, 0.74), Vector2(1.96, 0.48), Vector2(2.42, 0.22), Vector2(2.62, 0.0)],
		"accents": [{"kind": "oil_manifold_bank", "x": -0.42, "y": -0.55, "len": 0.80, "wid": 0.20, "h": 14.4}, {"kind": "oil_manifold_bank", "x": -0.42, "y": 0.55, "len": 0.80, "wid": 0.20, "h": 14.4}],
		"cargo": [{"kind": "oil_cask", "x": -1.65, "y": -0.50, "len": 0.40, "wid": 0.24, "h": 16.0}, {"kind": "oil_cask", "x": -1.65, "y": 0.50, "len": 0.40, "wid": 0.24, "h": 16.0}, {"kind": "cargo_drum", "x": 1.68, "y": 0.0, "len": 0.60, "wid": 0.58, "h": 18.0}]},
	"gullwing_daysailer": {"name": "Gullwing Daysailer", "faction": "reed", "role": "cutter", "tier": 1, "size": 14.0, "bridgeStyle": "stepped_cockpit", "bridge": {"x": -0.31, "len": 0.70, "wid": 0.48, "h": 17.8, "glass": true},
		"stations": [Vector2(-2.0, 0.48), Vector2(-1.70, 0.57), Vector2(-0.85, 0.58), Vector2(0.15, 0.59), Vector2(0.86, 0.54), Vector2(1.50, 0.34), Vector2(2.10, 0.07), Vector2(2.30, 0.0)],
		"accents": [{"kind": "trim_cells", "x": -1.15, "y": -0.40, "len": 0.24, "wid": 0.14, "h": 11.5}, {"kind": "trim_cells", "x": -1.15, "y": 0.40, "len": 0.24, "wid": 0.14, "h": 11.5}],
		"cargo": [{"kind": "rope_coil", "x": 1.52, "y": 0.0, "len": 0.24, "wid": 0.20, "h": 10.0}]},
	"osprey_cabin_cruiser": {"name": "Lacquered Osprey Cruiser", "faction": "compact", "role": "cutter", "tier": 2, "size": 17.0, "bridgeStyle": "interceptor_canopy", "bridge": {"x": -0.30, "len": 0.74, "wid": 0.51, "h": 21.0, "glass": true},
		"stations": [Vector2(-2.18, 0.54), Vector2(-1.82, 0.62), Vector2(-0.90, 0.65), Vector2(0.18, 0.67), Vector2(0.92, 0.59), Vector2(1.60, 0.36), Vector2(2.22, 0.10), Vector2(2.42, 0.0)],
		"accents": [{"kind": "signal_tube", "x": 1.52, "y": 0.0, "len": 0.24, "wid": 0.19, "h": 13.0}],
		"cargo": [{"kind": "cabin_locker", "x": 0.28, "y": -0.32, "len": 0.25, "wid": 0.20, "h": 12.6}, {"kind": "cabin_locker", "x": 0.28, "y": 0.32, "len": 0.25, "wid": 0.20, "h": 12.6}]},
	"aurelian_court_yacht": {"name": "Aurelian Viceroy Yacht", "faction": "compact", "role": "cruiser", "tier": 3, "size": 25.0, "bridgeStyle": "commodore_tower", "bridge": {"x": -0.31, "len": 0.75, "wid": 0.59, "h": 25.8, "glass": true},
		"stations": [Vector2(-2.34, 0.56), Vector2(-1.94, 0.68), Vector2(-0.95, 0.72), Vector2(0.20, 0.72), Vector2(0.96, 0.66), Vector2(1.64, 0.45), Vector2(2.34, 0.16), Vector2(2.58, 0.0)],
		"accents": [{"kind": "signal_wings", "x": -0.30, "y": -0.50, "len": 0.34, "wid": 0.15, "h": 20.0}, {"kind": "signal_wings", "x": -0.30, "y": 0.50, "len": 0.34, "wid": 0.15, "h": 20.0}],
		"cargo": [{"kind": "cabin_locker", "x": -1.30, "y": -0.43, "len": 0.26, "wid": 0.18, "h": 13.4}, {"kind": "cabin_locker", "x": -1.30, "y": 0.43, "len": 0.26, "wid": 0.18, "h": 13.4}, {"kind": "court_sun_deck", "x": 1.58, "y": 0.0, "len": 0.38, "wid": 0.36, "h": 11.4}]}
}

static func hull_ids() -> Array:
	return _HULL_ORDER.duplicate()

static func has_hull(id: String) -> bool:
	return _PROFILES.has(id)

static func profile(spec: Dictionary) -> Dictionary:
	var role: String=str(spec.get("role","corvette"))
	var hid: String=str(spec.get("id",""))
	if not _PROFILES.has(hid):hid=str(_ROLE_DEFAULT_ID.get(role,"harbor_sloop"))
	var entry: Dictionary=_PROFILES[hid]
	return {"hullId":hid,"archetype":_ROLE_ARCH.get(role,"patrol"),"stations":entry.stations.duplicate(),"bridgeStyle":entry.bridgeStyle,"bridge":entry.bridge.duplicate(true),"deckAccents":entry.accents.duplicate(true),"cargoDetails":entry.cargo.duplicate(true)}

static func stations(spec: Dictionary) -> Array:
	return profile(spec).stations

## Boat-to-boat waterline only: local spine ends and radius, in world units.
## Keep the existing size circle for terrain, weapons and unauthored test hulls.
static func contact_capsule090(spec: Dictionary) -> Vector3:
	var size: float=maxf(4.0,float(spec.get("size",16)))
	var radius: float=maxf(10.0,size)
	var id: String=str(spec.get("id",""))
	if not _PROFILES.has(id):return Vector3(0.0,0.0,radius)
	# Read the constant stations directly; profile() also copies decorative art.
	var hull_stations: Array=_PROFILES[id].stations
	var offset: float=CAT_OFFSET if str(spec.get("role",""))=="raider" else 0.0
	for station: Vector2 in hull_stations:
		radius=maxf(radius,(absf(station.y)+offset)*size)
	var stern: float=0.0
	var bow: float=0.0
	for station: Vector2 in hull_stations:
		var beam: float=(absf(station.y)+offset)*size
		var cap: float=sqrt(maxf(0.0,radius*radius-beam*beam))
		stern=minf(stern,station.x*size+cap)
		bow=maxf(bow,station.x*size-cap)
	# The capsule is convex and contains every station and the original circle.
	return Vector3(stern,bow,radius)

## Shared portrait/gallery framing; keep the original24 hulls' scale unchanged.
static func preview_span(spec: Dictionary) -> float:
	var hull_size: float = float(spec.get("size",16))
	var span: float = maxf(20.0,hull_size*4.6)
	if str(spec.get("civilianRole","")) not in ["fishing","transport","tanker","yacht"]:return span
	var extent: float = 0.0
	for station in stations(spec):extent=maxf(extent,absf(station.x))
	# Symmetric framing includes the longest profile end plus aft drive/propeller.
	return maxf(span,2.0*(extent+0.60)*hull_size)
