extends SceneTree
const D=preload("res://scripts/damage.gd")
const B=preload("res://scripts/battle.gd")
const SPEC={"id":"skiff","name":"Skiff","hp":130,"armor":1,"crewMin":2,"crewOptimal":5,"crewMax":7,"size":16,"speed":100,"turn":2,"pumps":1,"weapon":"gun","damage":12,"fireRate":2,"range":550}
func check(ok: bool,msg: String) -> void:
	if not ok:
		push_error(msg)
		quit(1)
	assert(ok,msg)
func make(count: int=1) -> Dictionary:
	var fleet: Array=[]
	for i in range(count):
		fleet.append(D.create_ship(SPEC))
	return B.create({"fleet":fleet,"enemySpecs":[SPEC],"seed":42})
func advance(st: Dictionary,count: int,input: Dictionary={}) -> void:
	for i in range(count):
		B.update(st,1.0/30.0,input)
func _initialize() -> void:
	var owned_enemy: Dictionary=D.create_ship(SPEC)
	var owned_test: Dictionary=B.create({"fleet":[D.create_ship(SPEC)],"enemyFleet":[owned_enemy],"seed":1})
	owned_test.ships[1].ammo=7.0
	check(owned_enemy.ammo==7.0,"NPC owner boat references retain actual stores")
	var ship: Dictionary=D.create_ship(SPEC)
	var st: Dictionary=B.create({"fleet":[ship,D.create_ship(SPEC)],"enemySpecs":[SPEC],"seed":42})
	st.ships[0].supplies=17.0
	check(ship.supplies==17.0,"Fleet references retained")
	check(B.select_flagship(st,st.ships[1].id),"Switch ally")
	check(not B.select_flagship(st,st.ships[2].id),"Reject enemy flagship")
	st.ships[1].sunk=true
	advance(st,1)
	check(B.get_flagship(st).id==ship.id and st.wrecks.size()==1,"Automatic flagship")
	var enemy: Dictionary=st.ships[2]
	enemy.x=ship.x+180
	enemy.y=ship.y
	enemy.spec.speed=0.0
	var hp: float=enemy.hp
	advance(st,90,{"fire":true,"aimX":enemy.x,"aimY":enemy.y})
	check(enemy.hp<hp,"Projectile damages enemy")
	check(ship.ammo<=76,"Player repeats firing")
	check(enemy.ammo<=76,"AI repeats firing")
	enemy.sunk=true
	advance(st,1)
	check(st.result=="won","Victory")
	var frozen: float=st.time
	advance(st,20)
	check(st.time==frozen,"Result freezes")
	st=make()
	st.ships[0].sunk=true
	advance(st,1)
	check(st.result=="lost","Defeat")
	st=make()
	for s in st.ships:
		s.ammo=0
	B.retreat(st)
	advance(st,361)
	check(st.result=="retreated","Twelve-second retreat")
	var a: Dictionary=make()
	var b: Dictionary=make()
	for i in range(3600):
		var target: Dictionary=a.ships[1]
		var input: Dictionary={"forward":i<200,"fire":true,"aimX":target.x,"aimY":target.y}
		B.update(a,1.0/30.0,input)
		B.update(b,1.0/30.0,input)
	check(a.ships==b.ships and a.projectiles==b.projectiles and a.result==b.result,"Deterministic battle")
	for s in a.ships:
		for key in ["x","y","angle","vx","vy","hp","water","fuel","ammo"]:
			check(is_finite(float(s[key])),"Finite "+key)
	check(a.effects.size()<=200 and a.projectiles.size()<=400 and a.log.size()<=12,"Bounded state")
	st=make()
	st.ships[0].ammo=0
	advance(st,120,{"fire":true,"aimX":1600,"aimY":850})
	for p in st.projectiles:
		check(p.team!="player","Dry ammo stops firing")
	st=make()
	enemy=st.ships[1]
	enemy.x=1000
	enemy.y=850
	enemy.spec.speed=0
	hp=enemy.hp
	st.projectiles.append({"x":800.0,"y":850.0,"px":800.0,"py":850.0,"vx":12000.0,"vy":0.0,"team":"player","damage":10.0,"kind":"bullet","life":1.0,"owner":"test","radius":2.0})
	advance(st,1)
	check(enemy.hp<hp,"Swept collision prevents tunneling")
	st=make(2)
	var ally: Dictionary=st.ships[1]
	ally.x=1000
	ally.y=850
	ally.spec.speed=0
	hp=ally.hp
	st.projectiles.append({"x":800.0,"y":850.0,"px":800.0,"py":850.0,"vx":12000.0,"vy":0.0,"team":"player","damage":100.0,"kind":"shell","life":1.0,"owner":"test","radius":2.0})
	advance(st,1)
	check(ally.hp==hp,"Friendly fire disabled")
	st=make()
	st.islands=[{"points":[[850,750],[900,750],[900,950],[850,950]]}]
	enemy=st.ships[1]
	enemy.x=1000
	enemy.y=850
	enemy.spec.speed=0
	hp=enemy.hp
	st.projectiles.append({"x":800.0,"y":850.0,"px":800.0,"py":850.0,"vx":12000.0,"vy":0.0,"team":"player","damage":100.0,"kind":"shell","life":1.0,"owner":"test","radius":2.0})
	advance(st,1)
	check(enemy.hp==hp,"Shore cover stops swept projectile before hull")
	st.ships[0].x=800
	st.ships[0].y=850
	advance(st,300,{"forward":true})
	check(not B._blocked(st,Vector2(st.ships[0].x,st.ships[0].y),B._radius(st.ships[0])),"Manual ship cannot enter land")
	print("battle: all native tests passed")
	quit(0)
