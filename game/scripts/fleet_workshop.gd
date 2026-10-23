extends RefCounted
## Knowledge-only templates and a copied-data, all-or-nothing fitting transaction.
## Public preview never calls Campaign mutators or Politics on live state.
const Refits=preload("res://scripts/refit.gd")
const Politics=preload("res://scripts/politics.gd")
const Identity=preload("res://scripts/fleet_identity.gd")
const Expedition=preload("res://scripts/expedition.gd")
const Manifest=preload("res://scripts/hold_manifest.gd")
const Money=preload("res://scripts/money.gd")
const Construction=preload("res://scripts/construction.gd")
const Deployment=preload("res://scripts/deployment.gd")
const MAX_TEMPLATES: int=24
const MAX_NAME: int=48
const EPS: float=0.000001
const ADVANCED: Array=["heavy_cannon","salvo_rocket","heavy_torpedo","heavy_drive","fortress_plating","naval_plating"]
const BILL_COINS: Array=["cost","materialCost","workerWages","expertWages","tax","margin","businessIncome"]
const YARD_KEYS: Array=["_yardWorkersUsed","_yardOrdinaryUsed","_yardSpecialistsUsed","yardWorkersReserved","yardOrdinaryReserved","yardSpecialistsReserved","yardAvailableWorkers","yardAvailableSpecialists"]

class PermissionView extends RefCounted:
	var state: Dictionary
	var data: Dictionary
	var harbor: Dictionary
	func _init(s: Dictionary,w: Dictionary,p: Dictionary):
		state=s;data=w;harbor=p
	func current_port() -> Dictionary:
		return harbor
	func fail(message: String) -> Dictionary:
		return {"ok":false,"message":message}

static func _no(message: String) -> Dictionary:
	return {"ok":false,"message":message,"error":message,"id":""}

static func _plain_name(value) -> bool:
	if not value is String or value.is_empty() or value.length()>MAX_NAME or value.strip_edges()!=value:return false
	for i in range(value.length()):
		if value.unicode_at(i)<32 or value.unicode_at(i)==127:return false
	return true

## Strict optional schema. No migration, normalization or modification of input.
## Each entry is {id, hull, name, loadout}; no stock, prices or condition in knowledge.
static func validate_templates(state: Dictionary,world: Dictionary) -> String:
	if not state.has("fitTemplates"):return ""
	var hulls: Dictionary={}
	for base in world.get("HULLS",[]):hulls[str(base.id)]=base
	return _library_error(state.fitTemplates,hulls)

static func _library_error(value,hulls: Dictionary={}) -> String:
	if not value is Array or value.size()>MAX_TEMPLATES:return "Fitting library must contain at most 24 templates."
	var ids: Dictionary={}
	var names: Dictionary={}
	for entry in value:
		if not entry is Dictionary or entry.size()!=4:return "A fitting template must contain id, hull, name and loadout only."
		for key in entry:
			if key not in ["id","hull","name","loadout"]:return "Unknown fitting template field."
		if not _plain_name(entry.get("id")) or ids.has(entry.id):return "Invalid or duplicate fitting template ID."
		if not _plain_name(entry.get("name")) or not _plain_name(entry.get("hull")) or not entry.get("loadout") is Dictionary:return "Invalid fitting template name, hull or fitting."
		var name_key: String=str(entry.hull)+":"+str(entry.name).to_lower()
		if names.has(name_key):return "Duplicate fitting template name for this hull."
		ids[entry.id]=true;names[name_key]=true
		if not hulls.is_empty():
			if not hulls.has(entry.hull):return "A fitting template references an unknown hull."
			var checked: Dictionary=Refits.normalize(hulls[entry.hull],entry.loadout)
			if not checked.ok:return "Invalid fitting template: "+str(checked.message)
		else:
			# CRUD still bounds/validates other records when no world was passed.
			var fit: Dictionary=entry.loadout
			if fit.size()!=3 or not fit.get("weapons") is Array or fit.weapons.size()<1 or fit.weapons.size()>4 or not fit.get("engine") is String or not fit.get("armor") is String:return "Invalid fitting template fields."
			var catalog: Dictionary=Refits.catalog()
			if not catalog.engines.has(fit.engine) or not catalog.armor.has(fit.armor):return "Unknown fitting template package."
			for id in fit.weapons:
				if not id is String or not catalog.weapons.has(id):return "Unknown fitting template weapon."
	return ""

