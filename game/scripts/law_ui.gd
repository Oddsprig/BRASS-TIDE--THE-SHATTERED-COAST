extends RefCounted
const Ops=preload("res://scripts/law_ops.gd")
const Goods=preload("res://scripts/goods.gd")
static func result(ui,r: Dictionary) -> void:
	ui.host.respond(r)
	if r.ok:ui.host.save_game(false)
	open(ui)
static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	ui.modal_kind="customs"
	var body=ui.modal("Cargo declarations & customs","LOCAL LICENCES · SHARED STOCK · ACTUAL COINS",1120,850)
	ui.paragraph(body,"Raw guns and engine assemblies are restricted at neutral harbors. Friendly standing admits them. A paid local licence covers a finite consignment for thirty days; fittings already installed on your boats and sealed contract freight are admitted separately.",16)
	var book: Dictionary=c.state.tradeLaw
	ui.label(body,"Manifest: "+str(book.mode).capitalize(),23,ui.GOLD,true)
	ui.paragraph(body,"A declared manifest is inspected openly. Concealment risks discovery at a real inspecting harbor or eligible nearby patrol. Each observer records one encounter per calendar day. Seized cargo enters the custodian harbor's public stores; a fine can leave an unpaid balance.",15)
	var modes=ui.row(body)
	ui.button(modes,"Declare manifest",func():result(ui,Ops.Law.set_mode(c,"declared")))
	ui.button(modes,"Conceal raw cargo",func():result(ui,Ops.Law.set_mode(c,"concealed")))
	for permit in book.permits:
		ui.paragraph(body,"%s · %s · %d unspent lots / %d covered aboard · expires day %.1f"%[str(c.port(permit.port).name),str(Goods.ITEMS[permit.good].name),int(permit.qty),int(permit.bound),float(permit.expires)],14,ui.TEAL)
	for debt in book.debts:
		var id: int=int(debt.id)
		ui.paragraph(body,"%s customs: %d coins still owed"%[str(c.port(debt.port).name),int(debt.amount)],16,ui.RED)
		ui.button(body,"Settle at the named harbor",func():result(ui,Ops.pay(c,id)))
	for ban in book.bans:
		ui.paragraph(body,"%s / %s carriers: %s restricted until day %.1f"%[str(ban.issuer).capitalize(),str(ban.target).capitalize(),str(Goods.ITEMS[ban.good].name),float(ban.expires)],14)
	var p: Dictionary=c.current_port()
	if not p.is_empty():
		ui.rule(body)
		ui.label(body,str(p.name)+" registry",23,ui.TEAL,true)
		var line=ui.row(body)
		var military=OptionButton.new();military.add_item("Gun assemblies");military.add_item("Engine assemblies");line.add_child(military)
		var count=SpinBox.new();count.min_value=1;count.max_value=1000;count.value=1;count.step=1;line.add_child(count)
		ui.paragraph(body,"A licence costs 69 coins: one quarter-day each of clerk labor and foreman oversight. It reserves no stock. Buy the actual goods from the market after registration.",14)
		ui.button(body,"Register a local consignment · 69 coins",func():result(ui,Ops.license(c,"guns" if military.selected==0 else "engines",int(count.value))))
		ui.label(body,"Unregistered broker",22,ui.GOLD,true)
		ui.paragraph(body,"Uses this same harbor inventory and protected export limits. The broker charges 28 coins for labor plus a 15% purchase premium or 15% sale discount. No secret stock is generated. Restricted raw cargo remains subject to customs.",14)
		var broker=ui.row(body);var goods=OptionButton.new();var keys: Array=Goods.ITEMS.keys()
		for good in keys:goods.add_item(str(Goods.ITEMS[good].name))
		broker.add_child(goods)
		var lots=SpinBox.new();lots.min_value=1;lots.max_value=1000;lots.value=1;lots.step=1;broker.add_child(lots)
		ui.button(broker,"Buy",func():result(ui,Ops.illicit(c,str(keys[goods.selected]),int(lots.value),"buy")))
		ui.button(broker,"Sell",func():result(ui,Ops.illicit(c,str(keys[goods.selected]),int(lots.value),"sell")))
		ui.label(body,"Military trade agreement",22,ui.GOLD,true)
		ui.paragraph(body,"Friendly standing lets you request a fifteen-day military restriction against one existing hostile faction pair. It affects guns or engine assemblies carried by those factions. Food, fuel, ordinary goods and faction relationships are unchanged. Registry labor costs 69 coins.",14)
		var target=OptionButton.new();var ids: Array=[]
		for faction in c.data.FACTIONS:
			if faction.id!=p.faction:ids.append(str(faction.id));target.add_item(str(faction.name))
		body.add_child(target)
		ui.button(body,"Register selected military restriction · 69 coins",func():result(ui,Ops.embargo(c,str(ids[target.selected]),"guns" if military.selected==0 else "engines")))
	else:ui.paragraph(body,"Visit an actual harbor for registry services, broker trades and local fine payments.",16)
	ui.button(body,"Close",ui.close_modal,true)
