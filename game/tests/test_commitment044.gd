extends SceneTree
## Focused 0.044 source candidate. Root alone runs native tests through TestBridge.
const Balance=preload("res://scripts/combat_balance044.gd")
const Refit=preload("res://scripts/refit.gd")
const Layout=preload("res://scripts/mount_layout.gd")
const Geometry=preload("res://scripts/weapon_geometry.gd")
const Damage=preload("res://scripts/damage.gd")
const Battle=preload("res://scripts/battle.gd")
const Lab=preload("res://scripts/fleet_lab.gd")
const Routes=preload("res://scripts/tactical_routes.gd")
const Records=preload("res://scripts/equipment_records.gd")
const Economy=preload("res://scripts/economy.gd")
const Goods=preload("res://scripts/goods.gd")
const Construction=preload("res://scripts/construction.gd")
const Money=preload("res://scripts/money.gd")
const Deployment=preload("res://scripts/deployment.gd")
const DT: float=1.0/60.0
const WALL_LIMIT_US: int=20000000
var checks: int=0
var failures: Array=[]
var started: int=0
var report: Dictionary={"fixture":"commitment044","kernels":[],"stock":[]}

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);print("FAIL commitment044: "+message)

func within_bound() -> bool:
	return Time.get_ticks_usec()-started<WALL_LIMIT_US

