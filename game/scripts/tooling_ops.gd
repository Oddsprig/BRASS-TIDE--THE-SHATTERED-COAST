extends RefCounted
const Locality064=preload("res://scripts/expedition.gd")
## Actual paid shore work, transport and owned workshop transactions.
const Tooling=preload("res://scripts/industrial_tooling.gd")
const Economy=preload("res://scripts/economy.gd")
const Goods=preload("res://scripts/goods.gd")
const Money=preload("res://scripts/money.gd")
const Politics=preload("res://scripts/politics.gd")
const Sources: Dictionary={
	"cinder_workshop_ruin":{"kind":"machine_tools","sourceId":"site:cinder_workshop_ruin","provenance":"site","condition":0.55},
	"rust_salvage_anchorage":{"kind":"engine_fixture","sourceId":"wreck:rust_salvage_anchorage","provenance":"wreck","condition":0.60},
	"shatter_wreck_field":{"kind":"hull_jig","sourceId":"wreck:shatter_wreck_field","provenance":"wreck","condition":0.45}
}
const RECIPES: Array=["supplies","timber","engines","guns"]

static func ensure(c) -> void:
	Tooling.ensure(c)
	if not c.state.get("toolingRecovery") is Dictionary:c.state.toolingRecovery={}

static func offer(c,site_id: String,kind: String) -> Dictionary:
	if not Locality064.home_local064(c.state):return c.fail("Machinery recovery requires Shatter Coast waters.")
	ensure(c)
	if not Sources.has(site_id) or Sources[site_id].kind!=kind:return c.fail("No matching machinery is evidenced here.")
	var site: Dictionary=c.Exploration.catalog_site(c.state,site_id)
	if site.is_empty() or int(c.state.get("exploration",{}).get("sites",{}).get(site_id,{}).get("level",0))<3:return c.fail("Complete the actual site survey before attempting machinery recovery.")
	var source: Dictionary=Sources[site_id]
	if source.provenance=="wreck" and c.distance(c.state.position,site)<=450:
		var record: Dictionary=c.Salvage.seed_site_wreck(c,site,"bilge_punt","tooling:"+site_id)
		if record.is_empty():return c.fail("This machinery has no physical wreck provenance.")
	var result: Dictionary=source.duplicate(true)
	result.merge({"ok":true,"siteId":site_id,"near":c.distance(c.state.position,site)<=450})
	return result

