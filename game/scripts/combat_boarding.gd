extends RefCounted
const Boarding=preload("res://scripts/boarding.gd")
const Events=preload("res://scripts/combat_events.gd")
const Tactical=preload("res://scripts/tactical_runtime.gd")

static func eligible(st: Dictionary,source: Dictionary,automatic: bool=false) -> bool:
	if source.get("sunk",false) or source.get("captureSecured",false) or source.get("supportOnly",false):return false
	var manual: bool=str(source.id)==str(st.get("playerId","")) and (not st.get("autopilot",true) or str(st.get("tactical",{}).get("manualId",""))==str(source.id))
	if manual:return false
	if automatic:return str(source.get("order","engage"))=="engage"
	var plan: Dictionary=source.get("boardingOrder",{})
	return not plan.is_empty() and int(plan.get("orderRevision",-1))==int(source.get("orderRevision",0)) and (str(source.get("order",""))=="board" or (plan.get("automatic",false) and str(source.get("order",""))=="engage"))

static func order(st: Dictionary,source_id: String,target_id: String,count: int,automatic: bool=false) -> Dictionary:
	var committed: int=st.get("captured",[]).size()+st.get("boarding",{}).get("jobs",[]).filter(func(job):return job.status=="active").size()
	if committed>=int(st.get("captureSlots",64)):return {"ok":false,"message":"Recover existing saved prizes before attempting another capture."}
	var source: Dictionary={};var target: Dictionary={}
	for b in st.ships:
		if str(b.id)==source_id:source=b
		if str(b.id)==target_id:target=b
	if source.is_empty() or target.is_empty() or source.sunk or target.sunk or source.get("captureSecured",false) or target.get("captureSecured",false) or source.team!="player" or target.team!="enemy" or source.get("supportOnly",false):return {"ok":false,"message":"Choose your live boat and an enemy boat."}
	if automatic and not eligible(st,source,true):return {"ok":false,"message":"The current command takes priority over automatic boarding."}
	if not Boarding._vulnerable(target):return {"ok":false,"message":"Disable the engine or weaken the hull before boarding."}
	if count<1 or count>int(source.get("boarders",0))-ceili(float(source.wounded)) or float(source.crew)-float(source.wounded)-count<float(source.crewMin):return {"ok":false,"message":"Keep the minimum working crew aboard; train and hire additional boarders."}
	if not automatic:Tactical.accept_command(st,source,"board",{"shipId":target_id})
	source.boardingOrder={"target":target_id,"count":count,"orderRevision":int(source.get("orderRevision",0)),"automatic":automatic}
	return {"ok":true,"message":"Approaching the disabled target. The party boards only on physical contact."}
static func tick(st: Dictionary,dt: float) -> void:
	for source in st.ships:
		if source.sunk or source.get("captureSecured",false):continue
		# A cautious doctrine can act on a nearby weak target; numerical crew only.
		if not source.get("boardingOrder") is Dictionary and st.get("autoBoard",true) and source.team=="player" and int(source.get("boarders",0))>=2 and eligible(st,source,true):
			for target in st.ships:
				if target.sunk or target.team!="enemy" or not Boarding._vulnerable(target):continue
				if Vector2(source.x-target.x,source.y-target.y).length()>650:continue
				var count: int=mini(int(source.get("boarders",0))-ceili(float(source.wounded)),floori(float(source.crew)-float(source.wounded)-float(source.crewMin)))
				if count>=2 and float(target.crew-target.wounded)<=count*0.5:order(st,str(source.id),str(target.id),count,true);break
		var plan: Dictionary=source.get("boardingOrder",{})
		if plan.is_empty():continue
		# Suspension/cancellation touches only an unlaunched plan; launched jobs
		# below keep their real people, timers, casualties and existing recall API.
		if not eligible(st,source):
			if int(plan.get("orderRevision",-1))!=int(source.get("orderRevision",0)) or str(source.get("order","")) not in ["board","engage"]:source.erase("boardingOrder")
			continue
		var target: Dictionary={}
		for b in st.ships:
			if str(b.id)==str(plan.target):target=b;break
		if target.is_empty() or target.sunk or target.team!="enemy":source.erase("boardingOrder");continue
		if Boarding._near(source,target):
			var result: Dictionary=Boarding.launch(st,str(source.id),str(target.id),int(plan.count))
			source.erase("boardingOrder")
			if not result.ok:st.log.push_front("Boarding cancelled: "+str(result.get("reason","conditions changed")));st.log.resize(mini(30,st.log.size()))
	Boarding.tick(st,dt)
	for source in st.ships:
		source.boarders=mini(int(source.get("boarders",0)),floori(float(source.crew)))
		if source.get("captureSecured",false):source.vx=0.0;source.vy=0.0
	for fort in st.get("coastalDefenses",[]):
		fort.cooldown=maxf(0,float(fort.cooldown)-dt)
		if fort.cooldown>0 or not fort.port.get("defenses",{}).get("active",false) or st.projectiles.size()>=400:continue
		var origin=Vector2(fort.x,fort.y);var target: Dictionary={}
		var reach: float=600.0 if fort.port.defenses.kind=="battery" else 180.0
		for b in st.ships:
			if b.sunk or b.team==fort.team or b.get("captureSecured",false):continue
			if origin.distance_to(Vector2(b.x,b.y))<=reach:target=b;break
		if target.is_empty():continue
		var shot: Dictionary=Boarding.take_defense_shot(fort.port)
		if not shot.ok:continue
		fort.cooldown=float(shot.cooldown)
		var angle: float=(Vector2(target.x,target.y)-origin).angle()
		var v: Vector2=Vector2.from_angle(angle)*float(shot.speed)
		st.projectiles.append({"x":origin.x,"y":origin.y,"px":origin.x,"py":origin.y,"vx":v.x,"vy":v.y,"team":fort.team,"damage":shot.damage,"kind":"shell","family":"cannon","variant":"light","life":shot.range/shot.speed,"age":0.0,"owner":"shore:"+str(fort.port.id),"sourceUid":"shore:"+str(fort.port.id),"sourceHull":"coastal_battery","mountId":"shore","mountIndex":0,"angle":angle,"radius":2.0,"penetration":4.0,"blastRadius":0.0,"incendiary":false,"height":12.0,"trail":"tracer"})
		var visual: Dictionary={"id":"shore:"+str(fort.port.id),"type":"coastal_battery","team":fort.team,"spec":{"id":"coastal_battery","material":"iron"}}
		Events.emit_fire(st,visual,{"id":"shore","kind":"cannon","damage":shot.damage,"barrelHeight":12.0},0,origin,angle,target)
static func approach(st: Dictionary,source: Dictionary,dt: float) -> Dictionary:
	if not eligible(st,source):return {}
	var plan: Dictionary=source.get("boardingOrder",{})
	if plan.is_empty():return {}
	for target in st.ships:
		if str(target.id)==str(plan.target) and not target.sunk and target.team!=source.team:
			var delta=Vector2(target.x-source.x,target.y-source.y)
			return {"angle":delta.angle(),"throttle":0.85 if delta.length()>90+float(source.spec.size) else 0.0}
	return {}
