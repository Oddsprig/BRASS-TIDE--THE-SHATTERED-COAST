extends RefCounted
## Paid, atomic fitting. Pure dictionaries; no campaign/economy dependency cycle.
const Goods=preload("res://scripts/goods.gd")
const Money=preload("res://scripts/money.gd")
const Deployment=preload("res://scripts/deployment.gd")
const Construction=preload("res://scripts/construction.gd")
const MAX_LOCKER: int=256
const MAX_COINS: float=9007199254740991.0

static func _number(value,fallback: float=0.0) -> float:
	return float(value) if (value is int or value is float) and is_finite(float(value)) else fallback

static func _whole(value) -> bool:
	var n: float=_number(value,-1.0)
	return n>=0.0 and n<=MAX_COINS and floor(n)==n

static func _fail(message: String) -> Dictionary:
	return {"ok":false,"error":message,"message":message}

static func _weapon(name: String,kind: String,size: int,op: int,damage: float,rate: float,distance: float,speed: float,ammo: int,materials: Dictionary,days: float,experts: float,description: String) -> Dictionary:
	return {"name":name,"label":name,"description":description,"kind":kind,"size":size,"op":op,"points":op,"damage":damage,"fireRate":rate,"range":distance,"speed":speed,"ammoCost":ammo,"materials":materials,"workerDays":days,"expertDays":experts}

static func catalog() -> Dictionary:
	return {
		"weapons":{
			"":{"name":"Empty hardpoint","label":"Empty hardpoint","description":"Remove the weapon into this boat's locker.","kind":"","size":0,"op":0,"points":0,"materials":{},"workerDays":0.5,"expertDays":0.25},
			"stock_primary":_weapon("Original primary","stock",1,2,0,0,0,0,1,{"guns":1,"supplies":1},2.0,0.5,"The hull's original paid primary weapon; main hardpoint only."),
			"rapid_gun":_weapon("Needle machine gun","gun",1,3,11,4.0,420,900,1,{"guns":1,"iron":0.3,"supplies":1},2.0,0.5,"Rapid close defense; light mount and one round per shot."),
			"heavy_gun":_weapon("Twin machine guns","gun",2,5,16,4.2,470,920,1,{"guns":2,"iron":1,"supplies":2},3.0,0.75,"Heavy rapid battery with better reach and sustained damage."),
			"light_cannon":_weapon("Harbor cannon","cannon",1,5,26,1.3,480,650,1,{"guns":1,"iron":2,"timber":0.5,"supplies":2},3.0,0.75,"Compact impact cannon; moderate rate and range."),
			"heavy_cannon":_weapon("Long iron cannon","cannon",3,8,48,1.0,620,690,2,{"guns":2,"iron":5,"timber":1,"supplies":3},5.0,1.25,"Long-range heavy impact; two rounds per discharge."),
			"fire_rocket":_weapon("Ember rocket rack","rocket",1,6,32,0.9,550,730,2,{"guns":1,"iron":1,"fuel":1,"supplies":2},3.0,0.75,"Fixed incendiary rockets with a small blast radius."),
			"salvo_rocket":_weapon("Storm rocket rack","rocket",3,9,48,1.0,620,760,3,{"guns":2,"iron":3,"fuel":2,"supplies":3},5.0,1.25,"Heavy fixed rocket battery; expensive ammunition salvos."),
			"light_torpedo":_weapon("Reed torpedo tube","torpedo",1,6,38,0.65,480,280,2,{"guns":1,"iron":2,"copper":0.5,"fuel":1,"supplies":2},3.0,0.75,"Fixed waterline attacks that penetrate armor."),
			"heavy_torpedo":_weapon("Deepwater torpedo tubes","torpedo",3,9,58,0.55,620,270,3,{"guns":2,"iron":5,"copper":1,"fuel":2,"supplies":3},5.0,1.25,"Long-range heavy torpedoes; three rounds per launch.")
		},
		"engines":{
			"stock_engine":{"name":"Original engine","description":"Original paid hull performance.","size":1,"op":0,"points":0,"speedMult":1.0,"turnMult":1.0,"fuelUse":1.0,"materials":{"engines":1,"supplies":1},"workerDays":3.0,"expertDays":0.75},
			"economy_drive":{"name":"Long-voyage engine","description":"Consumes less fuel; slightly lower speed.","size":1,"op":2,"points":2,"speedMult":0.94,"turnMult":1.04,"fuelUse":0.68,"materials":{"engines":1,"copper":0.5,"supplies":2},"workerDays":4.0,"expertDays":1.0},
			"boost_drive":{"name":"Racing engine","description":"Faster acceleration speed and turning at higher fuel use.","size":1,"op":4,"points":4,"speedMult":1.18,"turnMult":1.08,"fuelUse":1.35,"materials":{"engines":1,"iron":2,"copper":1,"supplies":2},"workerDays":5.0,"expertDays":1.25},
			"heavy_drive":{"name":"Twin marine engines","description":"High power and fuel demand; requires a larger hull.","size":2,"op":7,"points":7,"speedMult":1.32,"turnMult":0.95,"fuelUse":1.65,"materials":{"engines":2,"iron":3,"copper":1,"supplies":3},"workerDays":8.0,"expertDays":2.0}
		},
		"armor":{
			"stock_armor":{"name":"Original hull armor","description":"Original paid protection and speed.","size":1,"op":0,"points":0,"armorAdd":0.0,"speedMult":1.0,"turnMult":1.0,"materials":{"iron":2,"supplies":1},"workerDays":2.0,"expertDays":0.5},
			"scout_plating":{"name":"Riveted light plates","description":"Three additional armor; a small speed penalty.","size":1,"op":2,"points":2,"armorAdd":3.0,"speedMult":0.97,"turnMult":0.99,"materials":{"iron":3,"timber":0.5,"supplies":2},"workerDays":3.0,"expertDays":0.5},
			"naval_plating":{"name":"Naval armor belt","description":"Eight additional armor; lower speed and turning.","size":2,"op":5,"points":5,"armorAdd":8.0,"speedMult":0.89,"turnMult":0.95,"materials":{"iron":7,"timber":1,"supplies":3},"workerDays":6.0,"expertDays":1.0},
			"fortress_plating":{"name":"Fortress armor","description":"Fifteen additional armor; heavy speed and turning penalties.","size":3,"op":9,"points":9,"armorAdd":15.0,"speedMult":0.78,"turnMult":0.90,"materials":{"iron":12,"timber":1,"supplies":4},"workerDays":10.0,"expertDays":2.0}
		}
	}

