extends RefCounted
const Boarding=preload("res://scripts/boarding.gd")
const Combat=preload("res://scripts/combat_boarding.gd")
const Economy=preload("res://scripts/economy.gd")
const Politics=preload("res://scripts/politics.gd")
const Factions=preload("res://scripts/factions.gd")
const Lifecycle=preload("res://scripts/equipment_lifecycle.gd")
static func rules(c,p: Dictionary) -> Dictionary:
	return {"here":c.current_port().get("id","")==p.id and c.state.path.is_empty(),"service":bool(Politics.permit(c,"service").ok),"friendly":int(Factions.standing(c.state,str(p.faction)).score)>=20}
static func price(_c,p: Dictionary,good: String) -> int:return Economy.price(p,good,"buy")
static func capacity(c) -> int:
	var companies: int=0
	for owner in c.state.fleetOwners:
		if owner.get("playerCompany",false):companies+=owner.boats.size()
	return maxi(1,c.MAX_FLEET-companies)
static func prepare(saved: Dictionary) -> Dictionary:
	if saved.has("boardingRevision"):return saved
	var copy: Dictionary=saved.duplicate(true)
	copy.boardingRevision=26
	for p in copy.get("ports",[]):
		if p is Dictionary and p.get("training",{}).get("qualified") is Dictionary and not p.training.qualified.has("boarder"):p.training.qualified.boarder=0
	return copy
static func ensure(c) -> void:
	Boarding.harbor_rules=rules;Boarding.unit_price=price;Boarding.fleet_capacity=capacity;Boarding.household_key="householdPurse"
	Boarding.ensure_state(c)
	c.state.boardingRevision=26
	if not c.state.has("captiveBerths"):c.state.captiveBerths={}
	if not c.state.has("boardingLostPeople"):c.state.boardingLostPeople=0
	for owner in c.state.fleetOwners:
		for b in owner.boats:
			if not b.has("boarders"):b.boarders=0
static func message(c,r: Dictionary,text: String) -> Dictionary:
	r.message=text if r.ok else str(r.get("reason","Operation refused."))
	if r.ok:c.log_entry(str(r.message))
	return r
static func hire(c,uid: String,count: int) -> Dictionary:
	ensure(c)
	var b: Dictionary=c.find_boat(uid)
	if not b.is_empty() and float(b.crew)+count+float(c.state.captiveBerths.get(uid,0))+c.CrisisOps.Transport.assigned(c.state,uid)>float(b.crewMax):return c.fail("Captives occupy the remaining physical berths.")
	var r: Dictionary=Boarding.hire_party(c,uid,count)
	if r.ok:Economy.sync_workforce(c.current_port())
	return message(c,r,"Hired %d trained boarders into existing berths; their wage advance is in the crew purse."%count)
static func build(c,kind: String,count: int) -> Dictionary:
	ensure(c)
	var r: Dictionary=Boarding.build_defense(c,kind,count)
	if r.ok:Economy.sync_workforce(c.current_port())
	return message(c,r,"Coastal defense commissioned from paid labor, actual public materials and existing recruits. Daily wages and provisioning determine readiness.")
class DayView extends RefCounted:
	var state: Dictionary
	func _init(live: Dictionary):state=live.duplicate();state.econDay=int(live.econDay)+1
static func step(c,dt: float) -> void:
	for b in c.state.boardingPrizes:
		if not b.sunk:c.Damage.tick_ship(b,dt,{"inCombat":false})
		if b.sunk:c.Salvage.record_battle(c,{"ships":[b],"chartPosition":c.state.position},"lost-prize:"+str(b.uid))
	reconcile(c)
	c.state.boardingPrizes=c.state.boardingPrizes.filter(func(b):return not b.sunk)
static func daily(c) -> void:
	Boarding.daily_defenses(DayView.new(c.state))
	# Crewed pending prizes stay physical and receive ordinary payroll/rations.
	var extra: Dictionary=Economy.daily_upkeep(c.state.boardingPrizes)
	var due: int=int(extra.wages)
	var paid: int=mini(due,int(c.state.coins))
	c.Money.move(c.state,"coins",c.state,"crewPurse",paid,"Pending prize crews",c.state.moneyLog)
	c.state.wageArrears+=due-paid
	var food: float=float(extra.food)+float(c.state.captives)*0.08
	var used: float=minf(food,float(c.state.cargo.food));c.state.cargo.food-=used
	if used+0.000001<food:c.state.morale=maxf(10,float(c.state.morale)-3);c.log_entry("Prize crews or captives need more actual rations.")
static func reconcile(c) -> void:
	for b in c.state.fleet+c.state.boardingPrizes:b.boarders=mini(int(b.get("boarders",0)),floori(float(b.crew)))
	for uid in c.state.captiveBerths.keys():
		var found: Dictionary={}
		for b in c.state.fleet+c.state.boardingPrizes:
			if str(b.get("uid",""))==str(uid):found=b;break
		if found.is_empty() or found.sunk:
			var lost: int=int(c.state.captiveBerths[uid]);c.state.captives-=lost;c.state.boardingLostPeople+=lost;c.state.captiveBerths.erase(uid)
			c.log_entry("%d captives were lost with their actual carrier."%lost)
