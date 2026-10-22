extends RefCounted
## Paid drydock bays increase queue capacity, never create another workforce.
const Goods=preload("res://scripts/goods.gd")
const Economy=preload("res://scripts/economy.gd")
const Money=preload("res://scripts/money.gd")
const Politics=preload("res://scripts/politics.gd")
const Factions=preload("res://scripts/factions.gd")
const TEAM: Dictionary={"laborer":2,"shipwright":3,"mechanic":1,"engineer":1,"foreman":1}
const MATERIALS: Dictionary={"timber":8.0,"iron":6.0,"copper":2.0,"supplies":5.0,"engines":1.0}
const DAYS: float=5.0

static func ensure(c) -> void:
	if not c.state.get("yardProjects") is Array:c.state.yardProjects=[]
	if not c.state.has("yardSeq"):c.state.yardSeq=0

static func bays(state: Dictionary,port_id: String) -> int:
	var count: int=0
	for job in state.get("yardProjects",[]):
		if job.portId==port_id and job.status=="complete":count+=1
	return mini(2,count)

static func quote(c,business_id: String) -> Dictionary:
	ensure(c)
	var permission: Dictionary=Politics.permit(c,"service")
	if not permission.ok:return permission
	var p: Dictionary=c.current_port()
	if p.industry!="shipyard" or int(Factions.standing(c.state,p.faction).score)<20:return c.fail("Drydock expansion needs an existing shipyard and Friendly harbor partnership.")
	var b: Dictionary={}
	for candidate in c.state.businesses:
		if candidate.id==business_id:b=candidate
	if b.is_empty() or b.homePort!=p.id or b.kind!="workshop" or b.paused:return c.fail("An operating owned workshop at this shipyard must fund the project.")
	if bays(c.state,p.id)>=2:return c.fail("The two additional bays at this harbor are complete.")
	for job in c.state.yardProjects:
		if job.portId==p.id and job.status=="building":return c.fail("Complete the current harbor project first.")
	if int(p.availableWorkers)-ceili(float(p.get("_yardWorkersUsed",0)))<8 or int(p.availableSpecialists)-ceili(float(p.get("_yardSpecialistsUsed",0)))<3:return c.fail("The five-day job needs eight actual available workers, including three experts.")
	if p.get("training") is Dictionary and int(p.workforce)-int(p.training.qualified.sailor)<8:return c.fail("The remaining people are committed qualified recruits.")
	var materials: Dictionary={}
	var material_cost: int=0
	var scale: int=bays(c.state,p.id)+1
	for good in MATERIALS:
		materials[good]=float(MATERIALS[good])*scale
		if float(p.stocks.get(good,0))<float(materials[good]):return c.fail("The bay lacks physical "+str(Goods.ITEMS[good].name)+".")
		material_cost+=ceili(float(materials[good])*Economy.price(p,good))
	var household: int=0;var expert: int=0
	for occupation in TEAM:
		var pay: int=ceili(float(TEAM[occupation])*DAYS*int(Goods.WAGES[occupation]))
		if int(Goods.WAGES[occupation])>=150:expert+=pay
		else:household+=pay
	var margin: int=ceili(float(material_cost)*0.08)
	var duty: int=ceili(float(material_cost+household+expert)*0.05)
	return {"ok":true,"portId":p.id,"businessId":b.id,"materials":materials,"materialCost":material_cost,"householdTotal":household,"expertTotal":expert,"margin":margin,"duty":duty,"cost":material_cost+household+expert+margin+duty,"days":DAYS,"message":"Five-day drydock bay: %d materials + %d ordinary wages + %d expert wages + %d yard service + %d duty."%[material_cost,household,expert,margin,duty]}

static func begin(c,business_id: String) -> Dictionary:
	var q: Dictionary=quote(c,business_id)
	if not q.ok:return q
	var b: Dictionary={}
	for value in c.state.businesses:
		if value.id==business_id:b=value
	if int(b.coins)<int(q.cost):return c.fail("Fund %d coins in this workshop's operating purse."%q.cost)
	var p: Dictionary=c.current_port()
	c.state.yardSeq+=1
	var job: Dictionary={"id":"yard-%d"%int(c.state.yardSeq),"portId":p.id,"businessId":b.id,"status":"building","startedAt":float(c.state.day),"days":DAYS,"progress":0.0,"escrow":0,"householdTotal":q.householdTotal,"expertTotal":q.expertTotal,"householdPaid":0,"expertPaid":0,"workers":8,"specialists":3}
	Money.move(b,"coins",p,"cash",int(q.materialCost)+int(q.margin),"Drydock materials and yard service",c.state.moneyLog)
	Money.move(b,"coins",p,"governmentPurse",int(q.duty),"Drydock registry duty",c.state.moneyLog)
	Money.move(b,"coins",job,"escrow",int(q.householdTotal)+int(q.expertTotal),"Reserved drydock team wages",c.state.moneyLog)
	b.otherExpenses=int(b.get("otherExpenses",0))+int(q.materialCost)+int(q.margin)+int(q.duty)
	for good in q.materials:p.stocks[good]-=float(q.materials[good])
	p.workforce-=8;p.specialists-=3;p.specialistWorkers=p.specialists
	p.availableSpecialists=maxi(0,int(p.availableSpecialists)-3);Economy.sync_workforce(p)
	c.state.yardProjects.append(job)
	return c.ok("Actual drydock team reserved. New bay completes after five paid days; shared yard labor still limits all construction.")

