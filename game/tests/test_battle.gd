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
	if "--case=contacts051" in OS.get_cmdline_user_args():
		_contacts051()
		print("CONTACTS051: %d checks, %d failures" % [contact_checks051,contact_failures051])
		quit(0 if contact_failures051==0 else 1)
		return
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

var contact_checks051: int=0
var contact_failures051: int=0

func _contact_check051(ok: bool,message: String) -> void:
	contact_checks051+=1
	if not ok:
		contact_failures051+=1
		push_error("CONTACTS051: "+message)

func _contact_boat051(id: String,x: float,y: float,radius: float) -> Dictionary:
	var spec: Dictionary=SPEC.duplicate(true)
	spec.size=radius
	return D.create_ship(spec,{"id":id,"x":x,"y":y,"vx":1.25,"vy":-2.5,"angle":0.37,"hp":91.0,"fuel":13.0,"ammo":7.0,"supplies":3.0,"water":2.0,"fire":0.1})

func _contact_state051(ships: Array,islands: Array=[]) -> Dictionary:
	var rng: RandomNumberGenerator=RandomNumberGenerator.new()
	rng.seed=17051
	return {"ships":ships,"islands":islands,"rng":rng,"time":12.0,"events":[{"kind":"unchanged"}],"projectiles":[],"resources":{"coins":123,"crew":17}}

func _contact_run051(st: Dictionary,label: String,clear: bool=true) -> void:
	var before: Dictionary=st.duplicate(true)
	var replay: Dictionary=st.duplicate(true)
	var rng_state: int=st.rng.state
	var references: Array=st.ships.duplicate()
	B._collisions(st)
	B._collisions(replay)
	_contact_check051(st.ships==replay.ships,label+": deterministic contact result")
	_contact_check051(st.rng.state==rng_state,label+": RNG unchanged")
	var restored: Dictionary=st.duplicate(true)
	restored.ships=before.ships
	_contact_check051(restored==before,label+": non-ship state unchanged")
	for i in range(st.ships.size()):
		var ship: Dictionary=st.ships[i]
		var original: Dictionary=before.ships[i]
		var non_position: Dictionary=ship.duplicate(true)
		non_position.x=original.x;non_position.y=original.y
		_contact_check051(var_to_bytes(non_position)==var_to_bytes(original),label+": all non-position boat bytes unchanged "+str(i))
		_contact_check051(is_same(ship,references[i]),label+": live boat reference retained "+str(i))
		if ship.sunk:
			_contact_check051(ship==original,label+": sunk hull untouched")
			continue
		_contact_check051(not B._blocked(st,B._pos(ship),B._radius(ship)),label+": hull stays in water "+str(i))
		if not clear:continue
		for j in range(i+1,st.ships.size()):
			var other: Dictionary=st.ships[j]
			if other.sunk:continue
			_contact_check051(B._pos(ship).distance_to(B._pos(other))>=B._radius(ship)+B._radius(other)-0.0001,label+": physical clearance %d/%d" % [i,j])

