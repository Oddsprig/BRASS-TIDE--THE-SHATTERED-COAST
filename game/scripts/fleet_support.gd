extends RefCounted
const Identity=preload("res://scripts/fleet_identity.gd")
const Money=preload("res://scripts/money.gd")
const Economy=preload("res://scripts/economy.gd")
const Goods=preload("res://scripts/goods.gd")
const Workshop=preload("res://scripts/fleet_workshop.gd")
const Politics=preload("res://scripts/politics.gd")
const STAFF_EFFECTS: Dictionary={
	"pilot":{"speedMult":1.03,"turnMult":1.04},
	"gunner":{"fireRateMult":1.06},
	"chief_engineer":{"repairFactorAdd":0.25,"pumpsMult":1.10},
	"surveyor":{"surveyFactorAdd":0.30},
	"quartermaster":{"upkeepFactor":0.95}}
const STAFF_EFFECT_TEXT: Dictionary={
	"pilot":"Speed +3%; turn +4% on the fitted boat.",
	"gunner":"Fitted weapon and mount fire rate +6%.",
	"chief_engineer":"Repair factor +0.25; pumps +10%.",
	"surveyor":"Survey factor +0.30.",
	"quartermaster":"Rations use -5%; base wages stay 100 coins per sailor-day."}

## One detached panel read. Only Politics' copied permission state is normalized;
## no live ensure, reconcile, economy sync, crew or purse publication is allowed.
static func selected_view(c,uid: String) -> Dictionary:
	var boat: Dictionary=c.find_boat(uid)
	if boat.is_empty():return {"ok":false,"message":"Unknown boat."}
	var state: Dictionary=c.state
	var port: Dictionary=c.current_port()
	var permission: Dictionary={"ok":false,"message":"Stop at a harbor for this service."}
	if not port.is_empty():
		var view=Workshop.PermissionView.new(state.duplicate(true),c.data,port.duplicate(true))
		permission=Politics.permit(view,"service")
	var roles: Dictionary=Identity.roles()
	var hiring: Array=[]
	for role in roles:
		hiring.append(Identity.specialist_quote(state,boat,port,str(role),permission))
	var crew: float=maxf(0.0,float(boat.get("crew",0)))
	var wounded: float=maxf(0.0,float(boat.get("wounded",0)))
	var ashore: float=maxf(0.0,float(boat.get("shoreCrew",0)))
	var alive: int=0 if boat.get("sunk",false) else floori(crew)
	var base_arrears: int=int(state.get("wageArrears",0))
	var active_roles: Dictionary=boat.get("specialistActive",{})
	var staff: Array=[]
	var premium_per_day: int=0
	var premium_arrears: int=0
	var advance: int=Economy.recruit_cost(port,1) if not port.is_empty() else 0
	for rec in aboard(c,uid):
		var role: String=str(rec.get("role",""))
		if not roles.has(role):continue
		var info: Dictionary=roles[role]
		var premium: int=int(rec.get("premiumPerDay",info.premium))
		var arrears: int=int(rec.get("arrears",0))
		var working: bool=staff.size()<alive and bool(rec.get("active",false)) and bool(active_roles.get(role,false)) and arrears==0 and base_arrears==0
		var effect: String=str(STAFF_EFFECT_TEXT[role])
		if not working:
			var reason: String="benefit inactive"
			if staff.size()>=alive:reason="no living crew berth"
			elif base_arrears>0:reason="fleet base wages unpaid"
			elif arrears>0:reason="professional premium unpaid"
			effect="Suspended (%s). When working: %s"%[reason,effect]
		staff.append({"id":str(rec.get("id","")),"name":str(rec.get("name","Sailor")),
			"role":role,"roleName":str(info.name),"active":working,"effect":effect,
			"effects":STAFF_EFFECTS[role].duplicate(true) if working else {},
			"advance":advance,"premiumPerDay":premium,"basePerDay":Goods.SAILOR_WAGE,
			"totalPerDay":Goods.SAILOR_WAGE+premium,"coins":int(rec.get("coins",0)),"arrears":arrears})
		if not boat.get("sunk",false):premium_per_day+=premium
		premium_arrears+=arrears
	var base_pay: int=int(Economy.daily_upkeep([boat]).wages)
	var morale: float=float(state.get("morale",85.0))
	return {"ok":true,"boatUid":uid,"name":str(boat.get("name","Boat")),
		"commandPreference":Identity.command_preference(boat),
		"crew":{"aboard":crew,"wounded":wounded,"ashore":ashore,"able":maxf(0.0,crew-wounded-ashore),
			"minimum":float(boat.get("crewMin",0)),"optimal":float(boat.get("crewOptimal",0)),"maximum":float(boat.get("crewMax",0))},
		"morale":{"value":morale,"factor":clampf(morale/85.0,0.35,1.0)},
		"payroll":{"basePerSailorDay":Goods.SAILOR_WAGE,"basePerDay":base_pay,
			"premiumPerDay":premium_per_day,"totalPerDay":base_pay+premium_per_day,
			"fleetBaseArrears":base_arrears,"boatPremiumArrears":premium_arrears,"fleetCrewPurse":int(state.get("crewPurse",0))},
		"staff":staff,"hiring":hiring,"fittedSpec":c.fitted_spec(boat).duplicate(true),
		"effectiveSpec":boat.get("spec",{}).duplicate(true),
		"service":boat.get("service",{}).duplicate(true),"serviceHistory":boat.get("serviceHistory",[]).duplicate(true)}

static func combat(c) -> Array:
	return c.active_fleet().filter(func(b):return not b.get("supportOnly",false))

static func aboard(c,uid: String) -> Array:
	return c.state.get("specialists",[]).filter(func(r):return r.boatUid==uid and not r.get("discharged",false) and not r.get("lost",false))

static func reserve(c,uid: String) -> Dictionary:
	var b: Dictionary=c.find_boat(uid)
	if b.is_empty():return c.fail("Unknown boat.")
	if b.get("needsHarborRepair",false):return c.fail("Pay for harbor repair before returning a recovered prize to combat.")
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
		c.TrainingOps.Training.return_qualified(p,1,"gunner" if r.role=="gunner" else ("mechanic" if r.role=="chief_engineer" else "sailor"))
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