static func _size(spec: Dictionary) -> int:
	var size: float=_number(spec.get("size"),14.0)
	return 1 if size<19.0 else (2 if size<27.0 else 3)

static func hardpoints(spec: Dictionary) -> Array:
	var size: float=clampf(_number(spec.get("size"),14.0),8.0,48.0)
	var mount_size: int=_size(spec)
	var result: Array=[{"id":"mount0","label":"Main deck","size":mount_size,"x":size*0.65,"y":0.0,"arc":TAU,"angle":0.0},{"id":"mount1","label":"Aft deck","size":maxi(1,mount_size-1),"x":-size*0.60,"y":0.0,"arc":TAU,"angle":PI}]
	if size>=20.0:
		result.append({"id":"mount2","label":"Port deck","size":maxi(1,mount_size-1),"x":0.0,"y":-size*0.48,"arc":PI*1.25,"angle":-PI/2.0})
	if size>=28.0:
		result.append({"id":"mount3","label":"Starboard deck","size":maxi(1,mount_size-1),"x":0.0,"y":size*0.48,"arc":PI*1.25,"angle":PI/2.0})
	return result

static func defaults(spec: Dictionary) -> Dictionary:
	var weapons: Array[String]=[]
	for i in range(hardpoints(spec).size()): weapons.append("stock_primary" if i==0 else "")
	return {"weapons":weapons,"engine":"stock_engine","armor":"stock_armor"}

static func _budget(spec: Dictionary) -> int:
	return clampi(8+int(maxf(0.0,_number(spec.get("tier"),1.0)-1.0))*3+int(maxf(0.0,_number(spec.get("size"),14.0)-13.0)*0.75),8,36)

