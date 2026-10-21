extends RefCounted
const Deployment=preload("res://scripts/deployment.gd")
static func threat(c,convoy: Dictionary) -> Dictionary:
	var chart: Dictionary=c.NavalAI._find_patrol(c.state,str(convoy.get("id","")))
	if chart.is_empty() or c.distance(c.state.position,chart)>1800:return {}
	var nearest: Dictionary={};var distance: float=1800
	for p in c.state.patrols:
		var owner: Dictionary=c.fleet_owner(p.id)
		if owner.is_empty() or not owner.active or not p.active or c.Factions.relation(c.state,convoy.faction,owner.faction)>-20:continue
		if not owner.boats.any(func(b):return not b.sunk and b.ammo>0 and b.crew>=b.crewMin):continue
		var d: float=c.distance(p,chart)
		if d<distance:distance=d;nearest=owner
	return nearest

static func start(host,convoy_id: String) -> void:
	host.sync_economy()
	var c=host.core
	var convoy: Dictionary=c.fleet_owner(convoy_id)
	var enemy: Dictionary=threat(c,convoy)
	if convoy.is_empty() or enemy.is_empty() or convoy.kind!="trader" or c.Politics.hostile(c,convoy):host.ui.toast("No nearby peaceful convoy with an observed armed threat.",true);return
	var escorts: Array=c.FleetSupport.combat(c)
	var allies: Array=convoy.boats.filter(func(b):return not b.sunk and b.crew>=b.crewMin)
	if escorts.is_empty() or allies.is_empty() or Deployment.total(allies)>=300:host.ui.toast("A crewed combat boat and room beside the convoy in 300 points are required.",true);return
	var p: Dictionary=c.NavalAI._find_patrol(c.state,convoy_id)
	var event: String="escort:%s:%d"%[convoy_id,int(p.get("voyageSeq",0))]
	if c.state.escortEvents.has(event):host.ui.toast("This passage has already been credited. Let the convoy complete its delivery.",true);return
	host.begin_battle(enemy.boats.filter(func(b):return not b.sunk).map(func(b):return b.spec),{"kind":"escort","ownerId":enemy.id,"allyOwnerId":convoy_id,"escortEvent":event,"name":"Cover %s's escape window"%convoy.name,"mission":{"kind":"escort","allyUids":allies.map(func(b):return b.uid),"duration":45.0}})

static func settled(c,result: String,context: Dictionary) -> void:
	if context.get("kind","")!="escort":return
	var ally: Dictionary=c.fleet_owner(str(context.get("allyOwnerId","")))
	if ally.is_empty():return
	ally.active=ally.boats.any(func(b):return not b.sunk)
	if result!="won" or not ally.active:return
	var event: String=str(context.get("escortEvent",""))
	if c.state.escortEvents.has(event):return
	c.state.escortEvents[event]=true
	while c.state.escortEvents.size()>256:c.state.escortEvents.erase(c.state.escortEvents.keys()[0])
	c.state.campaignFacts.escortsSaved=int(c.state.campaignFacts.get("escortsSaved",0))+1
	c.Factions.adjust(c.state,ally.faction,5,"Protected an actual convoy passage",event)
	c.FleetIdentity.record_service(c,c.active_fleet().map(func(b):return b.uid),"rescue")
	c.log_entry("Convoy protected; its actual cargo and surviving boats continue their paid delivery. No bounty or enemy purse was promised.")
