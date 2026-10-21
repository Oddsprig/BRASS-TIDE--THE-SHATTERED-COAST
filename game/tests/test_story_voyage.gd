extends SceneTree
const C=preload("res://scripts/campaign.gd")
const M=preload("res://scripts/money.gd")
const G=preload("res://scripts/goods.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;print("FAIL story voyage: ",message)
func known(c,id: String,level: int):
	c.state.exploration.sites[id]={"level":level,"rewarded":false}
func _initialize():
	var w: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var c=C.new(w);c.new_game(161)
	var supply: int=M.total(c.state)
	check(c.StoryOps.start(c,"ironwood_for_the_mill").ok,"Actual harbor contact starts a clear journal lead without a failed delivery")
	check(not c.StoryOps.choose(c,"ironwood_for_the_mill","deliver_timber").ok,"Actual location gate prevents remote delivery")
	c.state.position=c.port_position("sawtooth_mill")
	check(c.trade("sawtooth_mill","timber",5,"buy").ok,"Merchant actually buys finite timber for the story delivery")
	check(c.StoryOps.choose(c,"ironwood_for_the_mill","deliver_timber").ok,"Real owned timber feeds mill inventory")
	known(c,"sawtooth_timber_stand",2)
	check(c.StoryOps.choose(c,"ironwood_for_the_mill","show_survey").ok,"Charted stand opens the buyer decision")
	c.state.position=c.port_position("brass_haven")
	check(c.StoryOps.choose(c,"ironwood_for_the_mill","forge_first").ok and c.state.storyRights.buyer=="forge","Actual branch selects a recipient and opportunity")
	check(c.Factions.standing(c.state,"forge").score==4 and c.Factions.standing(c.state,"compact").score==-2,"Story consequences change canonical faction standings")
	var rep: int=c.Factions.standing(c.state,"forge").score
	check(not c.StoryOps.choose(c,"ironwood_for_the_mill","compact_first").ok and c.Factions.standing(c.state,"forge").score==rep,"Settled branch cannot grant its consequences twice")
	c.state.position=c.port_position("sawtooth_mill")
	var offer: Dictionary={}
	for job in c.VoyageJobs.available(c):
		if str(job.id).begins_with("chainfreight-"):offer=job
	check(not offer.is_empty() and offer.targetPort=="anvil_dock","Decision opens the promised finite funded freight at its real source")
	check(c.accept_voyage_job(offer.id).ok and M.total(c.state)==supply,"Story-earned passage buys physical cargo and funds ordinary escrow without minting")
	check(c.state.storyRights.usedOffers.has(offer.id),"Opportunity has a stable once-only issue record")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok and c.state.storyRights.buyer=="forge","Actual save restores story branch, effects and accepted passage")
	c.new_game(162);c.state.position=c.port_position("reed_floats")
	c.StoryOps.start(c,"middle_sea_chart")
	known(c,"middle_chart_rock",2);c.StoryOps.choose(c,"middle_sea_chart","share_chart")
	known(c,"shatter_wreck_field",3);c.StoryOps.choose(c,"middle_sea_chart","mark_field")
	check(c.StoryOps.choose(c,"middle_sea_chart","open_field").ok and c.state.storyRights.openField,"Explorer chooses actual public salvage rights")
	var site: Dictionary=c.Exploration.catalog_site(c.state,"shatter_wreck_field")
	var record: Dictionary=c.Salvage.seed_site_wreck(c,site,"harbor_sloop")
	var wreck: Dictionary=c.Salvage.find_wreck(c.state,record.id)
	var owner: Dictionary=c.fleet_owner("patrol-1")
	for good in owner.cargo:owner.cargo[good]=0
	owner.tradeCargo=0
	var p: Dictionary=c.NavalAI._find_patrol(c.state,owner.id)
	p.x=site.x;p.y=site.y
	var before: float=0
	for good in wreck.components:before+=float(wreck.components[good])*float(G.ITEMS[good].weight)
	var kits: float=owner.boats[0].supplies+owner.boats[1].supplies
	c.StoryOps.daily(c)
	var after: float=0
	for good in wreck.components:after+=float(wreck.components[good])*float(G.ITEMS[good].weight)
	check(before>after and is_equal_approx(before-after,c.Economy.cargo_weight(owner.cargo)),"Nearby public salvor moves finite wreck material into an actual convoy hold")
	check(is_equal_approx(owner.boats[0].supplies+owner.boats[1].supplies,kits-0.25) and wreck.hullStripped,"Salvage work spends actual kits and prevents subsequently towing an intact hull")
	var cargo: float=owner.tradeCargo;c.StoryOps.daily(c)
	check(owner.tradeCargo==cargo,"The same company cannot work the field twice in one economic day")
	c.state.storyRights.openField=false;c.state.storyRights.privateField=true;c.state.econDay+=1;c.StoryOps.daily(c)
	check(owner.tradeCargo==cargo,"Private claim excludes those public salvage operations")
	var scene=load("res://main.tscn").instantiate();root.add_child(scene);await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("story-voyage-fixture");scene.new_game();scene.ui.StoryUI.open(scene.ui)
	check(scene.ui.modal_kind=="coastal_stories","Actual story journal and harbor lead menu render")
	scene.queue_free();await process_frame
	print("story voyage: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
