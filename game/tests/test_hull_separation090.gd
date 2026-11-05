extends SceneTree
## Bounded native primitives, not an AI encounter, rendered motion or FPS proof.
const B=preload("res://scripts/battle.gd")
const D=preload("res://scripts/damage.gd")
const H=preload("res://scripts/hull_profiles.gd")
const R=preload("res://scripts/tactical_routes.gd")
const S=preload("res://scripts/tactical_stations.gd")
var specs: Dictionary={}
var checks: int=0
var failures: int=0
var motions: Dictionary={}

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL HULL SEPARATION090: "+message)

func boat(type: String,id: String,p: Vector2,heading: float=0.0,team: String="player") -> Dictionary:
	return D.create_ship(specs[type],{"id":id,"uid":id,"team":team,"x":p.x,"y":p.y,"angle":heading,"order":"engage","orderTarget":{},"orderRevision":0})

func state(ships: Array,islands: Array=[]) -> Dictionary:
	var rng: RandomNumberGenerator=RandomNumberGenerator.new()
	rng.seed=90090
	return {"ships":ships,"islands":islands,"rng":rng,"time":0.0,"projectiles":[],"effects":[],"events":[],"log":[],"accounts":{"coins":12345,"crewPurse":500},"autopilot":true,"playerId":"","tactical":{"manualId":""}}

func gap(a: Dictionary,b: Dictionary) -> float:
	var ac: Vector3=H.contact_capsule090(a.spec)
	var bc: Vector3=H.contact_capsule090(b.spec)
	var af: Vector2=Vector2.from_angle(float(a.angle))
	var bf: Vector2=Vector2.from_angle(float(b.angle))
	# Independent segment-distance implementation, rather than the new normal solve.
	return R.segment_distance(B._pos(a)+af*ac.x,B._pos(a)+af*ac.y,B._pos(b)+bf*bc.x,B._pos(b)+bf*bc.y)-B._radius(a)-B._radius(b)

func resolve(st: Dictionary,label: String) -> void:
	var before: Dictionary=st.duplicate(true)
	var replay: Dictionary=st.duplicate(true)
	var refs: Array=st.ships.duplicate()
	var rng_state: int=st.rng.state
	B._collisions(st)
	B._collisions(replay)
	check(st.ships==replay.ships,label+": deterministic")
	check(st.rng.state==rng_state,label+": RNG retained")
	var restored: Dictionary=st.duplicate(true)
	restored.ships=before.ships
	check(restored==before,label+": non-ship state retained")
	for i: int in range(st.ships.size()):
		var ship: Dictionary=st.ships[i]
		var original: Dictionary=before.ships[i]
		var non_position: Dictionary=ship.duplicate(true)
		non_position.x=original.x;non_position.y=original.y
		check(var_to_bytes(non_position)==var_to_bytes(original) and is_same(ship,refs[i]),label+": owner/stats/stores retained "+str(i))
		if ship.sunk:continue
		check(not B._blocked(st,B._pos(ship),B._radius(ship)),label+": water "+str(i))
		for j: int in range(i+1,st.ships.size()):
			if not st.ships[j].sunk:check(gap(ship,st.ships[j])>=-0.0002,label+": hull gap %d/%d"%[i,j])

func motion_case(label: String,ships: Array,controls: Array,steps: int) -> Dictionary:
	var st: Dictionary=state(ships)
	var starts: Array=[]
	for ship: Dictionary in ships:starts.append(B._pos(ship))
	var minimum: float=INF
	var water: bool=true
	for tick: int in range(steps):
		for i: int in range(ships.size()):
			B._move(st,ships[i],1.0/30.0,float(controls[i][0]),float(controls[i][1]),false)
		B._collisions(st)
		for i: int in range(ships.size()):
			water=water and not B._blocked(st,B._pos(ships[i]),B._radius(ships[i]))
			for j: int in range(i+1,ships.size()):minimum=minf(minimum,gap(ships[i],ships[j]))
	check(minimum>=-0.0002,label+": each 30Hz post-contact pose clears waterlines")
	check(water,label+": every step stays in water")
	var progress: Array=[]
	for i: int in range(ships.size()):progress.append([B._pos(ships[i]).x-starts[i].x,B._pos(ships[i]).y-starts[i].y])
	var result: Dictionary={"steps":steps,"minimumCapsuleGap":minimum,"progress":progress}
	motions[label]=result
	return result

