extends RefCounted
## Main-thread finite mutations. Shipping.model owns only the merchant's spatial schedule.
const Shipping=preload("res://scripts/shipping068.gd")
const World=preload("res://scripts/ocean_world064.gd")
const Travel=preload("res://scripts/ocean_travel066.gd")
const Orders=preload("res://scripts/naval_orders.gd")
const Fleets=preload("res://scripts/fleet_economy.gd")
const Economy=preload("res://scripts/economy.gd")
const Money=preload("res://scripts/money.gd")
const Reserves=preload("res://scripts/harbor_reserves.gd")
const Exploration069=preload("res://scripts/exploration.gd")
const OWNER: String="patrol-7"
const ORIGIN: String="kelp_reach"
const PORT: String="westglass_anchorage"
const MAX_RECEIPTS: int=16
const OPENING: Dictionary={"food":16,"fuel":16,"supplies":8,"ammo":2}
const QUAY: Dictionary={"timber":8,"iron":2,"supplies":4}
const PURCHASES: Dictionary={"food":16,"fuel":16,"supplies":12,"ammo":2,"timber":8,"iron":2}

static func empty_book() -> Dictionary:
	return {"schema":1,"installation":{"status":"pending","reason":"","invoice":{},"attemptDay":0},
		"model":Shipping.empty_book(),"knownPorts":[],"receipts":[],"invoices":[],
		"nextReceipt":1,"launch":{"done":false,"amount":0},"holding":""}

static func _fail(message: String) -> Dictionary:
	return {"ok":false,"message":message}

static func _keys(value,keys: Array) -> bool:
	if not value is Dictionary or value.size()!=keys.size():return false
	for key in keys:
		if not value.has(key):return false
	return true

static func _number(value,low: float=0.0,whole: bool=false) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=9007199254740991.0 and (not whole or floorf(float(value))==float(value))

static func installed(state: Dictionary) -> bool:
	return str(state.get("shipping068",{}).get("installation",{}).get("status",""))=="installed"

static func harbors069(state: Dictionary) -> Array:
	var sector=state.get("sector069")
	return sector.harbors if sector is Dictionary and sector.get("harbors") is Array else []

static func definition069(state: Dictionary,id: String) -> Dictionary:
	for row in harbors069(state):
		if row is Dictionary and row.get("id")==id:return row
	return {}

static func known069(state: Dictionary,id: String) -> bool:
	var book=state.get("sectorKnowledge069")
	return book is Dictionary and book.get("ports") is Dictionary and book.ports.has(id) and not definition069(state,id).is_empty()

static func _knowledge069() -> Dictionary:
	return {"schema":1,"groups":{},"islands":{},"ports":{}}

# Called ONLY from explicit fresh new_game, before the final coinSupply. All
# defaults that create goods/people/money/hulls are overridden by the saved
# finite ledger. A visit/restore has no entry into this function.
static func install_sector069(c,sector: Dictionary) -> Dictionary:
	if c.state.has("sector069") or c.state.has("sectorApplied069") or not sector.get("openingLedger") is Dictionary:return _fail("A generated sector can be installed only once on a fresh career.")
	var staged: Array=[]
	var applied: Array=[]
	var allocations: Dictionary={}
	for row in sector.openingLedger.harbors:allocations[row.portId]=row.allocation
	var people: int=0
	var coins: int=0
	for harbor in sector.harbors:
		if not c.port(str(harbor.id)).is_empty() or not allocations.has(harbor.id):return _fail("A generated harbor has duplicate or missing opening provenance.")
		var definition: Dictionary=harbor.duplicate(true)
		definition.merge(allocations[harbor.id].duplicate(true),true)
		definition.merge({"shipStock":{},"shipIds":[],"buildQueue":[],"industryProgress":0.0,"recruitRemainder":0.0},true)
		var port: Dictionary=Economy.create_port(definition)
		for key in allocations[harbor.id]:
			if port.get(key)!=allocations[harbor.id][key]:return _fail("Generated opening defaults did not reconcile: "+str(harbor.id)+"."+str(key))
		# No HOME nearest-harbor route quote is meaningful in local coordinates.
		# Store the existing finite reserve policy once, without constructing nav.
		Reserves.ensure(port)
		staged.append(port);applied.append(str(harbor.id))
		people+=int(port.workforce);coins+=Money.port_total(port)
	if people!=int(sector.openingLedger.totals.workers) or coins!=int(sector.openingLedger.totals.coins):return _fail("Generated opening totals do not reconcile.")
	var knowledge: Dictionary=_knowledge069()
	var islands: Array=[]
	for region_id in sector.regionOrder:
		if sector.bands[region_id]=="settled":knowledge.groups[region_id]={"source":"public_chart069","day":float(c.state.day)}
	for row in sector.initialOwnership:
		if row.has("portId"):continue
		islands.append(row.duplicate(true))
		if sector.bands[row.regionId]=="settled":knowledge.islands[str(row.regionId)+"/"+str(row.islandId)]={"source":"public_chart069","day":float(c.state.day)}
	for row in sector.harbors:
		if sector.bands[row.regionId]=="settled":knowledge.ports[row.id]={"source":"public_chart069","day":float(c.state.day)}
	c.state.ports.append_array(staged)
	c.state["sector069"]=sector
	c.state["sectorApplied069"]={"schema":1,"provenance":"new_game_only:069.1","ports":applied}
	c.state["islandOwnership069"]=islands
	c.state["sectorKnowledge069"]=knowledge
	return {"ok":true,"message":"Created finite opening world accounts once: %d workers and %d coins in %d generated harbors."%[people,coins,staged.size()]}