func _contacts051() -> void:
	# An isolated contact retains the original symmetric 0.51 projection exactly
	# (within Vector2 precision), including when storage order is reversed.
	for reverse_order: bool in [false,true]:
		var left: Dictionary=_contact_boat051("isolated-left",500.0,850.0,10.0)
		var right: Dictionary=_contact_boat051("isolated-right",519.0,850.0,10.0)
		var pair: Array=[left,right]
		if reverse_order:pair.reverse()
		_contact_run051(_contact_state051(pair),"isolated original projection reverse="+str(reverse_order))
		_contact_check051(absf(float(left.x)-499.49)<0.0001 and float(left.y)==850.0,"original left 0.51 correction")
		_contact_check051(absf(float(right.x)-519.51)<0.0001 and float(right.y)==850.0,"original right 0.51 correction")
	# R17 actual endBoatMotion051, original Bilge13/Tin14 circles, stable indices
	# P5/P11/P12/P16/P17/P18. No simulated motion, damage or planner acceptance.
	var rows: Array=[
		["player-5-bilge_punt",13.0,954.50927734375,929.755249023438,-0.0106886178255081,-0.00339403259567916],
		["player-11-bilge_punt",13.0,932.580017089844,943.901916503906,-0.00000551475068277796,0.00000208996016226592],
		["player-12-bilge_punt",13.0,922.663146972656,992.358947753906,0.0,0.0],
		["player-16-tin_skiff",14.0,930.4384765625,890.489990234375,-40.3676681518555,12.8787670135498],
		["player-17-tin_skiff",14.0,925.738952636719,918.102416992188,-0.000108744548924733,0.000162455995450728],
		["player-18-tin_skiff",14.0,938.217590332031,970.287963867188,0.0000000000000002101617914662,0.0000000000000001440264250916]
	]
	var cluster: Array=[]
	for row: Array in rows:
		var boat: Dictionary=_contact_boat051(row[0],row[2],row[3],row[1])
		boat.vx=row[4];boat.vy=row[5]
		cluster.append(boat)
	_contact_check051(absf(B._pos(cluster[1]).distance_to(B._pos(cluster[4]))-26.691090984)<0.00001,"R17 P11/P17 captured penetration")
	_contact_check051(absf(B._pos(cluster[1]).distance_to(B._pos(cluster[5]))-26.981581264)<0.00001,"R17 P11/P18 captured penetration")
	var islands: Array=[{"points":[[850,80],[1130,120],[1210,310],[1030,420],[820,300]]},{"points":[[1040,1320],[1240,1250],[1430,1450],[1320,1640],[1070,1580]]}]
	for reverse_order: bool in [false,true]:
		var ordered: Array=cluster.duplicate(true)
		if reverse_order:ordered.reverse()
		var sentinel: Dictionary=_contact_boat051("separated",1400.0,800.0,16.0)
		var sentinel_before: PackedByteArray=var_to_bytes(sentinel)
		ordered.append(sentinel)
		_contact_run051(_contact_state051(ordered,islands),"R17 reverse="+str(reverse_order))
		_contact_check051(var_to_bytes(sentinel)==sentinel_before,"R17 unrelated separated hull unchanged")
	# The later B/C correction reopens A/B after the original single i<j sweep.
	for reverse_order: bool in [false,true]:
		var chain: Array=[_contact_boat051("a",500.0,850.0,10.0),_contact_boat051("b",519.0,850.0,10.0),_contact_boat051("c",538.0,850.0,10.0)]
		if reverse_order:chain.reverse()
		_contact_run051(_contact_state051(chain),"three-body reopened contact reverse="+str(reverse_order))
	var left_shore: Dictionary={"points":[[480,750],[500,750],[500,950],[480,950]]}
	var right_shore: Dictionary={"points":[[539,750],[560,750],[560,950],[539,950]]}
	for reverse_order: bool in [false,true]:
		var anchored: Dictionary=_contact_boat051("shore-held",510.0,850.0,10.0)
		var free: Dictionary=_contact_boat051("free",529.0,850.0,10.0)
		var held_before: PackedByteArray=var_to_bytes(anchored)
		var pair: Array=[anchored,free]
		if reverse_order:pair.reverse()
		_contact_run051(_contact_state051(pair,[left_shore]),"one shore-blocked reverse="+str(reverse_order))
		_contact_check051(var_to_bytes(anchored)==held_before,"shore-blocked endpoint never moves into land")
		_contact_check051(float(free.x)>529.0,"free endpoint resolves shore-held contact")
		var trapped: Array=[_contact_boat051("trapped-left",510.0,850.0,10.0),_contact_boat051("trapped-right",529.0,850.0,10.0)]
		if reverse_order:trapped.reverse()
		var trapped_before: PackedByteArray=var_to_bytes(trapped)
		_contact_run051(_contact_state051(trapped,[left_shore,right_shore]),"both shore-blocked terminate reverse="+str(reverse_order),false)
		_contact_check051(var_to_bytes(trapped)==trapped_before,"both blocked endpoints unchanged on no progress")
		_contact_check051(B._pos(trapped[0]).distance_to(B._pos(trapped[1]))<20.0-0.0001,"unresolved trapped overlap remains physically blocked")
	var separated: Array=[_contact_boat051("left",500.0,850.0,10.0),_contact_boat051("right",600.0,850.0,10.0),_contact_boat051("wreck",500.0,850.0,10.0)]
	separated[2].sunk=true
	var separated_before: PackedByteArray=var_to_bytes(separated)
	_contact_run051(_contact_state051(separated),"separated live hulls and overlapping sunk hull")
	_contact_check051(var_to_bytes(separated)==separated_before,"separated and sunk hulls never move")
