extends RefCounted
## Real campaign permissions and consequences. Personal contact trust stays in contacts.gd.
const Factions=preload("res://scripts/factions.gd")
const Money=preload("res://scripts/money.gd")

static func ensure(c) -> void:
	Factions.ensure(c.state,c.data)
	var b: Dictionary=c.state.relationships
	if not b.get("safeConduct") is Dictionary:b.safeConduct={}
	if not b.get("inspections") is Dictionary:b.inspections={}

static func access(c,p: Dictionary) -> Dictionary:
	ensure(c)
	var a: Dictionary=Factions.access(c.state,p)
	if not p.is_empty() and float(c.state.relationships.safeConduct.get(p.id,0))>float(c.state.day):
		a.entry="inspected";a.legal=true;a.inspection=true;a.contracts=true
		a.reason+=" A paid three-day safe conduct permits inspected civilian trade and negotiated work. Military permissions remain closed."
	return a

static func permit(c,action: String,item: String="") -> Dictionary:
	var p: Dictionary=c.current_port()
	if p.is_empty() or not c.state.path.is_empty():return c.fail("Stop at a harbor for this service.")
	var a: Dictionary=access(c,p)
	if not a.legal:return c.fail(a.reason+" Open Factions to negotiate safe conduct.")
	if action=="military" and not a.militaryFittings:return c.fail("Friendly standing is required for advanced military fittings. Basic weapons, repairs and civilian engines remain available.")
	if action=="buy_good" and item in a.restrictedGoods:return c.fail("Bulk guns and engine assemblies require friendly standing here.")
	if action=="repair" and a.claim>0:return c.fail("Settle this harbor's outstanding claim before using its repair yard.")
	if action=="contract" and not a.contracts:return c.fail("This harbor has suspended your contracts.")
	return {"ok":true,"message":a.reason}

static func inspect(c) -> Dictionary:
	var p: Dictionary=c.current_port()
	var a: Dictionary=access(c,p)
	if not a.legal:return c.fail(a.reason)
	if not a.inspection:return c.ok("Clear harbor access.")
	var key: String="%s:%d"%[p.id,int(c.state.day)]
	if not c.state.relationships.inspections.has(key):
		c.state.relationships.inspections[key]=true
		while c.state.relationships.inspections.size()>80:c.state.relationships.inspections.erase(c.state.relationships.inspections.keys()[0])
		c.log_entry("%s inspected the manifest: %.1f tons of declared cargo; owned fittings and sealed cargo admitted. No confiscation or invented fee."%[p.name,c.cargo_weight()])
	return c.ok("Inspection complete. Declared cargo admitted.")

static func parley(c) -> Dictionary:
	var p: Dictionary=c.current_port()
	if p.is_empty() or not c.state.path.is_empty():return c.fail("Approach the harbor and stop to request parley.")
	var a: Dictionary=access(c,p)
	if float(c.state.relationships.safeConduct.get(p.id,0))>float(c.state.day):return c.fail("Your three-day pass is still valid; it cannot be stacked.")
	if not a.hostile and a.claim<=0 and a.witnessed>=0:return c.fail("You already have ordinary legal entry; no payment is needed.")
	# Five watch days, two clerk days, one expert day and 50 coins registration.
	var claim_fee: int=int(a.claim)*100
	var bill: int=1000+claim_fee
	if int(c.state.coins)<bill:return c.fail("Parley needs %d coins: 750 worker pay, 200 expert pay, 50 registration and %d claims."%[bill,claim_fee])
	Money.move(c.state,"coins",p,"householdPurse",750,"Safe conduct watch and clerk wages",c.state.moneyLog)
	Money.move(c.state,"coins",p,"expertPurse",200,"Safe conduct expert wages",c.state.moneyLog)
	Money.move(c.state,"coins",p,"governmentPurse",50+claim_fee,"Safe conduct registration and restitution",c.state.moneyLog)
	if a.claim>0:
		# Each paid claim point is cleared, without an unbounded free reputation change.
		c.state.relationships.factions[p.faction].claims.erase(p.id)
	var previous_score: int=int(Factions.standing(c.state,p.faction).score)
	Factions.adjust(c.state,p.faction,10,"restitution:%s:Paid parley and civil settlement"%p.id)
	var row: Dictionary=c.state.relationships.factions[p.faction]
	row.score=mini(int(row.score),maxi(0,previous_score))
	row.band=Factions._band_for(int(row.score),str(row.band))
	c.state.relationships.safeConduct[p.id]=float(c.state.day)+3.0
	c.log_entry("Paid %d coins for three-day safe conduct at %s. Further public standing must be earned through work."%[bill,p.name])
	return c.ok("Three-day civilian safe conduct granted; complete work to earn lasting access.")

static func job_completed(c,job: Dictionary) -> void:
	var p: Dictionary=c.port(str(job.get("port","")))
	if p.is_empty():return
	Factions.adjust(c.state,p.faction,12 if job.get("story",false) else 7,"Fulfilled %s"%job.get("title","voyage work"),"paid:"+str(job.get("id","")))
	var dest: Dictionary=c.port(str(job.get("targetPort","")))
	if not dest.is_empty() and dest.faction!=p.faction:
		Factions.adjust(c.state,dest.faction,3,"Delivered contracted assistance","received:"+str(job.get("id","")))

static func declare_attack(c,owner: Dictionary) -> void:
	if owner.is_empty():return
	var id: String=str(owner.faction)
	if Factions.is_hostile(c.state,id):return
	var eid: String="attack:%s:%d"%[owner.id,c.state.wins+c.state.losses]
	Factions.adjust(c.state,id,-25,"Attack on peaceful shipping",eid)
	Factions.adjust(c.state,id,-25,"witness:Your fleet opened fire on peaceful shipping",eid+":witness")
	var home: String=str(owner.homePort)
	Factions.adjust(c.state,id,-20,"claim:%s:Shipping damage claim"%home,eid+":claim")

static func settled(c,owner: Dictionary,result: String,context: Dictionary) -> void:
	if owner.is_empty():return
	var id: String=str(owner.faction)
	var eid: String="battle:%s:%d"%[owner.id,c.state.wins+c.state.losses]
	if context.get("aggression",false):
		Factions.adjust(c.state,id,-25,"witness:Confirmed losses in your attack",eid)
	elif result=="won" and id=="raiders":
		for legal in ["compact","forge","reed"]:Factions.adjust(c.state,legal,2,"Defended coastal shipping",eid+":"+legal)

static func hostile(c,owner: Dictionary) -> bool:
	return not owner.is_empty() and Factions.is_hostile(c.state,str(owner.faction))