static func begin(c,site_id: String,kind: String) -> Dictionary:
	if not Locality064.home_local064(c.state):return c.fail("Machinery recovery requires Shatter Coast waters.")
	ensure(c)
	if not c.state.toolingRecovery.is_empty():return c.fail("Finish or recall the current recovery party first.")
	if not c.state.get("exploration",{}).get("assignment",{}).is_empty():return c.fail("Recall the current survey party first.")
	if not c.state.path.is_empty():return c.fail("Stop near the source before landing a recovery party.")
	var source: Dictionary=offer(c,site_id,kind)
	if not source.ok:return source
	if not source.near:return c.fail("Approach within recovery reach of the surveyed source.")
	if c.state.tooling.extracted.has(source.sourceId):return c.fail("This finite source was already extracted.")
	var spec: Dictionary=Tooling.KINDS[kind]
	if c.cargo_weight()+float(spec.weight)>c.capacity()+0.001 or not hold_room(c,float(spec.weight)):return c.fail("Make hold space for the machinery before landing.")
	var assignments: Dictionary={}
	var left: int=2
	for boat in c.active_fleet():
		var spare: int=maxi(0,floori(float(boat.crew)-float(boat.crewMin)-float(boat.get("shoreCrew",0))))
		var n: int=mini(left,spare)
		if n>0:assignments[boat.uid]=n;left-=n
		if left==0:break
	if left>0:return c.fail("Recovery needs two existing sailors above the boats' minimum crews.")
	var kits: float=float(spec.recoveryDays)*0.5
	var available: float=float(c.state.cargo.get("supplies",0))
	for boat in c.active_fleet():available+=float(boat.supplies)
	if available+0.00001<kits:return c.fail("Recovery needs %.1f real repair kits."%kits)
	var take: float=minf(kits,float(c.state.cargo.get("supplies",0)))
	c.state.cargo.supplies-=take
	var remainder: float=kits-take
	for boat in c.active_fleet():
		var used: float=minf(remainder,float(boat.supplies));boat.supplies-=used;remainder-=used
	for uid in assignments:
		var boat: Dictionary=c.find_boat(uid)
		boat.shoreCrew=int(boat.get("shoreCrew",0))+int(assignments[uid])
	c.state.toolingRecovery={"siteId":site_id,"sourceId":source.sourceId,"kind":kind,"startedAt":float(c.state.day),"readyAt":float(c.state.day)+float(spec.recoveryDays),"crewByBoat":assignments,"paid":0,"supplies":kits,"workerDays":2*int(spec.recoveryDays)}
	c.Manifest.allocate(c.state)
	c.log_entry("Landed two sailors for %s recovery. Normal crew wages still pay them once; %.1f kits committed."%[kind.replace("_"," "),kits])
	return c.ok("Recovery takes %d actual campaign days and %d coins of their ordinary earned wages. Remain nearby, keep payroll funded, then claim the machinery."%[int(spec.recoveryDays),2*int(spec.recoveryDays)*Goods.SAILOR_WAGE])

static func paid_day(c,paid: int,due: int) -> void:
	var job: Dictionary=c.state.get("toolingRecovery",{})
	if job.is_empty():return
	var ratio: float=minf(1,float(paid)/maxf(1,float(due)))
	job.paid=mini(int(job.workerDays)*Goods.SAILOR_WAGE,int(job.paid)+floori(2*Goods.SAILOR_WAGE*ratio))

static func cancel(c) -> Dictionary:
	ensure(c)
	if c.state.toolingRecovery.is_empty():return c.fail("No recovery party is ashore.")
	for uid in c.state.toolingRecovery.crewByBoat:
		var boat: Dictionary=c.find_boat(uid)
		if not boat.is_empty():boat.shoreCrew=maxi(0,int(boat.get("shoreCrew",0))-int(c.state.toolingRecovery.crewByBoat[uid]))
	c.state.toolingRecovery={}
	return c.ok("Recovery party recalled. Used kits and earned ordinary wages remain spent.")

static func settle(c,requirements: Dictionary) -> Dictionary:
	ensure(c)
	var job: Dictionary=c.state.toolingRecovery
	if job.is_empty() or job.sourceId!=requirements.sourceId or job.kind!=requirements.kind:return c.fail("Land a recovery party and complete its paid work first.")
	if float(c.state.day)+0.000001<float(job.readyAt) or int(job.paid)<int(requirements.wages):return c.fail("Recovery work or ordinary paid crew-days are still incomplete.")
	var source: Dictionary=offer(c,str(job.siteId),str(job.kind))
	if not source.ok or not source.near:return c.fail("Remain within reach of the actual recovery site.")
	for uid in job.crewByBoat:
		var boat: Dictionary=c.find_boat(uid)
		if boat.is_empty() or boat.sunk or float(boat.crew)<float(job.crewByBoat[uid]):return c.fail("The original recovery party is no longer available.")
	cancel(c)
	return c.ok("Completed actual paid recovery work consumed once.")

static func claim(c) -> Dictionary:
	ensure(c)
	if c.state.toolingRecovery.is_empty():return c.fail("No completed machinery recovery is waiting.")
	var job: Dictionary=c.state.toolingRecovery
	var result: Dictionary=Tooling.recover(c,str(job.siteId),str(job.kind))
	if result.ok:c.Manifest.allocate(c.state);c.log_entry(str(result.message))
	return result