# Sector.prepare validates canonical geometry/ledger before this account gate.
# These checks read live records without repairing missing ports or knowledge.
static func sector_error069(saved: Dictionary) -> String:
	if not saved.has("sector069"):
		for key in ["sectorApplied069","islandOwnership069","sectorKnowledge069"]:
			if saved.has(key):return "Sector records cannot extend a legacy two-region career."
		return ""
	var sector=saved.sector069
	if not sector is Dictionary or not sector.get("harbors") is Array or not sector.get("initialOwnership") is Array or not sector.get("bands") is Dictionary:return "Invalid generated sector records."
	if not _number(saved.get("seed"),0.0,true) or not _number(sector.get("seed"),0.0,true) or int(saved.seed)!=int(sector.seed):return "Campaign seed and generated sector provenance disagree."
	var journal=saved.get("sectorApplied069")
	if not _keys(journal,["schema","provenance","ports"]) or journal.schema!=1 or journal.provenance!="new_game_only:069.1" or not journal.ports is Array:return "Missing or invalid once-only sector installation journal."
	var expected: Array=[]
	var definitions: Dictionary={}
	for row in sector.harbors:
		if not row is Dictionary or not row.get("id") is String:return "Invalid generated harbor definition."
		expected.append(row.id);definitions[row.id]=row
	if journal.ports!=expected:return "Generated opening installation is incomplete or duplicated; restore cannot refill it."
	if not saved.get("ports") is Array:return "Missing generated harbor accounts."
	var seen: Dictionary={}
	for port in saved.ports:
		if not port is Dictionary:return "Invalid harbor account."
		if not definitions.has(port.get("id")):continue
		if seen.has(port.id):return "Duplicate generated harbor account."
		seen[port.id]=true
		for key in ["id","name","regionId","islandId","industry","specialty","x","y"]:
			if port.get(key)!=definitions[port.id].get(key):return "Generated harbor identity/berth does not match its saved definition."
		if port.get("faction") not in ["compact","forge","reed","raiders"]:return "Invalid live generated harbor owner."
		if port.get("shipStock")!={} or port.get("shipIds")!=[] or port.get("buildQueue")!=[]:return "Generated limited markets cannot contain boatyard assets."
		if not port.get("reserves") is Dictionary:return "Missing saved generated reserve policy."
		if not port.get("publicStores") is Dictionary:return "Missing explicit generated public stores."
		for good in Economy.GOODS:
			if not _number(port.publicStores.get(good)):return "Invalid generated public store."
		for key in ["population","workforce","workers","employedWorkers","availableWorkers","publicWorkers","specialists","specialistWorkers","availableSpecialists","recruits"]:
			if not _number(port.get(key),0.0,true):return "Invalid generated workforce account."
		if int(port.workers)+int(port.publicWorkers)+int(port.availableWorkers)!=int(port.workforce) or int(port.employedWorkers)!=int(port.workers) or int(port.specialistWorkers)!=int(port.specialists) or int(port.specialists)>int(port.workforce) or int(port.availableSpecialists)>mini(int(port.specialists),int(port.availableWorkers)) or int(port.recruits)>int(port.workforce):return "Generated workforce subsets do not reconcile."
	if seen.size()!=definitions.size():return "A generated harbor account is missing; restore cannot initialize it."
	var island_defs: Dictionary={}
	for row in sector.initialOwnership:
		if row is Dictionary and not row.has("portId"):island_defs[str(row.regionId)+"/"+str(row.islandId)]=row
	var islands=saved.get("islandOwnership069")
	if not islands is Array or islands.size()!=island_defs.size():return "Missing live sector island ownership."
	seen.clear()
	for row in islands:
		if not _keys(row,["regionId","islandId","faction"]) or not row.regionId is String or not row.islandId is String or row.faction not in ["","compact","forge","reed","raiders"]:return "Invalid live island ownership."
		var key: String=row.regionId+"/"+row.islandId
		if not island_defs.has(key) or seen.has(key):return "Unknown or duplicate live island ownership."
		seen[key]=true
	var knowledge=saved.get("sectorKnowledge069")
	if not _keys(knowledge,["schema","groups","islands","ports"]) or knowledge.schema!=1:return "Invalid sector knowledge book."
	for kind in ["groups","islands","ports"]:
		if not knowledge[kind] is Dictionary:return "Invalid sector knowledge collection."
		var catalog: Dictionary=sector.bands if kind=="groups" else (island_defs if kind=="islands" else definitions)
		if knowledge[kind].size()>catalog.size():return "Oversized sector knowledge."
		for key in knowledge[kind]:
			var record=knowledge[kind][key]
			if not key is String or not catalog.has(key) or not _keys(record,["source","day"]) or record.source not in ["public_chart069","observed069"] or not _number(record.day,1.0) or not _number(saved.get("day"),1.0) or float(record.day)>float(saved.day):return "Invalid earned sector knowledge provenance."
			var region: String=key if kind=="groups" else str(catalog[key].regionId)
			if record.source=="public_chart069" and sector.bands.get(region)!="settled":return "An unknown frontier/remote holding cannot be disclosed by an opening public chart."
	for key in knowledge.islands:
		if not knowledge.groups.has(island_defs[key].regionId):return "Known island has no earned group observation."
	for id in knowledge.ports:
		var definition: Dictionary=definitions[id]
		if not knowledge.groups.has(definition.regionId) or not knowledge.islands.has(str(definition.regionId)+"/"+str(definition.islandId)):return "Known harbor has no earned island/group observation."
	return ""

static func observe_sector069(c) -> void:
	if not c.state.has("sector069"):return
	var region: String=Exploration069.current_region(c.state)
	if region.is_empty() or region==World.HOME:return
	var book: Dictionary=c.state.sectorKnowledge069
	var observation: Dictionary={"source":"observed069","day":float(c.state.day)}
	if not book.groups.has(region):book.groups[region]=observation.duplicate()
	for site in c.state.sector069.sites:
		if site.regionId==region and World._distance(c.state.position,site)<=620.0:
			var key: String=str(region)+"/"+str(site.islandId)
			if not book.islands.has(key):book.islands[key]=observation.duplicate()
	for harbor in c.state.sector069.harbors:
		if harbor.regionId!=region or World._distance(c.state.position,harbor)>620.0:continue
		if not book.ports.has(harbor.id):book.ports[harbor.id]=observation.duplicate()
		var key: String=str(region)+"/"+str(harbor.islandId)
		if not book.islands.has(key):book.islands[key]=observation.duplicate()

static func _port_dto069(port: Dictionary,location: Dictionary) -> Dictionary:
	var dto: Dictionary={}
	for key in ["id","name","regionId","islandId","faction","industry","specialty","x","y"]:dto[key]=port[key]
	dto["atBerth"]=_at_berth(location,port)
	return dto

