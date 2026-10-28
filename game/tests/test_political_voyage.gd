extends SceneTree
const M=preload("res://scripts/money.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;print("FAIL political voyage: ",message)
func _initialize():
	# Reuse Main's Campaign for the whole fixture, including the existing UI
	# checks, rather than building a second world/navigation/owner baseline.
	var scene=load("res://main.tscn").instantiate();root.add_child(scene);await process_frame
	scene.save_directory=OS.get_user_data_dir().path_join("political-voyage-fixture")
	var c=scene.core;c.new_game(121)
	var initial_ui_state: Dictionary=c.state.duplicate(true)
	check(c.Factions.relation(c.state,"reed","raiders")==-25 and c.Factions.relation(c.state,"raiders","reed")==-25,"Canonical pair ordering preserves Reed-raider hostility in both directions")
	var supply: int=M.total(c.state)
	check(c.Politics.access(c,c.current_port()).legal,"Neutral civilian harbor access")
	var roles: Dictionary={"trader":"merchant convoy","patrol":"faction patrol","raider":"raiding fleet"}
	for kind in roles:
		var owners: Array=c.state.fleetOwners.filter(func(o):return o.kind==kind)
		check(not owners.is_empty(),"Seeded campaign contains actual %s fleet"%kind)
		if owners.is_empty():continue
		var contact: Dictionary=c.Politics.encounter(c.state,owners[0])
		check(contact.kind==kind and contact.role==roles[kind] and contact.factionId==owners[0].faction and contact.factionName==c.Factions.standing(c.state,owners[0].faction).name,"Actual %s kind and named faction explain contact"%kind)
		check(contact.hostile==c.Politics.hostile(c,owners[0]) and (contact.hostile if kind=="raider" else not contact.hostile),"Public hostility matches actual %s encounter policy"%kind)
		check(not contact.has("purpose") and not contact.has("x") and not contact.has("targetOwnerId") and not contact.has("cargo"),"Identity projection reveals no live %s orders or cargo"%kind)
		if kind=="raider":check(str(contact.reason).contains("hostile public standing"),"Initial raider hostility explains its public-standing cause")
	var identity_before: String=JSON.stringify(c.state)
	var detached: Dictionary=c.Politics.encounter(c.state,c.state.fleetOwners[0])
	detached.reason="Fixture changed explanation";detached.kind="Fixture changed kind"
	check(JSON.stringify(c.state)==identity_before,"Encounter explanation is detached and read-only")
	var before: String=JSON.stringify(c.state)
	check(not c.trade(c.current_port().id,"engines",1,"buy").ok and JSON.stringify(c.state)==before,"Restricted purchase fails atomically through actual campaign")
	check(c.Politics.permit(c,"service").ok and not c.Politics.permit(c,"military").ok,"Basic paid fittings available; advanced military gated")
	c.Factions.adjust(c.state,"compact",20,"Fixture fulfilled contracts")
	check(c.Politics.permit(c,"military").ok,"Friendly standing unlocks military equipment")
	var first: Dictionary=c.Factions.commission(c.state,"compact")
	check(not first.committed and M.total(c.state)==supply,"Commission first presents terms without a stipend")
	check(c.Factions.commission(c.state,"compact").committed and M.total(c.state)==supply,"Explicit acceptance applies political costs without coins")
	var enemy: Dictionary={"id":"peaceful-fixture","faction":"compact","homePort":"brass_haven","kind":"patrol"}
	c.Politics.declare_attack(c,enemy)
	c.Politics.settled(c,enemy,"won",{"aggression":true})
	check(c.Factions.is_hostile(c.state,"compact") and not c.Politics.permit(c,"service").ok,"Confirmed attack creates witnessed hostility independent of friendly public score")
	var hostile_patrol: Dictionary=c.Politics.encounter(c.state,enemy)
	check(hostile_patrol.hostile and hostile_patrol.role=="faction patrol" and str(hostile_patrol.reason).contains("unresolved witnessed offense"),"Hostile faction patrol remains a patrol and explains witnessed hostility")
	var hostile_trader: Dictionary=enemy.duplicate(true);hostile_trader.kind="trader"
	check(c.Politics.encounter(c.state,hostile_trader).role=="merchant convoy" and c.Politics.encounter(c.state,hostile_trader).hostile,"A hostile trader is still a merchant convoy")
	c.Factions.adjust(c.state,"compact",-25,"witness:Additional documented losses")
	c.Factions.adjust(c.state,"compact",-25,"witness:Additional documented losses")
	var p: Dictionary=c.current_port()
	var refused: Dictionary=c.Politics.access(c,p)
	check(not refused.legal and refused.entry=="refused" and not refused.safeConductActive and refused.safeConductDays==0.0,"Hostile harbor without paid conduct refuses entry")
	var fee: int=1000+int(c.Politics.access(c,p).claim)*100
	var purse: int=c.state.coins
	check(c.Politics.parley(c).ok and purse-c.state.coins==fee and M.total(c.state)==supply,"Parley pays exact workers, experts and government; global coins conserved")
	var admitted: Dictionary=c.Politics.access(c,p)
	check(admitted.legal and admitted.entry=="inspected" and admitted.inspection and admitted.contracts and admitted.safeConductActive,"Paid conduct enables actual inspected civilian entry and work")
	check(admitted.safeConductUntil==float(c.state.day)+3.0 and admitted.safeConductDays==3.0 and str(admitted.reason).contains("until day %.2f"%float(admitted.safeConductUntil)),"Effective access names absolute expiry and remaining days")
	check(not str(admitted.reason).contains("refuses entry") and str(admitted.reason).contains("Customs still apply") and str(admitted.reason).contains("remain restricted"),"Paid access explanation replaces refusal and retains customs/military limits")
	check(admitted.hostile and c.Politics.encounter(c.state,enemy).hostile and str(admitted.reason).contains("fleets remain hostile"),"A harbor pass does not remove witnessed hostility or at-sea risk")
	check(c.Politics.permit(c,"service").ok and not c.Politics.permit(c,"military").ok,"Paid temporary civilian access does not buy military trust")
	check(not c.Politics.permit(c,"buy_good","engines").ok,"Paid civilian conduct does not unlock restricted bulk engines")
	check(not c.Politics.parley(c).ok,"Pass cannot stack")
	var other_harbors: Array=c.state.ports.filter(func(q):return q.faction==p.faction and q.id!=p.id)
	check(not other_harbors.is_empty(),"Seeded faction has another harbor for the local-pass check")
	if not other_harbors.is_empty():check(not c.Politics.access(c,other_harbors[0]).safeConductActive and not c.Politics.access(c,other_harbors[0]).legal,"Conduct applies only at its paid harbor, not every harbor of the faction")
	var paid_state: Dictionary=c.state
	c.state=paid_state.duplicate(true)
	c.Factions.adjust(c.state,"compact",-3,"claim:brass_haven:Fixture subsequent harbor damage")
	var claimed: Dictionary=c.Politics.access(c,c.current_port())
	check(claimed.legal and claimed.claim==3 and str(claimed.reason).contains("claim of 3") and not c.Politics.permit(c,"repair").ok and c.Politics.permit(c,"contract").ok,"A new claim under valid conduct blocks repairs while civilian work remains legal")
	# Separately earned trust must keep its actual military permission even
	# while the local pass exists; the pass itself grants none of that trust.
	var recovered: Dictionary=c.state.relationships.factions.compact
	recovered.score=20;recovered.band="friendly";recovered.witnessed=0;recovered.claims={}
	var earned: Dictionary=c.Politics.access(c,c.current_port())
	check(earned.safeConductActive and earned.militaryFittings and c.Politics.permit(c,"military").ok and not str(earned.reason).contains("remain restricted"),"Paid-access explanation respects separately earned military permission")
	c.state=paid_state
	check(c.Politics.inspect(c).ok,"Actual inspected cargo admitted without invented fine")
	check(c.restore(JSON.parse_string(JSON.stringify(c.state))).ok,"Relationships and permit restore through real campaign schema")
	check(c.Politics.access(c,c.current_port()).safeConductUntil==admitted.safeConductUntil and c.Politics.access(c,c.current_port()).legal,"Actual campaign restore retains effective paid access and exact expiry")
	c.state.day=float(admitted.safeConductUntil)-0.01
	check(c.Politics.access(c,c.current_port()).safeConductActive,"Conduct remains valid immediately before expiry")
	c.state.day=float(admitted.safeConductUntil)
	var expired: Dictionary=c.Politics.access(c,c.current_port())
	check(not expired.safeConductActive and expired.safeConductDays==0.0 and not expired.legal and str(expired.reason).contains("expired on day %.2f"%float(admitted.safeConductUntil)),"Conduct expires exactly at its stored campaign day with an honest explanation")
	c.state.day+=0.1
	check(not c.Politics.permit(c,"service").ok,"Permit expires on the campaign clock")
	c.state=initial_ui_state
	scene.ui.FactionUI.open(scene.ui)
	check(scene.ui.modal_kind=="factions","Actual faction menu renders")
	scene.ui.FactionUI.terms(scene.ui,"compact")
	check(scene.ui.modal_open,"Actual commission review renders")
	scene.queue_free();await process_frame
	print("political voyage: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
