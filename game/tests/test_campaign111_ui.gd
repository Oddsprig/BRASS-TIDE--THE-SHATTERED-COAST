extends SceneTree
## Layout-only fixture. Existing starter hull stands in for locally secured
## property. Historical capture metadata is declared, not earned or native
## gameplay evidence. No boat, money, fitting or crew is added. Never store media.
class Preview extends "res://scripts/main.gd":
	var output111ui: String
	func _ready() -> void:
		qa_ocean066=true;super._ready()
		set_process(false);set_physics_process(false);set_process_input(false);set_process_unhandled_input(false)
		output111ui=OS.get_environment("GAME_TEST_ARTIFACTS").path_join("campaign111-ui")
		DirAccess.make_dir_recursive_absolute(output111ui)
		run111ui.call_deferred()
	func buttons111ui(node: Node) -> Array:
		var out: Array=[]
		if node is Button:out.append(node)
		for child in node.get_children():out.append_array(buttons111ui(child))
		return out
	func run111ui() -> void:
		if not core.new_game(123).ok:push_error("UI111 new career failed");get_tree().quit(2);return
		mode="campaign";paused=true;ui.close_modal();ui.build_hud()
		core.Contacts.visit(core.state,core.current_port(),core.state.day)
		if not core.StoryOps.start(core,core.Arc110.ID).ok:push_error("UI111 start failed");get_tree().quit(2);return
		core.Arc110.record(core).stage="second_signature111";core.Arc110.record(core).flags=["venn_claim_seen110"]
		var offers: Array=core.Arc111.offers(core)
		if offers.is_empty() or not core.Arc111.accept(core,offers[0]).ok:push_error("UI111 funded job failed");get_tree().quit(2);return
		var w: Dictionary=core.Arc111.work(core)
		if not core.VoyageJobs.abandon(core,str(w.jobId)).ok:push_error("UI111 real refund failed");get_tree().quit(2);return
		# Controlled visual state only. No native combat or captured hull claimed.
		core.state.battleSeq=1
		w.captures=[{"originalUid":str(w.targetUids[0]),"boatUid":str(core.state.fleet[0].uid),"kind":"captured","source":"layout-only111","sequence":1,"day":float(core.state.day)}]
		ui.StoryUI.open(ui);chart.step(0);ui.update_hud()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var report: Button=null
		var obsolete: bool=false
		for button in buttons111ui(ui):
			if button.text=="Send Tobin the report with secured original property":report=button
			if button.is_visible_in_tree() and button.text in ["Coastal watch and last sightings","Review original fitting or hull recovery"]:obsolete=true
		var visible: bool=report!=null and report.is_visible_in_tree() and not report.disabled
		var area: Rect2=get_viewport().get_visible_rect()
		if visible:
			var parent: Node=report.get_parent()
			while parent!=null:
				if parent is Control and parent.clip_contents:area=area.intersection(parent.get_global_rect())
				parent=parent.get_parent()
			visible=area.encloses(report.get_global_rect())
		var captured_ok: bool=get_viewport().get_texture().get_image().save_png(output111ui.path_join("property-ready-layout-fixture.png"))==OK
		var checks: Array=[{"name":"report action enabled and wholly visible inside the real clipped modal","passed":visible},{"name":"obsolete hunt and fitting-recovery actions absent after property secured","passed":not obsolete},{"name":"actual private viewport saved; original15k purse/one boat/five people unchanged","passed":captured_ok and core.state.coins==15000 and core.state.fleet.size()==1 and core.crew_count()==5}]
		var ok: bool=checks.all(func(row):return bool(row.passed))
		var file=FileAccess.open(output111ui.path_join("evidence.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"scope":"Layout-only declared capture metadata with existing starter hull; no gameplay/capture/earned progress claim; never store media","report_rect":{"x":report.get_global_rect().position.x,"y":report.get_global_rect().position.y,"height":report.get_global_rect().size.y} if report!=null else {},"owner_profile_used":false},"\t"));file.close()
		if not ok:push_error("UI111 layout check failed");get_tree().quit(2);return
		print("CAMPAIGN111_UI_DONE checks=3");get_tree().quit(0)
func _initialize() -> void:
	root.add_child(Preview.new())
