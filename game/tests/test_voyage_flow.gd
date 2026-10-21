extends SceneTree
const C=preload("res://scripts/campaign.gd")
const Money=preload("res://scripts/money.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;print("FAIL voyage flow: ",message)

func _initialize():
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var c=C.new(world)
	c.new_game(83)
	var original: int=Money.total(c.state)
	var freight: Dictionary={}
	var survey: Dictionary={}
	for offer in c.VoyageJobs.available(c):
		if offer.kind=="freight":freight=offer
		if offer.kind=="survey":survey=offer
	check(not freight.is_empty() and not survey.is_empty(),"Starting harbor offers different funded work")
	check(c.accept_voyage_job(freight.id).ok and c.accept_voyage_job(survey.id).ok,"Several commitments run through real campaign APIs")
	check(Money.total(c.state)==original,"Canonical global ledger includes each escrow exactly once")
	check(c.state.cargoManifest[c.state.fleet[0].uid].has("@job:"+str(freight.id)),"Sealed freight has an actual carrier")
	check(c.state.marketSnapshots.has(world.START.port),"Signing a real harbor contract records an actual visit")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(c.state))
	check(c.restore(saved).ok and c.state.voyageJobs.size()==2,"Actual campaign restore preserves multiple jobs, freight, contacts and escrow")
	c.state.fleet[0].sunk=true
	c.Manifest.losses(c.state)
	var job: Dictionary=c.VoyageJobs._find(c.state,freight.id)
	check(job.failed and job.freight.qty==0,"Sinking the carrier loses that sealed lot")
	check(not c.settle_voyage_job(freight.id).ok,"Lost freight cannot produce a paid delivery")
	check(c.settle_voyage_job(freight.id,true).ok and Money.total(c.state)==original,"Failure refunds actual unused escrow without minting")
	var scene=load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("voyage-flow-fixture")
	scene.new_game()
	var offers: Array=scene.core.VoyageJobs.available(scene.core)
	scene.core.accept_voyage_job(offers[0].id)
	scene.ui.VoyageUI.open(scene.ui)
	check(scene.ui.modal_kind=="voyage_jobs","Actual Main renders active and offered job cards")
	scene.ui.VoyageUI.open(scene.ui,"Contacts")
	check(scene.ui.modal_open,"Actual contact list renders")
	scene.ui.VoyageUI.open(scene.ui,"Market notes")
	check(scene.ui.modal_open,"Dated observations render from actual visits")
	scene.queue_free()
	await process_frame
	print("voyage flow: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
