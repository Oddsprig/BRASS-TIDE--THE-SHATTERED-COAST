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
	var until: float=float(c.state.relationships.safeConduct.get(p.get("id",""),0))
	a.safeConductActive=not p.is_empty() and until>float(c.state.day)
	a.safeConductUntil=until
	a.safeConductDays=maxf(0.0,until-float(c.state.day))
	a.standingReason=_standing_reason(Factions.standing(c.state,str(a.factionId)))
	if a.safeConductActive:
		a.entry="inspected";a.legal=true;a.inspection=true;a.contracts=true
		# Explain the effective permission, not the superseded standing refusal.
		a.reason="Paid civilian safe conduct permits inspected entry, trade and negotiated work at %s until day %.2f (%.2f days remaining). Customs still apply."%[str(a.portName),until,float(a.safeConductDays)]
		if not a.militaryFittings:a.reason+=" Advanced military fittings and bulk guns/engines remain restricted."
		if int(a.claim)>0:a.reason+=" The outstanding harbor claim of %d still blocks repairs until settled."%int(a.claim)
		a.reason+=" "+str(a.standingReason)+" This local harbor pass grants no protection from hostile fleets at sea."
	elif until>0.0:
		a.reason+=" Paid civilian safe conduct expired on day %.2f; current standing and claims now determine entry."%until
	return a

static func _standing_reason(view: Dictionary) -> String:
	if not bool(view.get("known",false)):return "No public standing is recorded for these colors."
	var text: String="Public standing with %s is %s (%+d); witnessed record %+d."%[str(view.name),str(view.band),int(view.score),int(view.witnessed)]
	var causes: PackedStringArray=[]
	if str(view.band)=="hostile":causes.append("hostile public standing")
	if int(view.witnessed)<=Factions.WITNESS_HOSTILE:causes.append("an unresolved witnessed offense")
	if not causes.is_empty():text+=" Its fleets remain hostile because of %s."%" and ".join(causes)
	else:text+=" Its fleets are not currently hostile to you."
	return text

static func encounter(state: Dictionary,owner: Dictionary) -> Dictionary:
	# Public identity only. The caller still owns the local observation boundary.
	var kind: String=str(owner.get("kind",""))
	var role: String="fleet"
	match kind:
		"trader":role="merchant convoy"
		"patrol":role="faction patrol"
		"raider":role="raiding fleet"
	var faction_id: String=str(owner.get("faction",""))
	var standing: Dictionary=Factions.standing(state,faction_id)
	return {"kind":kind,"role":role,"factionId":faction_id,"factionName":str(standing.name) if standing.known else "Unidentified colors","hostile":not owner.is_empty() and bool(standing.hostile),"reason":_standing_reason(standing)}

static func permit(c,action: String,item: String="",port_override: Dictionary={}) -> Dictionary:
	var p: Dictionary=port_override if not port_override.is_empty() else c.current_port()
	if p.is_empty() or not c.state.path.is_empty():return c.fail("Stop at a harbor for this service.")
	var a: Dictionary=access(c,p)
	if not a.legal:return c.fail(a.reason+" Open Factions to negotiate safe conduct.")
	if action=="military" and not a.militaryFittings:return c.fail("Advanced military fittings require friendly standing, no hostile witnessed offense and no outstanding harbor claim. Civilian services retain their own access and claim checks.")
	if action=="buy_good" and item in a.restrictedGoods:return c.fail("Bulk guns and engine assemblies require friendly standing, no hostile witnessed offense and no outstanding harbor claim here.")
	if action=="repair" and a.claim>0:return c.fail("Settle this harbor's outstanding claim before using its repair yard.")
	if action=="contract" and not a.contracts:return c.fail("This harbor has suspended your contracts.")
	return {"ok":true,"message":a.reason}

static func inspect(c) -> Dictionary:
	var p: Dictionary=c.current_port()
	var a: Dictionary=access(c,p)
	if not a.legal:return c.fail(a.reason)
	if not a.inspection:return c.ok("Clear harbor access.")
	var customs: Script=load("res://scripts/law_ops.gd")
	return customs.inspect(c,p)

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

## Read-only. A committed commission names lawful enemies; it does not make a peaceful fleet hostile.
static func commission_enemy(c,owner: Dictionary) -> Dictionary:
	var result: Dictionary={"lawful":false,"patronId":"","enemies":[],"reason":"No letters of marque are committed."}
	if owner.is_empty():result.reason="No fleet is identified.";return result
	var book: Dictionary=c.state.get("relationships",{}) if c.state.get("relationships") is Dictionary else {}
	var deal: Dictionary=book.get("commission",{}) if book.get("commission") is Dictionary else {}
	if not deal.get("committed",false):return result
	var patron: String=str(deal.get("factionId",""))
	var contract: Dictionary=deal.get("contract",{}) if deal.get("contract") is Dictionary else {}
	var enemies: Array=contract.get("enemies",[]) if contract.get("enemies") is Array else []
	result.patronId=patron
	result.enemies=enemies.duplicate()
	var faction: String=str(owner.get("faction",""))
	if not enemies.has(faction):result.reason="The committed letters do not name %s."%faction;return result
	if not hostile(c,owner):result.reason="Letters do not make a peaceful fleet a lawful target.";return result
	result.lawful=true
	result.reason="Letters of marque from %s name this hostile %s fleet."%[patron,faction]
	return result

static func settled(c,owner: Dictionary,result: String,context: Dictionary) -> void:
	if owner.is_empty():return
	var id: String=str(owner.faction)
	var eid: String="battle:%s:%d"%[owner.id,c.state.wins+c.state.losses]
	var letters: Dictionary=commission_enemy(c,owner)
	if context.get("aggression",false):
		Factions.adjust(c.state,id,-25,"witness:Confirmed losses in your attack",eid)
	elif result=="won" and id=="raiders":
		for legal in ["compact","forge","reed"]:
			var why: String="Defended coastal shipping"
			if letters.lawful and str(letters.patronId)==legal:why="Letters of marque for %s: defeated hostile %s."%[str(Factions.standing(c.state,legal).name),str(owner.get("name",id))]
			Factions.adjust(c.state,legal,2,why,eid+":"+legal)

static func hostile(c,owner: Dictionary) -> bool:
	return not owner.is_empty() and Factions.is_hostile(c.state,str(owner.faction))
