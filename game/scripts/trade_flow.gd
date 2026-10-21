extends RefCounted
const Intel=preload("res://scripts/trade_intel.gd")
## Existing authored blockade stations stay physical; ordinary NPCs use current positions.
static func blockades(c) -> Array:
	var blocked: Array=Intel.blockades(c)
	for pair in [["story-3","cinder_quay"],["story-7","shatter_spire"]]:
		var owner: Dictionary=c.fleet_owner(pair[0])
		if owner.is_empty() or not owner.get("active",false):continue
		if owner.boats.any(func(b):return not b.sunk and b.crew>=b.crewMin and b.fuel>=0.5 and b.ammo>=10):
			if not pair[1] in blocked:blocked.append(pair[1])
	return blocked

static func daily(c) -> void:
	for event in Intel.update(c):c.log_entry("%s blockade: %s."%[c.port(event.portId).name,event.cause])
	var blocked: Array=blockades(c)
	for p in c.state.ports:p.blockaded=p.id in blocked

static func observe(c) -> void:
	var p: Dictionary=c.current_port()
	if not p.is_empty() and c.Politics.access(c,p).legal:Intel.observe(c.state,p,c.state.day)
