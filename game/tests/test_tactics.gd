extends SceneTree
## Pure commander/deployment checks. Root runs this serially and headless.
const B=preload("res://scripts/battle.gd")
const D=preload("res://scripts/damage.gd")
const DP=preload("res://scripts/deployment.gd")
const SPEC={"id":"skiff","name":"Skiff","role":"skiff","tier":1,"hp":150,"armor":1,"crewMin":2,"crewOptimal":5,"crewMax":7,"size":16,"speed":100,"turn":2,"pumps":1,"weapon":"gun","damage":12,"fireRate":2,"range":550,"deploymentPoints":20}
var checks: int=0
var failures: int=0

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL tactics: "+message)

func advance(st: Dictionary,count: int,input: Dictionary={}) -> void:
	for i in range(count):
		B.update(st,1.0/30.0,input)

func boat(points: int=20,index: int=0) -> Dictionary:
	var spec: Dictionary=SPEC.duplicate(true)
	spec.deploymentPoints=points
	return D.create_ship(spec,{"uid":"owned-%d"%index})

func make(player_spec: Dictionary=SPEC,enemy_spec: Dictionary=SPEC) -> Dictionary:
	return B.create({"fleet":[D.create_ship(player_spec)],"enemySpecs":[enemy_spec],"seed":42})

func stationary(spec: Dictionary=SPEC) -> Dictionary:
	var st: Dictionary=make(spec)
	st.ships[0].x=500.0
	st.ships[0].y=850.0
	st.ships[0].angle=0.0
	st.ships[0].spec.speed=0.0
	st.ships[1].x=1000.0
	st.ships[1].y=850.0
	st.ships[1].spec.speed=0.0
	st.ships[1].ammo=0.0
	return st

func test_deployment() -> void:
	check(DP.LIMIT==300,"shared limit is 300 points")
	check(DP.cost({"hp":0,"size":0,"tier":0,"role":"skiff"})==8,"base cost has eight-point floor")
	check(DP.cost({"hp":2000,"size":90,"tier":8,"role":"cruiser"})==75,"base cost has 75-point ceiling")
	check(DP.cost({"hp":150,"size":14,"tier":1,"role":"skiff"})<DP.cost({"hp":500,"size":30,"tier":3,"role":"cruiser"}),"hull role/tier/HP/size affect deployment")
	var base: Dictionary=SPEC.duplicate(true)
	base.erase("deploymentPoints")
	var fitted: Dictionary={"baseSpec":base,"spec":base.duplicate(true)}
	fitted.spec.hp=900.0
	check(DP.cost(fitted)==DP.cost(base),"fallback cost uses the original hull")
	fitted.spec.deploymentPoints=47
	check(DP.cost(fitted)==47,"effective canonical points override original hull")
	var roster: Array=[boat(110,0),boat(210,1),boat(40,2),boat(301,3),boat(100,4)]
	var before: Array=roster.duplicate(true)
	var split: Dictionary=DP.split(roster)
	check(roster==before,"split is read only")
	check(split.points==250 and split.deployed.size()==3 and split.reserve.size()==2,"stable split skips overlarge boats without dropping later affordable boats")
	check(split.deployed[0].uid=="owned-0" and split.deployed[1].uid=="owned-2" and split.deployed[2].uid=="owned-4","deployed roster order stays stable")
	check(split.reserve[0].uid=="owned-1" and split.reserve[1].uid=="owned-3","reserve roster order stays stable")
	split.deployed[1].ammo=7.0
	split.reserve[1].fuel=9.0
	check(roster[2].ammo==7.0 and roster[3].fuel==9.0,"split preserves the actual owner references")
	check(DP.total([boat(150),boat(150)])==300 and DP.fits([boat(150)],{"deploymentPoints":150}),"exact 300-point boundary fits")
	check(not DP.fits([boat(150),boat(150)],{"deploymentPoints":8}),"acquisition rejects over-limit addition")
	check(DP.split(roster,0).reserve.size()==roster.size(),"zero custom budget reserves every boat")
	var many: Array=[]
	for i in range(32):
		many.append(boat(10,i))
	var enemies: Array=[boat(200,100),boat(200,101)]
	var reserved_player: Dictionary=many[30].duplicate(true)
	var reserved_enemy: Dictionary=enemies[1].duplicate(true)
	var st: Dictionary=B.create({"fleet":many,"enemyFleet":enemies,"seed":7})
	check(st.ships.size()==31 and st.deployment.player==300 and st.deployment.enemy==200,"battle deploys more than eight and budgets both sides")
	check(st.reserves.player.size()==2 and st.reserves.enemy.size()==1,"both sides retain over-budget reserves")
	check(many[30]==reserved_player and enemies[1]==reserved_enemy,"creating battle never adds transient fields to reserves")
	check(not B.select_flagship(st,many[30].id),"reserve boat cannot be selected as active flagship")
	for s in st.ships:
		if s.team=="enemy": s.sunk=true
	B.update(st,1.0/30.0)
	check(st.result=="won" and not enemies[1].sunk,"living enemy reserves do not prevent active-force victory")
	check(many[30]==reserved_player and enemies[1]==reserved_enemy,"battle ticks leave reserve damage/stores/geometry untouched")
	check(st.wrecks.size()==1,"reserves are never recorded as sunk")
	var survivors: Array=[boat(200,0),boat(200,1)]
	st=B.create({"fleet":survivors,"enemySpecs":[SPEC]})
	st.ships[0].sunk=true
	B.update(st,1.0/30.0)
	check(st.result=="lost" and not survivors[1].sunk and st.reserves.player.size()==1,"active-force defeat preserves a living owner reserve")