static func binding(c,business_id: String,kind: String) -> Dictionary:
	for b in c.state.get("businesses",[]):
		if b.id!=business_id or b.kind!="workshop":continue
		var good: String=str(b.get("recipeGood","supplies"))
		if kind=="machine_tools" and good=="supplies":return {"businessKind":b.kind,"good":good,"labor":"carpenter"}
		if kind=="engine_fixture" and good=="engines":return {"businessKind":b.kind,"good":good,"labor":"mechanic"}
		if kind=="hull_jig" and good=="timber":return {"businessKind":b.kind,"good":good,"labor":"carpenter"}
	return {}

static func recipe(c,business_id: String,good: String) -> Dictionary:
	var permission: Dictionary=Politics.permit(c,"service")
	if not permission.ok:return permission
	if good not in RECIPES:return c.fail("Choose kits, planks, engines or weapon assemblies.")
	for b in c.state.businesses:
		if b.id!=business_id:continue
		if b.kind!="workshop" or b.homePort!=c.current_port().id:return c.fail("Visit this workshop's home harbor.")
		if float(b.get("productionProgress",0))>0.000001:return c.fail("Finish or cancel the current paid batch before changing recipe.")
		for item in c.state.tooling.items:
			if item.businessId==business_id and item.location!="cargo" and item.location!="lost":return c.fail("Remove machinery before changing its actual recipe binding.")
		b.recipeGood=good
		return c.ok("Workshop now prepares "+str(Goods.ITEMS[good].name)+". Required trades and actual inputs still limit its output.")
	return c.fail("Unknown owned workshop.")

static func cancel_batch(c,business_id: String) -> Dictionary:
	var permission: Dictionary=Politics.permit(c,"service")
	if not permission.ok:return permission
	for b in c.state.businesses:
		if b.id!=business_id:continue
		if b.kind!="workshop" or b.homePort!=c.current_port().id:return c.fail("Visit this workshop's home harbor.")
		b.productionProgress=0.0
		return c.ok("Unfinished paid work cancelled. Earned wages stay spent; no finished goods or refund are created.")
	return c.fail("Unknown owned workshop.")

static func staff(c,business_id: String,occupation: String,hire: bool=true) -> Dictionary:
	var permission: Dictionary=Politics.permit(c,"service")
	if not permission.ok:return permission
	if occupation not in ["carpenter","mechanic","engineer","gunsmith"]:return c.fail("Unknown workshop trade.")
	for b in c.state.businesses:
		if b.id!=business_id:continue
		var p: Dictionary=c.current_port()
		if b.homePort!=p.id or b.kind!="workshop":return c.fail("Visit the actual owned workshop.")
		if int(b.arrearsHousehold)+int(b.arrearsExpert)>0:return c.fail("Settle staff arrears before changing the workforce.")
		var expert: bool=int(Goods.WAGES[occupation])>=150
		if hire:
			if b.employees.size()>=12:return c.fail("This workshop has twelve staff slots.")
			if int(p.availableWorkers)-ceili(float(p.get("_yardWorkersUsed",0)))<1 or (expert and int(p.availableSpecialists)-ceili(float(p.get("_yardSpecialistsUsed",0)))<1):return c.fail("No available local worker has this trade.")
			if p.get("training") is Dictionary and int(p.workforce)-int(p.training.qualified.sailor)<1:return c.fail("The remaining workers are committed qualified recruits.")
			var fee: int=ceili(0.5*Goods.WAGES.foreman)
			if not Money.move(b,"coins",p,"expertPurse",fee,"Workshop recruitment oversight",c.state.moneyLog):return c.fail("Recruitment oversight needs %d coins from the business."%fee)
			b.otherExpenses=int(b.get("otherExpenses",0))+fee
			p.workforce-=1
			if expert:p.specialists-=1;p.specialistWorkers=p.specialists
			b.employees.append({"name":"Local "+occupation,"occupation":occupation,"wage":Goods.WAGES[occupation],"specialist":expert})
		else:
			if b.employees.size()<=1:return c.fail("Keep at least one employee in the workplace.")
			var found: int=-1
			for i in range(b.employees.size()):
				if str(b.employees[i].occupation)==occupation:found=i;break
			if found<0:return c.fail("No employee has that occupation.")
			b.employees.remove_at(found);p.workforce+=1
			if expert:p.specialists+=1;p.specialistWorkers=p.specialists
		Economy.sync_workforce(p)
		p.availableSpecialists=mini(int(p.specialists),int(p.availableWorkers))
		c.HomeOps.Home.ensure(c.state)
		return c.ok("Actual workshop staff changed; ongoing wages use the existing paid payroll.")
	return c.fail("Unknown owned workshop.")

