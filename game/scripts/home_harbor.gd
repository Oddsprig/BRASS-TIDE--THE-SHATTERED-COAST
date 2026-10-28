extends RefCounted
## v0.017 home harbor: warehouse/rented berth and chartered salvage-yard /
## repair-workshop businesses at EXISTING ports, as plain state["businesses"]
## records with own inventory, own integer coins purse, real employees taken
## from the home port pool, and a working-capital reserve. Nothing is minted.
## Root adds business.coins to Money.total / the save schema and layers
## Factions checks over the docked + surveyed-site gates enforced here.

const Goods = preload("res://scripts/goods.gd")
const Money = preload("res://scripts/money.gd")
const Economy = preload("res://scripts/economy.gd")

const MAX_BUSINESSES := 12
const RESERVE_DAYS := 14
const NAMES := ["Ana Breg", "Piet Lorn", "Salla Miro", "Jonas Teek", "Ruth Calder", "Emre Vail", "Nils Ostro", "Faye Marlin"]

# employees: occupation -> headcount at Goods.WAGES. 150+/day occupations
# use the port specialist pool and expert purse; the rest are household.
const KINDS := {
	"warehouse": {"name": "Warehouse & Rented Berth", "capacity": 400.0,
		"materials": {"timber": 4.0, "logs": 3.0, "iron": 1.0},
		"setupLabor": {"laborer": 6.0, "foreman": 1.0},
		"employees": {"laborer": 2}, "inputCapital": 500, "charterSites": []},
	"salvage_yard": {"name": "Chartered Salvage Yard", "capacity": 600.0,
		"materials": {"timber": 6.0, "iron": 3.0, "supplies": 2.0},
		"setupLabor": {"laborer": 8.0, "mechanic": 2.0},
		"employees": {"laborer": 3, "mechanic": 1}, "inputCapital": 1500,
		"charterSites": ["rust_salvage_anchorage", "shatter_wreck_field"]},
	"workshop": {"name": "Chartered Repair Workshop", "capacity": 300.0,
		"materials": {"timber": 5.0, "iron": 2.0, "copper": 1.0, "supplies": 1.0},
		"setupLabor": {"carpenter": 6.0, "engineer": 1.0},
		"employees": {"carpenter": 3, "mechanic": 1}, "inputCapital": 1500,
		"charterSites": ["cinder_workshop_ruin"]},
}
const KIND_ALIASES := {"rented_berth": "warehouse", "berth": "warehouse",
	"repair_workshop": "workshop", "repair": "workshop", "salvage": "salvage_yard"}
const IN_DIRECTIONS := ["in", "store", "to_business", "deposit", "unload"]
const OUT_DIRECTIONS := ["out", "load", "to_fleet", "withdraw", "take"]


static func _is_num(v) -> bool:
	return (v is int or v is float) and is_finite(float(v))


static func _num(v, fallback: float = 0.0) -> float:
	return float(v) if _is_num(v) else fallback


static func _round2(v: float) -> float:
	return snappedf(v, 0.01)


static func _fail(core, message: String) -> Dictionary:
	return core.fail(message) if core != null and core.has_method("fail") else {"ok": false, "message": message}