func test_autopilot() -> void:
	var a: Dictionary=make()
	var b: Dictionary=make()
	check(a.autopilot,"battles default to flagship autopilot")
	for i in range(90):
		B.update(a,1.0/30.0,{"forward":true,"right":true,"boost":true,"fire":true,"aimX":700.0,"aimY":900.0})
		B.update(b,1.0/30.0)
	check(a.ships==b.ships and a.projectiles==b.projectiles,"camera-style flags without manual opt-in do not affect the AI flagship")
	check(a.ships[0].x>520.0,"AI flagship advances without input")
	var st: Dictionary=stationary()
	var s: Dictionary=st.ships[0]
	s.spec.speed=100.0
	B.set_order(st,"hold")
	B.update(st,1.0/30.0,{"manual":true,"forward":true,"right":true,"fire":true,"aimX":1000.0,"aimY":850.0})
	check(s.vx>0.0 and s.angle>0.0 and s.ammo==79.0,"explicit per-tick manual mode retains movement/steering/fire")
	check(st.autopilot,"per-tick manual opt-in does not silently change the persistent preference")
	check(not B.set_autopilot(st,false),"autopilot can be disabled explicitly")
	var x: float=s.x
	B.update(st,1.0/30.0,{"forward":true})
	check(s.x>x,"persistent manual mode accepts the legacy input API")
	check(B.set_autopilot(st,true),"autopilot can be restored explicitly")