static func normalize(spec: Dictionary,loadout: Dictionary) -> Dictionary:
	var input: Dictionary=defaults(spec) if loadout.is_empty() else loadout
	for key in input:
		if key not in ["weapons","engine","armor"]: return _fail("Unknown fitting field: "+str(key))
	if not input.get("weapons") is Array or not input.get("engine") is String or not input.get("armor") is String:
		return _fail("A fitting needs weapon IDs, an engine ID and an armor ID.")
	var mounts: Array=hardpoints(spec)
	if input.weapons.size()!=mounts.size(): return _fail("Weapon slots do not match this hull's hardpoints.")
	var cat: Dictionary=catalog()
	var clean: Dictionary={"weapons":[],"engine":input.engine,"armor":input.armor}
	var points: int=0
	for i in range(mounts.size()):
		var id=input.weapons[i]
		if not id is String or not cat.weapons.has(id): return _fail("Unknown weapon module.")
		var module: Dictionary=cat.weapons[id]
		if (id=="stock_primary" and i!=0) or int(module.size)>int(mounts[i].size): return _fail("That weapon does not fit this hardpoint.")
		clean.weapons.append(id)
		points+=int(module.op)
	for pair in [["engine","engines"],["armor","armor"]]:
		var id: String=input[pair[0]]
		if not cat[pair[1]].has(id): return _fail("Unknown "+str(pair[0])+" module.")
		var module: Dictionary=cat[pair[1]][id]
		if int(module.size)>_size(spec): return _fail("That "+str(pair[0])+" is too large for this hull.")
		points+=int(module.op)
	var maximum: int=_budget(spec)
	if points>maximum: return _fail("Fitting needs %d points; this hull has %d."%[points,maximum])
	return {"ok":true,"loadout":clean,"usedPoints":points,"maxPoints":maximum}

static func effective_spec(base: Dictionary,loadout: Dictionary) -> Dictionary:
	var normalized: Dictionary=normalize(base,loadout)
	if not normalized.ok: return {}
	var fit: Dictionary=normalized.loadout
	var cat: Dictionary=catalog()
	var engine: Dictionary=cat.engines[fit.engine]
	var armor: Dictionary=cat.armor[fit.armor]
	var result: Dictionary=base.duplicate(true)
	result.speed=maxf(0.0,_number(base.get("speed"),100.0))*engine.speedMult*armor.speedMult
	result.turn=maxf(0.0,_number(base.get("turn"),2.0))*engine.turnMult*armor.turnMult
	result.armor=maxf(0.0,_number(base.get("armor")))+armor.armorAdd
	result.hp=maxf(1.0,_number(base.get("hp"),150.0))
	result.fuelUse=engine.fuelUse
	result.weaponMounts=[]
	var points: Array=hardpoints(base)
	for i in range(points.size()):
		var id: String=fit.weapons[i]
		if id.is_empty(): continue
		var module: Dictionary=cat.weapons[id].duplicate(true)
		var original: bool=id=="stock_primary"
		if original:
			module.kind=str(base.get("weapon","gun"))
			for key in ["damage","fireRate","range"]: module[key]=_number(base.get(key),12.0 if key=="damage" else (2.0 if key=="fireRate" else 340.0))
			module.speed=240.0 if module.kind=="torpedo" else (730.0 if module.kind=="rocket" else (620.0 if module.kind=="cannon" else 850.0))
		var point: Dictionary=points[i]
		var fixed: bool=not original and module.kind in ["rocket","torpedo"]
		# Deck launchers point over the bow regardless of their deck position.
		result.weaponMounts.append({"id":point.id,"moduleId":id,"kind":module.kind,"damage":module.damage,"fireRate":module.fireRate,"range":module.range,"speed":module.speed,"ammoCost":module.ammoCost,"size":module.size,"x":point.x,"y":point.y,"arc":minf(point.arc,0.9) if fixed else point.arc,"angle":0.0 if original or fixed else point.angle})
	if not result.weaponMounts.is_empty():
		var primary: Dictionary=result.weaponMounts[0]
		result.weapon=primary.kind
		result.damage=primary.damage
		result.fireRate=primary.fireRate
		result.range=primary.range
		for mount in result.weaponMounts: result.range=maxf(result.range,mount.range)
	else:
		result.damage=0.0
		result.fireRate=0.0
		result.range=0.0
	result.ammoCapacity=80*maxi(1,result.weaponMounts.size())
	result.deploymentPoints=Deployment.cost(base)+int(ceil(maxf(0.0,float(normalized.usedPoints)-2.0)/3.0))
	return result