static func template_list(state: Dictionary,hull_id: String="") -> Array:
	var value=state.get("fitTemplates",[])
	if not _library_error(value).is_empty():return []
	var result: Array=[]
	for entry in value:
		if hull_id.is_empty() or entry.hull==hull_id:result.append(entry.duplicate(true))
	return result

static func save_template(state: Dictionary,base: Dictionary,name: String,loadout: Dictionary) -> Dictionary:
	var error: String=_library_error(state.get("fitTemplates",[]))
	if not error.is_empty():return _no(error)
	name=name.strip_edges()
	if not _plain_name(name) or not _plain_name(base.get("id")):return _no("Name the fitting with 1–48 printable characters and a known hull.")
	var fit: Dictionary=Refits.normalize(base,loadout)
	if not fit.ok:return _no(str(fit.message))
	var library: Array=template_list(state)
	for entry in library:
		if entry.hull==base.id and str(entry.name).to_lower()==name.to_lower():
			entry.name=name;entry.loadout=fit.loadout.duplicate(true)
			state.fitTemplates=library
			return {"ok":true,"message":"Updated fitting knowledge. No equipment or coins changed.","id":entry.id}
	if library.size()>=MAX_TEMPLATES:return _no("The fitting library holds 24 templates. Remove an unused template first.")
	var id: String=""
	for i in range(1,MAX_TEMPLATES+1):
		var candidate: String="fit-%d"%i
		if not library.any(func(entry):return entry.id==candidate):id=candidate;break
	library.append({"id":id,"hull":str(base.id),"name":name,"loadout":fit.loadout.duplicate(true)})
	state.fitTemplates=library
	return {"ok":true,"message":"Saved fitting knowledge. Installation still needs real parts and paid labor.","id":id}

static func delete_template(state: Dictionary,id: String) -> Dictionary:
	var error: String=_library_error(state.get("fitTemplates",[]))
	if not error.is_empty():return _no(error)
	var library: Array=template_list(state)
	for i in range(library.size()):
		if library[i].id==id:
			library.remove_at(i);state.fitTemplates=library
			return {"ok":true,"message":"Removed fitting knowledge. Equipment and purses are unchanged.","id":id}
	return _no("That fitting template is not in the library.")

static func _spec(state: Dictionary,ship: Dictionary,base: Dictionary,fit: Dictionary) -> Dictionary:
	var result: Dictionary=Identity.effective(ship,Refits.effective_spec(base,fit))
	var morale: float=clampf(Refits._number(state.get("morale"),85.0)/85.0,0.35,1.0)
	result.speed=float(result.speed)*morale
	result.fireRate=float(result.fireRate)*morale
	for mount in result.get("weaponMounts",[]):mount.fireRate=float(mount.fireRate)*morale
	return result

static func _empty_quote() -> Dictionary:
	return {"ok":false,"message":"","validDraft":false,"affordable":false,"applicable":false,"cost":0,"materials":{},"materialPrices":{},"materialCost":0,"workerWages":0,"expertWages":0,"tax":0,"margin":0,"businessIncome":0,"workerDays":0.0,"expertDays":0.0,"changes":[],"returns":{},"lockerAfter":{},"beforeSpec":{},"afterSpec":{},"newSpec":{},"beforeLoadout":{},"newLoadout":{},"usedPoints":0,"maxPoints":0,"reserve":{},"reasons":[],"quoteId":"","deploymentLimit":Deployment.LIMIT}

static func _reserve_info(state: Dictionary,before: Dictionary,after: Dictionary,coins: int) -> Dictionary:
	return {"before":before,"after":after,"afterCoins":coins,"arrears":int(state.get("wageArrears",0)),"debt":int(state.get("debt",0)),"dailyWages":after.dailyWages,"returnWages":after.returnWages,"shortfall":maxi(0,int(after.returnWages)+int(state.get("wageArrears",0))-coins),"basis":"Two-day harbor contingency allowance; no onward route selected."}

static func _refuse(q: Dictionary,message: String) -> Dictionary:
	q.reasons.append(message);q.message=message
	q.ok=false;q.applicable=false
	return {"quote":q}