func test_orders() -> void:
	var st: Dictionary=B.create({"fleet":[boat(),boat()],"enemySpecs":[SPEC],"seed":8})
	var a: Dictionary=st.ships[0]
	var b: Dictionary=st.ships[1]
	var enemy: Dictionary=st.ships[2]
	for s in st.ships: s.ammo=0.0
	enemy.spec.speed=0.0
	B.set_order(st,"hold")
	var before: Array=st.ships.duplicate(true)
	check(not B.issue_order(st,[a.id,enemy.id],"engage") and st.ships==before,"invalid recipient rejects the whole order atomically")
	check(not B.issue_order(st,[a.id],"move",{"x":NAN,"y":850.0}),"reject nonfinite target")
	check(not B.issue_order(st,[a.id],"move",{"x":-20.0,"y":850.0}),"reject target outside the battlefield")
	check(not B.issue_order(st,[a.id],"move",{"x":1000.0,"y":220.0}),"reject target on land")
	check(not B.issue_order(st,[a.id],"move") and not B.issue_order(st,[],"hold"),"reject missing destination/selection")
	check(not B.issue_order(st,[a.id],"attack",{"shipId":b.id}),"reject attack on friendly boat")
	check(not B.issue_order(st,[a.id],"escort",{"shipId":enemy.id}),"reject escorting enemy boat")
	check(not B.issue_order(st,[a.id],"attack",{"shipId":"missing"}),"reject missing target boat")
	check(st.ships==before,"all invalid target orders leave boats unchanged")
	var start_x: float=a.x
	var held: Vector2=Vector2(b.x,b.y)
	check(B.issue_order(st,[a.id,a.id],"move",{"x":760.0,"y":1050.0}),"valid move accepts deduplicated selection")
	advance(st,150)
	check(a.x>start_x+100.0 and b.order=="hold" and Vector2(b.x,b.y).distance_to(held)<1.0,"selected flagship follows move while the other boat holds")
	check(B.issue_order(st,[a.id],"attack",{"shipId":enemy.id}) and a.orderTarget.shipId==enemy.id,"per-boat attack retains target ID")
	check(B.issue_order(st,[a.id],"attack") and a.orderTarget.is_empty(),"attack without target uses nearest enemy")
	check(B.issue_order(st,[b.id],"escort",{"shipId":a.id}) and b.orderTarget.shipId==a.id,"escort retains allied leader")
	check(B.set_order(st,"engage")=="engage" and a.order=="engage" and b.order=="engage","legacy fleet-wide order reaches AI flagship and escorts")
	check(B.issue_order(st,[a.id],"withdraw"),"per-boat withdrawal accepted")
	var withdraw_x: float=a.x
	advance(st,90)
	check(a.x<withdraw_x-50.0,"AI flagship turns and withdraws")
	check(B.select_flagship(st,b.id) and b.selected and not a.selected,"existing flagship selection updates bounded selection data")
	# The farther explicit target must take priority over a nearer threat.
	st=B.create({"fleet":[boat()],"enemySpecs":[SPEC,SPEC],"seed":4})
	a=st.ships[0]
	a.x=500.0
	a.y=850.0
	a.spec.speed=0.0
	st.ships[1].x=600.0
	st.ships[1].y=750.0
	st.ships[2].x=850.0
	st.ships[2].y=850.0
	for i in [1,2]:
		st.ships[i].ammo=0.0
		st.ships[i].spec.speed=0.0
	B.issue_order(st,[a.id],"attack",{"shipId":st.ships[2].id})
	B.update(st,1.0/30.0)
	check(not st.projectiles.is_empty() and absf(st.projectiles[0].vy)<25.0,"attack order aims at the explicit target rather than nearer enemy")

func mounted_spec() -> Dictionary:
	var spec: Dictionary=SPEC.duplicate(true)
	spec.speed=0.0
	spec.weaponMounts=[]
	var families: Array=["gun","cannon","rocket","torpedo"]
	for i in range(4):
		spec.weaponMounts.append({"id":families[i],"kind":families[i],"damage":15.0,"fireRate":[4.0,1.0,0.5,0.25][i],"range":800.0,"speed":[850.0,620.0,730.0,240.0][i],"ammoCost":i+1,"x":8.0,"y":float(i-1)*3.0,"arc":TAU,"angle":0.0,"size":1})
	return spec