static func sector_view069(c) -> Dictionary:
	var region: String=str(c.state.get("world064",{}).get("regionId",World.HOME))
	var output: Dictionary={"schema":1,"seed":int(c.state.get("seed",0)),"generated":c.state.has("sector069"),"regionId":region,"groups":[],"ownership":[],"ports":[],"sites":[],"summary":"Existing two-region career preserved. Start a fresh campaign for the seeded 48-group ocean."}
	if not c.state.has("sector069"):return output
	var sector: Dictionary=c.state.sector069
	var knowledge: Dictionary=c.state.sectorKnowledge069
	var counts: Dictionary={}
	for id in sector.regionOrder:counts[id]={}
	for row in c.state.islandOwnership069:
		if not knowledge.islands.has(str(row.regionId)+"/"+str(row.islandId)):continue
		output.ownership.append(row.duplicate(true))
		var tally: Dictionary=counts[row.regionId]
		tally[row.faction]=int(tally.get(row.faction,0))+1
	var location: Dictionary=c.world_location064()
	for port in c.state.ports:
		var remote: bool=port.get("id")==PORT and installed(c.state) and PORT in c.state.shipping068.knownPorts
		var generated: bool=known069(c.state,str(port.id))
		var home: bool=str(port.get("regionId",World.HOME))==World.HOME
		if not home and not remote and not generated:continue
		var row: Dictionary={"regionId":str(port.get("regionId",World.HOME)),"islandId":str(port.get("islandId","")),"portId":str(port.id),"faction":str(port.faction)}
		if home:
			for initial in sector.initialOwnership:
				if initial.get("portId")==port.id:row.islandId=initial.islandId;break
		else:output.ports.append(_port_dto069(port,location))
		if row.islandId.is_empty():continue
		output.ownership.append(row)
		var tally: Dictionary=counts[row.regionId]
		tally[row.faction]=int(tally.get(row.faction,0))+1
	# The existing exploration boundary supplies only current-region earned rows.
	output.sites=Exploration069.visible_sites(c.state)
	var progress: Dictionary={}
	var records: Dictionary=c.state.get("exploration",{}).get("sites",{})
	for site in c.state.get("exploration",{}).get("catalog",[]):
		var site_region: String=str(site.get("regionId",World.HOME))
		progress[site_region]=maxi(int(progress.get(site_region,0)),int(records.get(site.id,{}).get("level",0)))
	for id in sector.regionOrder:
		var parts: Array=[]
		var tally: Dictionary=counts[id]
		var faction_ids: Array=tally.keys();faction_ids.sort()
		for faction_id in faction_ids:parts.append({"factionId":str(faction_id),"knownAssets":int(tally[faction_id])})
		var summary: String="unknown"
		if not parts.is_empty():summary="mixed" if parts.size()>1 else ("neutral" if parts[0].factionId=="" else "single")
		var level: String="unknown"
		if knowledge.groups.has(id):level="public_chart" if knowledge.groups[id].source=="public_chart069" else "sighted"
		if int(progress.get(id,0))>=2:level="surveyed" if int(progress[id])>=3 else "charted"
		output.groups.append({"regionId":str(id),"band":str(sector.bands[id]),"knowledge":level,"ownershipSummary":summary,"segments":parts})
	output.summary="48 seeded island groups. Public settled charts and earned observations show known ownership; paid surveys reveal resources and hazards. Finite opening world accounts were declared once when this campaign began."
	return output

static func _invoice_error(invoice) -> String:
	if not _keys(invoice,["donorId","workers","wage","operating","household","government","labor","purchases","consumed","total"]):return "Invalid branch installation invoice."
	var wage: int=Economy.ORDINARY_WAGE
	if invoice.donorId!=ORIGIN or invoice.workers!=8 or invoice.wage!=wage or invoice.operating!=20*8*wage or invoice.household!=5*8*wage or invoice.government!=10*8*wage or invoice.labor!=32*wage:return "Branch setup must retain its exact funded worker-day invoice."
	if not _keys(invoice.consumed,QUAY.keys()):return "Invalid consumed quay materials."
	for good in QUAY:
		if not _number(invoice.consumed[good],0.0,true) or int(invoice.consumed[good])!=int(QUAY[good]):return "Invalid consumed quay quantity."
	if not invoice.purchases is Array or invoice.purchases.size()!=PURCHASES.size():return "Invalid opening market purchase invoice."
	var seen: Dictionary={}
	var total: int=35*8*wage+32*wage
	for row in invoice.purchases:
		if not _keys(row,["good","qty","total"]) or not row.good is String or not PURCHASES.has(row.good) or seen.has(row.good) or row.qty!=PURCHASES[row.good] or not _number(row.total,1.0,true):return "Invalid or duplicate opening purchase."
		seen[row.good]=true;total+=int(row.total)
	if not _number(invoice.total,1.0,true) or int(invoice.total)!=total:return "Branch grant and purchase totals disagree."
	return ""

