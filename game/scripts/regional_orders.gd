extends RefCounted
## A regional watch is an order for an existing paid company, never a spawned fleet.
const Factions=preload("res://scripts/factions.gd")

static func operation(s: Dictionary,owner: Dictionary) -> Dictionary:
	var op: Dictionary=s.get("regionalCampaigns",{}).get("operations",{}).get("corridor",{})
	return op if op.get("status","")=="active" and op.get("ownerId","")==owner.get("id","") and op.get("ends",[]).size()==2 else {}

static func arrival(s: Dictionary,owner: Dictionary,p: Dictionary) -> void:
	var op: Dictionary=operation(s,owner)
	if op.is_empty() or not str(p.get("id","")) in op.ends:return
	if str(p.id)!=str(op.get("patrolLastPort","")):
		op.patrolVisits=int(op.get("patrolVisits",0))+1
		op.patrolLastPort=str(p.id)

static func plan(s: Dictionary,owner: Dictionary,current: String) -> Dictionary:
	var op: Dictionary=operation(s,owner)
	if op.is_empty() or owner.get("kind","")!="patrol":return {}
	var dest: String=str(op.ends[1]) if current==str(op.ends[0]) else str(op.ends[0])
	var ports: Array=s.get("ports",[])
	for p in ports:
		if str(p.id)==dest and str(p.faction)!=str(owner.get("faction","")) and Factions.relation(s,str(p.faction),str(owner.get("faction","")))<=Factions.ENEMY_AT:return {}
	return {"purpose":"patrol","destination":dest,"targetOwnerId":"","reason":"Regional corridor watch: %s. Two real endpoint visits and seven clear days are recorded; repairs and resupply take priority."%str(op.completionId)}