func test_mounts() -> void:
	var fitted: Dictionary=D.create_ship(SPEC,{"hp":71.0,"ammo":7.0,"fuel":8.0,"supplies":3.0})
	fitted.spec.armor=17.0
	B.create({"fleet":[fitted],"enemySpecs":[SPEC]})
	check(fitted.armor==17.0 and fitted.hp==71.0 and fitted.ammo==7.0 and fitted.fuel==8.0 and fitted.supplies==3.0,"effective armor is authoritative without healing or refilling the boat")
	var st: Dictionary=stationary(mounted_spec())
	var s: Dictionary=st.ships[0]
	B.update(st,1.0/30.0)
	check(st.projectiles.size()==4 and s.ammo==70.0,"all four independently fitted families fire and consume shared integer ammo")
	check(s.weaponCooldowns.size()==4 and is_equal_approx(s.cooldown,s.weaponCooldowns[0]),"primary timer remains compatible with legacy cooldown")
	var kinds: Dictionary={}
	for p in st.projectiles:
		kinds[p.kind]=p
		check(is_finite(p.life) and p.life>0.0 and p.life<40.0,"every projectile has useful finite life")
	check(kinds.has("bullet") and kinds.has("shell") and kinds.has("rocket") and kinds.has("torpedo"),"projectile family is preserved for rendering and impact")
	if kinds.size()==4:
		check(kinds.rocket.trail=="smoke" and kinds.torpedo.trail=="foam" and kinds.bullet.trail=="tracer","rocket/torpedo/gun trails are distinct")
		check(kinds.rocket.incendiary and kinds.rocket.blastRadius>0.0 and kinds.torpedo.penetration>kinds.shell.penetration,"rockets carry blast/fire and torpedoes carry penetration")
	advance(st,10)
	check(s.ammo==69.0 and s.weaponCooldowns[1]>0.5 and s.weaponCooldowns[2]>1.5,"rapid gun repeats while slower mounts cool independently")
	var timers: Array=s.weaponCooldowns.duplicate()
	s.ammo=0.0
	B.update(st,1.0/30.0)
	for i in range(timers.size()):
		check(is_equal_approx(s.weaponCooldowns[i],maxf(0.0,timers[i]-1.0/30.0)),"mount timer decrements exactly once")
	check(is_equal_approx(s.cooldown,s.weaponCooldowns[0]),"legacy timer does not double-decrement")
	st=stationary(mounted_spec())
	s=st.ships[0]
	s.ammo=5.0
	B.update(st,1.0/30.0)
	check(s.ammo==2.0 and st.projectiles.size()==2 and s.weaponCooldowns[2]==0.0 and s.weaponCooldowns[3]==0.0,"unaffordable mounts neither fire nor start cooldown")
	var fractional: Dictionary=SPEC.duplicate(true)
	fractional.weaponMounts=[{"id":"metered","kind":"gun","ammoCost":1.2,"range":800.0}]
	st=stationary(fractional)
	st.ships[0].ammo=3.0
	B.update(st,1.0/30.0)
	check(st.ships[0].ammo==1.0,"nonintegral mount ammo input is charged as whole rounds")
	var fixed: Dictionary=SPEC.duplicate(true)
	fixed.weaponMounts=[{"id":"broadside","kind":"torpedo","damage":12.0,"fireRate":1.0,"range":800.0,"speed":240.0,"ammoCost":1,"x":0.0,"y":0.0,"angle":PI/2.0,"arc":0.05}]
	st=stationary(fixed)
	s=st.ships[0]
	B._fire(st,s,Vector2(1000.0,850.0))
	check(s.ammo==80.0 and st.projectiles.is_empty(),"fixed mount cannot fire outside its local arc")
	advance(st,90)
	check(s.ammo<80.0 and absf(angle_difference(s.angle,-PI/2.0))<0.15,"AI rotates the hull to fire a fixed broadside mount")
	st=stationary()
	st.islands=[{"points":[[650.0,800.0],[652.0,800.0],[652.0,900.0],[650.0,900.0]]}]
	s=st.ships[0]
	B._fire(st,s,Vector2(1000.0,850.0))
	check(s.ammo==80.0 and st.projectiles.is_empty(),"even thin nearby land prevents firing and wasted ammo")
	var leading: Dictionary=SPEC.duplicate(true)
	leading.weaponMounts=[{"id":"lead","kind":"gun","range":800.0,"speed":300.0}]
	st=stationary(leading)
	st.ships[1].x=900.0
	st.ships[1].vy=100.0
	B._fire(st,st.ships[0],Vector2(900.0,850.0),st.ships[1])
	check(not st.projectiles.is_empty() and st.projectiles[0].vy>50.0,"AI firing computes a moving-target intercept")
	var unarmed: Dictionary=SPEC.duplicate(true)
	unarmed.weaponMounts=[]
	st=stationary(unarmed)
	B.update(st,1.0/30.0)
	check(st.ships[0].ammo==80.0 and st.ships[0].weaponCooldowns.is_empty(),"explicit empty fitting does not regenerate a legacy gun")

