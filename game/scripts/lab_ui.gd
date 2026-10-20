extends RefCounted
const Lab=preload("res://scripts/fleet_lab.gd")
const Refit=preload("res://scripts/refit.gd")
const Portrait=preload("res://scripts/boat_portrait.gd")

static func picker(parent: Node,options: Array,current: String,action: Callable) -> OptionButton:
	var choice=OptionButton.new()
	choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	choice.custom_minimum_size.y=34
	for item in options:
		choice.add_item(str(item.label))
		choice.set_item_metadata(choice.item_count-1,str(item.id))
		if str(item.id)==current: choice.select(choice.item_count-1)
	choice.item_selected.connect(func(index): action.call(str(choice.get_item_metadata(index))))
	parent.add_child(choice)
	return choice

static func open(ui):
	var host=ui.host
	if host.lab_config.is_empty(): host.lab_config=Lab.preset(host.data,"mixed")
	ui.modal_kind="lab"
	var body=ui.modal("Fleet battle laboratory","SANDBOX · NO CAREER REWARDS OR SAVES",1240,820)
	var top=ui.row(body)
	ui.label(top,"Preset",15,ui.GOLD)
	var choices: Array=[]
	for id in Lab.presets(): choices.append({"id":id,"label":Lab.presets()[id].label})
	picker(top,choices,"",func(id):host.lab_config=Lab.preset(host.data,id);open(ui))
	ui.label(top,"Seed",15)
	var seed_box=SpinBox.new()
	seed_box.min_value=1;seed_box.max_value=2147483647;seed_box.value=host.lab_seed
	seed_box.custom_minimum_size.x=125
	seed_box.value_changed.connect(func(value):host.lab_seed=int(value))
	top.add_child(seed_box)
	ui.paragraph(body,"Choose both fleets and their fittings. Each side may deploy 300 points. All boats start crewed and supplied; both fleets default to autopilot.",15)
	var summary=ui.label(body,"",17,ui.GOLD)
	var sides=ui.row(body)
	for team in ["player","enemy"]:
		var col=ui.column(sides)
		col.custom_minimum_size.x=480
		ui.eyebrow(col,"YOUR FLEET" if team=="player" else "OPPOSING FLEET")
		for i in range(host.lab_config[team].size()):
			var item: Dictionary=host.lab_config[team][i]
			var spec: Dictionary=Lab.hull(host.data,item.hull)
			var row=ui.row(col)
			var portrait=Portrait.new();portrait.set_spec(spec);portrait.custom_minimum_size=Vector2(86,53)
			row.add_child(portrait)
			var text=ui.column(row)
			ui.label(text,spec.name,16,ui.TEXT)
			ui.label(text,"%d points · %d crew each"%[host.Deployment.cost(Refit.effective_spec(spec,item.loadout)),spec.crewOptimal],12,ui.MUTED)
			var qty=SpinBox.new();qty.min_value=1;qty.max_value=40;qty.value=item.count
			qty.custom_minimum_size.x=72;row.add_child(qty)
			qty.value_changed.connect(func(value):item.count=int(value);update_summary(ui,summary))
			ui.button(row,"Fit",func():edit(ui,team,i))
			ui.button(row,"×",func():host.lab_config[team].remove_at(i);open(ui))
		ui.button(col,"+ Add boat",func():add(ui,team)).disabled=host.lab_config[team].size()>=24
	var actions=ui.row(body)
	var launch=ui.button(actions,"Launch fleet engagement",func():host.start_lab(),true)
	launch.name="LabLaunch"
	ui.button(actions,"Main menu",host.return_to_title)
	update_summary(ui,summary)
	launch.grab_focus()

static func update_summary(ui,label):
	var checked: Dictionary=Lab.inspect(ui.host.data,ui.host.lab_config)
	label.text=checked.error if not checked.ok else "YOU: %d / 300 points · %d boats · %d crew     |     OPPOSITION: %d / 300 points · %d boats · %d crew"%[checked.player.points,checked.player.boats,checked.player.crew,checked.enemy.points,checked.enemy.boats,checked.enemy.crew]
	var launch=ui.overlay.find_child("LabLaunch",true,false)
	if launch!=null: launch.disabled=not checked.ok