static func _signature(core,ship: Dictionary,dock: Dictionary,fit: Dictionary) -> String:
	# Include every input affecting the displayed fit, custody, bill and reserve.
	# Money/log/template edits elsewhere cannot silently amend a reviewed bill.
	var inputs: Dictionary={"ship":ship,"base":core.hull(str(ship.get("type",""))),"port":dock,"fit":fit,"scale":core.data.get("CAMPAIGN_SCALE",1)}
	for key in ["coins","coinSupply","crewPurse","wageArrears","debt","morale","day","econDay","position","path","relationships","fleet","cargo","specialists","tooling","freight","voyageJobs","regionalCrises","passengerTransport","captiveBerths"]:
		inputs[key]=core.state.get(key)
	return JSON.stringify(inputs,"",true,true).sha256_text()

static func _plan(core,uid: String,loadout: Dictionary) -> Dictionary:
	var q: Dictionary=_empty_quote()
	var ship: Dictionary=core.find_boat(uid)
	if ship.is_empty() or ship.get("sunk",false):return _refuse(q,"Choose a living boat in your flotilla.")
	var owned_index: int=-1
	for i in range(core.state.get("fleet",[]).size()):
		if is_same(core.state.fleet[i],ship):owned_index=i;break
	if owned_index<0:return _refuse(q,"That boat is not in your flotilla.")
	var base: Dictionary=core.hull(str(ship.get("type","")))
	if base.is_empty():return _refuse(q,"The hull is not in the current catalogue.")
	var before: Dictionary=Refits.normalize(base,ship.get("loadout",{})) if ship.get("loadout",{}) is Dictionary else _no("Malformed installed fitting.")
	if not before.ok:return _refuse(q,str(before.message))
	q.beforeLoadout=before.loadout.duplicate(true)
	q.beforeSpec=_spec(core.state,ship,base,before.loadout)
	var old_reserve: Dictionary=Expedition.report(core.state,core.data)
	q.reserve=_reserve_info(core.state,old_reserve,old_reserve.duplicate(true),int(Refits._number(core.state.get("coins"))))
	q.maxPoints=before.maxPoints
	var fit: Dictionary=Refits.normalize(base,loadout)
	q.usedPoints=fit.get("usedPoints",0);q.maxPoints=fit.get("maxPoints",q.maxPoints)
	q.newLoadout=fit.get("loadout",loadout).duplicate(true)
	if not fit.ok:return _refuse(q,str(fit.message))
	q.validDraft=true
	q.afterSpec=_spec(core.state,ship,base,fit.loadout)
	q.newSpec=q.afterSpec.duplicate(true)
	var stored: Dictionary=Refits._locker(ship.get("refitLocker",{}))
	if not stored.ok:return _refuse(q,str(stored.message))
	var pool: Dictionary=stored.locker.duplicate(true)
	var removed: Dictionary={}
	var slots: Array=[]
	for i in range(before.loadout.weapons.size()):slots.append("weapon:%d"%i)
	slots.append_array(["engine","armor"])
	var sockets: Array=Refits.hardpoints(base)
	for slot in slots:
		var old: Dictionary=Refits._slot(before.loadout,slot)
		var next: Dictionary=Refits._slot(fit.loadout,slot)
		if old.old==next.old:continue
		var id: String=str(old.old)
		var label: String="Propulsion" if slot=="engine" else "Hull protection"
		if old.index>=0:label="%d · %s"%[old.index+1,str(sockets[old.index].label)]
		q.changes.append({"slot":slot,"socketId":str(sockets[old.index].id) if old.index>=0 else slot,"label":label,"group":old.group,"oldModule":id,"moduleId":str(next.old)})
		if not id.is_empty():
			pool[id]=int(pool.get(id,0))+1
			q.returns[id]=int(q.returns.get(id,0))+1
			removed[id]=int(removed.get(id,0))+1
	# Every removal is in the pool BEFORE any destination consumes an item.
	var dock: Dictionary=core.current_port()
	var pricing_port: Dictionary=dock
	if not dock.get("stocks",{}) is Dictionary:
		pricing_port=dock.duplicate(true);pricing_port.stocks={}
	for change in q.changes:
		var id: String=change.moduleId
		var have: bool=not id.is_empty() and int(pool.get(id,0))>0
		change.source="yard"
		if id.is_empty():change.source="removal"
		elif have:
			change.source="moved" if int(removed.get(id,0))>0 else "locker"
			removed[id]=maxi(0,int(removed.get(id,0))-1)
			pool[id]-=1
			if pool[id]==0:pool.erase(id)
		var bill: Dictionary=Refits.fitting_bill(pricing_port,base,change.group,change.oldModule,id,have)
		change.bill=bill;change.fromLocker=have
		for key in BILL_COINS:q[key]+=int(bill[key])
		q.workerDays+=float(bill.workerDays);q.expertDays+=float(bill.expertDays)
		for good in bill.materials:
			q.materials[good]=float(q.materials.get(good,0.0))+float(bill.materials[good])
			q.materialPrices[good]=bill.materialPrices[good]
	q.lockerAfter=pool.duplicate(true)
	var checked_locker: Dictionary=Refits._locker(pool)
	if not checked_locker.ok:q.reasons.append(str(checked_locker.message))
	q.affordable=Refits._whole(core.state.get("coins")) and float(core.state.coins)>=q.cost
	var probe: Dictionary=ship.duplicate(true)
	probe.loadout=fit.loadout.duplicate(true);probe.refitLocker=pool.duplicate(true)
	# Only copied dictionaries are normalized. Hull damage/stores/crew stay intact.
	Refits.ensure(probe,base)
	probe.spec=q.afterSpec.duplicate(true)
	probe.economyFactor=clampf(Refits._number(core.state.get("morale"),85.0)/85.0,0.35,1.0)
	var staged: Dictionary=core.state.duplicate(true)
	staged.fleet[owned_index]=probe
	staged.coins=maxi(0,int(Refits._number(core.state.get("coins")))-int(q.cost))
	var next_reserve: Dictionary=Expedition.report(staged,core.data)
	q.reserve=_reserve_info(core.state,old_reserve,next_reserve,int(staged.coins))
	q.fleetPointsBefore=Deployment.total(core.state.fleet.filter(func(b):return not b.get("sunk",false)))
	q.fleetPointsAfter=q.fleetPointsBefore-Deployment.cost(ship)+Deployment.cost(probe)
	q.deploymentLimit=Deployment.LIMIT
	q.quoteId=_signature(core,ship,dock,fit.loadout)
	if Refits.opaque_condition(ship) and not q.changes.is_empty():q.reasons.append("The yard cannot safely transfer this boat's equipment. Keep its current fitting.")
	if dock.is_empty() or not core.state.get("path",[]).is_empty():
		q.reasons.append("Dock and stop at a harbor to pay for fitting work.")
	elif not str(ship.get("storedPort","")).is_empty() and ship.storedPort!=dock.get("id",""):
		q.reasons.append("Visit the harbor storing this hull before refitting it.")
	else:
		if not core.state.get("ports",[]).any(func(p):return is_same(p,dock)):q.reasons.append("The fitting yard must be an actual harbor in this campaign.")
		var permission_state: Dictionary=core.state.duplicate(true)
		var view: PermissionView=PermissionView.new(permission_state,core.data,dock.duplicate(true))
		var advanced: bool=q.changes.any(func(change):return change.moduleId in ADVANCED)
		var permission: Dictionary=Politics.permit(view,"military" if advanced else "service")
		q.permission=permission.duplicate(true)
		if not permission.ok:q.reasons.append(str(permission.message))
		if not dock.get("stocks") is Dictionary:
			q.reasons.append("The harbor needs physical material stocks.")
		else:
			q.materialAvailability={}
			for good in q.materials:
				var available: float=Refits._number(dock.stocks.get(good),-1.0)
				q.materialAvailability[good]=available
				if available+EPS<float(q.materials[good]):q.reasons.append("The shared yard lacks physical %s: %.2f needed, %.2f available."%[good,float(q.materials[good]),maxf(0,available)])
		var workforce: Dictionary=Refits._workforce(dock)
		q.workforce=workforce
		if workforce.free+EPS<q.workerDays+q.expertDays or workforce.freeExperts+EPS<q.expertDays:q.reasons.append("The shared yard lacks available ordinary workers or specialists for the whole fitting today.")
		var receipts: Dictionary={"cash":q.businessIncome,"householdPurse":q.workerWages,"expertPurse":q.expertWages,"governmentPurse":q.tax}
		for key in receipts:
			if not Refits._whole(dock.get(key,0)) or Refits._number(dock.get(key,0))+float(receipts[key])>Refits.MAX_COINS:q.reasons.append("The harbor coin ledger is invalid or full.");break
	if not q.affordable:q.reasons.append("The whole fitting needs %d coins; your purse has %d."%[q.cost,int(Refits._number(core.state.get("coins")))])
	if core.state.has("coinSupply") and (not Refits._whole(core.state.coinSupply) or Money.total(core.state)!=int(core.state.coinSupply)):q.reasons.append("The existing coin ledger must reconcile before fitting.")
	if float(next_reserve.overload)>float(old_reserve.overload)+EPS:q.reasons.append("This fitting would overflow the traveling holds with existing stores. Offload the excess first.")
	q.applicable=q.reasons.is_empty();q.ok=q.applicable
	q.message="Whole fitting: %d coins; %d changed slots."%[q.cost,q.changes.size()] if q.ok else str(q.reasons[0])
	Manifest.allocate(staged)
	return {"quote":q,"ship":probe,"port":dock,"manifest":staged.get("cargoManifest",{})}

