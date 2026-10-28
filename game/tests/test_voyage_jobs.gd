extends SceneTree
const Campaign = preload("res://scripts/campaign.gd")
const Jobs = preload("res://scripts/voyage_jobs.gd")
const Contacts = preload("res://scripts/contacts.gd")
const Exploration = preload("res://scripts/exploration.gd")
const Money = preload("res://scripts/money.gd")
var failures: Array = []
var checks: int = 0
var world: Dictionary
var c

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL " + message)

func reset() -> void:
	c.new_game(123)

# Root integration assumption under test locally: Money.total plus every
# side-job escrow must equal the campaign coin supply at all times.
func total_with_jobs() -> int:
	return Money.total(c.state) # Root integrates escrow into the canonical ledger once.

func offer_of_kind(offers: Array, kind: String) -> Dictionary:
	for offer in offers:
		if str(offer.get("kind", "")) == kind:
			return offer
	return {}

func goto_port(id: String) -> void:
	c.state.position = c.port_position(id)
	c.state.lastPort = id

func _initialize() -> void:
	world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	c = Campaign.new(world)
	_test_multiple_jobs_and_escrow()
	_test_capacity_and_freight()
	_test_survey_gating_and_delivery()
	_test_story_survey_pairing()
	_test_expiry_and_abandon()
	_test_contacts()
	_test_save_roundtrip()
	print("voyage_jobs: %d checks, %d failures" % [checks, failures.size()])
	if failures.is_empty():
		quit(0)
	else:
		quit(1)

func _test_multiple_jobs_and_escrow() -> void:
	reset()
	var first: Array = Jobs.available(c)
	var second: Array = Jobs.available(c)
	check(first == second, "Same-day offers are deterministic, never rerolled")
	var freight := offer_of_kind(first, "freight")
	var survey := offer_of_kind(first, "survey")
	check(not freight.is_empty(), "A funded freight job is offered at the start harbor")
	check(not survey.is_empty(), "A funded survey job is offered at the start harbor")
	if freight.is_empty() or survey.is_empty():
		return
	var supply: int = Money.total(c.state)
	var sponsor: Dictionary = c.port(freight.port)
	var cash_before: int = int(sponsor.cash)
	var stock_before: float = float(sponsor.stocks[freight.freight.good])
	check(bool(Jobs.accept(c, freight.id).ok), "Freight job accepts")
	check(bool(Jobs.accept(c, survey.id).ok), "Survey job accepts alongside it")
	check(c.state.voyageJobs.size() == 2, "Two compatible side jobs run at once")
	check(c.state.activeContract.is_empty() and c.state.freight.is_empty(), "Story contract slot and legacy freight stay untouched")
	check(int(sponsor.cash)==cash_before+int(freight.materialInvoice),"Treasury pays the supplier for physical relief freight; shipping fees stay in escrow")
	check(is_equal_approx(float(sponsor.stocks[freight.freight.good]), stock_before - float(freight.freight.qty)), "Sealed lot leaves source stocks on acceptance")
	check(total_with_jobs() == supply, "Coins conserve when escrows are counted (root Money.total hook)")
	check(not bool(Jobs.accept(c, freight.id).ok), "The same job cannot be accepted twice")
	check(offer_of_kind(Jobs.available(c), "freight").is_empty(), "Accepted freight job leaves the board")
	check(Jobs.pending_freight_weight(c.state) > 0.0, "Pending side freight weighs against the hold")

func _test_capacity_and_freight() -> void:
	reset()
	var freight := offer_of_kind(Jobs.available(c), "freight")
	check(not freight.is_empty(), "Freight offer exists for the capacity test")
	if freight.is_empty():
		return
	c.state.cargo.food = c.capacity()
	var sponsor: Dictionary = c.port(freight.port)
	var stock_before: float = float(sponsor.stocks[freight.freight.good])
	var cash_before: int = int(sponsor.cash)
	check(not bool(Jobs.accept(c, freight.id).ok), "Freight refuses when the combined hold is full")
	check(c.state.voyageJobs.is_empty(), "Refused acceptance creates no job")
	check(is_equal_approx(float(sponsor.stocks[freight.freight.good]), stock_before), "Refused acceptance takes no stock")
	check(int(sponsor.cash) == cash_before, "Refused acceptance moves no escrow")
	# Reserving one job's freight blocks gaming a second oversized commitment:
	# pending weight is counted before any root cargo integration.
	c.state.cargo.food = 0.0
	check(bool(Jobs.accept(c, freight.id).ok), "Freight accepts once the hold has room")
	var used: float=c.cargo_weight()
	check(used <= c.capacity(), "Cargo plus reserved side freight stays within capacity")