static func daily(c) -> void:
	ensure(c)
	for job in c.state.yardProjects:
		if job.status!="building":continue
		var elapsed: float=clampf(float(c.state.day)-float(job.startedAt),0,DAYS)
		if elapsed+0.000001>=DAYS:elapsed=DAYS
		var household_due: int=floori(float(job.householdTotal)*elapsed/DAYS+0.0000001)-int(job.householdPaid)
		var expert_due: int=floori(float(job.expertTotal)*elapsed/DAYS+0.0000001)-int(job.expertPaid)
		if int(job.escrow)<household_due+expert_due:continue
		var p: Dictionary=c.port(job.portId)
		Money.move(job,"escrow",p,"householdPurse",household_due,"Drydock worker wages",c.state.moneyLog)
		Money.move(job,"escrow",p,"expertPurse",expert_due,"Drydock expert wages",c.state.moneyLog)
		job.householdPaid+=household_due;job.expertPaid+=expert_due;job.progress=elapsed
		for b in c.state.businesses:
			if b.id==job.businessId:b.otherExpenses=int(b.get("otherExpenses",0))+household_due+expert_due
		if elapsed>=DAYS and int(job.escrow)==0:
			p.workforce+=int(job.workers);p.specialists+=int(job.specialists);p.specialistWorkers=p.specialists
			p.availableSpecialists+=int(job.specialists);Economy.sync_workforce(p)
			job.workers=0;job.specialists=0;job.status="complete"
			c.log_entry("%s drydock bay complete. Extra queue capacity uses the same finite paid workforce."%p.name)

static func validate(state: Dictionary,world: Dictionary) -> String:
	if not state.has("yardProjects"):return ""
	if not state.yardProjects is Array or state.yardProjects.size()>20:return "Invalid drydock project collection."
	if not (state.get("yardSeq") is int or state.get("yardSeq") is float) or not is_finite(float(state.yardSeq)) or state.yardSeq<0 or state.yardSeq>1000000 or floorf(float(state.yardSeq))!=float(state.yardSeq):return "Invalid yard sequence."
	var ports: Array=world.PORTS.map(func(p):return p.id)
	var ids: Dictionary={};var active: Dictionary={};var totals: Dictionary={}
	for job in state.yardProjects:
		if not job is Dictionary or not job.get("id") is String or ids.has(job.id) or job.get("portId") not in ports or job.get("status") not in ["building","complete"]:return "Invalid drydock identity."
		var serial: String=str(job.id).trim_prefix("yard-")
		if not str(job.id).begins_with("yard-") or not serial.is_valid_int() or int(serial)<1 or int(serial)>int(state.yardSeq) or str(int(serial))!=serial:return "Noncanonical drydock identity."
		ids[job.id]=true
		totals[job.portId]=int(totals.get(job.portId,0))+1
		if int(totals[job.portId])>2:return "Too many drydock bays at one harbor."
		for key in ["startedAt","days","progress","escrow","householdTotal","expertTotal","householdPaid","expertPaid","workers","specialists"]:
			if not (job.get(key) is int or job.get(key) is float) or not is_finite(float(job[key])) or job[key]<0:return "Invalid drydock account."
		for key in ["escrow","householdTotal","expertTotal","householdPaid","expertPaid","workers","specialists"]:
			if floorf(float(job[key]))!=float(job[key]) or float(job[key])>1000000000000:return "Fractional or excessive drydock account."
		if job.days!=DAYS or job.progress>DAYS or job.startedAt>state.day:return "Invalid drydock progress."
		if int(job.escrow)!=int(job.householdTotal)+int(job.expertTotal)-int(job.householdPaid)-int(job.expertPaid):return "Drydock escrow does not reconcile."
		if job.householdTotal!=2875 or job.expertTotal!=2625:return "Noncanonical drydock team wage bill."
		if int(job.householdPaid)!=floori(2875*float(job.progress)/DAYS+0.0000001) or int(job.expertPaid)!=floori(2625*float(job.progress)/DAYS+0.0000001):return "Drydock wages do not match earned work."
		if not state.get("businesses",[]).any(func(b):return b.id==job.get("businessId") and b.homePort==job.portId):return "Missing funding workshop."
		if job.status=="building":
			if job.workers!=8 or job.specialists!=3 or active.has(job.portId):return "Duplicate drydock team."
			active[job.portId]=true
		else:
			if job.workers!=0 or job.specialists!=0 or job.escrow!=0 or job.progress!=DAYS:return "Completed drydock retains unfinished work."
	return ""
