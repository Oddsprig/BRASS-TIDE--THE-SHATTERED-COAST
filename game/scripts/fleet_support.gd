extends RefCounted
const Identity=preload("res://scripts/fleet_identity.gd")
const Money=preload("res://scripts/money.gd")
const Economy=preload("res://scripts/economy.gd")
static func combat(c) -> Array:
	return c.active_fleet().filter(func(b):return not b.get("supportOnly",false))

static func aboard(c,uid: String) -> Array:
	return c.state.get("specialists",[]).filter(func(r):return r.boatUid==uid and not r.get("discharged",false) and not r.get("lost",false))

static func reserve(c,uid: String) -> Dictionary:
	var b: Dictionary=c.find_boat(uid)
	if b.is_empty():return c.fail("Unknown boat.")
	b.supportOnly=not b.get("supportOnly",false)
	return c.ok("Traveling support: stays outside battle deployment." if b.supportOnly else "Boat available for the next 300-point battle deployment.")

static func reconcile(c) -> void:
	Identity.ensure(c.state)
	for boat in c.state.fleet:
		var records: Array=aboard(c,boat.uid)
		var alive: int=0 if boat.sunk else maxi(0,floori(float(boat.crew)))
		for index in range(records.size()):
			if index<alive:continue
			var r: Dictionary=records[index]
			r.lost=true;r.active=false
			boat.specialistActive.erase(r.role)
			var home: Dictionary=c.port(str(r.portId))
			if not home.is_empty():Money.move(r,"coins",home,"expertPurse",int(r.coins),"Lost specialist savings to home estate",c.state.moneyLog)
			c.log_entry("%s lost aboard %s; earned savings passed to the home estate."%[r.name,boat.name])

static func dismiss(c,id: String) -> Dictionary:
	var permission: Dictionary=c.Politics.permit(c,"service")
	if not permission.ok:return permission
	for r in c.state.get("specialists",[]):
		if r.id!=id:continue
		var b: Dictionary=c.find_boat(str(r.boatUid))
		if b.is_empty() or r.get("discharged",false) or r.get("lost",false):return c.fail("This specialist is no longer aboard.")
		if int(b.get("shoreCrew",0))>0:return c.fail("Recall the shore party before changing its crew.")
		if not str(b.get("storedPort","")).is_empty() and b.storedPort!=c.current_port().id:return c.fail("Visit the harbor storing this hull first.")
		var probe: Dictionary=c.state.duplicate(true)
		for trial in probe.fleet:
			if trial.uid==b.uid:trial.crew=maxf(0,float(trial.crew)-1)
		if c.Expedition.cargo_weight(probe)>c.Expedition.capacity(probe)+0.001:return c.fail("Offload cargo before discharging a required carrier crew member.")
		if c.state.coins<int(r.arrears):return c.fail("Pay %d coins of professional arrears before discharge."%r.arrears)
		Money.move(c.state,"coins",r,"coins",int(r.arrears),"Discharged specialist arrears",c.state.moneyLog);r.arrears=0
		var p: Dictionary=c.current_port()
		var savings: int=floori(float(c.state.crewPurse)/maxi(1,c.crew_count()))
		Money.move(c.state,"crewPurse",p,"householdPurse",savings,"Discharged specialist base savings",c.state.moneyLog)
		Money.move(r,"coins",p,"expertPurse",int(r.coins),"Discharged specialist takes professional savings ashore",c.state.moneyLog)
		p.workforce+=1;p.recruits+=1;p.specialists+=1;p.specialistWorkers=p.specialists
		Economy.sync_workforce(p)
		b.crew=maxf(0,float(b.crew)-1);b.specialistActive.erase(r.role)
		r.discharged=true;r.active=false
		c.fit_boat(b);c.apply_morale();c.Manifest.allocate(c.state)
		return c.ok("Specialist discharged with earned savings; berth and harbor workforce reconciled.")
	return c.fail("Unknown specialist.")

static func repair_factor(c) -> float:
	var factor: float=1.0
	for b in c.active_fleet():factor=maxf(factor,float(b.spec.get("repairFactor",1)))
	return factor

static func premium(state: Dictionary,arrears: bool=false) -> int:
	var total: int=0
	for r in state.get("specialists",[]):
		if r.get("discharged",false) or r.get("lost",false):continue
		if state.get("fleet",[]).any(func(b):return b.get("uid","")==r.boatUid and not b.sunk):total+=int(r.arrears if arrears else r.premiumPerDay)
	return total