func _test_survey_gating_and_delivery() -> void:
	reset()
	# Give the starter boat a full bench so real survey parties can land.
	c.state.fleet[0].crew = 8.0
	c.state.cargo.supplies = 10.0
	c.state.cargo.food = 30.0
	var freight := offer_of_kind(Jobs.available(c), "freight")
	var survey := offer_of_kind(Jobs.available(c), "survey")
	check(bool(Jobs.accept(c, survey.id).ok), "Survey job accepts")
	check(bool(Jobs.accept(c, freight.id).ok), "Freight job accepts beside the survey")
	var site_id: String = str(survey.siteId)
	var sighted := {}
	for site in Exploration.sites(c.state):
		if str(site.id) == site_id:
			sighted = site
	check(int(sighted.get("level", 0)) >= 1, "Accepting a survey legitimately reveals the rumored site")
	check(not bool(Jobs.finish(c, survey.id).ok), "Survey cannot finish before a real level-3 survey")
	check(bool(Exploration.begin(c.state, site_id, "chart").ok), "Chart party lands")
	Exploration.advance(c.state, 1.0)
	check(not bool(Jobs.finish(c, survey.id).ok), "Charted alone still cannot finish the survey job")
	check(bool(Exploration.begin(c.state, site_id, "survey").ok), "Survey party lands")
	Exploration.advance(c.state, 2.5)
	var coins_before: int = int(c.state.coins)
	var paid: Dictionary = Jobs.finish(c, survey.id)
	check(bool(paid.ok) and int(paid.reward) == int(survey.reward), "Survey pays its escrow after level 3")
	check(int(c.state.coins) == coins_before + int(survey.reward), "Survey payment reaches the captain once")
	check(not bool(Jobs.finish(c, survey.id).ok), "Survey job cannot be paid twice")
	check(str(survey.id) in c.state.doneVoyageJobs, "Finished survey id is recorded as done")
	# Freight delivery lands the sealed lot in destination stocks.
	var target: Dictionary = c.port(freight.targetPort)
	var target_stock: float = float(target.stocks[freight.freight.good])
	goto_port(freight.targetPort)
	coins_before = int(c.state.coins)
	check(bool(Jobs.finish(c, freight.id).ok), "Freight finishes at its destination")
	check(is_equal_approx(float(target.stocks[freight.freight.good]), target_stock + float(freight.freight.qty)), "Delivered lot enters destination stocks")
	check(int(c.state.coins) == coins_before + int(freight.reward), "Freight payment reaches the captain once")
	check(Jobs.pending_freight_weight(c.state) == 0.0, "No sealed freight remains after delivery")

func _test_expiry_and_abandon() -> void:
	reset()
	var freight := offer_of_kind(Jobs.available(c), "freight")
	check(bool(Jobs.accept(c, freight.id).ok), "Freight job accepts for the expiry test")
	var job: Dictionary = c.state.voyageJobs[0]
	var sponsor: Dictionary = c.port(freight.port)
	var cash_after_accept: int=int(sponsor.governmentPurse)
	# At sea with sealed freight: abandoning must refuse, never jettison.
	c.state.position = {"x": 5200.0, "y": 3600.0}
	check(not bool(Jobs.abandon(c, freight.id).ok), "Sealed freight cannot be abandoned at sea")
	check(c.state.voyageJobs.size() == 1, "Refused abandon keeps the job and its freight")
	# Past the deadline: escrow refunds, freight survives for harbor unloading.
	c.state.day = float(job.deadlineDay) + 1.0
	check(not bool(Jobs.finish(c, freight.id).ok), "Expired freight cannot be finished for pay")
	check(int(sponsor.governmentPurse)==cash_after_accept+int(freight.reward),"Expiry refunds unused shipping escrow to its real treasury sponsor")
	var expired: Dictionary = c.state.voyageJobs[0]
	check(str(expired.state) == "expired" and not (expired.freight as Dictionary).is_empty(), "Expired job keeps its sealed freight, undeleted")
	goto_port(freight.targetPort)
	var dock: Dictionary = c.port(freight.targetPort)
	var dock_stock: float = float(dock.stocks[freight.freight.good])
	check(bool(Jobs.abandon(c, freight.id).ok), "Expired freight unloads by abandoning at a harbor")
	check(is_equal_approx(float(dock.stocks[freight.freight.good]), dock_stock + float(freight.freight.qty)), "Unloaded freight enters that harbor's stocks")
	check(c.state.voyageJobs.is_empty() and str(freight.id) in c.state.doneVoyageJobs, "Abandoned job closes and is remembered")