static func allot_captives(c) -> bool:
	var left: int=int(c.state.captives)
	var planned: Dictionary={}
	for b in c.state.fleet+c.state.boardingPrizes:
		if b.sunk or not str(b.get("storedPort","")).is_empty():continue
		var n: int=mini(left,maxi(0,floori(float(b.crewMax)-float(b.crew))-c.CrisisOps.Transport.assigned(c.state,str(b.uid))))
		if n>0:planned[str(b.uid)]=n;left-=n
	if left>0:
		for b in c.state.fleet+c.state.boardingPrizes:
			if b.sunk or not b.get("captureSecured",false):continue
			var n: int=mini(left,maxi(0,floori(float(b.spec.cargo))))
			if n>0:planned[str(b.uid)]=int(planned.get(str(b.uid),0))+n;left-=n
	if left>0:return false
	c.state.captiveBerths=planned
	return true
static func _capture_ready(b) -> bool:
	return b is Dictionary and b.get("sunk", false) != true and b.get("captureSecured", false) == true and b.get("supportOnly", false) == true and b.get("needsHarborRepair", false) == true

static func settle(c,battle: Dictionary) -> Dictionary:
	ensure(c)
	if battle.is_empty():return {"ok":true,"added":0}
	var ready: Array=[]
	var blocked:=false
	for b in battle.get("captured", []):
		if b is Dictionary and b.get("sunk", false) == true:
			continue
		if not _capture_ready(b):
			blocked=true
			break
		ready.append(b)
	var planned: Dictionary={"ok":true,"rows":[]}
	if not blocked:
		planned=Lifecycle.rehearse_captures(c.state, c.data, ready)
		if not planned.ok:
			return c.fail(str(planned.get("message", "Captured equipment was refused.")))
	# Securing a prize does not make a flooded hull immortal. Lost parties and
	# defenders cannot strand the victory screen or become living prize crew.
	var survivors: Array=[]
	for b in battle.get("captured",[]):
		if not b.get("sunk",false):survivors.append(b);continue
		if not b.get("boardingSettled",false):
			var party: int=0
			for job in battle.get("boarding",{}).get("jobs",[]):
				if str(job.target)==str(b.get("id","")):party+=int(job.get("prize",0))
			c.state.boardingLostPeople+=party+int(b.get("captives",0))
			b.boardingSettled=true;b.captives=0.0;b.crew=0.0;b.wounded=0.0;b.boarders=0
			c.log_entry("Secured prize lost to flooding before recovery; its actual people and wreck were recorded.")
	if battle.has("captured"):battle.captured=survivors
	var r: Dictionary=Boarding.settle(c,battle)
	if not r.ok:return message(c,r,"")
	for row in planned.get("rows", []):
		if row is Dictionary and row.get("boat") is Dictionary and not bool(row.get("physical", false)):
			Lifecycle.install_legacy(row.boat, row.get("staged", {}))
	for owner in c.state.fleetOwners:
		owner.boats=owner.boats.filter(func(b):return not b.get("captureSecured",false))
		if owner.boats.is_empty():owner.active=false
	for b in c.state.fleet+c.state.boardingPrizes:
		if not b.get("captureSecured",false):continue
		c.fit_boat(b);b.towed=true;b.towSpeedFactor=0.55
	if not allot_captives(c):return c.fail("Captured people exceed surviving berths; retain the engagement for recovery.")
	reconcile(c)
	return r
static func promote(c) -> Dictionary:
	ensure(c)
	var empty: Dictionary={"ships":[],"rng":RandomNumberGenerator.new(),"captured":[]}
	return message(c,Boarding.settle(c,empty),"Available roster places now hold the same saved prize boats. They still need paid harbor repair.")
static func release(c,count: int) -> Dictionary:
	var permission: Dictionary=Politics.permit(c,"service")
	if not permission.ok:return permission
	if count<1 or count>int(c.state.captives):return c.fail("Choose an existing captive count.")
	var p: Dictionary=c.current_port();p.workforce+=count;p.recruits+=count;c.state.captives-=count
	Economy.sync_workforce(p);allot_captives(c)
	return c.ok("%d captives released safely into this harbor's workforce. No sale or reward coins were created."%count)
static func coastal(c,battle: Dictionary) -> void:
	battle.coastalDefenses=[]
	for p in c.state.ports:
		if c.distance(c.state.position,p)>420 or not p.get("defenses",{}).get("active",false):continue
		var team: String="enemy" if Factions.is_hostile(c.state,str(p.faction)) else "player"
		battle.coastalDefenses.append({"port":p,"x":2060.0 if team=="enemy" else 240.0,"y":850.0,"team":team,"cooldown":0.0})
static func validate(s: Dictionary,world: Dictionary) -> String:
	if s.get("boardingRevision",26)!=26:return "Unknown boarding revision."
	var error: String=Boarding.validate(s,{"ports":world.PORTS})
	if not error.is_empty():return error
	var berths=s.get("captiveBerths",{})
	if not berths is Dictionary or berths.size()>160:return "Invalid captive berth assignments."
	var total: int=0
	for uid in berths:
		var n=berths[uid]
		if not uid is String or not Boarding._w(n) or int(n)<1:return "Invalid captive berth count."
		var found: Dictionary={}
		for b in s.fleet+s.get("boardingPrizes",[]):
			if b.get("uid","")==uid:found=b;break
		if found.is_empty() or found.sunk or float(found.crew)+float(n)>float(found.crewMax)+floorf(float(found.spec.cargo)):return "Captive carrier is absent, lost or over its physical berths."
		total+=int(n)
	if total!=int(s.get("captives",0)) or not Boarding._w(s.get("boardingLostPeople",0)):return "Captive custody and explicit losses do not reconcile."
	return ""