func condition(ship: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key in ["hp","maxHp","water","engine","ammo","fuel","supplies","crew","wounded","breaches","fire","sunk"]:
		result[key]=ship[key].duplicate(true) if ship[key] is Array or ship[key] is Dictionary else ship[key]
	return result

func specification_checks(world: Dictionary) -> void:
	var cat: Dictionary=Refit.catalog()
	for base in world.HULLS:
		var before: PackedByteArray=var_to_bytes(base)
		var spec: Dictionary=Refit.effective_spec(base,Refit.defaults(base))
		var point: Dictionary=Refit.hardpoints(base)[0]
		var heavy: bool=str(base.id) in ["furnace_turret","iron_bastion","maiden_dreadnought"]
		var expected_rate: float=1.0/1.8 if heavy else float(base.fireRate)
		var expected_arc: float=deg_to_rad(135.0) if heavy else TAU
		check(is_equal_approx(spec.fireRate,expected_rate) and is_equal_approx(spec.weaponMounts[0].arc,expected_arc),"stock actual rate/arc: "+str(base.id))
		var chooser: Dictionary=Refit.weapon_for_socket(base,cat.weapons.stock_primary,point,true)
		var runtime: Dictionary=Battle._base_mounts(Damage.create_ship(spec))[0]
		var art: Dictionary=Layout.mounts_of(spec)[0]
		var bare_art: Dictionary=Layout.mounts_of(base)[0]
		check(chooser.fireRate==runtime.fireRate and chooser.arc==runtime.arc and chooser.damage==runtime.damage and chooser.range==runtime.range and chooser.speed==runtime.speed,"published chooser helper agrees with actual stock runtime: "+str(base.id))
		check(art.arc==runtime.arc and bare_art.arc==runtime.arc and is_equal_approx(art.worldX,runtime.x) and is_equal_approx(art.worldY,runtime.y) and art.angle==runtime.angle,"stock art and refit use the runtime socket and arc: "+str(base.id))
		check(spec.damage==base.damage and spec.range==base.range and spec.speed==base.speed and spec.turn==base.turn and spec.hp==base.hp and spec.armor==base.armor and spec.ammoCapacity==80 and runtime.ammoCost==1 and Deployment.cost(spec)==Deployment.cost(base),"stock tuning preserves hit strength, travel hull, stores and DP: "+str(base.id))
		check(before==var_to_bytes(base),"weapon queries leave the economic hull catalogue unchanged: "+str(base.id))
		if heavy:report.stock.append({"hull":base.id,"oldRate":base.fireRate,"oldReloadSeconds":1.0/float(base.fireRate),"actualRate":spec.fireRate,"baseReloadSeconds":1.0/spec.fireRate,"arcDegrees":rad_to_deg(runtime.arc),"damage":spec.damage,"range":spec.range,"speed":runtime.speed,"ammoCost":runtime.ammoCost})
	var big: Dictionary=Lab.hull(world,"furnace_turret")
	for id in ["rapid_gun","heavy_gun","light_cannon","heavy_cannon","fire_rocket","salvo_rocket","light_torpedo","heavy_torpedo"]:
		var fit: Dictionary=Refit.defaults(big);fit.weapons[0]=id
		var spec: Dictionary=Refit.effective_spec(big,fit)
		var item: Dictionary=cat.weapons[id]
		var chooser: Dictionary=Refit.weapon_for_socket(big,item,Refit.hardpoints(big)[0])
		var actual: Dictionary=spec.weaponMounts[0]
		check(chooser.fireRate==actual.fireRate and chooser.arc==actual.arc and chooser.angle==actual.angle and chooser.damage==actual.damage and chooser.range==actual.range and chooser.speed==actual.speed and chooser.ammoCost==actual.ammoCost,"chooser and effective fitted descriptor agree: "+id)
		var expected_arc: float=deg_to_rad(135.0) if item.kind=="cannon" else (0.9 if item.kind in ["rocket","torpedo"] else TAU)
		check(is_equal_approx(actual.arc,expected_arc) and actual.fireRate==item.fireRate and Layout.mounts_of(spec)[0].arc==actual.arc,"fitted family keeps its shared actual arc and rate: "+id)
		var original_item: PackedByteArray=var_to_bytes(item)
		chooser.damage=-1.0;chooser.arc=0.0;chooser.materials.clear()
		check(var_to_bytes(item)==original_item and actual.damage==item.damage and is_equal_approx(actual.arc,expected_arc),"chooser descriptor edits cannot change physical/catalogue weapon values: "+id)
	for point in Refit.hardpoints(big):
		if str(point.id)=="mount0":continue
		check(Layout.weapon_aim(point,"cannon").arc==point.arc and Layout.weapon_aim(point,"gun").arc==point.arc and is_equal_approx(Layout.weapon_aim(point,"torpedo").arc,0.9),"aft/side cannon, gun and fixed-launcher arcs retained: "+str(point.id))
	check(is_equal_approx(cat.weapons.heavy_cannon.fireRate,1.0/1.8) and cat.weapons.heavy_cannon.ammoCost==2 and cat.weapons.heavy_cannon.damage==48 and cat.weapons.heavy_cannon.range==620 and cat.weapons.heavy_cannon.speed==690,"long iron keeps its actual two-round salvo, strength and travel")
	check(cat.weapons.heavy_cannon.materials=={"guns":2,"iron":5,"timber":1,"supplies":3} and cat.weapons.heavy_cannon.workerDays==5.0 and cat.weapons.heavy_cannon.expertDays==1.25 and cat.weapons.heavy_cannon.op==8,"heavy cannon paid inputs and fitting points are unchanged")
	check(Balance.fire_rate("cannon",3,0.25)==0.25 and Balance.firing_arc("cannon","mount0",3,1.0)==1.0,"slower reloads and narrower authored arcs are never loosened")

func paid_fitting_check(world: Dictionary) -> void:
	var base: Dictionary=Lab.hull(world,"furnace_turret")
	var ship: Dictionary=Damage.create_ship(base,{"uid":"commitment-paid","hp":400.0,"ammo":7.0,"fuel":12.0,"supplies":8.0})
	ship.loadout=Refit.defaults(base)
	var seeded: Dictionary=Records.initialize(ship,{"base":base.duplicate(true),"loadout":ship.loadout.duplicate(true),"catalog":Refit.catalog(),"identity":str(ship.uid),"knownUids":[]})
	check(bool(seeded.get("ok",false)),"paid-fit fixture seeds actual canonical physical equipment")
	if not seeded.get("ok",false):return
	Refit.ensure(ship,base)
	var port: Dictionary=Economy.create_port(world.PORTS[0])
	port.workforce=100;port.workers=0;port.publicWorkers=0;port.availableWorkers=100;port.specialists=20;port.availableSpecialists=20
	for good in Goods.ITEMS:port.stocks[good]=100.0
	Construction.begin_day(port)
	var state: Dictionary={"coins":1000000,"crewPurse":0,"ports":[port],"fleet":[ship],"moneyLog":[]}
	var old_condition: Dictionary=condition(ship)
	var before: Dictionary=state.duplicate(true)
	var coins: int=Money.total(state)
	var quote: Dictionary=Refit.quote(port,ship,"weapon:0","heavy_cannon",{"new":true})
	check(quote.get("ok",false) and state==before,"heavy tuning preserves read-only physical fitting quotes")
	if not quote.get("ok",false):return
	var installed: Dictionary=Refit.install(state,port,ship,"weapon:0","heavy_cannon",{"new":true})
	check(installed.get("ok",false) and condition(ship)==old_condition and Money.total(state)==coins and state.coins==before.coins-quote.cost,"real paid heavy fitting conserves coins and never refills stores or heals")
	if not installed.get("ok",false):return
	for good in quote.materials:check(is_equal_approx(float(port.stocks[good]),float(before.ports[0].stocks[good])-float(quote.materials[good])),"actual paid fitting consumes its existing material quote: "+str(good))
	check(Damage.inspect_owner_cached(ship).get("mode","")=="canonical" and is_equal_approx(ship.spec.fireRate,1.0/1.8),"installed physical heavy cannon remains valid with the shared actual reload")

func lanes(st: Dictionary) -> void:
	st.tactical.geometry=Routes.terrain(st)
	st.tactical.cells=Routes.grid(st.ships)
	st.tactical.budget={"fullRoutes":0,"cacheHits":0,"rollouts":0,"samples":0,"clearanceTests":0,"clearanceLimit":4096,"exhaustions":0,"rolled":{}}

func cooldown_step(st: Dictionary,ship: Dictionary) -> void:
	Damage.tick_ship(ship,DT,{"inCombat":true})
	Battle._tick_cooldowns(ship,DT)
	st.time+=DT
	Battle._projectiles(st,DT)

func kernel_check(world: Dictionary,module_id: String) -> void:
	var entry: Dictionary=Lab.entry(world,"furnace_turret");entry.loadout.weapons[0]=module_id
	var created: Dictionary=Lab.create(world,{"player":[entry],"enemy":[Lab.entry(world,"tin_skiff")]},4401)
	check(created.get("ok",false),"canonical stock/fitted opening created: "+module_id)
	if not created.get("ok",false):return
	var st: Dictionary=created.battle
	var heavy: Dictionary=st.ships[0];var light: Dictionary=st.ships[1]
	heavy.x=600.0;heavy.y=850.0;heavy.angle=0.0
	light.x=900.0;light.y=850.0
	Damage.set_policy(heavy,"fight")
	var mount: Dictionary=Battle._mounts(heavy)[0]
	var status: Dictionary=Damage.get_status(heavy)
	var cost: int=int(mount.ammoCost)
	heavy.ammo=float(2*cost+cost-1) # Two actual discharges, then insufficient rounds.
	var initial_ammo: float=heavy.ammo
	lanes(st)
	Battle._fire(st,heavy,Vector2(900,850))
	check(st.projectiles.size()==1,"actual cannon opens with a physical projectile: "+module_id)
	if st.projectiles.is_empty():return
	var shot: Dictionary=st.projectiles[0]
	var origin: Vector2=Battle._mount_origin(heavy,mount)+Vector2.RIGHT*float(mount.muzzleDistance)
	var expected_cooldown: float=1.0/(float(mount.fireRate)*maxf(0.15,float(status.weaponFactor)))
	check(Vector2(shot.x,shot.y).distance_to(origin)<0.0001 and shot.mountId==mount.id and shot.damage==mount.damage and is_equal_approx(Vector2(shot.vx,shot.vy).length(),float(mount.speed)) and is_equal_approx(float(shot.life),float(mount.range)/float(mount.speed)),"projectile retains the actual socket/muzzle, strength, speed and finite travel: "+module_id)
	check(is_equal_approx(heavy.cooldown,expected_cooldown) and heavy.cooldown>=1.8-0.000001 and heavy.ammo==initial_ammo-cost,"actual discharge publishes the crew/condition-aware cooldown and original ammunition cost: "+module_id)
	Battle._fire(st,heavy,Vector2(900,850))
	check(st.projectiles.size()==1 and heavy.ammo==initial_ammo-cost,"the reload window cannot be bypassed by another fire request: "+module_id)
	var start: Vector2=Vector2(shot.x,shot.y);var velocity: Vector2=Vector2(shot.vx,shot.vy)
	Battle._projectiles(st,DT)
	check(st.projectiles.size()==1 and Vector2(st.projectiles[0].x,st.projectiles[0].y).distance_to(start+velocity*DT)<0.0001 and is_equal_approx(st.projectiles[0].age,DT),"one real projectile tick travels at the unchanged launch speed: "+module_id)
	# A declared fixed-heading kernel, not a claim that an AI heavy cannot turn.
	# The light uses the live movement integrator from rest to cross the arc.
	var crossing_start: Vector2=Battle._mount_origin(heavy,mount)+Vector2.from_angle(deg_to_rad(55.0))*130.0
	light.x=crossing_start.x;light.y=crossing_start.y;light.angle=PI/2.0
	var crossed_at: float=-1.0
	while heavy.cooldown>0.0 and within_bound():
		Battle._move(st,light,DT,PI/2.0,1.0,false)
		cooldown_step(st,heavy)
		var bearing: float=(Vector2(light.x,light.y)-Battle._mount_origin(heavy,mount)).angle()
		if crossed_at<0.0 and absf(angle_difference(heavy.angle+mount.angle,bearing))>mount.arc*0.5+0.02:crossed_at=st.time
	check(crossed_at>0.0 and crossed_at<expected_cooldown-DT and light.fuel<120.0,"a fueled light can cross the fixed heavy bearing during its real reload: "+module_id)
	var events_before: int=st.eventSeq
	lanes(st);Battle._fire(st,heavy,Vector2(light.x,light.y))
	check(Vector2(light.x,light.y).distance_to(Battle._mount_origin(heavy,mount))<mount.range and st.eventSeq==events_before and heavy.ammo==initial_ammo-cost,"reloaded cannon withholds an in-range shot outside its actual arc: "+module_id)
	lanes(st);Battle._fire(st,heavy,Vector2(900,850))
	check(heavy.ammo==float(cost-1) and heavy.cooldown>0.0,"second real discharge leaves the finite magazine remainder: "+module_id)
	while heavy.cooldown>0.0 and within_bound():cooldown_step(st,heavy)
	events_before=st.eventSeq
	lanes(st);Battle._fire(st,heavy,Vector2(900,850))
	var fire_count: int=0
	for event in Battle.pop_events(st):
		if event.kind=="fire" and event.sourceId==heavy.id:fire_count+=1
	check(st.eventSeq==events_before and fire_count==2 and heavy.ammo==float(cost-1),"no third shot or free rounds after two actual finite salvos: "+module_id)
	report.kernels.append({"module":module_id,"scope":"fixed-heading live kernels, not AI acceptance or FPS","baseReloadSeconds":1.0/float(heavy.spec.fireRate),"actualCooldownSeconds":expected_cooldown,"arcDegrees":rad_to_deg(mount.arc),"lightCrossedAtSeconds":crossed_at,"ammoStart":initial_ammo,"ammoEnd":heavy.ammo,"ammoPerDischarge":cost,"fireEvents":fire_count,"projectileSpeed":mount.speed,"maxTravelSeconds":mount.range/mount.speed,"muzzleDistance":mount.muzzleDistance,"barrelHeight":Geometry.height(str(mount.kind),float(heavy.spec.size),int(mount.size))})

func opening(world: Dictionary) -> void:
	var light_entry: Dictionary=Lab.entry(world,"tin_skiff");light_entry.loadout.weapons[0]="light_torpedo"
	var created: Dictionary=Lab.create(world,{"player":[light_entry],"enemy":[Lab.entry(world,"furnace_turret")]},4401)
	check(created.get("ok",false),"one original torpedo pass versus stock heavy scenario uses canonical paid fits")
	if not created.get("ok",false):return
	var st: Dictionary=created.battle
	var light: Dictionary=st.ships[0];var heavy: Dictionary=st.ships[1]
	light.x=800.0;light.y=850.0;light.angle=0.0;light.ammo=4.0
	heavy.x=1130.0;heavy.y=850.0;heavy.angle=PI;heavy.ammo=4.0
	st.autoBoard=false
	check(st.autopilot and Battle.issue_order(st,[str(light.id)],"attack",{"shipId":str(heavy.id)}),"normal autopilot accepts the opening attack")
	var light_fires: int=0;var heavy_fires: int=0
	var last_heavy_fire: float=-1.0;var departure: float=-1.0
	var events: Array=[]
	var initial: Dictionary={"light":condition(light),"heavy":condition(heavy)}
	for tick in range(600):
		if not within_bound() or st.result!=null:break
		Battle.update(st,DT)
		for event in Battle.pop_events(st):
			if event.kind=="fire":
				if event.sourceId==light.id:light_fires+=1
				if event.sourceId==heavy.id:
					heavy_fires+=1
					check(last_heavy_fire<0.0 or float(st.time)-last_heavy_fire>=1.8-DT-0.000001,"normal AI heavy fire respects the committed minimum reload")
					last_heavy_fire=st.time
			events.append({"time":st.time,"kind":event.kind,"family":event.family,"source":event.sourceId,"target":event.targetId,"mount":event.mountId,"x":event.x,"y":event.y})
		if departure<0.0 and light_fires>0:
			check(Battle.issue_order(st,[str(light.id)],"move",{"x":550.0,"y":1120.0}),"the player can order an exit immediately after the real launcher salvo")
			departure=st.time
	check(light_fires>0 and heavy_fires>0 and departure>=0.0,"active normal AI opening contains both real cannon pressure and the finite launcher pass")
	check(light.ammo==4.0-float(light_fires)*2.0 and heavy.ammo==4.0-float(heavy_fires) and light.ammo>=0.0 and heavy.ammo>=0.0,"normal pass/exit never invents rounds or changes the original per-family salvo costs")
	var light_travel: float=Vector2(light.x,light.y).distance_to(Vector2(800,850))
	var heavy_travel: float=Vector2(heavy.x,heavy.y).distance_to(Vector2(1130,850))
	check(light_travel>5.0 and st.autopilot,"the firing pass and exit contain real light-craft movement under default autopilot")
	report.opening={"scope":"up to ten simulation seconds at normal 60Hz; one post-launch player move command, enemy AI unchanged","seed":4401,"initialGap":330.0,"simSeconds":st.time,"result":st.result,"departureOrderedAt":departure,"lightFires":light_fires,"heavyFires":heavy_fires,"lightDisplacement":light_travel,"heavyDisplacement":heavy_travel,"heavyHeadingChange":angle_difference(PI,float(heavy.angle)),"initial":initial,"final":{"light":condition(light),"heavy":condition(heavy)},"finalRange":Vector2(light.x,light.y).distance_to(Vector2(heavy.x,heavy.y)),"events":events}

func run() -> void:
	started=Time.get_ticks_usec()
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var before: PackedByteArray=var_to_bytes(world)
	specification_checks(world)
	paid_fitting_check(world)
	kernel_check(world,"stock_primary")
	kernel_check(world,"heavy_cannon")
	opening(world)
	check(before==var_to_bytes(world),"the whole focused scenario leaves world economics unchanged")
	check(within_bound(),"focused fixture completes within its twenty-second active bound")
	var folder: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	check(not folder.is_empty(),"Root supplies an isolated artifact directory")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		var file=FileAccess.open(folder.path_join("commitment044.json"),FileAccess.WRITE)
		check(file!=null,"focused report opens")
		if file!=null:
			report.complete=failures.is_empty();report.checks=checks;report.failures=failures;report.wallUs=Time.get_ticks_usec()-started
			file.store_string(JSON.stringify(report,"\t"));file.close()
	print("COMMITMENT044 %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