static func raw_error(saved: Dictionary) -> String:
	var remote: Array=[]
	if saved.get("ports") is Array:
		for row in saved.ports:
			if row is Dictionary and row.get("id")==PORT:remote.append(row)
	if not saved.has("shipping068"):
		return "A remote harbor requires its funded installation record." if not remote.is_empty() else ""
	var book=saved.shipping068
	if not _keys(book,["schema","installation","model","knownPorts","receipts","invoices","nextReceipt","launch","holding"]) or book.schema!=1:return "Invalid shipping068 book."
	if not World._plain(book) or not _keys(book.installation,["status","reason","invoice","attemptDay"]) or book.installation.status not in ["pending","installed"] or not book.installation.reason is String or book.installation.reason.length()>600 or not book.installation.invoice is Dictionary or not _number(book.installation.attemptDay,0.0,true):return "Invalid shipping installation state."
	if not _number(saved.get("econDay"),0.0,true) or float(book.installation.attemptDay)>float(saved.econDay):return "Invalid shipping installation attempt date."
	if not book.model is Dictionary or not book.knownPorts is Array or book.knownPorts.size()>1 or (not book.knownPorts.is_empty() and book.knownPorts!=[PORT]):return "Invalid remote harbor knowledge."
	if not book.holding is String or book.holding.length()>600 or not _number(book.nextReceipt,1.0,true):return "Invalid shipping status or receipt sequence."
	if not _keys(book.launch,["done","amount"]) or not book.launch.done is bool or not _number(book.launch.amount,0.0,true) or (not book.launch.done and book.launch.amount!=0):return "Invalid once-only launch remittance."
	if not book.receipts is Array or book.receipts.size()>MAX_RECEIPTS or not book.invoices is Array or book.invoices.size()>MAX_RECEIPTS:return "Invalid bounded shipping receipts."
	var previous: int=0
	for row in book.receipts:
		if not _keys(row,["sequence","day","portId","good","qty","side","total"]) or not _number(row.sequence,1.0,true) or int(row.sequence)<=previous or int(row.sequence)>=int(book.nextReceipt) or not _number(row.day,1.0) or not row.portId is String or (row.portId!=PORT and not known069(saved,row.portId)) or not row.good is String or not Economy.GOODS.has(row.good) or not _number(row.qty,1.0,true) or row.side not in ["buy","sell"] or not _number(row.total,1.0,true):return "Invalid player remote trade receipt."
		previous=int(row.sequence)
	previous=0
	for row in book.invoices:
		if not _keys(row,["sequence","day","kind","portId","good","qty","total"]) or not _number(row.sequence,1.0,true) or int(row.sequence)<=previous or not _number(row.day,1.0) or row.kind not in ["load","deliver","service"] or row.portId not in [ORIGIN,PORT] or row.good not in ["","food","logs"] or not _number(row.qty,0.0,true) or not _number(row.total,0.0,true):return "Invalid physical shipment invoice."
		previous=int(row.sequence)
	if book.installation.status=="pending":
		if not remote.is_empty() or not book.installation.invoice.is_empty() or not book.model.get("route",{}).is_empty() or not book.knownPorts.is_empty() or book.receipts.any(func(r):return r.portId==PORT) or not book.invoices.is_empty() or book.launch.done:return "Pending installation cannot own a Westglass harbor, shipment or money."
		return ""
	if saved.get("mapRevision")!=2 or remote.size()!=1:return "Installed shipping needs one migrated remote harbor."
	var error: String=_invoice_error(book.installation.invoice)
	if not error.is_empty():return error
	var definition: Dictionary=World.remote_port068()
	var port: Dictionary=remote[0]
	for key in definition:
		if port.get(key)!=definition[key]:return "Remote harbor identity, ownership or berth changed."
	if port.get("shipStock")!={} or port.get("shipIds")!=[] or port.get("buildQueue")!=[]:return "The bounded anchorage has no boatyard stock or construction."
	if not port.get("publicStores") is Dictionary:return "Remote public stores must be explicit."
	for good in Economy.GOODS:
		if not _number(port.publicStores.get(good)):return "Invalid remote public stores."
	if not _number(port.get("specialists")) or not _number(port.get("availableSpecialists")):return "Invalid remote specialist pool."
	return ""

static func prepare(saved: Dictionary,_world: Dictionary,context064: Dictionary) -> Dictionary:
	var error: String=raw_error(saved)
	if not error.is_empty():return _fail(error)
	var model: Dictionary=Shipping.prepare(saved,context064)
	if not model.get("ok",false):return _fail(str(model.get("message","Invalid shipping model.")))
	var book: Dictionary=saved.get("shipping068",empty_book()).duplicate(true)
	book["model"]=model.book
	if not book.invoices.is_empty() and int(book.invoices[-1].sequence)>int(book.model.get("route",{}).get("sequence",0)):return _fail("Shipment invoices exceed the committed route sequence.")
	return {"ok":true,"book":book}

static func _pending(c,message: String) -> Dictionary:
	var book: Dictionary=c.state.get("shipping068",empty_book()).duplicate(true)
	book.installation["reason"]=message.left(600)
	book.installation["attemptDay"]=int(c.state.get("econDay",1))
	c.state["shipping068"]=book
	return {"ok":false,"message":message,"pending":true}

static func install(c) -> Dictionary:
	if c.state.has("shipping068"):
		if installed(c.state):return {"ok":true,"message":"The existing branch accounts are already installed."}
		if int(c.state.get("econDay",1))<=int(c.state.shipping068.installation.attemptDay):return _fail(str(c.state.shipping068.installation.reason))
	if int(c.state.get("mapRevision",1))!=2:return _pending(c,"Westglass branch installation awaits legacy coast migration.")
	# All trial trades and account splits occur on a detached career. Failure only publishes a reason.
	var candidate: Dictionary=c.state.duplicate(true)
	var donor: Dictionary=Orders.find_port(candidate,ORIGIN)
	if donor.is_empty() or not Orders.find_port(candidate,PORT).is_empty():return _pending(c,"Westglass branch installation needs its original Kelp account and no existing duplicate harbor.")
	var ordinary: int=floori(float(donor.get("availableWorkers",0))-float(donor.get("availableSpecialists",0))-float(donor.get("_yardWorkersUsed",0)))
	if ordinary<8 or float(donor.get("population",0))<8 or float(donor.get("workforce",0))<8:return _pending(c,"Westglass branch pending: eight ordinary idle, unreserved Kelp residents are unavailable.")
	var definition: Dictionary=World.remote_port068()
	definition.merge({"description":"A pre-existing Kelp Reach timber branch; its founding accounts and eight residents were split once from Kelp Reach.","population":8,"workforce":8,"workers":0,"employedWorkers":0,"publicWorkers":0,"availableWorkers":8,"specialists":0,"specialistWorkers":0,"availableSpecialists":0,"recruits":0,"recruitRemainder":0.0,"cash":0,"householdPurse":0,"expertPurse":0,"governmentPurse":0,"stocks":{},"publicStores":{},"shipStock":{},"shipIds":[],"buildQueue":[]},true)
	for good in Economy.GOODS:definition.stocks[good]=0.0;definition.publicStores[good]=0.0
	var remote: Dictionary=Economy.create_port(definition)
	var invoice: Dictionary={"donorId":ORIGIN,"workers":8,"wage":Economy.ORDINARY_WAGE,"operating":20*8*Economy.ORDINARY_WAGE,"household":5*8*Economy.ORDINARY_WAGE,"government":10*8*Economy.ORDINARY_WAGE,"labor":32*Economy.ORDINARY_WAGE,"purchases":[],"consumed":QUAY.duplicate(),"total":35*8*Economy.ORDINARY_WAGE+32*Economy.ORDINARY_WAGE}
	var purchase_cost: int=0
	for good in PURCHASES:
		if floori(float(Reserves.exportable(donor,good)))<int(PURCHASES[good]):return _pending(c,"Westglass branch pending: Kelp has insufficient exportable %s for the recorded quay and opening stores."%good)
		purchase_cost+=Economy.price(donor,good,"buy")*int(PURCHASES[good])
	invoice.total+=purchase_cost
	if int(donor.governmentPurse)<int(invoice.total):return _pending(c,"Westglass branch pending: Kelp treasury cannot fund the derived %d-coin setup invoice."%int(invoice.total))
	Money.move(donor,"governmentPurse",remote,"cash",int(invoice.operating)+purchase_cost,"Historical Westglass operating and purchase allocation",candidate.moneyLog)
	Money.move(donor,"governmentPurse",remote,"householdPurse",int(invoice.household)+int(invoice.labor),"Historical Westglass household reserve and 32 quay worker-days",candidate.moneyLog)
	Money.move(donor,"governmentPurse",remote,"governmentPurse",int(invoice.government),"Historical Westglass government reserve",candidate.moneyLog)
	var wallet: Dictionary={"coins":remote.cash,"cargo":{}}
	for good in PURCHASES:
		var purchase: Dictionary=Economy.transact(donor,wallet,good,int(PURCHASES[good]),"buy")
		if not purchase.get("ok",false):return _pending(c,"Westglass branch pending: "+str(purchase.message))
		invoice.purchases.append({"good":good,"qty":int(purchase.qty),"total":int(purchase.total)})
	remote["cash"]=int(wallet.coins)
	for good in OPENING:remote.stocks[good]=float(OPENING[good])
	# The purchased quay materials are consumed once; none are added to live stocks.
	donor.population-=8;donor.workforce-=8;donor.availableWorkers-=8
	donor.recruits=maxi(0,int(donor.recruits)-8)
	Economy.sync_workforce(donor)
	var book: Dictionary=c.state.get("shipping068",empty_book()).duplicate(true)
	book.installation={"status":"installed","reason":"","invoice":invoice,"attemptDay":int(c.state.get("econDay",1))}
	candidate.ports.append(remote);candidate["shipping068"]=book
	if Money.total(candidate)!=Money.total(c.state):return _pending(c,"Westglass branch installation refused an inconsistent account split.")
	c.state=candidate
	return {"ok":true,"message":"Installed the historical Westglass branch split; no coins, residents or boats were created."}

