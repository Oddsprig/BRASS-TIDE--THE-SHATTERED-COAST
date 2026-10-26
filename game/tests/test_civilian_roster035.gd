extends SceneTree
## Focused v035 roster, physical bills, canonical births and one funded yard/market flow.
## Reference rows freeze the complete v034 hull definitions; no full-game suite is invoked.
const Campaign=preload("res://scripts/campaign.gd")
const Construction=preload("res://scripts/construction.gd")
const Harbor=preload("res://scripts/harbor.gd")
const Refits=preload("res://scripts/refit.gd")
const Births=preload("res://scripts/equipment_lifecycle.gd")
const Core=preload("res://scripts/equipment_condition.gd")
const Records=preload("res://scripts/equipment_records.gd")
const Money=preload("res://scripts/money.gd")
const Goods=preload("res://scripts/goods.gd")
const Deployment=preload("res://scripts/deployment.gd")
const SaveValidation=preload("res://scripts/save_validation.gd")
const Manifest=preload("res://scripts/hold_manifest.gd")
const Expedition=preload("res://scripts/expedition.gd")
const Economy=preload("res://scripts/economy.gd")
const LEGACY_KEYS: Array=["name","faction","role","tier","hp","armor","speed","turn","crewMin","crewOptimal","crewMax","cargo","weapon","fireRate","damage","range","size","pumps","description"]
const LEGACY_ROWS: Array=[
	["tin_skiff","Tinwake Skiff","compact","skiff",1,150,2,118,2.65,3,5,8,60,"gun",2.2,12,340,14,2.4,"Riveted utility harbor skiff fitted with a pintle heavy autocannon. Cheap, nimble, and dependable in a scrape."],
	["bilge_punt","Bilgewater Punt","raiders","skiff",1,135,1,122,2.75,3,4,7,45,"gun",2,10,310,13,2,"Patchwork reef skiff stripped of bulkheads for speed. Common among outer-channel lookouts and blockade scouts."],
	["lantern_skiff","Lantern Ward Skiff","compact","skiff",2,210,4,126,2.55,4,7,10,75,"gun",2.5,14,365,15,3,"Up-engined customs skiff with twin-fed rotary carbines and reinforced bilge stringers."],
	["marsh_dart","Marsh Dart Hydro","reed","cutter",1,140,2,142,2.9,3,5,8,50,"gun",2.4,11,330,14,2.3,"Shallow-step hydroplane cutter that skims across shoal water to run down smugglers."],
	["scab_cutter","Scabfin Cutter","raiders","cutter",2,230,4,138,2.6,5,8,12,70,"gun",2.6,15,360,17,3.1,"Twin-screw raider cutter with saw-toothed bow fenders and rapid-fire casemate repeaters."],
	["gale_cutter","Galeblade Interceptor","reed","cutter",3,310,6,148,2.7,6,11,15,85,"gun",2.9,18,390,18,3.8,"Supercharged commune pursuit craft built to outflank heavy flotillas and shred exposed gun crews."],
	["silt_lugger","Silt Runner Lugger","reed","raider",1,185,3,104,2.1,4,6,10,130,"gun",1.9,13,345,17,2.8,"Broad-beamed estuary freighter with concealed deck guns and cavernous dry-cargo holds."],
	["hook_raider","Grapnel Blockade Runner","raiders","raider",2,275,6,120,2.2,6,10,15,165,"cannon",1.15,24,410,20,3.5,"Fast contraband runner carrying a low-velocity deck howitzer and reinforced smuggling lockers."],
	["mercantile_clipper","Sovereign Armed Packet","compact","raider",3,380,9,116,1.95,8,14,20,230,"cannon",1.3,28,440,23,4.5,"Armored Compact treasury packet capable of hauling bulk high-value cargo right through a cordon."],
	["harbor_sloop","Breakwater Patrol Sloop","compact","corvette",1,195,4,108,2.2,4,7,11,80,"cannon",1.1,20,385,17,2.9,"Sturdy brass-trimmed sloop mounting a quick-firing bow pounder for coastal convoy duty."],
	["ash_corvette","Ashwake Escort Corvette","forge","corvette",2,310,8,102,1.9,7,12,17,105,"cannon",1.2,26,430,21,3.9,"Welded foundry corvette with turtleback armored decking and a high-velocity turret gun."],
	["aegis_corvette","Vanguard Line Corvette","compact","corvette",3,430,11,106,1.85,9,16,23,125,"cannon",1.35,31,470,24,4.8,"Fleet-standard Compact escort vessel balancing rangefinder gunnery with compartmentalized flood control."],
	["reed_stinger","Fen Stinger Torpedo Launch","reed","torpedo",2,215,4,136,2.5,5,8,12,60,"torpedo",0.55,36,420,17,3.2,"Low-profile marsh launch carrying twin compressed-air drop collars for close-range hull breaches."],
	["krill_torpedo","Tallowfin Torpedo Boat","raiders","torpedo",3,320,7,134,2.35,7,12,17,75,"torpedo",0.65,42,465,20,4,"Raider wolfpack strike craft built around centerline reloads that crack heavy armor belts open."],
	["manta_strike","Manta Flotilla Leader","reed","torpedo",4,450,10,132,2.25,11,18,25,100,"torpedo",0.75,48,510,24,5.2,"Premier hydro-foil torpedo destroyer capable of devastating dreadnought formations at high speed."],
	["slag_gunboat","Slagclast River Gunboat","forge","gunboat",2,350,10,86,1.65,8,13,19,95,"cannon",0.95,32,460,22,4.2,"Casemate ironclad gunboat built to trade broadsides in narrow industrial straits."],
	["bellows_gunboat","Bellows Siege Gunboat","forge","gunboat",3,490,14,80,1.5,11,18,26,120,"cannon",1.05,39,520,26,5.4,"Twin-turret foundry monitor whose heavy armor shrugs off small-caliber gunfire."],
	["furnace_turret","Furnace Sovereign Monitor","forge","gunboat",4,610,18,72,1.3,15,25,34,145,"cannon",1.1,46,575,30,6.4,"Floating steel bastion mounting a long-barrel coastal siege rifle and high-volume steam bilge ejectors."],
	["barbed_lance","Sparkrack Rocket Scow","raiders","rocket",2,260,6,98,1.85,6,10,15,80,"rocket",0.85,30,480,20,3.4,"Converted ore barge fitted with angled incendiary rocket rails that saturate enemy decks with fire."],
	["cinder_monitor","Pyreclast Rocket Monitor","forge","rocket",3,420,12,88,1.6,10,17,24,110,"rocket",0.95,37,545,25,4.9,"Armored bombardment platform firing spin-stabilized thermite rockets across long open-water lanes."],
	["wraith_rocket","Hellbore Salvo Cruiser","raiders","rocket",4,540,14,94,1.55,14,24,32,135,"rocket",1.05,44,600,29,5.8,"Heavy raider battery vessel built to rain salvos from extreme range before closing for the kill."],
	["cobalt_frigate","Cobalt Commodore Frigate","compact","cruiser",2,390,10,96,1.7,9,15,22,140,"cannon",1.25,29,465,24,4.5,"Command frigate equipped with armored sponsons, dual diesel-turbines, and brigade damage-control teams."],
	["iron_bastion","Bastion Armored Cruiser","compact","cruiser",3,560,16,84,1.4,14,24,33,175,"cannon",1.2,41,550,31,6,"Heavy fleet flagship of the Compact, built to anchor battle lines and absorb punishing salvos."],
	["maiden_dreadnought","Shatter Throne Dreadnought","forge","cruiser",4,700,20,68,1.15,22,36,48,220,"cannon",1.15,50,620,36,7.5,"Apex capital warship of the Shatter Coast: triple-belted krupp steel, twin siege turrets, and massive bilge manifolds."],
]
## Accepted names, existing combat roles, civilian tags and crew/cargo/fuel capacities.
const CIVILIANS: Dictionary={
	"kelpnet_dory":["Kelpnet Dory","reed","skiff","fishing",1,13,3,4,6,35,40],
	"brinehook_longliner":["Brinehook Longliner","compact","skiff","fishing",2,15,3,5,8,55,60],
	"mother_gull_trawler":["Mother Gull Trawler","reed","raider","fishing",2,19,4,7,11,110,100],
	"fenhopper_lighter":["Fenhopper Lighter","reed","raider","transport",1,17,4,6,10,140,90],
	"tideledger_coaster":["Tideledger Coaster","compact","raider","transport",2,21,5,9,14,200,140],
	"fourport_packet":["Fourport Packet","compact","raider","transport",3,24,7,12,18,260,180],
	"brasswind_motor_galleon":["Brasswind Motor-Galleon","compact","raider","transport",3,28,9,16,24,340,240],
	"seepoil_tanker":["Seepoil Tanker Barge","forge","corvette","tanker",2,20,5,8,13,150,130],
	"blackwater_fleet_tanker":["Blackwater Fleet Tanker","forge","corvette","tanker",3,27,8,14,22,280,220],
	"gullwing_daysailer":["Gullwing Daysailer","reed","cutter","yacht",1,14,3,4,7,20,55],
	"osprey_cabin_cruiser":["Lacquered Osprey Cruiser","compact","cutter","yacht",2,17,3,6,10,30,80],
	"aurelian_court_yacht":["Aurelian Viceroy Yacht","compact","cruiser","yacht",3,25,6,12,20,45,160],
}
## Frozen physical reference bills: materials in MATERIAL_ORDER, ordinary/expert days, commission/ready coins.
const REFERENCE_BILLS: Dictionary={
	"kelpnet_dory":[[3.73,1.62,1.28,0.7,1.32,1,1,0.97],21.43,6.05,37473,38207],
	"brinehook_longliner":[[5.62,2.16,1.79,0.89,2.0,1,1,1.08],30.14,8.04,40940,41949],
	"mother_gull_trawler":[[20.24,5.58,5.94,2.42,6.49,2,1,2.91],99.1,23.87,87701,90830],
	"fenhopper_lighter":[[16.66,4.7,4.61,2.03,5.14,2,1,2.63],80.8,19.81,80502,83085],
	"tideledger_coaster":[[25.67,6.6,7.08,2.83,7.89,2,1,3.26],120.95,28.53,96223,100006],
	"fourport_packet":[[33.84,8.23,9.28,3.77,10.31,3,1,4.59],159.27,37.6,130981,135873],
	"brasswind_motor_galleon":[[46.07,10.59,12.89,4.86,14.01,3,1,5.46],213.73,49.39,152460,158948],
	"seepoil_tanker":[[23.05,6.19,6.54,2.81,7.75,2,1,3.09],111.95,26.51,92710,96221],
	"blackwater_fleet_tanker":[[42.32,10.03,12.06,4.76,13.62,3,1,5.21],200.06,46.36,147135,153220],
	"gullwing_daysailer":[[6.89,2.67,2.0,1.02,2.35,1,1,1.22],36.66,9.3,43185,44454],
	"osprey_cabin_cruiser":[[15.78,3.96,3.66,1.67,6.95,2,1,2.32],63.88,16.03,76073,78140],
	"aurelian_court_yacht":[[41.32,8.52,10.25,3.9,16.81,3,1,4.67],168.46,39.49,138992,144113],
}
var checks: int=0
var failures: int=0
var c
var bills: Array=[]

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL civilian roster035: ",message)

