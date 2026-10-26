extends RefCounted
## Physical convoy objectives. Waiting and destroying escorts never count as passage.
const Routes=preload("res://scripts/tactical_routes.gd")
const Tactical=preload("res://scripts/tactical_runtime.gd")
const Deployment=preload("res://scripts/deployment.gd")
const Damage=preload("res://scripts/damage.gd")

static func is_convoy(st: Dictionary) -> bool:
	return str(st.get("mission",{}).get("kind","")) in ["escort","intercept"]

static func carrier_uids(mission: Dictionary) -> Array:
	var out: Array=[]
	for uid in mission.get("carrierUids",mission.get("allyUids",[])):
		if not str(uid).is_empty() and not str(uid) in out:out.append(str(uid))
	return out

static func deployment_error(fleet: Array,enemies: Array,mission: Dictionary) -> String:
	if not is_convoy({"mission":mission}):return ""
	var uids: Array=carrier_uids(mission)
	if uids.is_empty():return "A convoy needs at least one assigned physical carrier."
	var team: String=str(mission.get("carrierTeam","player" if mission.kind=="escort" else "enemy"))
	if not team in ["player","enemy"]:return "Unknown convoy side."
	var deployed: Array=Deployment.split(fleet if team=="player" else enemies).deployed
	for uid in uids:
		if not deployed.any(func(b):return str(b.get("uid",""))==uid and not b.get("sunk",false) and float(b.get("crew",0))>=float(b.get("crewMin",1))):
			return "Every assigned convoy carrier must be crewed and fit within its side's 300 deployment points."
	if not Deployment.split(fleet).deployed.any(func(b):return not str(b.get("uid","")) in mission.get("allyUids",[]) and not (team=="player" and str(b.get("uid","")) in uids) and not b.get("sunk",false) and float(b.get("crew",0))>=float(b.get("crewMin",1))):
		return "At least one of your own crewed combat boats must deploy beside the convoy within 300 points."
	return ""

static func _budget() -> Dictionary:
	return {"clearanceTests":0,"clearanceLimit":4096,"exhaustions":0}

static func configure(st: Dictionary) -> void:
	if not is_convoy(st) or st.has("convoy"):return
	var mission: Dictionary=st.mission
	var kind: String=str(mission.kind)
	var exit: Dictionary=mission.get("exit",{"x":2180.0 if kind=="escort" else 120.0,"y":850.0,"radius":70.0}).duplicate(true)
	var actors: Dictionary={}
	var largest: float=10.0
	for uid in carrier_uids(mission):
		for ship in st.ships:
			if str(ship.get("uid",""))!=uid:continue
			actors[uid]=ship
			largest=maxf(largest,float(ship.spec.get("size",16)))
			break
	var radius: float=Damage.number(exit.get("radius"),70.0)
	var point: Vector2=Vector2(Damage.number(exit.get("x"),NAN),Damage.number(exit.get("y"),NAN))
	exit.radius=radius
	var valid: bool=radius>largest and radius<=180.0 and point.is_finite()
	if valid:valid=Routes.sweep(Routes.terrain(st),point,point,radius+largest,_budget())=="valid"
	st.convoy={"kind":kind,"carrierTeam":str(mission.get("carrierTeam","player" if kind=="escort" else "enemy")),"uids":carrier_uids(mission),"actors":actors,"followers":{},"exit":exit,"exitValid":valid,"cargo":mission.get("carrierCargo",{}).duplicate(true)}
	st.escapedShips=[]
	st.objectiveOnly=true
	if actors.size()!=st.convoy.uids.size() or actors.is_empty() or not valid:
		st.startError="The assigned convoy or its authored water-safe exit is unavailable."
		st.result="lost";st.objectiveSuccess=false
		return
	# Initial commands only. Later player commands and manual helm retain authority.
	var leader: Dictionary=actors[st.convoy.uids[0]]
	for ship in st.ships:
		if ship.get("sunk",false) or ship.get("captureSecured",false):continue
		if actors.has(str(ship.get("uid",""))):
			Tactical.accept_command(st,ship,"move",{"x":point.x,"y":point.y},true)
		elif str(ship.team)==str(st.convoy.carrierTeam):
			Tactical.accept_command(st,ship,"escort",{"shipId":str(leader.id)},true)
		else:
			Tactical.accept_command(st,ship,"attack",{"shipId":str(leader.id)},true)
		if not actors.has(str(ship.get("uid",""))):
			st.convoy.followers[str(ship.id)]={"order":str(ship.order),"revision":int(ship.orderRevision),"target":str(leader.id)}

