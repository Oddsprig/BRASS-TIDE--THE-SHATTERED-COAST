extends SceneTree
const Money=preload("res://scripts/money.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL customs voyage: "+text)
func _initialize() -> void:
	var scene=load("res://main.tscn").instantiate();root.add_child(scene);await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("customs-voyage-fixture")
	scene.new_game();scene.set_process(false);scene.set_physics_process(false)
	var c=scene.core
	var home: Dictionary=c.current_port()
	var original_hull: Dictionary=c.state.fleet[0]
	Money.move(home,"governmentPurse",c.state,"coins",50000,"Finite customs fixture capital",c.state.moneyLog)
	# Relocate existing military inventory for this deterministic local counter.
	for p in c.state.ports:
		if p.id==home.id:continue
		var n: float=minf(float(p.stocks.guns),maxf(0,12-float(home.stocks.guns)))
		p.stocks.guns-=n;home.stocks.guns+=n
	var supply: int=Money.total(c.state)
	check(not c.trade(home.id,"guns",1,"buy").ok,"Neutral raw military purchase requires standing or a paid consignment")
	var households: int=int(home.householdPurse);var experts: int=int(home.expertPurse);var purse: int=int(c.state.coins)
	var r: Dictionary=c.LawOps.license(c,"guns",1)
	check(r.ok,"Actual local registry accepts a consignment: "+str(r.get("message","")))
	if not r.ok:scene.queue_free();await process_frame;quit(1);return
	home=c.current_port()
	check(int(c.state.coins)==purse-69 and int(home.householdPurse)==households+25 and int(home.expertPurse)==experts+44,"69 registry coins reach the actual clerk and foreman purses")
	var stock: float=float(home.stocks.guns)
	r=c.trade(home.id,"guns",1,"buy")
	check(r.ok and float(c.state.cargo.guns)==1 and float(c.current_port().stocks.guns)==stock-1,"Licensed purchase consumes real stock and actual hold space")
	check(is_same(home,c.current_port()) and is_same(original_hull,c.state.fleet[0]),"Atomic customs and trade publication preserve actual live harbor and hull identities")
	check(int(c.state.tradeLaw.permits[0].qty)==0 and int(c.state.tradeLaw.permits[0].bound)==1,"Licence quantity binds once to the purchased cargo")
	check(not c.trade(home.id,"guns",1,"buy").ok,"Exhausted licence cannot buy a second consignment")
	c.Factions.adjust(c.state,"compact",-20,"Witnessed fixture inspection","customs-wary")
	r=c.Politics.inspect(c)
	check(r.ok and float(c.state.cargo.guns)==1,"Actual wary harbor admits its covered consignment")
	r=c.LawOps.illicit(c,"guns",2,"buy")
	check(r.ok and float(c.state.cargo.guns)==3,"Broker uses the same actual stock without a second secret inventory")
	# Next calendar day permits a new real encounter, without fabricating payroll.
	c.state.day+=1
	Money.move(c.state,"coins",c.current_port(),"cash",int(c.state.coins)-10,"Finite fixture low purse",c.state.moneyLog)
	var stores: float=float(c.current_port().publicStores.guns)
	r=c.Politics.inspect(c)
	check(r.ok and float(c.state.cargo.guns)==1 and float(c.current_port().publicStores.guns)==stores+2,"Inspection transfers only uncovered raw cargo into the named public stores")
	check(int(r.get("paid",0))==10 and int(r.get("debt",0))>0 and int(c.state.coins)==0,"Affordable fine is transferred and its unpaid remainder persists")
	var debt_id: int=int(c.state.tradeLaw.debts[0].id)
	var public_before: float=float(c.current_port().publicStores.guns)
	var repeated: Dictionary=c.Politics.inspect(c)
	check(repeated.ok and c.current_port().publicStores.guns==public_before,"Repeated encounter cannot seize or fine the same cargo twice")
	check(Money.total(c.state)==supply and c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Native campaign save/load preserves customs, provenance, purses and debt")
	c.state.position=c.port_position("kelp_reach")
	check(not c.LawOps.pay(c,debt_id).ok,"Remote debt payment requires meeting the actual custodian harbor")
	c.state.position=c.port_position("brass_haven")
	Money.move(c.current_port(),"governmentPurse",c.state,"coins",10000,"Finite debt and diplomacy fixture",c.state.moneyLog)
	check(c.LawOps.pay(c,debt_id).ok and c.state.tradeLaw.debts.is_empty(),"Named harbor receives the actual debt settlement")
	c.Factions.adjust(c.state,"compact",25,"Paid convoy fixture","customs-friendly-a")
	c.Factions.adjust(c.state,"compact",25,"Paid convoy fixture","customs-friendly-b")
	r=c.LawOps.embargo(c,"raiders","guns")
	check(r.ok,"Friendly harbor can negotiate an existing hostile pair restriction: "+str(r.get("message","")))
	var raider: Dictionary={}
	for owner in c.state.fleetOwners:
		if owner.faction=="raiders":raider=owner;break
	Money.move(c.current_port(),"governmentPurse",raider,"coins",10000,"Finite carrier policy fixture",c.state.moneyLog)
	var raw_stock: float=float(c.current_port().stocks.guns)
	check(c.Fleets._purchase(raider,c.current_port(),"guns",1)==0 and float(c.current_port().stocks.guns)==raw_stock,"Actual NPC purchase path obeys cached military embargo")
	check(c.Fleets.allowed_trade(raider,c.current_port(),"food") and not c.Fleets.allowed_trade(raider,c.current_port(),"guns",c),"Basic food is outside the military restriction on both carrier paths")
	var relation: int=c.Factions.relation(c.state,"compact","raiders")
	c.state.day+=16;c.LawOps.daily(c)
	check(c.Fleets.allowed_trade(c.fleet_owner(str(raider.id)),c.current_port(),"guns") and c.Factions.relation(c.state,"compact","raiders")==relation,"Expiry restores commodity permission without resetting faction hostility")
	var police: Dictionary={};var patrol: Dictionary={}
	for owner in c.state.fleetOwners:
		if owner.kind=="patrol" and owner.active:police=owner;break
	for p in c.state.patrols:
		if p.id==police.get("id",""):patrol=p;break
	check(not patrol.is_empty(),"Real persistent coastal police observer exists")
	if not patrol.is_empty():
		c.state.position=c.port_position(police.homePort);patrol.x=c.state.position.x;patrol.y=c.state.position.y
		c.LawOps.refresh(c)
		check(c.LawOps.eligible(c,patrol,police),"Only an actual nonhostile local patrol qualifies as a customs witness")
		var encounter: Dictionary=c.LawOps.inspect(c,patrol)
		check(encounter.ok and c.state.tradeLaw.seenBy.has("patrol:"+str(patrol.id)),"Nearby police encounter is recorded against its actual owner and home custodian")
	check(Money.total(c.state)==supply and c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Policy expiry, patrol witnesses and finite transactions remain save-valid")
	var bad: Dictionary=JSON.parse_string(JSON.stringify(c.state));bad.tradeLaw.debts.append({"id":bad.tradeLaw.next,"port":"imaginary","amount":10})
	check(not c.restore(bad).ok,"Unknown custody and out-of-sequence customs records are refused")
	scene.ui.LawUI.open(scene.ui)
	check(scene.ui.modal_kind=="customs","Native manifest, registry, broker and agreement controls render")
	scene.queue_free();await process_frame
	print("customs voyage: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