func _test_story_survey_pairing() -> void:
	# Isolated gate fixtures; expedition057 alone owns actual travel/work proof.
	reset()
	goto_port("reed_floats")
	check(Jobs.survey_pairing(c).is_empty(),"Unaccepted stories do not steer paid survey work")
	check(bool(c.StoryOps.start(c,"middle_sea_chart").ok),"Wren accepts the actual lead")
	var stories: Dictionary=c.state.stories.duplicate(true)
	var pairing: Dictionary=Jobs.survey_pairing(c)
	check(str(pairing.get("siteId",""))=="middle_chart_rock" and int(pairing.get("storyLevel",0))==2 and int(pairing.get("paidLevel",0))==3,"Current level2 clue retains full level3 paid work")
	pairing.siteId="detached-only"
	var survey: Dictionary=offer_of_kind(Jobs.available(c),"survey")
	check(str(survey.get("siteId",""))=="middle_chart_rock","Funded current objective replaces the generic catalog pick")
	check(c.state.stories==stories,"Pairing/board queries do not advance the story")
	check(str(survey.get("id",""))=="vsurvey-reed_floats-1-middle_chart_rock","Pairing keeps ordinary survey IDs")
	check(preload("res://scripts/voyage_ui.gd").survey_terms(c,survey).contains("level 2"),"Paid text explains the level2 clue/full3 distinction")
	Contacts.record(c.state,"contact_sister_wren","job:pairing-fixture:paid",5)
	survey=offer_of_kind(Jobs.available(c),"survey")
	check(str(survey.get("sponsorContactId",""))=="contact_sister_wren","056 patron memory recommends the same ordinary offer")
	var baseline: Dictionary=c.state.duplicate(true)
	var sponsor: Dictionary=c.port("reed_floats")
	var supply: int=Money.total(c.state)
	Money.move(sponsor,"governmentPurse",sponsor,"cash",int(sponsor.governmentPurse))
	check(offer_of_kind(Jobs.available(c),"survey").is_empty(),"Unfunded patron cannot promise a paired survey")
	check(not c.accept_voyage_job(str(survey.id)).ok and Money.total(c.state)==supply,"Unfunded refusal creates no capital")
	c.state=baseline.duplicate(true)
	for i in range(Jobs.MAX_ACTIVE):
		c.state.voyageJobs.append({"id":"slot-fixture-%d"%i,"kind":"bounty","port":"reed_floats","targetPort":"reed_floats","reward":1,"escrow":0,"deadlineDay":100.0,"state":"active"})
	check(not c.accept_voyage_job(str(survey.id)).ok and c.state.voyageJobs.size()==Jobs.MAX_ACTIVE,"Pairing cannot bypass six carried commitments")
	c.state=baseline.duplicate(true)
	check(bool(c.accept_voyage_job(str(survey.id)).ok),"Paired survey uses existing funded acceptance")
	check(Jobs.survey_pairing(c).is_empty(),"Carried work is not a second paired fee")
	check(not c.accept_voyage_job(str(survey.id)).ok,"Paired survey still cannot be accepted twice")
	c.state.day=2.0
	for offer in Jobs.available(c):
		check(str(offer.get("siteId",""))!="middle_chart_rock","Next day cannot duplicate a carried paid survey")
	c.state=baseline.duplicate(true)
	c.state.exploration.sites["middle_chart_rock"]={"level":3,"rewarded":true}
	for offer in Jobs.available(c):
		check(str(offer.get("siteId",""))!="middle_chart_rock","Already surveyed work earns no new offer")
	check(bool(c.StoryOps.choose(c,"middle_sea_chart","keep_secret").ok),"Isolated earned choice advances its authored gate")
	check(str(Jobs.survey_pairing(c).get("siteId",""))=="shatter_wreck_field","Next accepted current objective becomes preferred at Wren")
	check(Jobs.survey_pairing(c,"brass_haven").is_empty(),"Other harbors retain their daily catalog choice")