static func snapshot(c) -> Dictionary:
	var owner: Dictionary=Orders.find_owner(c.state,OWNER).duplicate(true)
	var patrol: Dictionary=Orders.find_patrol(c.state,OWNER).duplicate(true)
	var reserves: Dictionary=Orders.fleet_reserves(owner)
	var performance: Dictionary=Orders.fleet_performance(owner)
	return {"owner":owner,"patrol":patrol,"originPort":c.port(ORIGIN).duplicate(true),"remotePort":c.port(PORT).duplicate(true) if installed(c.state) else {},"reserves":reserves,"performance":performance,"clearance":_clearance(owner),"campaignScale":float(c.data.get("CAMPAIGN_SCALE",1.0))}

static func _clearance(owner: Dictionary) -> float:
	var result: float=10.0
	for boat in owner.get("boats",[]):
		if not boat.get("sunk",false):result=maxf(result,float(boat.get("spec",{}).get("size",10.0)))
	return result

static func actor(c) -> Dictionary:
	if not installed(c.state):return {}
	return Shipping.actor(c.state.shipping068.model,snapshot(c))

static func _admission_block(c) -> String:
	var owner: Dictionary=Orders.find_owner(c.state,OWNER)
	if owner.is_empty() or not Orders.RegionalOrders.operation(c.state,owner).is_empty() or owner.get("playerCompany",false):return "The original Kelp trader is unavailable or assigned to another operation."
	for port in c.state.ports:
		for order in port.get("buildQueue",[]):
			if str(order.get("npcOwnerId",""))==OWNER:return "The Kelp trader has a conflicting paid yard collection."
	return ""

static func stage(c,_dt: float) -> Dictionary:
	var current: Dictionary=c.state.get("shipping068",empty_book()).model
	var staged: Dictionary={"ok":true,"model":current.duplicate(true),"proposal":{},"command":{},"actor":{},"message":""}
	if not installed(c.state):return staged
	var physical: Dictionary=snapshot(c)
	if c.pending_days>0:
		staged.actor=Shipping.actor(current,physical)
		staged.message="Awaiting the existing daily economy publication before port transactions."
		return staged
	var now: float=float(c.state.day)*45.0
	var route: Dictionary=current.route
	if route.is_empty():
		if c.ocean_watch066<1.0:return staged
		var admission: String=_admission_block(c)
		if not admission.is_empty():staged.message=admission;return staged
	# The model coalesces watches itself. No per-frame route quotation or nav build.
	if route.is_empty() or now+0.000001>=float(route.nextDueSecond):
		var planned: Dictionary=Shipping.plan(c.ocean_context064,current,physical,now)
		if not planned.get("ok",false):staged.message=str(planned.get("message","Merchant route is holding."))
		else:
			staged.message=str(planned.get("message",""))
			staged.command=planned.command
			staged.proposal=planned.book
			if planned.command.is_empty():staged.model=planned.book
			elif route.is_empty() and not planned.book.route.is_empty():
				# Admit the exact paid Kelp berth before its first finite service command.
				staged.model=planned.book.duplicate(true)
				staged.model.route["sequence"]=0;staged.model.route["nextDueSecond"]=now
			var next_route: Dictionary=planned.book.get("route",{})
			if not route.is_empty() and not next_route.is_empty() and not Travel.same_world(route.location.world064,next_route.location.world064):
				var participants: Array=c.OceanCampaign066.actors(c,c.state.ocean066)
				var pending: bool=c.events.any(func(e):return str(e.get("kind","")) in ["encounter","ocean_encounter066","defeat"])
				var blocker: String=Travel.transition_blocker(participants,c.OceanCampaign066.relations(c,participants),c.state.ocean066.memory,pending)
				if not blocker.is_empty():
					staged.model=current.duplicate(true);staged.proposal={};staged.command={};staged.message=blocker
	staged.actor=Shipping.actor(staged.model,physical)
	return staged

static func _publish_model(c,model: Dictionary) -> void:
	c.state.shipping068["model"]=model
	var route: Dictionary=model.route
	if route.is_empty():return
	var patrol: Dictionary=Orders.find_patrol(c.state,OWNER)
	patrol["active"]=false;patrol["hidden"]=true;patrol["holding"]=true
	patrol["course"]=[];patrol["courseLength"]=0.0;patrol["progress"]=0.0
	patrol.erase("interceptPoint")
	var owner: Dictionary=Orders.find_owner(c.state,OWNER)
	if route.phase in ["outbound","return","lost"]:
		owner["atPort"]="";owner.erase("harborServiceUntilDay")
	elif route.phase in ["home_service","remote_service"]:
		owner["atPort"]=ORIGIN if route.phase=="home_service" else PORT

