extends SceneTree
## Prepared source only. Root must run this through the shared Test Bridge.
const Campaign=preload("res://scripts/campaign.gd")
const Contacts=preload("res://scripts/contacts.gd")
const Jobs=preload("res://scripts/voyage_jobs.gd")
const Money=preload("res://scripts/money.gd")
const VoyageUI=preload("res://scripts/voyage_ui.gd")
const BROKER="contact_tobin_hale"
var checks: int=0
var failures: int=0
var c
var baseline: Dictionary
var earned: Dictionary

func check(value: bool, message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL contact opportunity056: ",message)

func dock(id: String) -> void:
	c.state.position=c.port_position(id);c.state.lastPort=id;c.state.path=[]

func reset(source: Dictionary) -> void:
	c.state=source.duplicate(true)

func assets() -> Dictionary:
	return {"coins":Money.total(c.state),"cargo":c.state.cargo.duplicate(true),
		"ports":c.state.ports.duplicate(true),"jobs":c.state.voyageJobs.duplicate(true),
		"contacts":Contacts.list_contacts(c.state)}

func _initialize() -> void:
	print("contact opportunity056: one seeded Campaign setup")
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c=Campaign.new(world);c.new_game(5603)
	baseline=c.state.duplicate(true)
	check(Jobs.contact_opportunity(c,BROKER).is_empty(),"An unmet contact has no earned recommendation")
	Contacts.visit(c.state,c.current_port(),c.state.day)
	Contacts.record(c.state,BROKER,"favor:fixture",5,"A favor is not paid work")
	Contacts.record(c.state,BROKER,"naval:fixture",0,"Witnessed another fleet's fight")
	check(Contacts.completed_work(c.state,BROKER).is_empty() and Jobs.contact_opportunity(c,BROKER).is_empty(),"Visits, favors and witnessed fights do not qualify as fulfilled paid work")
	check(Jobs.contact_opportunity(c,"").is_empty(),"Empty contact id cannot select untagged board work")
	reset(baseline)
	var survey: Dictionary={}
	for offer in Jobs.available(c):
		if offer.kind==Jobs.KIND_SURVEY:survey=offer;break
	check(not survey.is_empty(),"Seed has funded work to earn the broker's memory")
	if survey.is_empty():finish();return
	var supply: int=Money.total(c.state)
	check(c.accept_voyage_job(str(survey.id)).ok,"Ordinary survey is funded through the actual campaign API")
	# Seed the completed physical survey condition; this fixture tests settlement,
	# not the exploration work loop, and does not claim observed play coverage.
	c.state.exploration.sites[str(survey.siteId)].level=3
	check(c.settle_voyage_job(str(survey.id)).ok,"Real completed-work settlement creates the remembered promise")
	check(Money.total(c.state)==supply,"Completed work transfers existing escrow without minting")
	var memory: Dictionary=Contacts.completed_work(c.state,BROKER)
	check(str(memory.get("event",""))=="job:"+str(survey.id)+":paid" and memory.get("port","")=="brass_haven" and float(memory.get("day",-1))==float(c.state.day),"Completed memory records its exact event, actual harbor and campaign date")
	check(not Contacts.record(c.state,BROKER,str(memory.get("event","")),5).applied,"Repeated work event cannot award trust twice")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Actual save/restore retains the earned memory")
	earned=c.state.duplicate(true)
	test_success_and_repeat()
	test_refusals()
	test_failure_and_legacy()
	finish()

func finish() -> void:
	print("contact opportunity056: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

func test_success_and_repeat() -> void:
	reset(earned)
	var before: Dictionary=assets()
	var offer: Dictionary=Jobs.contact_opportunity(c,BROKER)
	check(not offer.is_empty() and offer.kind==Jobs.KIND_FREIGHT,"Broker selects one compatible existing freight job")
	if offer.is_empty():return
	var selected: int=0
	for job in Jobs.available(c):
		if not str(job.get("sponsorContactId","")).is_empty():selected+=1
	check(selected==1 and Jobs.contact_opportunity(c,BROKER)==offer,"Repeated review selects exactly one stable board offer")
	check(assets()==before,"Review moves no money, cargo, people, trust or commitments")
	var copy: Dictionary=Jobs.contact_opportunity(c,BROKER)
	copy.freight.qty=9999;copy.sponsorEventId="changed"
	check(Jobs.contact_opportunity(c,BROKER)==offer,"Opportunity payload is detached from state and later queries")
	var shown: String=VoyageUI.sponsor_reason(c,offer)
	check(shown.contains("Tobin Hale") and shown.contains("Brass Haven") and shown.contains("day1.0"),"Presentation names the sponsor and honest qualifying date/location")
	var origin: Dictionary=c.current_port()
	var treasury: int=int(origin.governmentPurse)
	var stock: float=float(origin.stocks[str(offer.freight.good)])
	var total: int=Money.total(c.state)
	check(c.accept_voyage_job(str(offer.id)).ok,"Earned work accepts through ordinary funded job and manifest APIs")
	check(int(origin.governmentPurse)==treasury-int(offer.reward)-int(offer.materialInvoice) and float(origin.stocks[str(offer.freight.good)])==stock-float(offer.freight.qty),"Real treasury pays invoice and escrow; the actual lot leaves stock")
	check(Money.total(c.state)==total,"Recommendation acceptance conserves all coins")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Active sponsored job passes real save/restore")
	var active: Dictionary=Jobs._find(c.state,str(offer.id))
	for key in ["sponsorContactId","sponsorEventId","sponsorEventDay","sponsorEventPort"]:
		check(active.get(key)==offer.get(key),"Sponsor metadata survives sanitizer and restore: "+key)
	check(Contacts._find(c.state,BROKER).workOpportunityUsed and Jobs.contact_opportunity(c,BROKER).is_empty(),"Saved consumption prevents another recommendation")
	check(not c.accept_voyage_job(str(offer.id)).ok,"Repeat acceptance cannot duplicate escrow or freight")
	var trust: int=int(Contacts._find(c.state,BROKER).trust)
	dock(str(offer.targetPort))
	check(c.settle_voyage_job(str(offer.id)).ok,"Physical delivery at its real destination releases escrow")
	check(int(Contacts._find(c.state,BROKER).trust)==trust+5,"Original named sponsor remembers success away from their harbor")
	check(Contacts.completed_work(c.state,BROKER).get("port","")==str(offer.targetPort),"Sponsor memory records where delivery actually completed")
	var after: Dictionary=assets()
	check(not c.settle_voyage_job(str(offer.id)).ok and assets()==after,"Repeat completion creates neither reward nor trust")
	dock("brass_haven")
	check(Jobs.contact_opportunity(c,BROKER).is_empty() and Money.total(c.state)==total,"Completed referral does not reroll or create money")

func test_refusals() -> void:
	for refusal in ["purse","stock","hold","crew","access","roster"]:
		reset(earned)
		var offer: Dictionary=Jobs.contact_opportunity(c,BROKER)
		if offer.is_empty():check(false,"Refusal baseline has an opportunity: "+refusal);continue
		var p: Dictionary=c.current_port()
		if refusal=="purse":Money.move(p,"governmentPurse",p,"cash",int(p.governmentPurse),"Fixture reserves treasury funds elsewhere",c.state.moneyLog)
		elif refusal=="stock":
			for good in p.stocks:p.stocks[good]=0.0
		elif refusal=="hold":c.state.cargo.food=c.capacity()+1.0
		elif refusal=="crew":
			for boat in c.state.fleet:boat.crew=0
		elif refusal=="access":
			for i in range(3):c.Factions.adjust(c.state,str(p.faction),-25,"witness:056 documented hostility %d"%i)
		elif refusal=="roster":
			for i in range(6):
				var occupied: Dictionary=Jobs._sanitize_job(offer)
				occupied.id="occupied-%d"%i;occupied.state="active";occupied.freight={};occupied.escrow=0
				c.state.voyageJobs.append(occupied)
		check(Jobs.contact_opportunity(c,BROKER).is_empty(),"Incompatible opportunity disappears after current "+refusal+" changes")
		var before: Dictionary=assets()
		check(not c.accept_voyage_job(str(offer.id)).ok,"Acceptance rechecks current "+refusal)
		check(assets()==before and not Contacts._find(c.state,BROKER).workOpportunityUsed,"Refusal preserves resources and the earned introduction: "+refusal)

func test_failure_and_legacy() -> void:
	reset(earned)
	var offer: Dictionary=Jobs.contact_opportunity(c,BROKER)
	if offer.is_empty():check(false,"Failure case has funded work");return
	check(c.accept_voyage_job(str(offer.id)).ok,"Failure case accepts actual funded work")
	var trust: int=int(Contacts._find(c.state,BROKER).trust)
	dock(str(offer.targetPort))
	check(c.settle_voyage_job(str(offer.id),true).ok,"Abandonment safely unloads freight at a different harbor")
	check(int(Contacts._find(c.state,BROKER).trust)==trust-5,"Named sponsor remembers failure even away from home")
	check(Contacts.completed_work(c.state,BROKER).get("event","")!="job:"+str(offer.id)+":paid","Abandonment cannot become a positive completed-work memory")
	reset(baseline)
	var legacy: Dictionary=Jobs._sanitize_job({"id":"legacy","port":"brass_haven"})
	check(str(legacy.sponsorContactId).is_empty(),"Unsponsored legacy jobs retain empty sponsor metadata")
	Contacts.record(c.state,BROKER,"job:old:paid",5,"Legacy completed work")
	var memory: Dictionary=Contacts.completed_work(c.state,BROKER)
	check(not memory.has("port"),"Legacy memory does not fabricate a completion location")
	var old_offer: Dictionary=Jobs.contact_opportunity(c,BROKER)
	check(not old_offer.is_empty() and VoyageUI.sponsor_reason(c,old_offer).contains("location not recorded"),"Legacy qualifying work displays its missing location honestly")
	reset(baseline)
	dock("reed_floats")
	Contacts.record(c.state,"contact_sister_wren","job:prior-survey:paid",5,"Prior completed survey","reed_floats")
	var survey: Dictionary=Jobs.contact_opportunity(c,"contact_sister_wren")
	check(not survey.is_empty() and survey.kind==Jobs.KIND_SURVEY,"Survey patron selects an existing survey rather than unrelated freight")