func _test_contacts() -> void:
	reset()
	var contacts: Array = Contacts.list_contacts(c.state)
	check(contacts.size() == 4, "Four authored harbor contacts exist")
	var roles := {}
	for contact in contacts:
		roles[str(contact.role)] = contact
		check(int(contact.trust) == 0 and not bool(contact.met), "Contacts start unmet and neutral " + str(contact.id))
	for role in ["shipwright", "broker", "survey_patron", "salvage_agent"]:
		check(roles.has(role), "Contact role present: " + role)
	check(c.state.marketSnapshots.is_empty(), "No market snapshot exists before any visit")
	var home: Dictionary = c.port(world.START.port)
	var visited: Dictionary = Contacts.visit(c.state, home, c.state.day)
	check(bool(visited.ok) and c.state.marketSnapshots.has(home.id), "Visiting records that harbor's dated snapshot")
	check(is_equal_approx(float(c.state.marketSnapshots[home.id].day), float(c.state.day)), "Snapshot is stamped with the visit day")
	check(not (visited.contact as Dictionary).is_empty() and bool(visited.contact.met), "Visiting Brass Haven meets its broker")
	var broker_id: String = str(roles["broker"].id)
	check(bool(Contacts.record(c.state, broker_id, "job:vfreight-test", 7).applied), "First trust event applies")
	var repeat: Dictionary = Contacts.record(c.state, broker_id, "job:vfreight-test", 7)
	check(not bool(repeat.applied) and int(repeat.trust) == 7, "The same event id never applies twice")
	for i in range(10):
		Contacts.record(c.state, broker_id, "favor-%d" % i, 50)
	var broker := {}
	for contact in Contacts.list_contacts(c.state):
		if str(contact.id) == broker_id:
			broker = contact
	check(int(broker.trust) == 100, "Trust clamps at 100 however many favors land")
	check(int((roles["shipwright"] as Dictionary).trust) == 0, "Broker trust never leaks into other contacts")
	check(not Contacts.record(c.state, "nobody", "x", 1).ok, "Unknown contact events are refused")

func _test_save_roundtrip() -> void:
	reset()
	var freight := offer_of_kind(Jobs.available(c), "freight")
	Jobs.accept(c, freight.id)
	Contacts.visit(c.state, c.port(world.START.port), c.state.day)
	Contacts.record(c.state, str(Contacts.list_contacts(c.state)[0].id), "intro", 3)
	var text: String = JSON.stringify(c.state)
	var restored = JSON.parse_string(text)
	check(restored is Dictionary, "State with jobs and contacts survives JSON roundtrip")
	if restored is Dictionary:
		var c2 = Campaign.new(world)
		c2.state = restored
		Jobs.ensure(c2)
		Contacts.ensure(c2.state, world)
		check(c2.state.voyageJobs.size() == 1, "Active side job survives the roundtrip")
		check(int(c2.state.voyageJobs[0].escrow) == int(freight.reward), "Escrow amount survives the roundtrip")
		check(not (c2.state.voyageJobs[0].freight as Dictionary).is_empty(), "Sealed freight record survives the roundtrip")
		check(Contacts.list_contacts(c2.state).size() == 4, "Contacts survive the roundtrip")
		check(c2.state.marketSnapshots.has(world.START.port), "Market snapshot survives the roundtrip")
	# Legacy state gains both systems without touching its own fields.
	var legacy := {"coins": 42, "day": 2.0, "ports": []}
	Contacts.ensure(legacy, world)
	check(legacy.contacts.size() == 4 and int(legacy.coins) == 42, "Contacts ensure() migrates legacy saves in place")