static func _trade(owner: Dictionary,port: Dictionary,good: String,qty: int,side: String,c) -> Dictionary:
	if qty<=0:return {"ok":true,"qty":0,"total":0,"message":"No affordable lot; existing cargo stays aboard."}
	if not Fleets.allowed_trade(owner,port,good,c):return _fail("Faction trade rules forbid this shipment good.")
	var wallet: Dictionary={"coins":int(owner.coins),"cargo":owner.cargo}
	var result: Dictionary=Economy.transact(port,wallet,good,qty,side,Fleets._capacity(owner))
	if result.get("ok",false):owner["coins"]=int(wallet.coins)
	return result

static func _service_payroll_days(c) -> int:
	# The sole daily payroll is discrete. Reserve an actual boundary during this
	# quarter-day call plus at most one accepted4s scheduling interval.
	return maxi(0,floori(float(c.state.day)+0.25+4.0/45.0)-int(c.state.econDay))

static func _launch(c,owner: Dictionary,port: Dictionary,location: Dictionary,required: Dictionary) -> Dictionary:
	var book: Dictionary=c.state.shipping068
	if book.launch.done:return {"ok":true,"message":"The one launch remittance has already been recorded."}
	if port.id!=ORIGIN or not _at_berth(location,port):return _fail("Launch remittance requires the actual Kelp berth.")
	# Existing purchased coastal cargo may be sold here, never erased or re-seeded.
	var old_good: String=str(owner.get("tradeGood","food"))
	var old_qty: int=mini(floori(float(owner.get("tradeCargo",0))),floori(float(owner.cargo.get(old_good,0))))
	var retained: int=mini(64,old_qty) if old_good=="food" else 0
	var sell: int=mini(maxi(0,old_qty-retained),int(port.cash)/maxi(1,Economy.price(port,old_good,"sell")))
	if sell>0:
		var sale: Dictionary=_trade(owner,port,old_good,sell,"sell",c)
		if sale.get("ok",false):owner.tradeCargo=maxf(0.0,float(owner.tradeCargo)-float(sale.qty))
	if float(owner.get("tradeCargo",0))>float(retained)+0.000001:return _fail("Existing excess coastal cargo remains aboard until Kelp can buy it; it is not replaced by a new manifest.")
	var upkeep: Dictionary=Fleets.upkeep(owner)
	var setup_days: int=_service_payroll_days(c)
	var provision_days: float=float(required.days)+float(setup_days)
	var personal_food: float=maxf(0.0,float(owner.cargo.get("food",0))-(float(owner.tradeCargo) if old_good=="food" else 0.0))
	var food_need: int=maxi(0,ceili(float(upkeep.food)*provision_days-personal_food))
	var cost: int=int(required.wageCoins)+ceili(float(upkeep.wages)*setup_days)+int(required.repairCoins)+food_need*Economy.price(port,"food","buy")
	var living: Array=Orders.living_boats(owner)
	var fuel_hold: int=floori(float(owner.cargo.get("fuel",0)))
	for boat in Orders.living_boats(owner):
		var target: float=maxf(3.0,ceilf(float(upkeep.fuel)*provision_days/maxi(1,living.size())))
		var fuel_need: int=maxi(0,ceili(target-float(boat.get("fuel",0))))
		var held: int=mini(fuel_need,fuel_hold);fuel_hold-=held
		cost+=(fuel_need-held)*Economy.price(port,"fuel","buy")
		cost+=maxi(0,ceili(2.0-float(boat.get("supplies",0))))*Economy.price(port,"supplies","buy")
		cost+=maxi(0,ceili((50.0-float(boat.get("ammo",0)))/50.0))*Economy.price(port,"ammo","buy")
	# Crew savings can purchase rations; readiness funding does not buy a commercial lot.
	var available: int=int(owner.coins)+mini(int(owner.crewPurse),food_need*Economy.price(port,"food","buy"))
	var deficit: int=maxi(0,cost-available)
	if int(port.governmentPurse)<deficit:return _fail("Kelp cannot fund the calculated %d-coin readiness deficit; merchant holds."%deficit)
	if deficit>0 and not Money.move(port,"governmentPurse",owner,"coins",deficit,"Once-only calculated Westglass round-trip readiness remittance",c.state.moneyLog):return _fail("Launch remittance failed without a top-up.")
	book["launch"]={"done":true,"amount":deficit}
	return {"ok":true,"message":"Recorded the actual calculated launch remittance."}

static func _execute(c,command: Dictionary,proposal: Dictionary) -> Dictionary:
	var current: Dictionary=c.state.shipping068.model.route
	var next_route: Dictionary=proposal.get("route",{})
	if current.is_empty() or next_route.is_empty() or str(command.get("ownerId",""))!=OWNER or int(command.get("sequence",-1))!=int(current.sequence)+1 or int(next_route.sequence)!=int(command.sequence):return _fail("The shipment command is stale or has no physical enrolled owner.")
	var owner: Dictionary=Orders.find_owner(c.state,OWNER)
	var port: Dictionary=c.port(str(command.get("portId","")))
	var location: Dictionary=current.location
	if port.is_empty() or not _at_berth(location,port) or not owner.get("active",false) or Orders.living_boats(owner).is_empty():return _fail("Shipment settlement requires its actual surviving carrier at the stopped berth.")
	var kind: String=str(command.get("kind",""))
	var good: String=str(command.get("good",""))
	var qty: int=int(command.get("qty",0))
	var result: Dictionary
	if kind=="service":
		var required: Dictionary=Shipping.requirements(c.ocean_context064,snapshot(c))
		if not required.get("ok",false):return required
		if port.id==ORIGIN:
			var funded: Dictionary=_launch(c,owner,port,location,required)
			if not funded.get("ok",false):return funded
		var provision_days: float=float(required.days)*(1.0 if port.id==ORIGIN else 0.5)+float(_service_payroll_days(c))
		result=Fleets.dock_at068(owner,port,location,provision_days,c)
	elif kind=="load":
		var retained_manifest: bool=qty==0 and good==str(owner.get("tradeGood","")) and float(owner.get("tradeCargo",0))>0.0
		if (good!=("food" if port.id==ORIGIN else "logs") and not retained_manifest) or qty<0 or qty>64:return _fail("Shipping loads are a bounded food lot outward or an optional real logs lot homeward.")
		if port.id==ORIGIN and (good!="food" or float(owner.get("tradeCargo",0))+qty<1.0 or float(owner.get("tradeCargo",0))+qty>64.0):return _fail("The outward food manifest must contain one to64 actual paid lots.")
		var required: Dictionary=Shipping.requirements(c.ocean_context064,snapshot(c))
		if not required.get("ok",false):return required
		var reserve: int=ceili(float(required.wageCoins)*(1.0 if port.id==ORIGIN else 0.5))+int(required.repairCoins)
		if int(owner.coins)-qty*Economy.price(port,good,"buy")<reserve:return _fail("The requested lot would spend the conservative round-trip wage and repair reserve.")
		if qty>0 and float(owner.get("tradeCargo",0))>0.000001:return _fail("Unsold cargo keeps its original manifest; a different load cannot overwrite it.")
		result=_trade(owner,port,good,qty,"buy",c)
		if result.get("ok",false) and qty>0:owner["tradeGood"]=good;owner["tradeCargo"]=float(result.qty)
	elif kind=="deliver":
		if good!=str(owner.get("tradeGood","")) or qty<0 or qty>floori(float(owner.get("tradeCargo",0))):return _fail("A shipment cannot sell another owner's or unmanifested goods.")
		result=_trade(owner,port,good,qty,"sell",c)
		if result.get("ok",false):
			owner["tradeCargo"]=maxf(0.0,float(owner.tradeCargo)-float(result.qty))
			owner["tradeDelivered"]=float(owner.get("tradeDelivered",0))+float(result.qty)
	else:return _fail("Unknown shipment mutation.")
	if not result.get("ok",false):return result
	var invoice: Dictionary={"sequence":int(command.sequence),"day":float(c.state.day),"kind":kind,"portId":str(port.id),"good":good,"qty":int(result.get("qty",qty)),"total":int(result.get("total",result.get("spent",0)))}
	c.state.shipping068.invoices.append(invoice)
	while c.state.shipping068.invoices.size()>MAX_RECEIPTS:c.state.shipping068.invoices.pop_front()
	_publish_model(c,proposal)
	return result