static func _locker(value) -> Dictionary:
	if not (value is Dictionary or value is Array): return _fail("Refit locker must contain module counts.")
	var cat: Dictionary=catalog()
	var known: Dictionary={}
	for family in ["weapons","engines","armor"]:
		for id in cat[family]:
			if not str(id).is_empty(): known[id]=true
	var counts: Dictionary={}
	var entries: Array=[]
	if value is Dictionary:
		for id in value: entries.append({"id":id,"count":value[id]})
	else:
		entries=value
	var total: int=0
	if entries.size()>MAX_LOCKER: return _fail("Refit locker is too large.")
	for entry in entries:
		var id=entry.get("id") if entry is Dictionary else entry
		var count=entry.get("count",1) if entry is Dictionary else 1
		if entry is Dictionary:
			for key in entry:
				if key not in ["id","count"]: return _fail("Unknown locker field.")
		if not id is String or not known.has(id) or not _whole(count) or float(count)>MAX_LOCKER:
			return _fail("Refit locker has an unknown module or invalid count.")
		total+=int(count)
		if total>MAX_LOCKER: return _fail("Refit locker holds too many parts.")
		if int(count)>0: counts[id]=int(counts.get(id,0))+int(count)
	return {"ok":true,"locker":counts}

static func ensure(ship: Dictionary,base: Dictionary={}) -> void:
	var original: Dictionary=base if not base.is_empty() else ship.get("baseSpec",ship.get("spec",{}))
	if original.is_empty(): return
	var loadout=ship.get("loadout",defaults(original))
	if not loadout is Dictionary: return
	var fit: Dictionary=normalize(original,loadout)
	var stored: Dictionary=_locker(ship.get("refitLocker",{}))
	if not fit.ok or not stored.ok: return
	var spec: Dictionary=effective_spec(original,fit.loadout)
	var old_max: float=maxf(1.0,_number(ship.get("maxHp"),spec.hp))
	var old_hp: float=clampf(_number(ship.get("hp"),old_max),0.0,old_max)
	ship.baseSpec=original.duplicate(true)
	ship.loadout=fit.loadout
	ship.refitLocker=stored.locker
	ship.spec=spec
	ship.maxHp=spec.hp
	# Armor changes protection/drag, never max HP. Canonical hull migration
	# preserves damage fraction if a supplied base changes maximum HP.
	ship.hp=old_hp if is_equal_approx(old_max,spec.hp) else minf(old_hp,spec.hp*(old_hp/old_max))
	ship.armor=spec.armor

static func _slot(loadout: Dictionary,slot: String) -> Dictionary:
	if slot in ["engine","armor"]:
		return {"ok":true,"group":"engines" if slot=="engine" else "armor","key":slot,"index":-1,"old":loadout[slot]}
	var parts: PackedStringArray=slot.split(":")
	if parts.size()!=2 or parts[0]!="weapon" or not parts[1].is_valid_int(): return _fail("Unknown fitting slot.")
	var index: int=int(parts[1])
	if index<0 or index>=loadout.weapons.size(): return _fail("Unknown hardpoint.")
	return {"ok":true,"group":"weapons","key":"weapons","index":index,"old":loadout.weapons[index]}

static func _price(port: Dictionary,good: String) -> int:
	var override=port.get("refitPrices",{}).get(good) if port.get("refitPrices",{}) is Dictionary else null
	if _whole(override) and float(override)>0.0: return int(override)
	var stock: float=maxf(0.0,_number(port.get("stocks",{}).get(good)))
	# A bounded scarcity premium on the actual recursive paid input cost.
	var factor: float=(1.0+0.35/(1.0+stock/10.0))*(1.15 if port.get("blockaded",false) else 1.0)
	return maxi(1,int(ceil(Goods.cost(good)*factor)))

