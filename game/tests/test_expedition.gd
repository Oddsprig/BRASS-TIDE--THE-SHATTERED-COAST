extends SceneTree
const C=preload("res://scripts/campaign.gd")
const E=preload("res://scripts/expedition.gd")
const Money=preload("res://scripts/money.gd")
const Deployment=preload("res://scripts/deployment.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;print("FAIL expedition: ",message)

func _initialize():
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	print("expedition stage 1/3: seed baseline and legacy checks")
	var c=C.new(data)
	var seeded: Dictionary=c.new_game(83)
	check(bool(seeded.get("ok",false)),"Seeded campaign passes its normal career publication validation")
	if not bool(seeded.get("ok",false)):
		quit(1)
		return
	# Snapshot the published career before any legacy or synthetic mutations.
	var baseline: Dictionary=c.state.duplicate(true)
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
	# These synchronous cases never step the campaign or start private work.
	# Reuse immutable navigation; replace all mutable voyage data with deep copies.
	print("expedition stage 2/3: detached preparation checks")
	c.state=baseline.duplicate(true)
	c.events.clear()
	_preparation052(c)
	print("expedition stage 3/3: detached ownership/deployment checks")
	c.state=baseline.duplicate(true)
	c.events.clear()
	_owned_deployment052(c)
	c.state=baseline.duplicate(true)
	c.events.clear()
	_island_preparation057(c)
	print("expedition: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

func _preparation052(c) -> void:
	var b: Dictionary=c.state.fleet[0]
	var untowed_speed: float=c.travel_speed()
	# These unseeded shells isolate accounting rules; the separate Main fixture
	# proves career growth through an actual paid Harbor purchase instead.
	var idle: Dictionary=c.add_boat(c.hull(b.type),4)
	idle.mothballed=true
	var stored: Dictionary=c.add_boat(c.hull(b.type),6)
	stored.storedPort=c.data.START.port
	var short_crew: Dictionary=c.add_boat(c.hull(b.type),int(b.crewMin)-1)
	short_crew.mothballed=false
	var wreck: Dictionary=c.add_boat(c.hull(b.type),7)
	wreck.sunk=true
	var repair: Dictionary=c.add_boat(c.hull(b.type),3)
	repair.needsHarborRepair=true
	c.state.specialists=[{"premiumPerDay":37},{"premiumPerDay":91,"discharged":true},{"premiumPerDay":83,"lost":true}]
	var owned_crew: int=int(b.crew)+4+6+int(short_crew.crew)+3
	var snapshot: String=JSON.stringify(c.state)
	var r: Dictionary=c.expedition_report(18000.0)
	check(snapshot==JSON.stringify(c.state),"Preparation and support projections leave actual voyage resources unchanged")
	check(r.crew==int(b.crew) and is_equal_approx(r.usableCapacity,float(b.spec.cargo)),"Inactive, stored, undercrewed, sunk and repair-only hulls grant no active crew or holds")
	check(r.dailyWages==owned_crew*100+37,"All living owned sailors, including stored crew, and only live specialist premiums stay on payroll")
	var actual_speed: float=c.travel_speed()
	var expected_days: float=18000.0*2.0/maxf(0.01,actual_speed)/c.DAY_SECONDS+float(r.reserveDays)
	check(is_equal_approx(r.tripDays,expected_days) and r.returnWages==ceili(expected_days*r.dailyWages),"Real towing speed controls the whole return allowance without a guessed speed clamp")
	check(actual_speed<untowed_speed,"Inactive hulls impose a real towing burden")
	_preparation_fields052(c,r,owned_crew,actual_speed)

func _preparation_fields052(c,r: Dictionary,owned_crew: int,actual_speed: float) -> void:
	check(is_equal_approx(r.routeSpeed,actual_speed) and is_equal_approx(r.routeDistance,18000.0),"Preparation publishes the actual route speed and full supplied distance")
	check(is_equal_approx(r.foodPerDay,owned_crew*0.08),"Stored and inactive owned people still need rations")
	check(r.travelingCount==1 and r.ownedCount==5 and r.storedCount==1,"Owned, stored and traveling hull counts exclude the sunk hull")
	check(r.boats.size()==1 and r.boats[0].uid==c.state.flagship,"Only the actual traveling boat contributes a working tank")
	var tank: Dictionary=r.boats[0]
	check(is_equal_approx(tank.fuelRequired,float(tank.fuelPerDay)*r.tripDays) and is_equal_approx(tank.loadedDays,float(tank.loadedFuel)/float(tank.fuelPerDay)),"Actual boat burn determines required fuel and loaded endurance")
	check(is_equal_approx(tank.tankCapacity,float(c.state.fleet[0].spec.get("fuelCapacity",60))) and is_equal_approx(tank.tankShortfall,maxf(0,float(tank.fuelRequired)-float(tank.tankCapacity))),"Allowance beyond the actual fitted tank stays an explicit boat limit")
	check(r.supportOptions.size()==4,"Only owned inactive nonsunk hulls appear as hypothetical support")
	for option in r.supportOptions:
		check(option.projectionOnly and option.uid!=c.state.flagship,"Support options explicitly describe projections, without activating a boat")
		var boat: Dictionary=c.find_boat(str(option.uid))
		var missing: int=maxi(0,int(boat.crewMin)-int(boat.crew))
		check(option.crewToMinimum==missing and option.additionalDailyWages==missing*100,"Support payroll adds only missing crew; existing sailors are already paid")
	# Set the rations between the untowed and actual route allowances. A stale
	# derived-speed warning would miss this shortage even if tripDays was fixed.
	var solo: Dictionary=c.state.duplicate(true)
	solo.fleet=[c.state.fleet[0].duplicate(true)]
	var solo_days: float=E.report(solo,c.data,18000.0).tripDays
	c.state.cargo.food=(solo_days+float(r.tripDays))*0.5*float(r.foodPerDay)
	r=c.expedition_report(18000.0)
	check(r.foodShortfall>0 and r.warnings.any(func(w):return "food" in str(w).to_lower()),"Food shortfall and warning both follow actual towing speed")
	check(is_equal_approx(r.foodRequired,r.foodPerDay*r.tripDays) and is_equal_approx(r.payloadAfterFood,maxf(0,r.freeCapacity-r.foodShortfall*float(c.Economy.GOODS.food.weight))),"Useful payload reserves real hold space for the missing return food")
	c.state.cargo.food=0.0
	c.state.cargo.fuel=7.0
	c.state.fleet[0].fuel=0.0
	c.state.wageArrears=73
	check(Money.move(c.state,"coins",c.current_port(),"cash",int(c.state.coins),"Preparation shortage fixture"),"Shortage fixture transfers the purse instead of deleting money")
	var before: String=JSON.stringify(c.state)
	r=c.expedition_report(18000.0)
	check(before==JSON.stringify(c.state),"Shortfall report does not load reserves, spend money, hire crew or teleport support")
	check(r.fuelDays==0 and r.looseFuel==7 and r.boats[0].loadedFuel==0,"Loose fuel cannot disguise an empty working tank")
	check(is_equal_approx(r.fuelShortfall,r.fuelRequired) and r.fuelShortfall>0,"Empty loaded tank owes the complete physical fuel requirement")
	check(is_equal_approx(r.foodShortfall,r.foodRequired) and r.wageShortfall==r.returnWages+73,"Food and payroll shortages include real return allowance and existing arrears")
	check(not r.readyForAllowance and not str(r.bottleneck).is_empty(),"Unfunded allowance exposes a useful limit")
	for key in ["routeDistance","routeSpeed","outwardDays","returnDays","foodRequired","foodShortfall","fuelRequired","fuelShortfall","wageShortfall","payloadAfterFood","allowanceOverload"]:
		check(is_finite(float(r[key])) and float(r[key])>=0,"Finite nonnegative preparation "+key)
	for boat in c.state.fleet:boat.mothballed=true
	r=c.expedition_report(18000.0)
	check(r.boats.is_empty() and r.travelingCount==0 and r.usableCapacity==0 and not r.readyForAllowance,"Empty traveling fleet has no borrowed tanks, hold or readiness")
	for key in ["routeSpeed","outwardDays","returnDays","tripDays","foodShortfall","fuelShortfall","wageShortfall"]:
		check(is_finite(float(r[key])) and float(r[key])>=0,"No active fleet remains finite: "+key)

func _owned_deployment052(c) -> void:
	# Synthetic ownership fixture only, separate from the paid progression case.
	for i in range(5):c.add_boat(c.hull("iron_bastion"),14)
	var before: String=JSON.stringify(c.state)
	var r: Dictionary=c.expedition_report()
	var split: Dictionary=Deployment.split(c.active_fleet())
	check(r.ownedDP>300 and r.ownedDP==Deployment.total(c.state.fleet),"Large owned fleet points are real and may exceed the battle budget")
	check(r.battleLimit==300 and r.battleDP==split.points and r.battleDP<=300,"Report uses the real 300-point deployment split")
	check(split.reserve.size()>0 and split.deployed.size()+split.reserve.size()==c.state.fleet.size(),"Over-budget hulls remain owned in battle reserves")
	check(r.battleReserveCount==split.reserve.size() and before==JSON.stringify(c.state),"Deployment preview preserves every boat, purse and resource")

func _island_preparation057(c) -> void:
	# Detached accounting fixtures only. C's separate057 voyage must earn all
	# progress and provision through real public recruitment/purchase APIs.
	var site: Dictionary=c.Exploration.catalog_site(c.state,"middle_chart_rock")
	var hidden: String=JSON.stringify(c.state)
	var unknown: Dictionary=E.preview(c,"shatter_wreck_field",str(c.data.START.port))
	check(hidden==JSON.stringify(c.state) and unknown.siteId=="" and unknown.siteName=="Unknown landing" and not unknown.readyForAllowance,"Unknown-site preview withholds its details and preserves the career")
	c.Exploration.discover_near(c.state,site,1.0)
	var b: Dictionary=c.state.fleet[0]
	b.spec=b.spec.duplicate(true)
	b.spec.surveyFactor=2.0
	b.crew=int(b.crewMin)+4
	var before: String=JSON.stringify(c.state)
	var clue: Dictionary=E.preview(c,site.id,str(c.data.START.port),"",2)
	var paid: Dictionary=E.preview(c,site.id,str(c.data.START.port))
	check(before==JSON.stringify(c.state),"Island route/work quotations neither sight future clues nor spend stores, hire, sail or progress work")
	check(is_equal_approx(clue.chartDays,0.5) and clue.surveyDays==0 and is_equal_approx(paid.surveyDays,1.25),"Actual fitted surveyFactor shortens quoted chart and full paid-survey work")
	check(paid.shoreDays>clue.shoreDays and paid.shoreKits==3 and paid.crewNeeded==4,"Paid level3 budgets the additional survey above the level2 story clue")
	check(paid.returnPortId==str(c.data.START.port) and not str(paid.returnPortName).is_empty(),"Explicit sponsoring return harbor is named and retained")
	check(is_equal_approx(paid.foodRequired,paid.foodPerDay*paid.payrollDays),"Shore prepaid rations are included once within whole-day fleet food accounting")
	for row in paid.boats:
		check(is_equal_approx(row.fuelRequired,row.fuelPerDay*(paid.travelDays+paid.reserveDays)),"Idle chart/survey days never burn working boat fuel")
	check(is_equal_approx(paid.returnNow.shoreDays,0) and paid.returnNow.returnWages<=paid.returnWages,"Immediate return omits all optional shore work and its payroll")
	var anchorage: Dictionary=c.Exploration.catalog_site(c.state,"rust_salvage_anchorage")
	c.Exploration.discover_near(c.state,anchorage,1.0)
	var side: Dictionary=E.preview(c,site.id,str(c.data.START.port),anchorage.id)
	check(side.detour.shoreDays>side.shoreDays and side.detour.shoreKits==6,"Known optional anchorage budgets its actual remaining work and finite kit costs as well")
	b.crew=int(b.crewMin)
	b.fuel=0.0
	b.supplies=0.0
	c.state.cargo.food=0.0
	c.state.cargo.supplies=0.0
	c.state.cargo.fuel=90.0
	c.state.coins=0 # Isolated shortage accounting, not a claimed funded voyage.
	var poor: Dictionary=E.preview(c,site.id,str(c.data.START.port))
	check(poor.crewShortfall==4 and poor.kitShortfall==3 and poor.wageShortfall>0 and poor.foodShortfall>0,"Missing spare crew, shore kits, food and actual payroll coins stay explicit")
	check(poor.looseFuel==90 and poor.boats[0].loadedFuel==0 and poor.fuelShortfall>0 and not poor.readyForAllowance,"Cargo fuel cannot hide an individual boat's dry tank")
	c.state.position={"x":-10000.0,"y":-10000.0}
	var blocked: Dictionary=E.preview(c,site.id,str(c.data.START.port))
	check(not blocked.routeOk and not blocked.readyForAllowance and not str(blocked.routeMessage).is_empty(),"A refused actual water route never becomes a zero-distance ready allowance")