static func commit(c,staged: Dictionary) -> void:
	if not installed(c.state):return
	c.state.shipping068["holding"]=str(staged.get("message","")).left(600)
	_publish_model(c,staged.model)
	if not staged.get("command",{}).is_empty():
		var result: Dictionary=_execute(c,staged.command,staged.proposal)
		if not result.get("ok",false):
			c.state.shipping068["holding"]=str(result.get("message","Physical shipping settlement refused.")).left(600)
			c.state.shipping068.model.route["nextDueSecond"]=float(c.state.day)*45.0+1.0

static func _at_berth(location: Dictionary,port: Dictionary) -> bool:
	var region: String=str(port.get("regionId",World.HOME))
	return location.get("world064",{}).get("regionId")==region and location.get("world064",{}).get("layer")==("home" if region==World.HOME else "local") and location.get("path",[]).is_empty() and World._distance(location.get("position",{}),port)<40.0

static func _forget_pursuits(c,id: String) -> void:
	var memory: Dictionary=c.state.ocean066.memory
	for key in memory.pursuits.keys():
		if str(key)==id or str(memory.pursuits[key].get("targetId",""))==id:memory.pursuits.erase(key)

static func record_losses(c) -> void:
	if not installed(c.state):return
	var route: Dictionary=c.state.shipping068.model.route
	if route.is_empty():return
	var owner: Dictionary=Orders.find_owner(c.state,OWNER)
	var pending: Array=owner.get("boats",[]).filter(func(b):return b.get("sunk",false) and not b.get("wreckRecorded",false))
	var remaining: int=pending.size()
	var living: int=Orders.living_boats(owner).size()
	for boat in pending:
		var records: Array=c.Salvage.record_battle(c,{"ships":[boat],"chartPosition":route.location.position,"world064":route.location.world064},"shipping-npc:"+str(boat.uid))
		if records.is_empty():continue
		var wreck: Dictionary=c.Salvage.find_wreck(c.state,str(records[0].id))
		for good in owner.cargo:
			var lost: float=float(owner.cargo[good])/maxi(1,living+remaining)
			owner.cargo[good]=maxf(0.0,float(owner.cargo[good])-lost)
			wreck.stores[good]=float(wreck.stores.get(good,0))+lost*0.5
			if good==owner.get("tradeGood",""):owner["tradeCargo"]=maxf(0.0,float(owner.get("tradeCargo",0))-lost)
		boat["wreckRecorded"]=true;remaining-=1
	if living==0:
		route["phase"]="lost";route.location["path"]=[];route.location["destination"]=""
		owner["active"]=false;owner["atPort"]="";owner.erase("harborServiceUntilDay")
		_forget_pursuits(c,OWNER)

static func after_step(c,_watch_due: bool=false) -> void:
	record_losses(c)
	if not installed(c.state):return
	if c.state.get("world064",{}).get("regionId")==World.REMOTE and c.state.world064.layer=="local" and World._distance(c.state.position,World.remote_port068())<=620.0 and PORT not in c.state.shipping068.knownPorts:
		c.state.shipping068.knownPorts.append(PORT)
		c.log_entry("Sighted Westglass Anchorage, a Reedwater harbor on Westglass. The rest of Glasswind's holdings are unknown.")

static func daily(c) -> void:
	# Fleets.tick has already paid wages/burned food/fuel/applied passive damage once.
	if not installed(c.state):install(c)
	record_losses(c)

static func resolve_encounter(c,encounter: Dictionary) -> Dictionary:
	var a: String=str(encounter.get("attackerId",""))
	var b: String=str(encounter.get("defenderId",""))
	if a not in ["patrol-0",OWNER] or b not in ["patrol-0",OWNER] or a==b:return _fail("This is not the bounded shared NPC contact.")
	var raider: Dictionary=c.state.get("ocean066",{}).get("contact",{})
	var merchant: Dictionary=c.state.get("shipping068",{}).get("model",{}).get("route",{})
	if raider.is_empty() or merchant.is_empty():return _fail("The existing physical NPC contact is no longer enrolled.")
	var location_a: Dictionary=raider.location if a=="patrol-0" else merchant.location
	var location_b: Dictionary=raider.location if b=="patrol-0" else merchant.location
	var result: Dictionary=c.NavalAI.resolve_at068(c,a,b,location_a,location_b)
	if result.get("ok",false):
		_forget_pursuits(c,OWNER)
		c.OceanCampaign066.record_losses(c);record_losses(c)
		if result.get("event",{}).get("witnessed",false):c.log_entry(str(result.get("summary","The observed fleets exchanged fire.")))
	return result