static func _workforce(port: Dictionary) -> Dictionary:
	var total: float=Construction._available_total_workers(port) if port.has("workforce") or port.has("availableWorkers") else 0.0
	var has_experts: bool=false
	for key in ["availableSpecialists","specialists","supervisors","expertWorkers","experts"]:
		if port.has(key): has_experts=true
	var specialists: float=minf(total,Construction._available_specialists(port,total)) if has_experts else 0.0
	var used: float=maxf(_number(port.get("_yardWorkersUsed")),_number(port.get("yardWorkersReserved")))
	var experts_used: float=maxf(_number(port.get("_yardSpecialistsUsed")),_number(port.get("yardSpecialistsReserved")))
	return {"total":total,"specialists":specialists,"used":used,"expertsUsed":experts_used,"free":maxf(0.0,total-used),"freeExperts":maxf(0.0,specialists-experts_used)}

static func quote(port: Dictionary,ship: Dictionary,slot: String,module_id: String) -> Dictionary:
	if ship.get("sunk",false) or not ship.get("spec") is Dictionary or not port.get("stocks") is Dictionary:
		return _fail("A living boat and a harbor with physical stocks are required.")
	var probe: Dictionary=ship.duplicate(true)
	ensure(probe)
	if not probe.get("loadout") is Dictionary: return _fail("The boat's fitting is malformed.")
	var old_fit: Dictionary=normalize(probe.get("baseSpec",{}),probe.loadout)
	var stored: Dictionary=_locker(probe.get("refitLocker",{}))
	if not old_fit.ok: return old_fit
	if not stored.ok: return stored
	var position: Dictionary=_slot(old_fit.loadout,slot)
	if not position.ok: return position
	var cat: Dictionary=catalog()
	if not cat[position.group].has(module_id): return _fail("Unknown module for this slot.")
	if position.old==module_id: return _fail("That module is already installed.")
	var next: Dictionary=old_fit.loadout.duplicate(true)
	if position.index>=0: next.weapons[position.index]=module_id
	else: next[position.key]=module_id
	var normalized: Dictionary=normalize(probe.baseSpec,next)
	if not normalized.ok: return normalized
	var module: Dictionary=cat[position.group][module_id]
	var owned: bool=not module_id.is_empty() and int(stored.locker.get(module_id,0))>0
	var materials: Dictionary={} if owned else module.materials.duplicate(true)
	if not owned and module_id in ["stock_primary","stock_engine"]:
		var blueprint: Dictionary=Construction.blueprint(probe.baseSpec)
		materials["guns" if module_id=="stock_primary" else "engines"]=maxi(1,int(ceil(blueprint.weaponUnits if module_id=="stock_primary" else blueprint.engineUnits)))
	var worker_days: float=float(module.workerDays)+(0.5 if not str(position.old).is_empty() else 0.0)
	var expert_days: float=float(module.expertDays)+(0.25 if not str(position.old).is_empty() else 0.0)
	var material_cost: int=0
	var prices: Dictionary={}
	for good in materials:
		prices[good]=_price(port,good)
		material_cost+=int(ceil(float(materials[good])*prices[good]))
	var worker_wages: int=int(ceil(worker_days*Goods.WAGES.shipwright))
	var expert_wages: int=int(ceil(expert_days*Goods.WAGES.engineer))
	var subtotal: int=material_cost+worker_wages+expert_wages
	var tax: int=int(ceil(subtotal*0.05))
	var margin: int=int(ceil(subtotal*0.08))
	var cost: int=subtotal+tax+margin
	var q: Dictionary={"ok":true,"message":"%s: %d coins (%d parts, %d worker wages, %d expert wages, %d yard margin, %d duty)."%[module.name,cost,material_cost,worker_wages,expert_wages,margin,tax],"cost":cost,"materials":materials,"materialPrices":prices,"materialCost":material_cost,"workerWages":worker_wages,"expertWages":expert_wages,"tax":tax,"margin":margin,"businessIncome":material_cost+margin,"workerDays":worker_days,"expertDays":expert_days,"fromLocker":owned,"newLoadout":normalized.loadout,"newSpec":effective_spec(probe.baseSpec,normalized.loadout),"usedPoints":normalized.usedPoints,"maxPoints":normalized.maxPoints,"oldModule":position.old,"moduleId":module_id}
	for good in materials:
		if _number(port.stocks.get(good),-1.0)+0.000001<float(materials[good]):
			q.ok=false
			q.message="The yard lacks physical "+str(Goods.ITEMS[good].name)+" for this refit."
	var workers: Dictionary=_workforce(port)
	if workers.free+0.000001<worker_days+expert_days or workers.freeExperts+0.000001<expert_days:
		q.ok=false
		q.message="The shared yard has insufficient available workers or specialists today."
	return q