func profiles() -> void:
	check(specs.size()==36,"all 36 canonical specs loaded")
	for id: String in H.hull_ids():
		var spec: Dictionary=specs[id]
		var before: PackedByteArray=var_to_bytes(spec)
		var capsule: Vector3=H.contact_capsule090(spec)
		check(capsule.z==B._radius({"spec":spec}),id+": canonical capsule radius equals terrain/hit radius")
		var covered: bool=true
		var offset: float=H.CAT_OFFSET if str(spec.role)=="raider" else 0.0
		for station: Vector2 in H.stations(spec):
			var p: Vector2=Vector2(station.x,(absf(station.y)+offset))*float(spec.size)
			covered=covered and R.distance(p,Vector2(capsule.x,0.0),Vector2(capsule.y,0.0))<=capsule.z+0.0001
		check(covered and capsule.x<=0.0 and capsule.y>=0.0,id+": every authored station and original circle contained")
		check(var_to_bytes(spec)==before,id+": spec unchanged")
	var legacy: Dictionary={"size":13.123456789,"id":"unprofiled"}
	check(H.contact_capsule090(legacy).x==0.0 and H.contact_capsule090(legacy).y==0.0,"unprofiled hull retains circle")
	for row: Array in [[Vector2.ZERO,Vector2.RIGHT*20.0,Vector2(5,7),Vector2(30,7)],[Vector2.ZERO,Vector2.RIGHT*20.0,Vector2(9,-10),Vector2(9,10)],[Vector2(2,3),Vector2(2,3),Vector2(15,4),Vector2(15,4)]]:
		check(absf(B._capsule_delta090(row[0],row[1],row[2],row[3]).length()-R.segment_distance(row[0],row[1],row[2],row[3]))<0.0001,"parallel/crossing/point segment normal matches independent distance")

func contacts() -> void:
	for reversed: bool in [false,true]:
		var a: Dictionary=boat("brasswind_motor_galleon","loaded",Vector2(700,850))
		var b: Dictionary=boat("blackwater_fleet_tanker","tanker",Vector2(785,850),PI/5.0)
		a.cargo={"food":350,"metal":120};b.cargo={"fuel":500}
		check(B._pos(a).distance_to(B._pos(b))>B._radius(a)+B._radius(b) and gap(a,b)<0.0,"old circles miss a real long-hull contact")
		var pair: Array=[a,b]
		if reversed:pair.reverse()
		resolve(state(pair),"loaded angled pair reverse="+str(reversed))
	var crowd: Array=[boat("brasswind_motor_galleon","a",Vector2(700,850)),boat("brasswind_motor_galleon","b",Vector2(785,850)),boat("brasswind_motor_galleon","c",Vector2(870,850))]
	resolve(state(crowd),"reopened three-hull contact")
	var left: Dictionary={"points":[[0,0],[500,0],[500,1700],[0,1700]]}
	var held: Dictionary=boat("brasswind_motor_galleon","held",Vector2(528,850))
	var free: Dictionary=boat("brasswind_motor_galleon","free",Vector2(585,850))
	var held_bytes: PackedByteArray=var_to_bytes(held)
	resolve(state([held,free],[left]),"one shore-held hull")
	check(var_to_bytes(held)==held_bytes,"contact never pushes held endpoint into shore")
	var trapped: Dictionary=state([boat("brasswind_motor_galleon","left",Vector2(530,850)),boat("brasswind_motor_galleon","right",Vector2(585,850))],[left,{"points":[[615,0],[2300,0],[2300,1700],[615,1700]]}])
	var trapped_bytes: PackedByteArray=var_to_bytes(trapped.ships)
	B._collisions(trapped)
	check(var_to_bytes(trapped.ships)==trapped_bytes and gap(trapped.ships[0],trapped.ships[1])<0.0,"two shore-blocked endpoints retain honest unresolved contact")

