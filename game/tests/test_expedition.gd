extends SceneTree
const C=preload("res://scripts/campaign.gd")
const E=preload("res://scripts/expedition.gd")
const Money=preload("res://scripts/money.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;print("FAIL expedition: ",message)

func _initialize():
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var c=C.new(data)
	c.new_game(83)
	var before: String=JSON.stringify(c.state)
	var r: Dictionary=E.report(c.state,data,1000)
	check(before==JSON.stringify(c.state),"Report does not mutate the voyage")
	check(r.dailyWages==500 and r.crew==5,"Five sailors cost500coins/day")
	check(is_equal_approx(r.foodDays,float(data.START.food)/0.4),"Food endurance uses actual0.08ration/day")
	var b: Dictionary=c.state.fleet[0]
	var fuel_use: float=45*(0.011+float(b.spec.size)*0.0002)*maxf(0.2,float(b.spec.get("fuelUse",1)))
	check(is_equal_approx(r.fuelDays,float(b.fuel)/fuel_use),"Fuel endurance matches campaign per-second burn")
	check(r.tripDays>r.reserveDays and r.returnWages==ceili(r.tripDays*500),"Round trip includes a funded contingency")
	var other: Dictionary=c.add_boat(c.hull(b.type),int(b.crewMin))
	other.fuel=0
	check(E.report(c.state,data).fuelDays==0,"Least-fueled traveling boat limits range")
	other.mothballed=true
	check(E.capacity(c.state)==float(b.spec.cargo),"Mothballed hull supplies no capacity")
	other.mothballed=false;other.storedPort=data.START.port
	check(E.capacity(c.state)==float(b.spec.cargo),"Stored hull supplies no capacity")
	var initial_weight: float=E.cargo_weight(c.state)
	c.state.freight={"good":"iron","qty":30}
	check(is_equal_approx(E.cargo_weight(c.state),initial_weight+90),"Freight has real material weight")
	check(E.report(c.state,data).overload>0 and not c.chart_course(c.state.position).ok,"Overweight cargo blocks departure without deletion")
	check(c.state.freight.qty==30,"Rejected departure preserves freight")
	c.state.freight={}
	b.fuel=63
	b.ammo=float(b.spec.ammoCapacity)+100
	b.supplies=23
	check(is_equal_approx(E.cargo_weight(c.state),initial_weight+8),"Only working stores above fitted tank/rack/magazine limits occupy holds")
	Money.move(c.state,"coins",c.port(data.START.port),"cash",int(c.state.coins),"Broke fixture")
	check(E.report(c.state,data).affordableDays==0,"Empty captain purse cannot promise paid days")
	for boat in c.state.fleet:boat.mothballed=true
	r=E.report(c.state,data)
	for key in ["usableCapacity","cargoWeight","freeCapacity","overload","fuelDays","foodDays","repairKits","affordableDays","tripDays"]:check(is_finite(float(r[key])) and float(r[key])>=0,"Finite nonnegative "+key)
	check(not r.warnings.is_empty() and r.fuelDays==0,"Empty fleet has explicit warnings and no false infinite range")
	print("expedition: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