static func _ok(core, message: String, extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = core.ok(message) if core != null and core.has_method("ok") else {"ok": true, "message": message}
	out.merge(extra, true)
	return out


static func _kind(kind: String) -> String:
	var k := kind.strip_edges().to_lower()
	return str(KIND_ALIASES.get(k, k))


static func _state(core) -> Dictionary:
	return core.state if core != null and core.get("state") is Dictionary else {}


static func _port(core, state: Dictionary, port_id: String) -> Dictionary:
	if core != null and core.has_method("port"):
		var found: Dictionary = core.port(port_id)
		if not found.is_empty():
			return found
	for p in state.get("ports", []) if state.get("ports") is Array else []:
		if p is Dictionary and str(p.get("id", "")) == port_id:
			return p
	return {}


static func _docked_port(core) -> Dictionary:
	return core.current_port() if core != null and core.has_method("current_port") else {}


static func _business(state: Dictionary, business_id: String) -> Dictionary:
	for b in state.get("businesses", []) if state.get("businesses") is Array else []:
		if b is Dictionary and str(b.get("id", "")) == business_id:
			return b
	return {}


static func _surveyed_site(state: Dictionary, site_ids: Array) -> String:
	var ex: Dictionary = state.get("exploration", {}) if state.get("exploration") is Dictionary else {}
	var sites: Dictionary = ex.get("sites", {}) if ex.get("sites") is Dictionary else {}
	for site_id in site_ids:
		var rec = sites.get(str(site_id), null)
		if rec is Dictionary and int(_num(rec.get("level", 0))) >= 3:
			return str(site_id)
	return ""


static func _daily_wages(employees: Array) -> Dictionary:
	var household := 0
	var expert := 0
	for e in employees:
		if e is Dictionary:
			if bool(e.get("specialist", false)):
				expert += int(_num(e.get("wage", 0)))
			else:
				household += int(_num(e.get("wage", 0)))
	return {"household": household, "expert": expert, "total": household + expert}


static func _reserve(business: Dictionary) -> int:
	var wages := _daily_wages(business.get("employees", []) if business.get("employees") is Array else [])
	return RESERVE_DAYS * int(wages["total"]) + maxi(0, int(_num(business.get("workingCapital", 0))))


static func _inventory_weight(inventory: Dictionary) -> float:
	var total := 0.0
	for good in inventory:
		if Goods.ITEMS.has(str(good)):
			total += maxf(0.0, _num(inventory[good])) * float(Goods.ITEMS[str(good)]["weight"])
	return _round2(total)


static func _clean_inventory(raw) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for good in raw:
			if Goods.ITEMS.has(str(good)):
				out[str(good)] = _round2(maxf(0.0, _num(raw[good])))
	return out


# Normalizes state["businesses"]/["businessSeq"] IN PLACE (live references
# stay valid). Unknown kinds / id-less records drop; tallies clamp >= 0.
static func ensure(state: Dictionary) -> Array:
	if not (state.get("businesses") is Array):
		state["businesses"] = []
	var cleaned: Array = []
	var max_suffix := 0
	for raw in state["businesses"]:
		if not (raw is Dictionary) or str(raw.get("id", "")).is_empty():
			continue
		var kind := _kind(str(raw.get("kind", "")))
		if not KINDS.has(kind) or cleaned.any(func(b): return str(b["id"]) == str(raw["id"])):
			continue
		var spec: Dictionary = KINDS[kind]
		var employees: Array = []
		for e in raw.get("employees", []) if raw.get("employees") is Array else []:
			if e is Dictionary and Goods.WAGES.has(str(e.get("occupation", ""))):
				var occ := str(e["occupation"])
				e["name"] = str(e.get("name", "Worker"))
				e["wage"] = int(Goods.WAGES[occ])
				e["specialist"] = int(Goods.WAGES[occ]) >= 150
				employees.append(e)
		raw["id"] = str(raw["id"])
		raw["kind"] = kind
		raw["name"] = str(raw.get("name", spec["name"]))
		raw["homePort"] = str(raw.get("homePort", ""))
		raw["charterSite"] = str(raw.get("charterSite", ""))
		raw["coins"] = maxi(0, int(_num(raw.get("coins", 0))))
		raw["inventory"] = _clean_inventory(raw.get("inventory", {}))
		raw["inventoryBasis"]=_clean_inventory(raw.get("inventoryBasis",{}))
		raw["autoSell"]=bool(raw.get("autoSell",true))
		raw["capacity"] = float(spec["capacity"])
		raw["employees"] = employees
		raw["dailyWages"]=int(_daily_wages(employees).total)
		raw["workingCapital"] = maxi(0, int(_num(raw.get("workingCapital", spec["inputCapital"]))))
		for key in ["capitalIn", "revenue", "wagesPaid", "dividendsPaid", "arrearsHousehold", "arrearsExpert", "costOfSales", "otherExpenses", "inKindCapital", "inKindReturned"]:
			raw[key] = maxi(0, int(_num(raw.get(key, 0))))
		raw["paused"] = bool(raw.get("paused", false))
		raw["establishedDay"] = _num(raw.get("establishedDay", 0.0))
		cleaned.append(raw)
		var tail := str(raw["id"]).trim_prefix("business-")
		if tail.is_valid_int():
			max_suffix = maxi(max_suffix, int(tail))
		if cleaned.size() >= MAX_BUSINESSES:
			break
	state["businesses"] = cleaned
	state["businessSeq"] = maxi(int(_num(state.get("businessSeq", 0))), max_suffix)
	return cleaned


static func list_businesses(state: Dictionary) -> Array:
	var out: Array = []
	for b in ensure(state):
		var row: Dictionary = (b as Dictionary).duplicate(true)
		row["dailyWages"] = int(_daily_wages(row["employees"])["total"])
		row["reserve"] = _reserve(b)
		row["storedWeight"] = _inventory_weight(b["inventory"])
		out.append(row)
	return out


# Raw optional work receipts: never reconstruct working days from money paid.
# Called by campaign validation BEFORE any normalizing ensure on loaded state.
static func validate(state: Dictionary) -> String:
	for b in state.get("businesses", []) if state.get("businesses") is Array else []:
		if not b is Dictionary:continue # Existing business schema checks this record.
		if b.has("paidWorkDays") != b.has("lastPaidWorkDay"):return "Incomplete business work-day receipt."
		if not b.has("paidWorkDays"):continue
		for key in ["paidWorkDays", "lastPaidWorkDay"]:
			var value: Variant=b[key]
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or floorf(float(value))!=float(value):return "Invalid business work-day receipt."
		var count: float=float(b.paidWorkDays)
		var stamp: float=float(b.lastPaidWorkDay)
		var published: float=_num(state.get("econDay",0))
		if count<0 or count>1000000000 or stamp< -1 or stamp>minf(1000000000,published):return "Business work-day receipt exceeds published days."
		if (count==0 and stamp!= -1) or (count>0 and (stamp<1 or count>stamp)):return "Inconsistent business work-day receipt."
	return ""


static func _staffed(business: Dictionary) -> bool:
	var kind: String=_kind(str(business.get("kind","")))
	if not KINDS.has(kind):return false
	var roster: Dictionary={}
	for e in business.get("employees",[]) if business.get("employees") is Array else []:
		if not e is Dictionary or not Goods.WAGES.has(str(e.get("occupation",""))) or int(_num(e.get("wage",0)))<=0:return false
		var occupation: String=str(e.occupation)
		roster[occupation]=int(roster.get(occupation,0))+1
	if roster.is_empty():return false
	var required: Dictionary=KINDS[kind].employees
	if kind=="workshop":
		var good: String=str(business.get("recipeGood","supplies"))
		if not Goods.ITEMS.has(good):return false
		# Workshops already support paid changes of recipe and actual trades.
		for occupation in Goods.ITEMS[good].labor:
			if int(roster.get(occupation,0))<1:return false
		return true
	for occupation in required:
		if int(roster.get(occupation,0))<int(required[occupation]):return false
	return true


# Owned books only. No live normalization, economic step, quote or remote stocks.
static func business_view(state: Dictionary, business_id: String) -> Dictionary:
	var actual: Dictionary=_business(state,business_id)
	if actual.is_empty():return {}
	var row: Dictionary=actual.duplicate(true)
	var employees: Array=row.get("employees",[]) if row.get("employees") is Array else []
	var inventory: Dictionary=row.get("inventory",{}) if row.get("inventory") is Dictionary else {}
	var labor: Dictionary=row.get("labor",{}) if row.get("labor") is Dictionary else {}
	row.dailyWages=int(_daily_wages(employees).total)
	row.reserve=_reserve(row);row.storedWeight=_inventory_weight(inventory)
	row.paidWorkDays=int(row.get("paidWorkDays",0));row.lastPaidWorkDay=int(row.get("lastPaidWorkDay",-1))
	row.staffed=_staffed(row)
	row.arrears=int(row.get("arrearsHousehold",0))+int(row.get("arrearsExpert",0))
	row.payrollShortfall=maxi(0,int(row.arrears)+int(row.dailyWages)-int(row.get("coins",0)))
	row.laborNotice=str(labor.get("notice","No published labor shift."))
	var published: int=int(state.get("econDay",0))
	# During the authoritative daily step the receipt is one ahead of econDay;
	# after that step, econDay publishes it. Older shifts remain dated history.
	row.working=bool(row.staffed) and int(row.arrears)==0 and not bool(row.get("paused",false)) and int(row.paidWorkDays)>0 and int(row.lastPaidWorkDay)==int(labor.get("lastProcessedEconomicDay",-1)) and int(row.lastPaidWorkDay)>=published and int(row.lastPaidWorkDay)<=published+1 and float(row.get("workFactor",0))>0
	row.stallReason="";row.resumeReason="Continue funding actual daily payroll; later work days require published working shifts."
	if _port(null,state,str(row.get("homePort",""))).is_empty():
		row.working=false;row.stallReason="No existing home harbor; work is paused."
		row.resumeReason="A real home harbor is required; no goods or staff are supplied automatically."
	elif not row.staffed:
		row.stallReason="The recorded workforce lacks the required staff or recipe trades."
		row.resumeReason="Use existing paid staffing and a supported recipe before a later working shift."
	elif int(row.arrears)>0:
		row.stallReason="Payroll arrears: %d coins. %s"%[int(row.arrears),str(row.laborNotice)]
		row.resumeReason="Business needs %d more coins for arrears plus next base payroll; any stoppage still needs home negotiation and paid rest."%int(row.payrollShortfall)
	elif bool(labor.get("striking",false)):
		row.working=false;row.stallReason=str(row.laborNotice)
	elif str(labor.get("policy","normal"))=="rest":
		row.working=false;row.stallReason="Paid rest does not add a working day. "+str(row.laborNotice)
		row.resumeReason="Choose a working policy and fund a later actual shift after required recovery."
	elif not row.working:
		row.stallReason="No qualifying paid working shift has been published. "+str(row.laborNotice)
		row.resumeReason="Fund the next published whole business day; capital and wage debt payments are not extra work days."
	if bool(labor.get("striking",false)):
		if bool(labor.get("agreed",false)):
			row.resumeReason="Agreement already paid; %d recorded paid rest days remain, then recovery still needs fatigue <=60 and unrest <=50. Base payroll remains %d coins/day."%[int(labor.get("restDays",0)),int(row.dailyWages)]
		else:
			var negotiation: int=int(row.arrears)+ceili(float(Goods.WAGES.laborer)/4)+ceili(float(Goods.WAGES.foreman)/4)
			row.resumeReason="At home, existing negotiation needs %d business coins within its policy cap, %d owned food and one repair-kit lot, followed by two later paid rest days."%[negotiation,maxi(1,employees.size())]
	row.materials=[];row.materialsReady=true
	row.productionReason="Storage and berth service; no production recipe." if str(row.get("kind",""))=="warehouse" else "Only owned stored salvage can be sold; no wrecks or goods are created."
	if str(row.get("kind",""))=="workshop":
		var good: String=str(row.get("recipeGood","supplies"))
		if not Goods.ITEMS.has(good):
			row.materialsReady=false;row.productionReason="No supported workshop recipe."
		else:
			var recipe: Dictionary=Goods.ITEMS[good]
			var shortages: Array[String]=[]
			var next_weight: float=float(row.storedWeight)+float(recipe.weight)
			for ingredient in recipe.inputs:
				var need: float=float(recipe.inputs[ingredient])
				var held: float=_num(inventory.get(ingredient,0))
				var shortfall: float=maxf(0,need-held)
				row.materials.append({"good":str(ingredient),"held":held,"perLot":need,"shortfall":shortfall})
				next_weight-=need*float(Goods.ITEMS[ingredient].weight)
				if shortfall>0.000001:shortages.append("%.2f %s"%[shortfall,str(Goods.ITEMS[ingredient].name)])
			row.materialsReady=shortages.is_empty()
			if not shortages.is_empty():row.productionReason="Next lot lacks owned inputs: "+", ".join(shortages)+". Deposit actual cargo at home; payroll still costs coins."
			elif next_weight>float(row.get("capacity",0))+0.000001:row.productionReason="Store has no room for the next output lot; load or sell actual stock."
			elif not row.staffed:row.productionReason="The recipe lacks an actual required trade; paid staffing must supply it."
			else:row.productionReason="Stored inputs support a lot; output still requires actual paid recipe labor."
	return row


# Read-only quote. Needs docking at that existing port; charters also need
# their relevant site surveyed (level 3). Bill: port materials at Economy
# prices + setup wage-days + 8% margin + 5% duty + opening-float deposit.
static func quote(core, kind: String, port_id: String) -> Dictionary:
	var state := _state(core)
	if state.is_empty():
		return _fail(core, "No campaign state.")
	var permission: Dictionary=preload("res://scripts/politics.gd").permit(core,"service")
	if not permission.ok:return permission
	var k := _kind(kind)
	if not KINDS.has(k):
		return _fail(core, "Unknown home-harbor business kind.")
	var port := _port(core, state, port_id)
	if port.is_empty() or not (port.get("stocks") is Dictionary):
		return _fail(core, "That is not an existing harbor with physical stocks.")
	var docked := _docked_port(core)
	if docked.is_empty() or str(docked.get("id", "")) != port_id:
		return _fail(core, "Establish a home-harbor business while docked at that harbor.")
	var spec: Dictionary = KINDS[k]
	var charter_sites: Array = spec["charterSites"]
	var surveyed := _surveyed_site(state, charter_sites)
	if not charter_sites.is_empty() and surveyed.is_empty():
		var needed := "a surveyed salvage anchorage or wreck field" if k == "salvage_yard" else "the Cinder Crown Workshop Ruin surveyed"
		return _fail(core, "This charter needs %s first." % needed)
	var rights: Dictionary=state.get("storyRights",{})
	if k=="workshop" and not rights.get("workshopCharter",false):return _fail(core,"Back Mara's charter in The Cold Workshop story first.")
	if k=="salvage_yard" and not rights.get("openField",false) and not rights.get("privateField",false):return _fail(core,"Register a public or private field claim in The Middle Sea Chart story first.")
	if k=="salvage_yard" and rights.get("privateField",false) and str(port.faction)!="raiders":return _fail(core,"The private salvage charter is registered through a Reef harbor. Public claims can establish legal cooperative yards elsewhere.")
	var businesses: Array = state.get("businesses", []) if state.get("businesses") is Array else []
	if businesses.size() >= MAX_BUSINESSES:
		return _fail(core, "The flotilla already runs as many shore businesses as it can manage.")
	for b in businesses:
		if b is Dictionary and _kind(str(b.get("kind", ""))) == k and str(b.get("homePort", "")) == port_id:
			return _fail(core, "You already run a %s at this harbor." % str(spec["name"]))
	var materials: Dictionary = (spec["materials"] as Dictionary).duplicate(true)
	var prices := {}
	var material_cost := 0
	for good in materials:
		prices[good] = Economy.price(port, str(good))
		material_cost += ceili(float(materials[good]) * float(prices[good]))
		if _num(port["stocks"].get(good, 0.0)) + 0.000001 < float(materials[good]):
			return _fail(core, "The harbor lacks physical %s for the setup." % str(Goods.ITEMS[str(good)]["name"]))
	var setup_ordinary_days := 0.0
	var setup_expert_days := 0.0
	var setup_ordinary_wages := 0
	var setup_expert_wages := 0
	for occ in spec["setupLabor"]:
		var days := float(spec["setupLabor"][occ])
		var pay := ceili(days * float(Goods.WAGES[str(occ)]))
		if int(Goods.WAGES[str(occ)]) >= 150:
			setup_expert_days += days
			setup_expert_wages += pay
		else:
			setup_ordinary_days += days
			setup_ordinary_wages += pay
	var staff: Array = []
	var staff_total := 0
	var staff_experts := 0
	var daily := 0
	for occ in spec["employees"]:
		var count := int(spec["employees"][occ])
		var wage := int(Goods.WAGES[str(occ)])
		staff.append({"occupation": str(occ), "count": count, "wage": wage, "specialist": wage >= 150})
		staff_total += count
		daily += count * wage
		if wage >= 150:
			staff_experts += count
	var free_workers := maxf(0.0, _num(port.get("availableWorkers", port.get("workforce", 0))) - _num(port.get("_yardWorkersUsed", 0)))
	var free_experts := maxf(0.0, _num(port.get("availableSpecialists", port.get("specialistWorkers", 0))) - _num(port.get("_yardSpecialistsUsed", 0)))
	if int(_num(port.get("workforce", 0))) < staff_total or free_workers + 0.000001 < ceilf(setup_ordinary_days + setup_expert_days) + float(staff_total):
		return _fail(core, "This harbor has no available workforce to spare for setup and staff.")
	if free_experts + 0.000001 < ceilf(setup_expert_days) + float(staff_experts):
		return _fail(core, "This harbor has no free specialists to spare for setup and staff.")
	var subtotal := material_cost + setup_ordinary_wages + setup_expert_wages
	var margin := ceili(subtotal * 0.08)
	var duty := ceili(subtotal * 0.05)
	var setup_cost := subtotal + margin + duty
	var deposit := RESERVE_DAYS * daily + int(spec["inputCapital"])
	var q := {"ok": true, "kind": k, "kindName": str(spec["name"]), "portId": port_id,
		"charterSite": surveyed, "capacity": float(spec["capacity"]),
		"materials": materials, "materialPrices": prices, "materialCost": material_cost,
		"setupOrdinaryDays": setup_ordinary_days, "setupExpertDays": setup_expert_days,
		"setupOrdinaryWages": setup_ordinary_wages, "setupExpertWages": setup_expert_wages,
		"margin": margin, "duty": duty, "setupCost": setup_cost,
		"workingCapitalDeposit": deposit, "inputCapital": int(spec["inputCapital"]),
		"cost": setup_cost + deposit, "staff": staff, "staffTotal": staff_total,
		"staffExperts": staff_experts, "dailyWages": daily, "reserve": deposit,
		"affordable": int(_num(state.get("coins", 0))) >= setup_cost + deposit,
		"message": "%s at %s: %d coins setup plus %d working capital." % [str(spec["name"]), str(port.get("name", port_id)), setup_cost, deposit]}
	return q


# Atomic: refusals precede writes. Materials leave port stocks, setup coins
# split to port purses, deposit moves captain -> business, and staff leave
# the port workforce/recruits/specialists pools permanently.
static func establish(core, kind: String, port_id: String) -> Dictionary:
	var q := quote(core, kind, port_id)
	if not bool(q.get("ok", false)):
		return q
	var state := _state(core)
	ensure(state)
	if int(_num(state.get("coins", 0))) < int(q["cost"]):
		return _fail(core, "Establishing needs %d coins including working capital." % int(q["cost"]))
	var port := _port(core, state, port_id)
	state["businessSeq"] = int(state.get("businessSeq", 0)) + 1
	var seq := int(state["businessSeq"])
	var employees: Array = []
	var n := 0
	for row in q["staff"]:
		for i in range(int(row["count"])):
			employees.append({"id":"staff-%d-%d"%[seq,n],"name": NAMES[(seq * 7 + n) % NAMES.size()],
				"occupation": str(row["occupation"]), "wage": int(row["wage"]),
				"specialist": bool(row["specialist"])})
			n += 1
	var business := {"id": "business-%d" % seq, "kind": str(q["kind"]),
		"name": str(q["kindName"]), "homePort": port_id, "charterSite": str(q["charterSite"]),
		"coins": 0, "inventory": {},"inventoryBasis":{},"autoSell":true,"costOfSales":0,"inKindCapital":0,"inKindReturned":0, "capacity": float(q["capacity"]), "employees": employees,
		"workingCapital": int(q["inputCapital"]), "capitalIn": 0, "revenue": 0,
		"wagesPaid": 0, "dividendsPaid": 0, "arrearsHousehold": 0, "arrearsExpert": 0,
		"paidWorkDays": 0, "lastPaidWorkDay": -1,
		"paused": false, "establishedDay": _num(state.get("day", 0.0))}
	state["businesses"].append(business)
	var ledger: Array = state.get("moneyLog", []) if state.get("moneyLog") is Array else []
	Money.move(state, "coins", port, "cash", int(q["materialCost"]) + int(q["margin"]), "Home-harbor setup materials and margin", ledger)
	Money.move(state, "coins", port, "householdPurse", int(q["setupOrdinaryWages"]), "Home-harbor setup wages", ledger)
	Money.move(state, "coins", port, "expertPurse", int(q["setupExpertWages"]), "Home-harbor setup specialist wages", ledger)
	Money.move(state, "coins", port, "governmentPurse", int(q["duty"]), "Home-harbor charter duty", ledger)
	Money.move(state, "coins", business, "coins", int(q["workingCapitalDeposit"]), "Home-harbor working capital", ledger)
	business["capitalIn"] = int(q["workingCapitalDeposit"])
	state["moneyLog"] = ledger
	for good in q["materials"]:
		port["stocks"][good] = _round2(maxf(0.0, _num(port["stocks"].get(good, 0.0)) - float(q["materials"][good])))
	port["_yardWorkersUsed"] = _num(port.get("_yardWorkersUsed", 0)) + ceilf(float(q["setupOrdinaryDays"]) + float(q["setupExpertDays"]))
	port["_yardSpecialistsUsed"] = _num(port.get("_yardSpecialistsUsed", 0)) + ceilf(float(q["setupExpertDays"]))
	port["workforce"] = maxi(0, int(_num(port.get("workforce", 0))) - int(q["staffTotal"]))
	port["recruits"] = maxi(0, int(_num(port.get("recruits", 0))) - int(q["staffTotal"]))
	if int(q["staffExperts"]) > 0:
		port["specialists"] = maxi(0, int(_num(port.get("specialists", port.get("specialistWorkers", 0)))) - int(q["staffExperts"]))
		port["specialistWorkers"] = int(port["specialists"])
		port["availableSpecialists"] = maxi(0, int(_num(port.get("availableSpecialists", 0))) - int(q["staffExperts"]))
	Economy.sync_workforce(port)
	return _ok(core, "%s established at %s with %d staff and %d coins working capital." % [str(q["kindName"]), str(port.get("name", port_id)), int(q["staffTotal"]), int(q["workingCapitalDeposit"])],
		{"business": business.duplicate(true), "cost": int(q["cost"]), "setupCost": int(q["setupCost"])})


# Real goods state.cargo <-> business inventory, docked at home only.
# Stored weight is capacity-capped and never counts as traveling hold.
static func transfer_goods(core, business_id: String, good: String, qty: float, direction: String) -> Dictionary:
	var state := _state(core)
	if state.is_empty():
		return _fail(core, "No campaign state.")
	ensure(state)
	var business := _business(state, business_id)
	if business.is_empty():
		return _fail(core, "No such home-harbor business.")
	if not Goods.ITEMS.has(good):
		return _fail(core, "Unknown good.")
	var dir := direction.strip_edges().to_lower()
	if not (dir in IN_DIRECTIONS or dir in OUT_DIRECTIONS):
		return _fail(core, "Direction must be in or out.")
	if not is_finite(qty) or qty <= 0.0:
		return _fail(core, "Quantity must be positive.")
	var docked := _docked_port(core)
	if docked.is_empty() or str(docked.get("id", "")) != str(business["homePort"]):
		return _fail(core, "Move shore goods while docked at the business's home harbor.")
	var permission: Dictionary=preload("res://scripts/politics.gd").permit(core,"service")
	if not permission.ok:return permission
	var amount := _round2(qty)
	if amount<=0:return _fail(core,"Smallest storage lot is 0.01.")
	var weight := amount * float(Goods.ITEMS[good]["weight"])
	var cargo: Dictionary = state.get("cargo", {}) if state.get("cargo") is Dictionary else {}
	if dir in IN_DIRECTIONS:
		if _num(cargo.get(good, 0.0)) + 0.000001 < amount:
			return _fail(core, "The fleet hold does not carry that much %s." % str(Goods.ITEMS[good]["name"]))
		if _inventory_weight(business["inventory"]) + weight > float(business["capacity"]) + 0.000001:
			return _fail(core, "The %s store is full." % str(business["name"]))
		var basis: int=ceili(amount*float(Goods.cost(good)))
		business["inventoryBasis"][good]=float(business["inventoryBasis"].get(good,0))+basis
		business["inKindCapital"]+=basis
		cargo[good] = _round2(_num(cargo.get(good, 0.0)) - amount)
		business["inventory"][good] = _round2(_num(business["inventory"].get(good, 0.0)) + amount)
		state["cargo"] = cargo
		preload("res://scripts/hold_manifest.gd").allocate(state)
		return _ok(core, "Stored %s %s ashore." % [str(amount), str(Goods.ITEMS[good]["name"])], {"stored": float(business["inventory"][good])})
	if _num(business["inventory"].get(good, 0.0)) + 0.000001 < amount:
		return _fail(core, "The store does not hold that much %s." % str(Goods.ITEMS[good]["name"]))
	if core.has_method("cargo_weight") and core.has_method("capacity"):
		if float(core.cargo_weight()) + weight > float(core.capacity()) + 0.000001:
			return _fail(core, "The fleet hold cannot take that much more weight.")
	business["inKindReturned"]+=ceili(_take_basis(business,good,amount))
	business["inventory"][good] = _round2(_num(business["inventory"].get(good, 0.0)) - amount)
	cargo[good] = _round2(_num(cargo.get(good, 0.0)) + amount)
	state["cargo"] = cargo
	preload("res://scripts/hold_manifest.gd").allocate(state)
	return _ok(core, "Loaded %s %s from the shore store." % [str(amount), str(Goods.ITEMS[good]["name"])], {"stored": float(business["inventory"][good])})


# Captain -> business; counted as contributed capital, never dividendable.
static func capital(core, business_id: String, amount: int) -> Dictionary:
	var state := _state(core)
	if state.is_empty():
		return _fail(core, "No campaign state.")
	ensure(state)
	var business := _business(state, business_id)
	if business.is_empty():
		return _fail(core, "No such home-harbor business.")
	var docked: Dictionary=_docked_port(core)
	if docked.is_empty() or str(docked.id)!=str(business.homePort):return _fail(core,"Handle company coins at its home harbor.")
	var permission: Dictionary=preload("res://scripts/politics.gd").permit(core,"service")
	if not permission.ok:return permission
	if amount <= 0:
		return _fail(core, "Capital must be a positive coin amount.")
	var ledger: Array = state.get("moneyLog", []) if state.get("moneyLog") is Array else []
	if not Money.move(state, "coins", business, "coins", amount, "Home-harbor capital", ledger):
		return _fail(core, "The captain's purse cannot cover that capital.")
	state["moneyLog"] = ledger
	business["capitalIn"] = int(business["capitalIn"]) + amount
	return _ok(core, "Added %d coins of working capital." % amount, {"coins": int(business["coins"])})


# Business -> captain, capped by the 14-day wage + input reserve AND by
# earned surplus only (revenue - wagesPaid - dividendsPaid).
static func dividend(core, business_id: String, amount: int) -> Dictionary:
	var state := _state(core)
	if state.is_empty():
		return _fail(core, "No campaign state.")
	ensure(state)
	var business := _business(state, business_id)
	if business.is_empty():
		return _fail(core, "No such home-harbor business.")
	var docked: Dictionary=_docked_port(core)
	if docked.is_empty() or str(docked.id)!=str(business.homePort):return _fail(core,"Handle company coins at its home harbor.")
	var permission: Dictionary=preload("res://scripts/politics.gd").permit(core,"service")
	if not permission.ok:return permission
	if amount <= 0:
		return _fail(core, "A dividend must be a positive coin amount.")
	var earned := int(business["revenue"]) - int(business["wagesPaid"]) - int(business.get("costOfSales",0)) - int(business["dividendsPaid"]) - int(business.get("otherExpenses",0))
	var ceiling := maxi(0, mini(int(business["coins"]) - _reserve(business), earned))
	if amount > ceiling:
		return _fail(core, "Dividends are limited to %d earned coins above the 14-day reserve." % ceiling)
	var ledger: Array = state.get("moneyLog", []) if state.get("moneyLog") is Array else []
	if not Money.move(business, "coins", state, "coins", amount, "Home-harbor dividend", ledger):
		return _fail(core, "The business purse cannot cover that dividend.")
	state["moneyLog"] = ledger
	business["dividendsPaid"] = int(business["dividendsPaid"]) + amount
	return _ok(core, "Drew a %d-coin dividend." % amount, {"coins": int(business["coins"]), "maxDividend": ceiling - amount})


# Goods "supplies" recipe verbatim, limited by materials/labor/capacity.
static func _produce(business: Dictionary, days: float) -> int:
	var good: String=str(business.get("recipeGood","supplies"))
	var recipe: Dictionary=Goods.ITEMS[good]
	var inputs: Dictionary=recipe.inputs
	var labor: Dictionary=recipe.labor
	var throughput: float=1000000
	var factor: float=float(business.get("toolingFactor",1))
	var named_labor: String=str(business.get("toolingLabor",""))
	for occupation in labor:
		var worker_days: float=0
		for employee in business.employees:
			if str(employee.occupation)==str(occupation):worker_days+=days
		if str(occupation)==named_labor:worker_days*=factor
		throughput=minf(throughput,worker_days/float(labor[occupation]))
	if throughput<=0:return 0
	var material_cap: int=1000000
	for ingredient in inputs:material_cap=mini(material_cap,floori(_num(business.inventory.get(ingredient,0))/float(inputs[ingredient])+0.000001))
	var progress: float=minf(float(material_cap),float(business.get("productionProgress",0))+throughput)
	var output: int=floori(progress+0.000001)
	while output>0:
		var weight: float=_inventory_weight(business.inventory)+float(output)*float(Goods.ITEMS[good].weight)
		for ingredient in inputs:weight-=float(output)*float(inputs[ingredient])*float(Goods.ITEMS[ingredient].weight)
		if weight<=float(business.capacity)+0.000001:break
		output-=1
	business.productionProgress=clampf(progress-float(output),0,0.999999)
	if output<=0:return 0
	var basis: float=0
	for ingredient in inputs:
		var amount: float=float(output)*float(inputs[ingredient])
		basis+=_take_basis(business,str(ingredient),amount)
		business.inventory[ingredient]=_round2(_num(business.inventory.get(ingredient,0))-amount)
	business.inventoryBasis[good]=float(business.inventoryBasis.get(good,0))+basis
	business.inventory[good]=_round2(_num(business.inventory.get(good,0))+output)
	return output

# Whole units to the home port only below equilibrium and within its cash.
static func _sell(state: Dictionary, business: Dictionary, port: Dictionary, goods: Array, ledger: Array) -> int:
	var earned := 0
	for good in goods:
		var g := str(good)
		var held := int(floor(_num(business["inventory"].get(g, 0.0))))
		if held <= 0:
			continue
		var need := int(floor(float(Economy.get_equilibrium_stock(port, g)) - _num(port["stocks"].get(g, 0.0))))
		if need <= 0:
			continue
		var unit := maxi(1, Economy.price(port, g, "sell"))
		var qty := mini(held, mini(need, int(_num(port.get("cash", 0))) / unit))
		if qty <= 0:
			continue
		var total := qty * unit
		if not Money.move(port, "cash", business, "coins", total, "Home-harbor sale: " + g, ledger):
			continue
		business["costOfSales"]+=ceili(_take_basis(business,g,float(qty)))
		business["inventory"][g] = _round2(_num(business["inventory"].get(g, 0.0)) - float(qty))
		port["stocks"][g] = _round2(_num(port["stocks"].get(g, 0.0)) + float(qty))
		business["revenue"] = int(business["revenue"]) + total
		earned += total
	return earned


# Whole days: arrears then wages business -> home household/expert purses.
# Shortfall records arrears and pauses work. Paid workshops produce/sell
# supplies; paid salvage yards sell stored salvage. Never spawns wrecks.
static func tick(core, days: float = 1.0) -> Array:
	var messages: Array = []
	var state := _state(core)
	if state.is_empty():
		return messages
	ensure(state)
	var whole := maxi(0, int(floor(days))) if is_finite(days) else 0
	if whole == 0:
		return messages
	var ledger: Array = state.get("moneyLog", []) if state.get("moneyLog") is Array else []
	for business in state["businesses"]:
		var port := _port(core, state, str(business["homePort"]))
		if port.is_empty() or not (port.get("stocks") is Dictionary):
			business["paused"] = true
			messages.append("%s has no home harbor; work paused, purse preserved." % str(business["name"]))
			continue
		var wages := _daily_wages(business["employees"])
		var owed_household := int(business["arrearsHousehold"]) + int(wages["household"]) * whole
		var owed_expert := int(business["arrearsExpert"]) + int(wages["expert"]) * whole
		var paid_household := mini(int(business["coins"]), owed_household)
		if paid_household > 0:
			Money.move(business, "coins", port, "householdPurse", paid_household, "Home-harbor wages", ledger)
		var paid_expert := mini(int(business["coins"]), owed_expert)
		if paid_expert > 0:
			Money.move(business, "coins", port, "expertPurse", paid_expert, "Home-harbor specialist wages", ledger)
		business["wagesPaid"] = int(business["wagesPaid"]) + paid_household + paid_expert
		business["arrearsHousehold"] = owed_household - paid_household
		business["arrearsExpert"] = owed_expert - paid_expert
		business["paused"] = int(business["arrearsHousehold"]) > 0 or int(business["arrearsExpert"]) > 0
		var worker_ops: Script=load("res://scripts/worker_ops.gd")
		var before_inventory: Dictionary=business.inventory.duplicate(true)
		var prior_notice: String=str(business.get("labor",{}).get("notice",""))
		var shift: Dictionary=worker_ops.step(core,business,port)
		worker_ops.account_materials(business,before_inventory)
		business.workFactor=float(shift.workFactor)
		if not shift.canWork:business.paused=true
		if str(shift.message)!=prior_notice:messages.append(str(business.name)+": "+str(shift.message))
		if bool(business["paused"]):
			var shortfall: int=int(business["arrearsHousehold"])+int(business["arrearsExpert"])
			if shortfall>0:messages.append("%s wages short by %d coins; work paused."%[str(business["name"]),shortfall])
			continue
		# The shift runs at econDay+1, then Campaign.apply_economy publishes that
		# same day AFTER HomeOps.daily and RegionalOps.daily. Bulk wage totals,
		# overtime and arrears settlements cannot manufacture distinct shifts.
		var work_day: int=int(state.econDay)+1
		if whole==1 and bool(shift.canWork) and float(shift.workFactor)>0 and int(wages.total)>0 and _staffed(business) and int(business.get("lastPaidWorkDay",-1))<work_day:
			business.paidWorkDays=int(business.get("paidWorkDays",0))+1
			business.lastPaidWorkDay=work_day
		if str(business["kind"]) == "workshop":
			business.toolingPaidDay=int(state.econDay)
			var tooling_api: Script=load("res://scripts/industrial_tooling.gd")
			tooling_api.service(core,str(business.id))
			business.toolingFactor=tooling_api.production_factor(core,str(business.id))
			business.toolingLabor=""
			for item in state.get("tooling",{}).get("items",[]):
				if item.businessId==business.id and item.location=="active":business.toolingLabor=str(item.recipeLabor)
			var kits := _produce(business, float(whole)*float(business.get("workFactor",1)))
			if kits > 0:
				messages.append("%s made %d %s from paid labor and stored materials." % [str(business["name"]), kits,str(Goods.ITEMS[str(business.get("recipeGood","supplies"))].name)])
			if business.autoSell:_sell(state, business, port, [str(business.get("recipeGood","supplies"))], ledger)
		elif str(business["kind"]) == "salvage_yard" and business.autoSell:
			var goods: Array = (business["inventory"] as Dictionary).keys()
			goods.sort()
			var earned := _sell(state, business, port, goods, ledger)
			if earned > 0:
				messages.append("%s sold stored salvage for %d coins." % [str(business["name"]), earned])
	state["moneyLog"] = ledger
	return messages

static func _take_basis(business: Dictionary,good: String,qty: float) -> float:
	var held: float=float(business.inventory.get(good,0))
	var basis: float=float(business.inventoryBasis.get(good,0))
	var removed: float=basis*clampf(qty/maxf(0.000001,held),0,1)
	business.inventoryBasis[good]=maxf(0,basis-removed)
	return removed
