extends SceneTree
const C=preload("res://scripts/campaign.gd")
const Money=preload("res://scripts/money.gd")
const Damage=preload("res://scripts/damage.gd")
const Expedition=preload("res://scripts/expedition.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;print("FAIL island voyage: ",message)

func _initialize():
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var c=C.new(world)
	c.new_game(42)
	var site: Dictionary=c.Exploration.catalog_site(c.state,"lantern_fresh_cove")
	c.state.position={"x":site.x,"y":site.y}
	c.stop_sailing()
	c.Exploration.discover_near(c.state,site,1)
	c.state.cargo.supplies=6.0 # An explicitly isolated test-fixture inventory.
	var b: Dictionary=c.state.fleet[0]
	var food: float=c.state.cargo.food
	var purse: int=Money.total(c.state)
	var wages: int=c.state.coins
	var before: float=Damage.get_status(b).crewGuns
	check(c.begin_survey(site.id,"chart").ok,"Near a sighted landing, spare sailors can begin charting")
	check(int(b.shoreCrew)==2 and Damage.get_status(b).crewGuns<before,"Shore party cannot simultaneously man boat weapons")
	check(not c.chart_course(c.state.position).ok,"Fleet cannot leave its party behind accidentally")
	var ashore_before: String=JSON.stringify(c.state)
	var ashore: Dictionary=Expedition.preview(c,site.id,str(world.START.port),"",2)
	check(ashore_before==JSON.stringify(c.state) and ashore.work.size()==1 and ashore.work[0].inProgress,"Mid-assignment preparation reads only the actual saved shore party")
	check(ashore.shoreFood==0 and ashore.shoreKits==0 and is_equal_approx(ashore.chartDays,1.0),"Already prepaid shore stores are never charged a second time")
	check(is_equal_approx(ashore.foodRequired,maxf(0,ashore.foodPerDay*ashore.payrollDays-float(c.state.surveyFoodCredit))),"Unused prepaid rations offset normal future fleet consumption exactly once")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	check(c.restore(saved).ok,"Mid-survey save restores")
	var restored: Dictionary=Expedition.preview(c,site.id,str(world.START.port),"",2)
	check(is_equal_approx(restored.chartDays,ashore.chartDays) and is_equal_approx(restored.foodRequired,ashore.foodRequired),"Restored party keeps its remaining days and actual food credit in preparation")
	c.wait_day()
	c.apply_economy(c.state.ports,[],1)
	check(c.state.exploration.sites[site.id].level==2,"A paid day completes the coastal chart")
	check(is_equal_approx(c.state.cargo.food,food-0.4),"Five crew consume0.4food/day including prepaid shore rations exactly once")
	check(c.state.coins==wages-500 and Money.total(c.state)==purse,"The entire crew receives its real daily500coins without minting")
	check(int(c.state.fleet[0].get("shoreCrew",0))==0,"Party returns to boat duties")
	check(not c.begin_survey(site.id,"chart").ok,"Chart reward cannot repeat")
	var bad: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	bad.exploration.catalog[0].x=-1
	var snapshot: String=JSON.stringify(c.state)
	check(not c.restore(bad).ok and JSON.stringify(c.state)==snapshot,"Malformed discoveries refuse atomically")
	var scene=load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("island-fixture")
	scene.new_game()
	scene.ui.CampaignUI.islands(scene.ui)
	check(scene.ui.modal_kind=="islands","Island charts open in actual Main")
	scene.ui.CampaignUI.site(scene.ui,"lantern_fresh_cove")
	check(scene.ui.modal_kind=="island_site","Individual discovered landing opens in actual Main")
	scene.ui.CampaignUI.expedition(scene.ui)
	check(scene.ui.modal_kind=="expedition" and scene.selected_site=="lantern_fresh_cove","Selected island opens the existing preparation panel")
	scene.ui.CampaignUI.expedition(scene.ui,false)
	check(scene.ui.modal_kind=="expedition","Selected harbor preparation remains explicitly available")
	scene.queue_free()
	await process_frame
	print("island voyage: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