static func remote_gate(c,port_id: String="") -> Dictionary:
	var selected: String=port_id
	var location: Dictionary=c.world_location064()
	if selected.is_empty():
		for row in c.state.get("ports",[]):
			if row.get("regionId",World.HOME)==World.HOME:continue
			if not (row.id==PORT and installed(c.state) and PORT in c.state.shipping068.knownPorts) and not known069(c.state,str(row.id)):continue
			if _at_berth(location,row):selected=str(row.id);break
	var known: bool=(selected==PORT and installed(c.state) and PORT in c.state.shipping068.knownPorts) or known069(c.state,selected)
	if not known:return _fail("Choose a known installed harbor on the current local chart.")
	var port: Dictionary=c.port(selected)
	if port.is_empty() or not _at_berth(location,port):return _fail("Stop within40water units of this harbor's actual berth to trade.")
	if not c.travel_lock064.is_empty():return _fail(c.travel_lock064)
	if not c.state.get("exploration",{}).get("assignment",{}).is_empty() or not c.state.get("toolingRecovery",{}).is_empty() or c.state.get("fleet",[]).any(func(b):return int(b.get("shoreCrew",0))>0):return _fail("Recall every active work party before trading.")
	if c.events.any(func(e):return str(e.get("kind","")) in ["encounter","ocean_encounter066","defeat"]):return _fail("Resolve the physical encounter before trading.")
	var blocked: String=c.OceanCampaign066.blocker(c)
	if not blocked.is_empty():return _fail(blocked)
	# Permission observation may normalize faction books; isolate those writes from views.
	var policy_state: Dictionary={"day":c.state.day,"relationships":c.state.get("relationships",{}).duplicate(true)}
	var access: Dictionary=c.Politics.access({"state":policy_state,"data":c.data},port)
	if not access.get("legal",false):return _fail(str(access.get("reason","Harbor entry is refused.")))
	return {"ok":true,"port":port,"access":access}

static func remote_view(c,port_id: String="") -> Dictionary:
	var gate: Dictionary=remote_gate(c,port_id)
	if not gate.get("ok",false):return {}
	var port: Dictionary=gate.port
	var view: Dictionary=_port_dto069(port,c.world_location064())
	view["stocks"]=port.stocks.duplicate(true);view["cash"]=int(port.cash)
	view["prices"]={}
	for good in Economy.GOODS:view.prices[good]={"buy":Economy.price(port,good,"buy"),"sell":Economy.price(port,good,"sell")}
	view["playerCoins"]=int(c.state.coins);view["freeCapacity"]=maxf(0.0,c.capacity()-c.cargo_weight())
	return view

static func market(c,good: String,qty: int,side: String,port_id: String="") -> Dictionary:
	var gate: Dictionary=remote_gate(c,port_id)
	if not gate.get("ok",false):return gate
	if not c.LawOps.allow_player(c,gate.port,good):return _fail("Your carrier agreement restricts this good here.")
	if side=="buy" and good in gate.access.get("restrictedGoods",[]):return _fail("The harbor restricts this military commodity.")
	var overflow: float=maxf(0.0,c.cargo_weight()-Economy.cargo_weight(c.state.cargo)-c.freight_weight())
	var result: Dictionary=Economy.transact(gate.port,c.state,good,qty,side,maxf(0.0,c.capacity()-c.freight_weight()-overflow))
	if not result.get("ok",false):return result
	c.LawOps.reconcile(c)
	c.Manifest.allocate(c.state)
	var book: Dictionary=c.state.shipping068
	var receipt: Dictionary={"sequence":int(book.nextReceipt),"day":float(c.state.day),"portId":str(gate.port.id),"good":good,"qty":int(result.qty),"side":side,"total":int(result.total)}
	book.receipts.append(receipt);book.nextReceipt+=1
	while book.receipts.size()>MAX_RECEIPTS:book.receipts.pop_front()
	result["receipt"]=receipt.duplicate(true)
	return result

static func view(c) -> Dictionary:
	var output: Dictionary={"ports":[],"ownership":[],"contacts":[],"route":{},"receipts":[],"summary":""}
	if c.state.is_empty():return output
	for port in c.state.get("ports",[]):
		if not known069(c.state,str(port.id)):continue
		output.ports.append(_port_dto069(port,c.world_location064()))
		output.ownership.append({"regionId":str(port.regionId),"islandId":str(port.islandId),"portId":str(port.id),"faction":str(port.faction)})
	var book: Dictionary=c.state.get("shipping068",empty_book())
	output.receipts=book.receipts.duplicate(true)
	if not installed(c.state):
		if c.home_local064():output.summary=str(book.installation.reason)
		return output
	if PORT in book.knownPorts:
		var port: Dictionary=World.remote_port068()
		port["atBerth"]=_at_berth(c.world_location064(),port)
		output.ports.append(port)
		output.ownership.append({"regionId":World.REMOTE,"islandId":"glasswind_west","portId":PORT,"faction":"reed"})
		output.receipts=book.receipts.duplicate(true)
		output.summary="Known Reedwater harbor on Westglass; other Glasswind island holdings are unknown."
	var now: float=float(c.state.day)*45.0
	var seen: Dictionary=c.state.get("ocean066",{}).get("memory",{}).get("sightings",{}).get("player",{}).get(OWNER,{})
	if seen.is_empty() or float(seen.get("expiresSecond",0))<=now or not Travel.same_world(seen.get("world064"),c.state.get("world064")):return output
	var age: float=maxf(0.0,now-float(seen.seenSecond))
	var owner: Dictionary=Orders.find_owner(c.state,OWNER)
	output.contacts.append({"id":OWNER,"ownerId":OWNER,"name":str(owner.get("name","Kelp merchant")),"faction":str(owner.get("faction","reed")),"role":"trader","hostile":bool(c.Politics.hostile(c,owner)),"visibility":"visible" if age<=1.5 else "last_known","world064":seen.world064.duplicate(true),"position":seen.position.duplicate(true),"heading":float(seen.heading),"uncertaintyRadius":0.0 if age<=1.5 else minf(1800.0,age*120.0),"ageSeconds":age,"sightedDay":float(seen.seenSecond)/45.0,"intentLabel":"Dated merchant sighting; investigate or avoid","provenance":"Existing Kelp merchant patrol-7; same physical fleet","boats":seen.boats.duplicate(true)})
	# Dated observations cannot reveal a live unseen phase, purse, manifest or route.
	output.route={"ownerId":OWNER,"phase":"observed","reason":"Dated merchant contact; accounts and destination are private.","seenSecond":float(seen.seenSecond)}
	return output