static func add(ui,team: String):
	ui.modal_kind="lab"
	var body=ui.modal("Add a boat","%s FLEET"%team.to_upper(),780,650)
	var selected: Array=[ui.host.data.HULLS[0].id]
	var choices: Array=[]
	for spec in ui.host.data.HULLS: choices.append({"id":spec.id,"label":"%s · %d points · %d crew"%[spec.name,ui.host.Deployment.cost(spec),spec.crewOptimal]})
	picker(body,choices,str(selected[0]),func(id):selected[0]=id)
	ui.paragraph(body,"Add a stock hull, then choose its weapons, engine and armor using Fit. The laboratory never bills a career.")
	ui.button(body,"Add to fleet",func():ui.host.lab_config[team].append(Lab.entry(ui.host.data,str(selected[0])));open(ui),true)
	ui.button(body,"Back",func():open(ui))

static func edit(ui,team: String,index: int):
	var item: Dictionary=ui.host.lab_config[team][index]
	var spec: Dictionary=Lab.hull(ui.host.data,item.hull)
	var draft: Dictionary=item.loadout.duplicate(true)
	ui.modal_kind="lab"
	var body=ui.modal(spec.name,"LABORATORY FITTING · NO COINS SPENT",820,730)
	var portrait=Portrait.new();portrait.set_spec(spec);portrait.custom_minimum_size=Vector2(600,130);body.add_child(portrait)
	var cat: Dictionary=Refit.catalog()
	var mounts: Array=Refit.hardpoints(spec)
	for i in range(mounts.size()):
		ui.label(body,"%s · size %d"%[mounts[i].label,mounts[i].size],14,ui.GOLD)
		var choices: Array=[]
		for id in cat.weapons:
			if cat.weapons[id].size<=mounts[i].size and (id!="stock_primary" or i==0): choices.append({"id":id,"label":cat.weapons[id].name})
		picker(body,choices,draft.weapons[i],func(id):draft.weapons[i]=id)
	for slot in ["engine","armor"]:
		ui.label(body,slot.capitalize(),14,ui.GOLD)
		var choices: Array=[]
		var group: Dictionary=cat.engines if slot=="engine" else cat.armor
		for id in group: choices.append({"id":id,"label":group[id].name})
		picker(body,choices,draft[slot],func(id):draft[slot]=id)
	var status=ui.paragraph(body,"The normal hardpoint sizes and fitting-point budget apply.",14)
	ui.button(body,"Apply fitting",func():
		var checked: Dictionary=Refit.normalize(spec,draft)
		if checked.ok: item.loadout=draft.duplicate(true);open(ui)
		else: status.text=checked.message
	,true)
	ui.button(body,"Cancel",func():open(ui))

static func results(ui):
	var host=ui.host
	ui.modal_kind="outcome"
	var body=ui.modal("Engagement complete","LABORATORY · SEED %d"%host.lab_seed,850,700)
	ui.label(body,str(host.battle.result).capitalize(),32,ui.GOLD,true)
	ui.paragraph(body,"Test fixtures only. No coins, salvage or laboratory hulls enter your voyage.")
	for team in ["player","enemy"]:
		var boats: Array=host.battle.ships.filter(func(s):return s.team==team)
		var alive=0;var holes=0;var water=0.0;var ammo=0.0
		for ship in boats:
			alive+=0 if ship.sunk else 1;holes+=ship.breaches.size();water+=ship.water;ammo+=ship.ammo
		ui.label(body,"%s: %d / %d afloat · %d breaches · %.0f L flooding · %.0f ammo left"%[team.capitalize(),alive,boats.size(),holes,water,ammo],16)
	ui.paragraph(body,"Simulation time: %.1f seconds. Same seed and fittings reproduce the same starting engagement."%host.battle.time,15)
	ui.button(body,"Replay same fleets / seed",host.start_lab,true)
	ui.button(body,"Change fleets",host.open_lab)
	ui.button(body,"Main menu",host.return_to_title)