func test_engagement_range() -> void:
	var mixed: Dictionary=SPEC.duplicate(true)
	mixed.weaponMounts=[{"id":"long","kind":"cannon","damage":48.0,"fireRate":1.0,"range":620.0,"speed":690.0,"ammoCost":2},{"id":"short","kind":"gun","damage":11.0,"fireRate":4.0,"range":420.0,"speed":900.0,"ammoCost":1}]
	var ship: Dictionary=D.create_ship(mixed)
	check(B._weapon_range(ship)==620.0 and B._engagement_range(ship)==420.0,"mixed battery closes enough to use at least 80 percent of available DPS")
	ship.spec.weaponMounts.reverse()
	check(B._engagement_range(ship)==420.0,"engagement calculation is independent of mounting order")
	ship.spec.weaponMounts=mixed.weaponMounts.duplicate(true)
	ship.spec.weaponMounts[1].damage=1.0
	ship.spec.weaponMounts[1].fireRate=1.0
	check(B._engagement_range(ship)==620.0,"negligible short-range weapon does not force a heavy battery into close combat")
	ship.spec.weaponMounts[0].damage=80.0
	ship.spec.weaponMounts[0].fireRate=1.0
	ship.spec.weaponMounts[1].damage=20.0
	check(B._engagement_range(ship)==620.0,"exactly 80 percent of DPS can retain the longer range")
	ship.spec.weaponMounts[0].damage=100.0
	ship.spec.weaponMounts[1].kind="torpedo"
	check(B._engagement_range(ship)==420.0,"torpedo weighting includes its actual 1.8 impact multiplier")
	ship.spec.weaponMounts=mixed.weaponMounts.duplicate(true)
	ship.ammo=1.0
	check(B._engagement_range(ship)==420.0 and B._weapon_range(ship)==620.0,"unaffordable long weapon is excluded from desired range without changing maximum reach")
	ship.spec.weaponMounts[0].ammoCost=1
	ship.spec.weaponMounts[1].ammoCost=3
	ship.ammo=2.0
	check(B._engagement_range(ship)==620.0,"unaffordable short weapon cannot force an approach")
	ship.ammo=0.0
	check(B._engagement_range(ship)==B._weapon_range(ship),"fully dry battery retains its old safe spacing")
	ship=D.create_ship(SPEC)
	check(B._engagement_range(ship)==B._weapon_range(ship),"legacy single weapon retains its exact preferred range")
	ship.spec.weaponMounts=mixed.weaponMounts.duplicate(true)
	for mount in ship.spec.weaponMounts: mount.range=550.0
	check(B._engagement_range(ship)==550.0,"same-range fitted battery retains its original spacing")
	ship.spec.weaponMounts=[]
	check(B._engagement_range(ship)==80.0,"unarmed fallback retains the existing bounded range")
	var st: Dictionary=stationary(mixed)
	ship=st.ships[0]
	ship.spec.speed=100.0
	B.update(st,1.0/30.0)
	var fired_long: bool=false
	var fired_short: bool=false
	for p in st.projectiles:
		if p.owner==ship.id and p.mountId=="long": fired_long=true
		if p.owner==ship.id and p.mountId=="short": fired_short=true
	check(fired_long and not fired_short,"AI takes long-range firing opportunity while still outside its preferred mixed range")
	for frame in range(60):
		B.update(st,1.0/30.0)
		for p in st.projectiles:
			if p.owner==ship.id and p.mountId=="short": fired_short=true
	check(fired_short,"actual mixed-range AI approaches and fires the secondary weapon")
	st=B.create({"fleet":[D.create_ship(mixed)],"enemySpecs":[mixed],"seed":19})
	st.ships[0].x=500.0
	st.ships[0].y=850.0
	st.ships[1].x=900.0
	st.ships[1].y=850.0
	B.update(st,1.0/30.0)
	check(st.ships[0].vx>8.0 and st.ships[1].vx< -8.0 and is_equal_approx(st.ships[0].vx,-st.ships[1].vx),"player and enemy both close at full combat throttle for the same mixed battery")
	st=stationary()
	ship=st.ships[0]
	ship.spec.speed=100.0
	st.ships[1].x=850.0
	B.update(st,1.0/30.0)
	var original_velocity: float=100.0*0.18*(1.0-exp(-4.0/30.0))
	check(is_equal_approx(ship.vx,original_velocity),"single-weapon AI keeps the original throttle at the original standoff distance")

