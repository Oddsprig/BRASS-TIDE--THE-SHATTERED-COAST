extends RefCounted
## Pure weapon commitment shared by stock/refitted specs and mounting geometry.
## No campaign/catalogue mutation, timers, damage or equipment-condition rules.
const HEAVY_CANNON_RELOAD_SECONDS: float=1.8
const HEAVY_MAIN_CANNON_ARC: float=PI*0.75 # 135 degrees, +/-67.5 from the bow.

static func fire_rate(kind: String,weapon_size: int,rate: float) -> float:
	# A slower authored cannon stays slower. Never accelerate an existing weapon.
	return minf(rate,1.0/HEAVY_CANNON_RELOAD_SECONDS) if kind.to_lower()=="cannon" and weapon_size>=3 else rate

static func firing_arc(kind: String,socket_id: String,socket_size: int,arc: float) -> float:
	# This is the large forward socket's cannon traverse, including smaller
	# cannons fitted there. Guns, aft/side sockets and launchers retain their arcs.
	return minf(arc,HEAVY_MAIN_CANNON_ARC) if kind.to_lower()=="cannon" and socket_id=="mount0" and socket_size>=3 else arc

static func cannon_commitment_text() -> String:
	return "%.1f s base reload at full efficiency; %.0f-degree forward arc on a large main-deck socket."%[HEAVY_CANNON_RELOAD_SECONDS,rad_to_deg(HEAVY_MAIN_CANNON_ARC)]