static func validate(c_state: Dictionary,world: Dictionary) -> String:
	var error: String=Tooling.validate(c_state,world)
	if not error.is_empty():return error
	if c_state.has("toolingRecovery"):
		var job=c_state.toolingRecovery
		if not job is Dictionary:return "Invalid machinery recovery job."
		if not job.is_empty():
			if job.get("siteId") not in Sources or job.get("kind")!=Sources[job.siteId].kind or job.get("sourceId")!=Sources[job.siteId].sourceId:return "Invalid machinery recovery source."
			for key in ["startedAt","readyAt","paid","supplies","workerDays"]:
				if not (job.get(key) is int or job.get(key) is float) or not is_finite(float(job[key])) or job[key]<0:return "Invalid recovery work account."
			if not job.get("crewByBoat") is Dictionary or job.crewByBoat.size()>48:return "Invalid recovery party."
			var count: int=0
			for uid in job.crewByBoat:
				var n=job.crewByBoat[uid]
				if not (n is int or n is float) or floorf(float(n))!=float(n) or n<1:return "Invalid assigned recovery sailors."
				count+=int(n)
				var found: bool=false
				for boat in c_state.fleet:
					if boat.uid==uid and not boat.sunk and float(boat.get("shoreCrew",0))>=float(n):found=true
				if not found:return "Missing original recovery crew."
			var days: int=int(Tooling.KINDS[job.kind].recoveryDays)
			if count!=2 or absf(float(job.readyAt)-float(job.startedAt)-days)>0.00001 or float(job.startedAt)>float(c_state.day):return "Invalid recovery duration or crew."
			if float(job.workerDays)!=2*days or float(job.supplies)!=float(days)*0.5 or float(job.paid)>2*days*Goods.SAILOR_WAGE or floorf(float(job.paid))!=float(job.paid):return "Invalid recovery paid work or committed materials."
	for b in c_state.get("businesses",[]):
		if b.has("otherExpenses") and (not (b.otherExpenses is int or b.otherExpenses is float) or not is_finite(float(b.otherExpenses)) or b.otherExpenses<0 or floorf(float(b.otherExpenses))!=float(b.otherExpenses)):return "Invalid workshop expense account."
		if b.has("recipeGood") and b.recipeGood not in RECIPES:return "Unknown workshop recipe."
		if b.has("productionProgress") and (not (b.productionProgress is int or b.productionProgress is float) or not is_finite(float(b.productionProgress)) or b.productionProgress<0 or b.productionProgress>=1.000001):return "Invalid paid workshop work."
	return ""

static func hold_room(c,weight: float) -> bool:
	var kind: String=""
	for key in Tooling.KINDS:
		if absf(float(Tooling.KINDS[key].weight)-weight)<0.000001:kind=key;break
	if kind.is_empty():return false
	var probe: Dictionary=c.state.duplicate(true)
	probe.tooling.items.append({"id":"room-probe","kind":kind,"location":"cargo"})
	c.Manifest.allocate(probe)
	return not probe.cargoManifest.get("unassigned",{}).has("@tool:room-probe")
