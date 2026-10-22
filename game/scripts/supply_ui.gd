extends RefCounted
const Reserves=preload("res://scripts/harbor_reserves.gd")
const Ops=preload("res://scripts/reserve_ops.gd")
const Goods=preload("res://scripts/goods.gd")
static func act(ui,policy: String="") -> void:
	ui.host.sync_economy()
	var result: Dictionary=Ops.release_food(ui.host.core) if policy.is_empty() else Ops.policy(ui.host.core,policy)
	ui.host.respond(result)
	if result.ok:ui.host.save_game(false)
	open(ui)

static func open(ui) -> void:
	ui.host.sync_economy()
	var c=ui.host.core
	var p: Dictionary=c.current_port()
	if p.is_empty():ui.toast("Visit a harbor to inspect its stores.",true);return
	Ops.ensure(c)
	var r: Dictionary=Reserves.report(p)
	ui.modal_kind="harbor_reserves"
	var body=ui.modal("Harbor reserves & production","ON HAND · COMMITTED · IN TRANSIT",1100,820)
	ui.label(body,p.name,26,ui.GOLD,true)
	ui.paragraph(body,"Policy: %s · resupply horizon %.1f days · operating buffer %.2f days. The horizon estimates a local round trip by cargo launch plus handling time."%[str(r.policy).capitalize(),float(r.resupplyDays),float(r.operatingDays)],16,ui.TEAL)
	ui.paragraph(body,"Households use %.2f food lots per day. Recipe inputs and actual home-fleet consumption add recorded demand. Commercial and government stores have separate owners; promised cargo is still at sea. Named freight and build orders already withdraw their own actual materials.",15)
	for good in ["food","fuel","ammo","supplies"]:
		var item: Dictionary=r.goods[good]
		ui.rule(body)
		ui.label(body,str(Goods.ITEMS[good].name),22,ui.GOLD,true)
		ui.paragraph(body,"Commercial %.2f · public %.2f · inbound %.2f · new sales %.2f"%[float(item.commercialStock),float(item.publicStock),float(item.incoming),float(item.exportable)],16)
		if item.noDemand:ui.paragraph(body,"No recorded daily use yet. Existing stock remains available unless actually committed.",14,ui.MUTED)
		else:ui.paragraph(body,"Daily use %.2f · commercial coverage %.2f days · public coverage %.2f days
Operating stock held %.2f · advisory public target %.2f"%[float(item.dailyDemand),float(item.commercialCoverageDays),float(item.publicCoverageDays),float(item.operatingProtected),float(item.publicTarget)],15,ui.TEAL)
		ui.paragraph(body,str(item.reason),13,ui.MUTED)
	ui.rule(body)
	ui.paragraph(body,"Friendly harbor partners may advise supply policy. Essential production receives a bounded share of feasible paid workers before remaining work is allocated. Inputs and payroll still limit every recipe; extra priorities never create a second workforce.",15)
	var actions=ui.row(body)
	ui.button(actions,"Supply security",func():act(ui,"security"))
	ui.button(actions,"Commercial priority",func():act(ui,"commercial"))
	ui.paragraph(body,"Public granary release: up to one day of actual food into this harbor's commercial store. Friendly approval and available staff required. Clerk25 + oversight22 = 47 coins; the food remains for ordinary local purchases.",14)
	ui.button(body,"Request public food release · 47 coins",func():act(ui))
	ui.button(body,"Back to market",func():ui.open_port("Market"),true)