static func install(state: Dictionary,port: Dictionary,ship: Dictionary,slot: String,module_id: String) -> Dictionary:
	var q: Dictionary=quote(port,ship,slot,module_id)
	if not q.ok: return q
	if not _whole(state.get("coins")) or float(state.coins)<q.cost: return _fail("The refit needs %d coins."%q.cost)
	for key in ["cash","householdPurse","expertPurse","governmentPurse"]:
		if not _whole(port.get(key,0)): return _fail("The harbor coin ledger is invalid.")
	if state.get("fleet") is Array:
		var owns: bool=false
		var living: Array=[]
		for boat in state.fleet:
			if is_same(boat,ship): owns=true
			if not boat.get("sunk",false): living.append(boat)
		if not owns: return _fail("That boat is not in your flotilla.")
		var points: int=Deployment.total(living)
		var future: int=points-Deployment.cost(ship)+Deployment.cost(q.newSpec)
		if future>Deployment.LIMIT and future>points: return _fail("This refit would exceed the fleet's 300 deployment points.")
	var probe: Dictionary=ship.duplicate(true)
	ensure(probe)
	var stored: Dictionary=_locker(probe.refitLocker)
	if not stored.ok: return stored
	var locker: Dictionary=stored.locker
	if q.fromLocker:
		locker[module_id]-=1
		if locker[module_id]==0: locker.erase(module_id)
	if not str(q.oldModule).is_empty(): locker[q.oldModule]=int(locker.get(q.oldModule,0))+1
	var checked: Dictionary=_locker(locker)
	if not checked.ok: return checked
	probe.loadout=q.newLoadout
	probe.refitLocker=checked.locker
	ensure(probe,probe.baseSpec)
	var dock: Dictionary=port.duplicate(true)
	var wallet: Dictionary={"coins":int(state.coins)}
	var ledger: Array=state.get("moneyLog",[]).duplicate(true) if state.get("moneyLog",[]) is Array else []
	for payment in [["cash",q.businessIncome,"Refit parts and yard margin"],["householdPurse",q.workerWages,"Refit shipwright wages"],["expertPurse",q.expertWages,"Refit engineer wages"],["governmentPurse",q.tax,"Refit duty"]]:
		if not Money.move(wallet,"coins",dock,payment[0],int(payment[1]),payment[2],ledger): return _fail("The refit payment could not be reconciled.")
	for good in q.materials: dock.stocks[good]=maxf(0.0,float(dock.stocks[good])-float(q.materials[good]))
	var workers: Dictionary=_workforce(port)
	dock._yardWorkersUsed=workers.used
	dock._yardSpecialistsUsed=workers.expertsUsed
	dock._yardOrdinaryUsed=maxf(_number(port.get("_yardOrdinaryUsed")),_number(port.get("yardOrdinaryReserved")))
	Construction._record_yard_reservation(dock,workers.total,workers.specialists,q.workerDays+q.expertDays,q.workerDays,q.expertDays)
	# Commit after every possible refusal; retain the original boat/port objects.
	state.coins=wallet.coins
	state.moneyLog=ledger
	for key in ["cash","householdPurse","expertPurse","governmentPurse","stocks","_yardWorkersUsed","_yardOrdinaryUsed","_yardSpecialistsUsed","yardWorkersReserved","yardOrdinaryReserved","yardSpecialistsReserved","yardAvailableWorkers","yardAvailableSpecialists"]: port[key]=dock[key]
	for key in ["baseSpec","loadout","refitLocker","spec","maxHp","hp","armor"]: ship[key]=probe[key]
	q.message="Installed "+str(catalog()[_slot(ship.loadout,slot).group][module_id].name)+" for %d coins. Removed equipment stays in this boat's locker."%q.cost
	return q