func maneuvering() -> void:
	var crossing: Array=[boat("tin_skiff","east",Vector2(740,850)),boat("tin_skiff","south",Vector2(850,740),PI/2.0)]
	var result: Dictionary=motion_case("crossing",crossing,[[0.0,0.8],[PI/2.0,0.8]],150)
	check(float(result.progress[0][0])>200.0 and float(result.progress[1][1])>200.0,"crossing traffic makes forward progress")
	var heavy: Dictionary=boat("iron_bastion","turner",Vector2(820,850))
	var light: Dictionary=boat("tin_skiff","alongside",Vector2(820,900))
	motion_case("heavy turn",[heavy,light],[[PI/2.0,0.0],[0.0,0.0]],45)
	check(absf(angle_difference(0.0,float(heavy.angle)))>1.0,"heavy can complete a substantial turn beside a light hull")
	var leader: Dictionary=boat("brasswind_motor_galleon","leader",Vector2(650,850))
	var escort: Dictionary=boat("tin_skiff","escort",Vector2.ZERO)
	var view: Dictionary={"groups":{},"options":{"byId":{}}}
	for formation: String in ["line","column","screen"]:
		view.options.byId[escort.id]={"formation":formation}
		var p: Vector2=B._pos(leader)+S.formation_offset(view,escort,leader)
		escort.x=p.x;escort.y=p.y
		check(gap(leader,escort)>0.0,formation+": existing escort slot clears authored hulls")
	view.options.byId[escort.id]={"formation":"line"}
	var slot: Vector2=B._pos(leader)+S.formation_offset(view,escort,leader)
	escort.x=slot.x;escort.y=slot.y;escort.order="escort"
	leader.cargo={"food":350,"metal":120}
	result=motion_case("escort loaded civilian",[leader,escort],[[0.0,0.7],[0.0,0.7]],90)
	check(float(result.progress[0][0])>50.0 and float(result.progress[1][0])>50.0 and leader.cargo=={"food":350,"metal":120} and escort.order=="escort","loaded leader and escort advance with stores/order retained")
	var retreat: Dictionary=boat("tin_skiff","withdraw",Vector2(1100,910),PI)
	retreat.order="withdraw"
	var blocker: Dictionary=boat("brasswind_motor_galleon","friend",Vector2(950,850))
	var budget: Dictionary={"clearanceTests":0,"clearanceLimit":128,"exhaustions":0,"separatingEgress051":true}
	check(R.occupied(R.grid([retreat,blocker]),retreat,B._pos(retreat),Vector2(800,910),B._radius(retreat)+4.0,0.0,5.0,budget,true)=="valid","existing traffic gate admits a narrow broadside withdrawal")
	result=motion_case("retreat past friend",[retreat,blocker],[[PI,0.8],[0.0,0.0]],150)
	check(float(result.progress[0][0])< -200.0 and retreat.order=="withdraw","withdrawal passes friend without a frozen bunch")