static func preview(core,uid: String,loadout: Dictionary) -> Dictionary:
	return _plan(core,uid,loadout).quote

static func apply(core,uid: String,loadout: Dictionary,expected_quote: Dictionary={}) -> Dictionary:
	var plan: Dictionary=_plan(core,uid,loadout)
	var q: Dictionary=plan.quote
	if not expected_quote.is_empty() and (str(expected_quote.get("quoteId","")).is_empty() or str(expected_quote.quoteId)!=str(q.quoteId)):
		q.ok=false;q.applicable=false;q.message="This fitting quote is stale. Review the current bill before applying it."
		return q
	if not q.ok:return q
	if q.changes.is_empty():
		q.message="This fitting is already installed.";q.changed=false
		return q
	var ship: Dictionary=core.find_boat(uid)
	var dock: Dictionary=plan.port
	var next_port: Dictionary=dock.duplicate(true)
	var wallet: Dictionary={"coins":int(core.state.coins)}
	var ledger: Array=core.state.get("moneyLog",[]).duplicate(true)
	for payment in [["cash",q.businessIncome,"Workshop parts and yard margin"],["householdPurse",q.workerWages,"Workshop shipwright wages"],["expertPurse",q.expertWages,"Workshop engineer wages"],["governmentPurse",q.tax,"Workshop fitting duty"]]:
		if not Money.move(wallet,"coins",next_port,payment[0],int(payment[1]),payment[2],ledger):return _no("The fitting payment could not be reconciled.")
	for good in q.materials:next_port.stocks[good]=maxf(0.0,float(next_port.stocks[good])-float(q.materials[good]))
	var workforce: Dictionary=Refits._workforce(dock)
	next_port._yardWorkersUsed=workforce.used;next_port._yardSpecialistsUsed=workforce.expertsUsed
	next_port._yardOrdinaryUsed=maxf(Refits._number(dock.get("_yardOrdinaryUsed")),Refits._number(dock.get("yardOrdinaryReserved")))
	Construction._record_yard_reservation(next_port,workforce.total,workforce.specialists,q.workerDays+q.expertDays,q.workerDays,q.expertDays)
	if int(wallet.coins)+Money.port_total(next_port)!=int(core.state.coins)+Money.port_total(dock):return _no("The fitting bill could not be reconciled. Nothing changed.")
	# No failure path follows. Preserve canonical state, harbor, stocks and hull refs.
	core.state.coins=wallet.coins;core.state.moneyLog=ledger
	for key in ["cash","householdPurse","expertPurse","governmentPurse"]:dock[key]=next_port[key]
	for good in q.materials:dock.stocks[good]=next_port.stocks[good]
	for key in YARD_KEYS:dock[key]=next_port[key]
	for key in ["baseSpec","loadout","refitLocker","spec","maxHp","hp","armor","economyFactor"]:ship[key]=plan.ship[key]
	core.state.cargoManifest=plan.manifest
	q.changed=true;q.message="Applied the reviewed fitting for %d coins. Removed modules remain exactly once in this boat's locker or new sockets."%q.cost
	return q