func same_data(a,b) -> bool:
	if (a is int or a is float) and (b is int or b is float):return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same_data(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in range(a.size()):
			if not same_data(a[i],b[i]):return false
		return true
	return a==b

func people() -> int:
	var total: int=c.crew_count()
	for p in c.state.ports:total+=int(p.workforce)
	for owner in c.state.fleetOwners:
		for boat in owner.boats:total+=int(boat.crew)
	return total

func _initialize() -> void:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	_test_roster_and_bills(world)
	_write_bills()
	c=Campaign.new(world)
	var started: Dictionary=c.new_game(3501)
	check(bool(started.ok),"36-hull world publishes an actual canonical career: "+str(started.get("message","")))
	if started.ok:
		_test_catalogue()
		_test_births()
		_test_paid_yard_and_market()
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

func _test_roster_and_bills(world: Dictionary) -> void:
	var by_id: Dictionary={}
	var names: Dictionary={}
	var counts: Dictionary={"fishing":0,"transport":0,"tanker":0,"yacht":0}
	for h in world.HULLS:
		check(not by_id.has(h.id) and not names.has(h.name),"unique original hull identity: "+str(h.id))
		by_id[h.id]=h;names[h.name]=true
		if counts.has(h.get("civilianRole","")):counts[h.civilianRole]+=1
	check(world.HULLS.size()==LEGACY_ROWS.size()+CIVILIANS.size(),"only the accepted twelve extend the original roster to36")
	check(counts=={"fishing":3,"transport":4,"tanker":2,"yacht":3},"exact fishing/transport/tanker/yacht distribution")
	for row in LEGACY_ROWS:
		var h: Dictionary=by_id.get(row[0],{})
		var unchanged: bool=h.size()==LEGACY_KEYS.size()+1
		for i in range(LEGACY_KEYS.size()):unchanged=unchanged and h.get(LEGACY_KEYS[i])==row[i+1]
		check(unchanged,"complete previous hull definition unchanged: "+str(row[0]))
	var keys: Array=["name","faction","role","civilianRole","tier","size","crewMin","crewOptimal","crewMax","cargo","fuelCapacity"]
	for id in CIVILIANS:
		var h: Dictionary=by_id.get(id,{})
		check(not h.is_empty(),"accepted civilian blueprint exists: "+id)
		if h.is_empty():continue
		var exact: bool=true
		for i in range(keys.size()):exact=exact and h.get(keys[i])==CIVILIANS[id][i]
		check(exact,"accepted name, role, scale, crew and capacities: "+id)
		check(h.role in Construction.ROLE_GEOMETRY and h.weapon=="gun" and h.weaponCount==1 and h.damage<=12 and h.armor>=1 and h.armor<=6 and h.hp<=430 and h.turn>0 and h.pumps>0 and not h.has("price"),"working civilian physics and one light stock gun without an authored coin price: "+id)
		var q: Dictionary=Construction.quote(h)
		var reference: Array=REFERENCE_BILLS[id]
		var quantities: Array=[]
		for good in Construction.MATERIAL_ORDER:quantities.append(q.materials[good])
		check(same_data(quantities,reference[0]) and is_equal_approx(q.ordinaryDays,reference[1]) and is_equal_approx(q.expertDays,reference[2]) and q.commissionPrice==reference[3] and q.readyPrice==reference[4],"physical reference materials, worker/expert days and derived prices: "+id)
		var material_cost: int=0
		for good in q.materials:material_cost+=maxi(1,roundi(float(q.materials[good])*Goods.cost(good)))
		var ordinary_cost: int=0
		var expert_cost: int=0
		for occupation in Construction.ORDINARY_OCCUPATIONS:ordinary_cost+=maxi(1,roundi(float(q.ordinaryLabor[occupation])*int(Goods.WAGES[occupation])))
		for occupation in Construction.EXPERT_OCCUPATIONS:expert_cost+=maxi(1,roundi(float(q.expertLabor[occupation])*int(Goods.WAGES[occupation])))
		var item_sum: int=0
		for item in q.lineItems:item_sum+=int(item.cost)
		check(q.materialCost==material_cost and q.laborCost==ordinary_cost and q.supervisionCost==expert_cost and q.total==item_sum and q.total==q.materialCost+q.laborCost+q.supervisionCost+q.overhead+q.margin+q.tax and q.readyPrice==q.total+q.readyStorageCost and int(q.wages.laborer)==100 and Goods.SAILOR_WAGE==100,"all priced materials, workers, experts, margin, tax and ready storage reconcile: "+id)
		var ignored_price: Dictionary=h.duplicate(true)
		ignored_price.price=1
		check(Construction.quote(ignored_price).readyPrice==q.readyPrice,"construction remains the authoritative price: "+id)
		bills.append({"id":id,"name":h.name,"civilianRole":h.civilianRole,"role":h.role,"readyPrice":q.readyPrice,"commissionPrice":q.commissionPrice,"materials":q.materials,"ordinaryWorkerDays":q.ordinaryDays,"expertDays":q.expertDays,"ordinaryLabor":q.ordinaryLabor,"expertLabor":q.expertLabor,"dailyCrewPay":int(h.crewOptimal)*Goods.SAILOR_WAGE,"minimumDailyCrewPay":int(h.crewMin)*Goods.SAILOR_WAGE,"maximumDailyCrewPay":int(h.crewMax)*Goods.SAILOR_WAGE,"fuelCapacity":h.fuelCapacity,"basis":h.description,"lineItems":q.lineItems,"readyStorageCost":q.readyStorageCost})

func _write_bills() -> void:
	var folder: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	check(not folder.is_empty(),"Test Bridge provides the bill artifact directory")
	if folder.is_empty():return
	var made: Error=DirAccess.make_dir_recursive_absolute(folder)
	check(made==OK or made==ERR_ALREADY_EXISTS,"bill artifact directory is available")
	if made!=OK and made!=ERR_ALREADY_EXISTS:return
	var file: FileAccess=FileAccess.open(folder.path_join("CIVILIAN COSTS v0.035.json"),FileAccess.WRITE)
	check(file!=null,"actual quote artifact opens")
	if file==null:return
	file.store_string(JSON.stringify({"version":"0.035","basis":"Existing Construction.quote at recursive Goods prices; 100 coins per sailor-day. Working fuel, ammunition and supplies are purchased separately.","hulls":bills},"\t"))
	file.close()
	check(bills.size()==CIVILIANS.size(),"cost artifact contains all twelve actual bills")

func _test_catalogue() -> void:
	var offered: Dictionary={}
	for p in c.state.ports:
		var before: Dictionary=p.duplicate(true)
		var ids: Array=Harbor.catalogue(c,p)
		check(same_data(p,before),"catalogue read leaves actual stock, coins and yard unchanged: "+str(p.id))
		for id in p.shipIds:check(id in ids,"existing yard drawing retained: "+str(id))
		for id in CIVILIANS:
			var h: Dictionary=c.hull(id)
			if id in ids:
				offered[id]=true
				check(h.faction==p.faction and int(p.shipStock.get(id,0))==0,"matching-faction civilian is commissionable without free ready stock: "+id)
		ids.append("detached-fixture-only")
		check(not "detached-fixture-only" in Harbor.catalogue(c,p),"catalogue returns a detached list")
	check(offered.size()==CIVILIANS.size(),"all twelve designs are available through actual faction harbor catalogues")

func _test_births() -> void:
	var before: Dictionary=c.state.duplicate(true)
	var fleet: Array=[]
	for id in CIVILIANS:
		var h: Dictionary=c.hull(id)
		check(h.price==Construction.quote(h).readyPrice,"Campaign publishes the computed catalogue price: "+id)
		var staged: Dictionary=Births.stage_birth(c.state,c.data,h,"civilian035-"+id,{})
		check(bool(staged.ok),"actual canonical equipment birth: "+id+" "+str(staged.get("message","")))
		if not staged.ok:continue
		var boat: Dictionary=Births.materialize(h,int(h.crewOptimal),staged,true)
		Refits.ensure(boat,h)
		boat.spec=Refits.effective_spec(h,boat.loadout)
		var records: Dictionary=Records.snapshot(boat)
		var installed: Dictionary=Core.inspect_installed(boat.moduleCondition)
		check(records.ok and not records.get("needsInitialize",true) and installed.ok and installed.items.size()==4 and records.engineFactor>0 and records.pumpFactor>0,"canonical engine, armor, pumps and one paid gun remain operational: "+id)
		var sockets: Array=Refits.hardpoints(h)
		var empty_optional: bool=boat.loadout.weapons[0]=="stock_primary"
		for i in range(1,sockets.size()):empty_optional=empty_optional and boat.loadout.weapons[i]==""
		check(empty_optional and boat.spec.weaponMounts.size()==1 and boat.spec.weaponMounts[0].id==sockets[0].id and boat.spec.weaponMounts[0].x==sockets[0].x and boat.spec.weaponMounts[0].y==sockets[0].y and boat.fuel==0 and boat.ammo==0 and boat.supplies==0,"one physical stock mount, empty optional sockets and no free working stores: "+id)
		var upgrade: Dictionary=boat.loadout.duplicate(true)
		upgrade.weapons[1]="rapid_gun";upgrade.engine="economy_drive"
		var valid: Dictionary=Refits.normalize(h,upgrade)
		check(valid.ok,"existing optional weapon and economy-drive refits remain valid: "+id)
		if valid.ok:
			var fitted: Dictionary=Refits.effective_spec(h,valid.loadout)
			check(fitted.civilianRole==h.civilianRole and fitted.cargo==h.cargo and fitted.fuelCapacity==h.fuelCapacity and fitted.weaponMounts.size()==2 and fitted.weaponMounts[1].id==sockets[1].id and fitted.fuelUse<1.0,"fitted role, holds, tanks and mount identities persist: "+id)
		upgrade.weapons[1]="stock_primary"
		check(not Refits.normalize(h,upgrade).ok,"stock gun cannot be cloned into an optional hardpoint: "+id)
		var good: String={"fishing":"preserved_fish","transport":"timber","tanker":"fuel","yacht":"food"}[h.civilianRole]
		var cargo: Dictionary={good:4.0}
		var manifest: Dictionary={"fleet":[boat],"cargo":cargo}
		Manifest.allocate(manifest)
		check(boat.crew==h.crewOptimal and Expedition.capacity(manifest)==h.cargo and manifest.cargoManifest.get(boat.uid,{}).get(good,0)==4.0 and not manifest.cargoManifest.has("unassigned"),"role cargo fits its actual crewed carrier: "+id)
		fleet.append(boat)
	var deployment: Dictionary=Deployment.split(fleet)
	check(Deployment.LIMIT==300 and deployment.points<=300 and not deployment.reserve.is_empty() and deployment.deployed.size()+deployment.reserve.size()==fleet.size(),"civilian hulls share the unchanged300-point deployment limit")
	check(same_data(c.state,before),"private staged births/refit previews never grant hulls, people, stores or coins to the campaign")

func _fund(amount: int,p: Dictionary) -> void:
	var needed: int=maxi(0,amount-int(c.state.coins))
	check(Money.move(p,"governmentPurse",c.state,"coins",needed,"Finite fixture funding",c.state.moneyLog),"existing government coins fund the actual transaction")

func _gather_materials(p: Dictionary,materials: Dictionary) -> void:
	# Move existing lots between fixture harbors; never create materials.
	for good in materials:
		var needed: float=maxf(0,float(materials[good])-float(p.stocks[good]))
		for source in c.state.ports:
			if source.id==p.id:continue
			var qty: float=minf(needed,float(source.stocks[good]))
			source.stocks[good]-=qty;p.stocks[good]+=qty;needed-=qty
			if needed<=0.000001:break
		check(needed<=0.000001,"physical existing stocks cover "+str(good))

func _test_paid_yard_and_market() -> void:
	var p: Dictionary=c.current_port()
	var h: Dictionary=c.hull("brinehook_longliner")
	var total: int=Money.total(c.state)
	var headcount: int=people()
	check(not c.buy_boat(h.id).ok,"a new drawing cannot be bought as an unbuilt free hull")
	Money.move(c.state,"coins",p,"governmentPurse",int(c.state.coins))
	var refused: Dictionary=c.state.duplicate(true)
	check(not c.commission(h.id).ok and same_data(c.state,refused),"unfunded civilian commission refuses atomically")
	_gather_materials(p,Construction.blueprint(h).materials)
	var q: Dictionary=c.ship_quote(h,p)
	_fund(int(q.commissionPrice)+int(q.readyPrice)+20000,p)
	var coins: int=int(c.state.coins)
	var stocks: Dictionary=p.stocks.duplicate(true)
	var household: int=int(p.householdPurse)
	var experts: int=int(p.expertPurse)
	var tax: int=int(p.governmentPurse)
	var result: Dictionary=c.commission(h.id)
	check(result.ok,"actual visible-catalogue civilian commission accepts funded payment: "+str(result.get("message","")))
	if not result.ok:return
	check(int(c.state.coins)==coins-int(q.commissionPrice) and int(p.governmentPurse)==tax+int(q.tax) and Money.total(c.state)==total and people()==headcount,"commission pays the exact bill and duty while conserving finite coins and people")
	for good in q.materials:check(is_equal_approx(float(stocks[good])-float(p.stocks[good]),float(q.materials[good])),"commission consumes quoted real material: "+str(good))
	var order: Dictionary=p.buildQueue[-1]
	check(not order.ready and order.escrow==q.laborCost+q.supervisionCost and not c.collect_boat(p.buildQueue.size()-1).ok,"unworked hull retains actual wage escrow and cannot launch")
	var available: float=float(p.availableSpecialists)
	p.availableSpecialists=0
	Construction.begin_day(p)
	var blocked: Dictionary=Construction.advance(p,order,1.0)
	check(blocked.spent==0 and blocked.workedDays==0 and p.householdPurse==household and p.expertPurse==experts and Money.total(c.state)==total,"no expert availability means no work or wages")
	p.availableSpecialists=available
	Construction.begin_day(p)
	Construction.advance(p,order,float(q.estimatedDays)+1.0)
	check(order.ready and order.escrow==0 and order.laborPaid==q.laborCost and order.supervisionPaid==q.supervisionCost and p.householdPurse==household+int(q.laborCost) and p.expertPurse==experts+int(q.supervisionCost),"bounded actual yard work pays the exact existing worker and expert purses")
	var collected: Dictionary=c.collect_boat(p.buildQueue.size()-1)
	check(collected.ok and Money.total(c.state)==total and people()==headcount,"paid completed civilian hull collects without creating crew or coins")
	if not collected.ok:return
	var boat: Dictionary=c.state.fleet[-1]
	check(boat.type==h.id and boat.crew==0 and boat.mothballed and boat.fuel==0 and boat.ammo==0 and boat.supplies==0 and Records.snapshot(boat).ok,"commission publishes canonical equipment with empty crew and working stores")
	var hire: int=Economy.recruit_cost(p,int(h.crewMin))
	var crew_purse: int=int(c.state.crewPurse)
	var recruited: Dictionary=c.recruit_crew(boat.uid,int(h.crewMin))
	check(recruited.ok and boat.crew==h.crewMin and not boat.mothballed and c.state.crewPurse==crew_purse+hire and people()==headcount and Money.total(c.state)==total,"minimum sailors transfer from the actual workforce with their paid advance")
	stocks=p.stocks.duplicate(true)
	check(c.resupply_boat(boat.uid,"voyage").ok and boat.fuel==3.0 and boat.ammo==80.0 and boat.supplies==6.0,"civilian hull buys usable working stores through the existing harbor path")
	for good in ["fuel","ammo","supplies"]:check(is_equal_approx(float(stocks[good]),float(p.stocks[good])+float(boat[good])/(Goods.ROUNDS_PER_CASE if good=="ammo" else 1.0)),"working stores retain actual finite custody: "+good)
	var sold_uid: String=boat.uid
	var sold: Dictionary=c.sell_boat(boat.uid)
	check(sold.ok and int(p.shipStock.get(h.id,0))==1 and people()==headcount and Money.total(c.state)==total,"actual yard purchase creates the new stock key with returned sailors and finite coins")
	if not sold.ok:return
	var stocked: Dictionary=SaveValidation.validate(JSON.parse_string(JSON.stringify(c.state)),c.data)
	check(stocked.ok,"real positive civilian shipStock validates: "+str(stocked.get("message","")))
	q=c.ship_quote(h,p);hire=Economy.recruit_cost(p,int(h.crewMin))
	_fund(int(q.readyPrice)+hire+1000,p)
	coins=int(c.state.coins);crew_purse=int(c.state.crewPurse)
	var bought: Dictionary=c.buy_boat(h.id)
	check(bought.ok and int(c.state.coins)==coins-int(q.readyPrice)-hire and int(c.state.crewPurse)==crew_purse+hire and int(p.shipStock.get(h.id,-1))==0,"existing ready-market callback buys civilian stock at its authoritative quote and crew advance")
	if not bought.ok:return
	boat=c.state.fleet[-1]
	check(boat.type==h.id and boat.uid!=sold_uid and boat.crew==h.crewMin and Records.snapshot(boat).ok and people()==headcount and Money.total(c.state)==total,"ready civilian acquisition publishes one unique canonical hull without minting people or coins")
	boat.hp-=7.0
	var before: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	var restored: Dictionary=c.restore(before.duplicate(true))
	check(restored.ok,"paid civilian and actual stock keys restore: "+str(restored.get("message","")))
	if not restored.ok:return
	check(same_data(c.state.fleet,before.fleet),"restore preserves complete fleet JSON including civilian spec, crew, damage, loadout, equipment UIDs and conditions")
	check(same_data(c.state.ports,before.ports) and Money.total(c.state)==total and people()==headcount,"restore preserves actual yard stock, materials, worker/expert purses and conserved people/coins")