func formations_and_boundaries() -> void:
	for type: String in ["tin_skiff","brasswind_motor_galleon"]:
		var fleet: Array=[D.create_ship(specs[type]),D.create_ship(specs[type])]
		var layout: Dictionary=B._formation_positions({"islands":[]},fleet,[])
		check(not layout.has("error"),type+": formation available")
		if layout.has("error"):continue
		var a: Dictionary=boat(type,"first",layout.player[0])
		var b: Dictionary=boat(type,"second",layout.player[1])
		check(gap(a,b)>=4.0-0.0002,type+": spawn columns clear actual hulls")
		check(absf(B._pos(b).x-B._pos(a).x-85.0)<0.0001 if type=="tin_skiff" else B._pos(b).x-B._pos(a).x>85.0,type+": spacing grows only for a longer hull")
	var a: Dictionary=boat("brasswind_motor_galleon","boundary",Vector2(700,850))
	var shore: Dictionary=state([a],[{"points":[[0,0],[650,0],[650,1700],[0,1700]]}])
	check(not B._blocked(shore,Vector2(679,850),B._radius(a)) and B._blocked(shore,Vector2(677,850),B._radius(a)),"terrain still uses the original 28-unit radius")
	for offset: float in [31.0,27.0]:
		var target: Dictionary=boat("brasswind_motor_galleon","hit-test",Vector2(1000,850),0.0,"enemy")
		var st: Dictionary=state([target])
		var hp: float=float(target.hp)
		st.projectiles.append({"x":800.0,"y":850.0+offset,"px":800.0,"py":850.0+offset,"vx":12000.0,"vy":0.0,"team":"player","damage":30.0,"kind":"bullet","life":1.0,"owner":"fixture","radius":2.0})
		B._projectiles(st,1.0/30.0)
		check(target.hp==hp if offset>30.0 else target.hp<hp,"projectile boundary retains size plus projectile radius at offset "+str(offset))

func intentional_contact() -> void:
	for order: String in ["ram","board"]:
		var a: Dictionary=boat("tin_skiff","source",Vector2(700,850),0.0)
		var b: Dictionary=boat("tin_skiff","target",Vector2(745,850),0.0,"enemy")
		a.order=order;a.orderTarget={"shipId":b.id}
		var st: Dictionary=state([a,b])
		var before: PackedByteArray=var_to_bytes(st.ships)
		B._collisions(st)
		check(var_to_bytes(st.ships)==before and gap(a,b)<0.0,order+": intentional target keeps original circle contact")
	var a: Dictionary=boat("tin_skiff","auto-source",Vector2(700,850))
	var b: Dictionary=boat("tin_skiff","auto-target",Vector2(745,850),0.0,"enemy")
	a.boardingOrder={"target":b.id,"count":2,"orderRevision":0,"automatic":true}
	var st: Dictionary=state([a,b])
	st.playerId=a.id
	check(B._contact_target090(st,a)==b.id,"current automatic boarding retains its exact target")
	st.autopilot=false
	check(B._contact_target090(st,a).is_empty(),"manual takeover revokes automatic boarding exemption")
	resolve(st,"manual takeover hull contact")
	st.autopilot=true;st.tactical.manualId=a.id
	check(B._contact_target090(st,a).is_empty(),"live tactical manualId revokes automatic boarding exemption")
	st.tactical.manualId="";a.orderRevision=1
	check(B._contact_target090(st,a).is_empty(),"stale boarding revision grants no contact exemption")

func _initialize() -> void:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	if not data is Dictionary or not data.get("HULLS") is Array:
		print("FAIL HULL SEPARATION090: canonical hull data unavailable")
		quit(1);return
	for spec: Dictionary in data.HULLS:specs[str(spec.id)]=spec
	profiles()
	contacts()
	maneuvering()
	formations_and_boundaries()
	intentional_contact()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file: FileAccess=FileAccess.open(arg.substr(9),FileAccess.WRITE)
			check(file!=null,"requested report file writable")
			if file!=null:
				file.store_string(JSON.stringify({"schema":1,"scope":"hull-separation090-native-primitives","checks":checks,"failures":failures,"motions":motions,"renderedMotion":false,"performanceMeasured":false},"\t"))
	print("HULL SEPARATION090: %d checks, %d failures; native candidate"%[checks,failures])
	quit(0 if failures==0 else 1)