func test_impacts() -> void:
	var armor: Dictionary=SPEC.duplicate(true)
	armor.hp=1000.0
	armor.armor=30.0
	var gun: Dictionary=D.create_ship(armor)
	var cannon: Dictionary=D.create_ship(armor)
	var torpedo: Dictionary=D.create_ship(armor)
	var rocket: Dictionary=D.create_ship(armor)
	var rng: RandomNumberGenerator=RandomNumberGenerator.new()
	rng.seed=12
	D.apply_hit(gun,{"damage":40.0,"kind":"bullet"},rng)
	D.apply_hit(cannon,{"damage":40.0,"kind":"shell","penetration":4.0},rng)
	D.apply_hit(torpedo,{"damage":40.0,"kind":"torpedo","penetration":18.0},rng)
	D.apply_hit(rocket,{"damage":40.0,"kind":"rocket","incendiary":true},rng)
	check(torpedo.hp<cannon.hp and cannon.hp<gun.hp,"armor penetration differentiates torpedo/cannon/gun impacts")
	check(D.sum_areas(torpedo)>0.0 and torpedo.breaches[0].section=="waterline","torpedo always opens a waterline breach")
	check(rocket.fire>0.0,"rocket impact ignites the target")
	var st: Dictionary=B.create({"fleet":[D.create_ship(armor)],"enemySpecs":[armor,armor],"seed":13})
	st.ships[0].x=500.0
	st.ships[0].y=850.0
	st.ships[1].x=900.0
	st.ships[1].y=850.0
	st.ships[2].x=930.0
	st.ships[2].y=850.0
	st.projectiles.append({"x":800.0,"y":850.0,"px":800.0,"py":850.0,"vx":12000.0,"vy":0.0,"team":"player","damage":40.0,"kind":"rocket","life":1.0,"owner":"fixture","radius":3.0,"blastRadius":36.0,"incendiary":true})
	B._projectiles(st,1.0/30.0)
	check(st.ships[1].fire>0.0 and st.ships[2].fire>0.0 and st.ships[2].hp<1000.0,"rocket blast reaches a nearby enemy as well as its direct target")
	check(st.ships[0].hp==1000.0,"rocket blast preserves no-friendly-fire rule")

func test_unassisted() -> void:
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var st: Dictionary=B.create({"fleet":[D.create_ship(world.HULLS[0])],"enemySpecs":[world.HULLS[1]],"seed":91})
	for frame in range(9000):
		if st.result!=null: break
		B.update(st,1.0/30.0)
	check(st.result=="won" and st.time>1.0 and st.time<300.0,"actual roster skiff duel completes and is winnable with zero captain input")
	check(st.ships[0].ammo<80.0 and st.ships[1].sunk,"unassisted result comes from real finite ammunition and hull damage")
	check(st.effects.size()<=200 and st.projectiles.size()<=400 and st.log.size()<=12,"autobattle state remains bounded")
	for s in st.ships:
		for key in ["x","y","angle","vx","vy","hp","water","fuel","ammo"]:
			check(is_finite(float(s[key])),"autobattle keeps finite "+key)
	var frozen: float=st.time
	advance(st,20)
	check(st.time==frozen,"completed autobattle freezes")

func _initialize() -> void:
	test_deployment()
	test_autopilot()
	test_orders()
	test_mounts()
	test_engagement_range()
	test_impacts()
	test_unassisted()
	print("tactics: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
