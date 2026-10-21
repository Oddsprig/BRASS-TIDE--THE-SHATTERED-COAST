extends RefCounted
const Stories=preload("res://scripts/coastal_stories.gd")
static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	c.StoryOps.ensure(c)
	var p: Dictionary=c.current_port()
	if not p.is_empty() and c.Politics.access(c,p).legal:c.Contacts.visit(c.state,p,c.state.day)
	ui.modal_kind="coastal_stories"
	var body=ui.modal("Coastal stories & expedition leads","FOUR ORIGINAL CHAINS · DECISIONS THAT OPEN DIFFERENT WORK",1070,820)
	ui.paragraph(body,"Keep several leads alongside your paid voyage jobs. Surveys, deliveries and actual fleet defeats advance them. Knowledge and relationships are the rewards; any later freight or business still needs a real sponsor, materials and workers.",16)
	for row in Stories.journal(c.state):
		var entry: Dictionary=row
		ui.rule(body)
		ui.label(body,entry.title+" · "+("Complete" if entry.done else entry.approach.capitalize()),26,ui.GOLD,true)
		var stage: Dictionary=Stories._stage_def(Stories._chain_def(c.state,entry.chainId),entry.stage)
		ui.paragraph(body,str(stage.get("body","")),17,ui.TEXT)
		ui.paragraph(body,entry.nextAction,16,ui.TEAL)
		if entry.done:continue
		var location: Dictionary=entry.location
		ui.button(body,"Chart "+location.name,func():ui.host.respond(c.chart_course({"x":location.x,"y":location.y},location.id if location.kind=="port" else ""));ui.close_modal())
		var gate: Dictionary=Stories._gate(c,c.state,stage.get("gate",{}))
		if not gate.ok:ui.paragraph(body,gate.message,14,ui.RED)
		for option in entry.choices:
			var choice: Dictionary=option
			ui.paragraph(body,choice.tradeoff,15)
			ui.button(body,choice.text,func():ui.host.respond(c.StoryOps.choose(c,entry.chainId,choice.id));ui.host.save_game(false);open(ui),true).disabled=not gate.ok or (not str(choice.get("requiresFlag","")).is_empty() and not entry.flags.has(choice.requiresFlag))
	ui.rule(body)
	ui.label(body,"Harbor leads",26,ui.GOLD,true)
	var offers: Array=Stories.available(c)
	for item in offers:
		var offer: Dictionary=item
		ui.label(body,offer.title,23,ui.GOLD,true)
		ui.paragraph(body,offer.summary,16)
		ui.button(body,"Hear this contact's lead",func():ui.host.respond(c.StoryOps.start(c,offer.id));ui.host.save_game(false);open(ui))
	if offers.is_empty():ui.paragraph(body,"Visit Tobin at Brass Haven, Wren at Reedwater Floats, Cass at Rust Anchorage, or Mara at Anvil Dock. Their leads stay in this journal once accepted.",16)
	ui.button(body,"Funded voyage jobs & contacts",func():ui.VoyageUI.open(ui))