static func retarget(st: Dictionary,input: Dictionary={}) -> void:
	if not st.has("convoy") or st.get("result")!=null:return
	var leader: Dictionary={}
	for uid in st.convoy.uids:
		var ship: Dictionary=st.convoy.actors.get(uid,{})
		if not ship.is_empty() and _fate(st,ship)=="afloat":leader=ship;break
	if leader.is_empty():return
	for ship in st.ships:
		var prior: Dictionary=st.convoy.get("followers",{}).get(str(ship.id),{})
		if prior.is_empty() or ship.get("sunk",false) or ship.get("captureSecured",false):continue
		var manual: bool=str(ship.id)==str(st.get("playerId","")) and (input.get("manual",false) or not st.get("autopilot",true) or str(st.tactical.get("manualId",""))==str(ship.id))
		if manual or int(ship.get("orderRevision",0))!=int(prior.revision) or str(ship.get("order",""))!=str(prior.order) or str(ship.get("orderTarget",{}).get("shipId",""))!=str(prior.target):continue
		var old_live: bool=st.ships.any(func(b):return str(b.id)==str(prior.target) and not b.get("sunk",false) and not b.get("captureSecured",false))
		if old_live:continue
		Tactical.accept_command(st,ship,str(prior.order),{"shipId":str(leader.id)},true)
		prior.revision=int(ship.orderRevision);prior.target=str(leader.id)

static func _fate(st: Dictionary,ship: Dictionary) -> String:
	if ship.get("sunk",false):return "sunk"
	if ship.get("captureSecured",false) or str(ship.get("team",""))!=str(st.convoy.carrierTeam):return "captured"
	if ship.get("battleEscaped",false):return "escaped"
	return "afloat" if st.get("result")==null else "stranded"

static func snapshot(st: Dictionary) -> Dictionary:
	if not is_convoy(st) or not st.has("convoy"):return {}
	var out: Dictionary={"kind":str(st.convoy.kind),"exit":st.convoy.exit.duplicate(true),"total":st.convoy.uids.size(),"afloat":0,"escaped":0,"sunk":0,"captured":0,"stranded":0,"success":bool(st.get("objectiveSuccess",false)),"partial":false,"carriers":[]}
	for uid in st.convoy.uids:
		var ship: Dictionary=st.convoy.actors.get(uid,{})
		var fate: String="stranded" if ship.is_empty() else _fate(st,ship)
		out[fate]=int(out.get(fate,0))+1
		out.carriers.append({"uid":uid,"name":str(ship.get("name",uid)),"fate":fate,"cargoAboard":st.convoy.cargo.get(uid,{}).duplicate(true),"crewAlive":Damage.number(ship.get("crew")),"crewWounded":Damage.number(ship.get("wounded")),"hp":Damage.number(ship.get("hp")),"sourceWreckId":""})
	out.partial=(int(out.escaped)>0 and int(out.escaped)<int(out.total)) if out.kind=="escort" else (int(out.sunk)+int(out.captured)>0 and int(out.sunk)+int(out.captured)<int(out.total))
	out.label=label(st)
	return out

static func update(st: Dictionary) -> void:
	if not is_convoy(st) or st.get("result")!=null:return
	configure(st)
	if st.get("result")!=null:return
	var geometry: Dictionary=Routes.terrain(st)
	var exit: Dictionary=st.convoy.exit
	for uid in st.convoy.uids:
		var ship: Dictionary=st.convoy.actors.get(uid,{})
		if ship.is_empty() or _fate(st,ship)!="afloat":continue
		var r: float=maxf(10.0,float(ship.spec.get("size",16)))
		var point: Vector2=Vector2(ship.x,ship.y)
		if point.distance_to(Vector2(exit.x,exit.y))+r>float(exit.radius):continue
		if Routes.sweep(geometry,point,point,r,_budget())!="valid":continue
		ship.battleEscaped=true
		# Preserve the live owner object, outside the arena's target/movement lists.
		st.escapedShips.append(ship)
		st.ships.erase(ship)
		st.tactical.ships.erase(str(ship.id));st.tactical.observed.erase(str(ship.id))
	retarget(st)
	var outcome: Dictionary=snapshot(st)
	st.mission.status="%d escaped / %d sunk / %d captured"%[outcome.escaped,outcome.sunk,outcome.captured]
	if int(outcome.afloat)>0:return
	st.objectiveSuccess=int(outcome.escaped)==int(outcome.total) if outcome.kind=="escort" else int(outcome.sunk)+int(outcome.captured)==int(outcome.total)
	st.result="won" if st.objectiveSuccess else "lost"
	st.convoyOutcome=snapshot(st)

static func label(st: Dictionary) -> String:
	if not is_convoy(st):return "Defeat the opposing fleet; withdraw when the cost is too high."
	if not st.has("convoy"):return "Get every loaded boat to the authored exit."
	var escaped: int=0
	for ship in st.convoy.actors.values():
		if _fate(st,ship)=="escaped":escaped+=1
	var goal: String="Escort loaded boats to Exit" if st.convoy.kind=="escort" else "Stop loaded boats before Exit"
	var port_name: String=str(st.convoy.exit.get("portName",st.convoy.exit.get("portId","")))
	return "%s%s · %d/%d escaped"%[goal,", then continue to "+port_name if not port_name.is_empty() else "",escaped,st.convoy.uids.size()]
