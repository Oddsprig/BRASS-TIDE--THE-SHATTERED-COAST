extends RefCounted
const Politics=preload("res://scripts/politics.gd")
const Factions=preload("res://scripts/factions.gd")
static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	Politics.ensure(c)
	ui.modal_kind="factions"
	var body=ui.modal("Factions & safe passage","REPUTATION HAS PRACTICAL CONSEQUENCES",1050,820)
	ui.paragraph(body,"Work earns public standing. Witnessed attacks and harbor claims are recorded separately. A commission is optional and changes legal relations with its patron's enemies. Personal contact trust remains in Contacts.",16)
	var p: Dictionary=c.current_port()
	if not p.is_empty():
		var a: Dictionary=Politics.access(c,p)
		ui.label(body,p.name+" · "+a.entry,24,ui.GOLD,true)
		ui.paragraph(body,a.reason,15)
		if a.hostile or a.claim>0 or a.witnessed<0:
			ui.paragraph(body,"Parley: %d coins. Three days of inspected civilian access; +10 restitution. Complete funded work to earn lasting entry. No military access is purchased."%(1000+int(a.claim)*100),15)
			ui.button(body,"Pay for safe conduct / settle claims",func():ui.host.respond(Politics.parley(c));ui.host.save_game(false);open(ui),true)
	for f in c.data.FACTIONS:
		var id: String=f.id
		var s: Dictionary=Factions.standing(c.state,id)
		ui.rule(body)
		ui.label(body,"%s · %s (%+d)"%[f.name,s.label,s.score],23,ui.GOLD,true)
		ui.paragraph(body,"Witnessed offenses: %+d · Claims: %d · %s"%[s.witnessed,s.claimTotal,"hostile patrols" if s.hostile else "peaceful passage"],15)
		var relations: PackedStringArray=[]
		for other in c.data.FACTIONS:
			if other.id!=id:relations.append("%s %+d"%[other.name,Factions.relation(c.state,id,other.id)])
		ui.paragraph(body,"Faction relations: "+" · ".join(relations),13)
		ui.button(body,"Review commission terms",func():terms(ui,id))
	for entry in c.state.relationships.log.slice(-8):ui.paragraph(body,"Day%d · %s · %s"%[entry.day,entry.factionId,entry.reason],13)

static func terms(ui,id: String) -> void:
	var c=ui.host.core
	var r: Dictionary=Factions.commission(c.state,id)
	var body=ui.modal("Letters of marque","REVIEW BEFORE ACCEPTING",850,600)
	ui.paragraph(body,str(r.get("warning",r.message)),18)
	if not r.get("committed",false):ui.button(body,"Accept this commission",func():ui.host.respond(Factions.commission(c.state,id));ui.host.save_game(false);open(ui),true)
	ui.button(body,"Remain independent / back",func():c.state.relationships.commission.pending=false;open(ui))
