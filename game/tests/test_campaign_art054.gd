extends SceneTree
## PREPARED, NATIVE UNRUN. Root runs after the two named art commits are integrated.
## Finite asset/layout checks and one paused actual Main career; no desktop input.
const FleetArt=preload("res://scripts/campaign_fleet_art054.gd")
const Landmarks=preload("res://scripts/campaign_landmark_art054.gd")
const Chart=preload("res://scripts/chart.gd")
const Damage=preload("res://scripts/damage.gd")
const Refit=preload("res://scripts/refit.gd")
const Profiles=preload("res://scripts/hull_profiles.gd")
const ChartTest=preload("res://tests/test_chart_readability040.gd")

var game
var checks: int=0
var failures: int=0
var started: int=0
var finished: bool=false
var summaries: Array=[]

func check(ok: bool,message: String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL campaign art054: "+message)
	return ok

func finite_rect(rect: Rect2) -> bool:
	return is_finite(rect.position.x) and is_finite(rect.position.y) and is_finite(rect.size.x) and is_finite(rect.size.y) and rect.size.x>=0.0 and rect.size.y>=0.0

func primitives_inside(recorder,bounds: Rect2) -> bool:
	for primitive in recorder.prims:
		var pad: float=float(primitive.get("r",0.0)) if str(primitive.t)=="circle" else maxf(0.0,float(primitive.get("w",0.0)))*0.5
		for pair in primitive.get("pts",[]):
			var at:=Vector2(pair[0],pair[1])
			if not bounds.grow(0.5).encloses(Rect2(at-Vector2.ONE*pad,Vector2.ONE*pad*2)):return false
	return true

func boat_for(data: Dictionary,id: String) -> Dictionary:
	for spec in data.HULLS:
		if str(spec.id)==id:
			var fit: Dictionary=Refit.defaults(spec)
			var effective: Dictionary=Refit.effective_spec(spec,fit)
			return Damage.create_ship(effective,{"uid":"art054-"+id,"baseSpec":spec.duplicate(true),"loadout":fit})
	check(false,"Fixture names a real canonical hull: "+id)
	return {}

func asset_cases(data: Dictionary) -> void:
	var frozen: PackedByteArray=var_to_bytes(data)
	var paths: Dictionary={}
	check(data.HULLS.size()==36,"All36 canonical hulls are the finite asset cohort")
	for spec in data.HULLS:
		var info: Dictionary=FleetArt.asset_info(spec)
		var path: String=str(info.get("path",""))
		var rect: Rect2=info.get("local_bounds",Rect2())
		check(str(info.get("hull_id",""))==str(spec.id) and path.begins_with("res://assets/campaign054/boats/") and not paths.has(path),"Distinct original top-down asset resolves for "+str(spec.id))
		paths[path]=true
		check(finite_rect(rect) and rect.has_area() and info.get("stations",[])==Profiles.stations(spec),"Exact canonical physical hull profile and finite bounds resolve for "+str(spec.id))
		var exists: bool=ResourceLoader.exists(path,"Texture2D")
		check(exists,"Root-imported hull texture exists: "+str(spec.id))
		if exists:
			var texture=load(path)
			check(texture is Texture2D and texture.get_width()>0 and texture.get_height()>0,"Hull texture loads with nonzero dimensions: "+str(spec.id))
	check(var_to_bytes(data)==frozen,"Resolving all36 profiles/assets preserves authored hulls and geography")

func formation_case(name_text: String,boats: Array,heading: float,scale_value: float) -> Dictionary:
	var frozen: PackedByteArray=var_to_bytes(boats)
	var center:=Vector2(640,400)
	var plan: Dictionary=FleetArt.layout(boats,center,heading,scale_value,{"viewport":Rect2(0,0,1280,800)})
	var vessels: Array=plan.get("vessels",[])
	check(int(plan.get("roster_count",-1))==boats.size() and vessels.size()==mini(5,boats.size()),name_text+" draws only its actual bounded roster")
	check(int(plan.get("visible_count",-1))==vessels.size() and int(plan.get("omitted_count",-1))==boats.size()-vessels.size(),name_text+" reports displayed/omitted real boats")
	var bounds: Rect2=plan.get("bounds",Rect2())
	check(finite_rect(bounds) and bounds.has_area() and bounds.size.x<=512.0 and bounds.size.y<=512.0,name_text+" has finite compact screen bounds")
	var identities: Dictionary={}
	var footprints: Array=[]
	var overlap: bool=false
	for i in range(vessels.size()):
		var vessel: Dictionary=vessels[i]
		var uid: String=str(vessel.get("uid",""))
		var owner: Dictionary={}
		for boat in boats:
			if str(boat.get("uid",""))==uid:owner=boat;break
		check(not owner.is_empty() and not identities.has(uid),name_text+" vessel has one actual input identity")
		identities[uid]=true
		if owner.is_empty():continue
		var rect: Rect2=vessel.get("bounds",Rect2())
		var transform: Transform2D=vessel.get("transform",Transform2D.IDENTITY)
		var point: Vector2=vessel.get("center",Vector2.ZERO)
		var local: Rect2=FleetArt.asset_info(owner.spec).local_bounds
		var footprint: PackedVector2Array=transform*PackedVector2Array([local.position,Vector2(local.end.x,local.position.y),local.end,Vector2(local.position.x,local.end.y)])
		check(finite_rect(rect) and rect.has_area() and bounds.grow(0.01).encloses(rect),name_text+" formation bounds contain this whole boat")
		var footprint_inside: bool=true
		for p in footprint:footprint_inside=footprint_inside and rect.grow(0.01).has_point(p)
		check(footprint_inside,name_text+" rotated hull art fits the published screen bounds")
		check((transform*Vector2.ZERO).distance_to(point)<0.01 and transform.x.normalized().dot(Vector2.from_angle(heading))>0.999 and absf(angle_difference(float(vessel.get("angle",0.0)),heading))<0.001,name_text+" bow/local transform follows chart heading")
		check(str(vessel.get("hull_id",""))==str(owner.spec.id) and str(vessel.get("asset_path",""))==str(FleetArt.asset_info(owner.spec).path),name_text+" uses the real design's chart asset")
		var actual_mounts: Array=owner.spec.get("weaponMounts",[])
		var mounts: Array=vessel.get("mounts",[])
		check(mounts.size()==actual_mounts.size(),name_text+" neither invents nor drops fitted guns")
		for m in range(mini(mounts.size(),actual_mounts.size())):
			check(str(mounts[m].get("id",""))==str(actual_mounts[m].get("id","")) and str(mounts[m].get("module_id",""))==str(actual_mounts[m].get("moduleId","")) and str(mounts[m].get("kind",""))==str(actual_mounts[m].get("kind","")) and is_equal_approx(float(mounts[m].get("angle",0)),float(actual_mounts[m].get("angle",0))) and is_equal_approx(float(mounts[m].get("world_x",0)),float(actual_mounts[m].get("x",0))) and is_equal_approx(float(mounts[m].get("world_y",0)),float(actual_mounts[m].get("y",0))),name_text+" fitted module/mount identity, angle and physical origin match the effective spec")
		for previous: PackedVector2Array in footprints:overlap=overlap or not Geometry2D.intersect_polygons(footprint,previous).is_empty()
		footprints.append(footprint)
	check(not overlap,name_text+" rotated hull footprints do not overlap")
	if not vessels.is_empty():check(Vector2(vessels[0].center).distance_to(center)<0.001,name_text+" lead stays at the exact projected fleet position")
	var before_plan: PackedByteArray=var_to_bytes(plan)
	var recorder=ChartTest.ChartRecorder.new()
	var drawn: Dictionary=FleetArt.draw(recorder,plan,Chart.GOLD,true)
	check(int(drawn.get("drawn_vessels",-1))==vessels.size() and recorder.invalid==0 and primitives_inside(recorder,bounds.grow(1)),name_text+" public draw consumes the finite real plan inside its published bounds")
	check(var_to_bytes(boats)==frozen and var_to_bytes(plan)==before_plan,name_text+" planning/drawing preserve every boat, fitting and plan")
	summaries.append({"case":name_text,"roster":boats.size(),"visible":vessels.size(),"lod":plan.get("lod",-1),"bounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]})
	return plan

func fleet_cases(data: Dictionary) -> void:
	var small: Array=[boat_for(data,"tin_skiff")]
	var mixed: Array=[boat_for(data,"aegis_corvette"),boat_for(data,"lantern_skiff"),boat_for(data,"slag_gunboat")]
	var civilians: Array=[boat_for(data,"tideledger_coaster"),boat_for(data,"blackwater_fleet_tanker"),boat_for(data,"aurelian_court_yacht"),boat_for(data,"kelpnet_dory")]
	# One detached, valid refit exercises a real additional aft fitting; no
	# actual campaign boat is granted weapons, resources or an invented escort.
	var refitted: Dictionary=mixed[0]
	refitted.loadout.weapons[1]="rapid_gun"
	var valid: Dictionary=Refit.normalize(refitted.baseSpec,refitted.loadout)
	check(bool(valid.get("ok",false)),"Mixed-art fixture uses a valid current weapons:Array refit")
	refitted.spec=Refit.effective_spec(refitted.baseSpec,refitted.loadout)
	var solo: Dictionary=formation_case("one real starter",small,0.0,0.5)
	var turn: Dictionary=formation_case("quarter-turn mixed fleet",mixed,PI*0.5,0.5)
	var civil: Dictionary=formation_case("civilian cargo/tanker/yacht/fishing",civilians,-0.4,0.5)
	check(civil.vessels[0].asset_path!=civil.vessels[1].asset_path and civil.vessels[1].asset_path!=civil.vessels[2].asset_path and float(civil.vessels[1].length_px)>float(solo.vessels[0].length_px),"Civilian designs resolve distinct assets and a large tanker reads larger than the starter")
	var far: Dictionary=formation_case("overview mixed fleet",mixed,PI*0.5,0.08)
	check(int(far.lod)>int(turn.lod) and float(far.vessels[0].length_px)<float(turn.vessels[0].length_px),"Low zoom selects simpler smaller nautical art")
	var capped: Dictionary=FleetArt.layout(small+mixed+civilians,Vector2(640,400),0.0,0.5)
	check(capped.vessels.size()<=5 and int(capped.roster_count)==8 and int(capped.omitted_count)==8-capped.vessels.size(),"Five-boat draw cap reports the real omitted roster")
	var empty: Dictionary=FleetArt.layout([],Vector2(640,400),0.0,0.5)
	check(empty.vessels.is_empty() and not Rect2(empty.bounds).has_area(),"An empty roster creates no decorative boat")
	var culled: Dictionary=FleetArt.layout(small,Vector2(-2000,-2000),0.0,0.5,{"viewport":Rect2(0,0,1280,800)})
	check(culled.vessels.is_empty(),"Offscreen formation is culled")

func landmark_cases(sites: Array) -> void:
	var frozen: PackedByteArray=var_to_bytes(sites)
	for site in sites:
		var hidden: Dictionary=Landmarks.plan(site,0,Vector2(640,400),0.5)
		check(hidden.get("commands",[]).is_empty(),"Unknown site emits no drawable feature: "+str(site.id))
		var known: Dictionary=Landmarks.plan(site,2,Vector2(640,400),0.5)
		var recorder=ChartTest.ChartRecorder.new()
		Landmarks.draw(recorder,known)
		check(recorder.invalid==0 and not recorder.prims.is_empty() and primitives_inside(recorder,known.bounds) and int(known.primitive_count)<=80,"Authored known landmark has finite bounded draw geometry: "+str(site.id))
	# One authored ruin/clue at three knowledge levels; no synthetic terrain or rewards.
	var site: Dictionary={}
	for candidate in sites:
		if str(candidate.id)=="cinder_workshop_ruin":site=candidate;break
	if not check(not site.is_empty(),"Knowledge fixture uses the authored workshop ruin"):return
	var sighted: Dictionary=Landmarks.plan(site,1,Vector2(640,400),0.5)
	var charted: Dictionary=Landmarks.plan(site,2,Vector2(640,400),0.5)
	check(not sighted.get("commands",[]).is_empty() and not charted.get("commands",[]).is_empty(),"Observed clue and identified ruin both have actual feature art")
	check(not bool(sighted.get("identified",true)) and str(sighted.get("label",""))!=str(site.name) and not sighted.has("discovery") and not sighted.has("resource") and not sighted.has("reward"),"Sighted art does not identify the undiscovered name, discovery or resource")
	check(bool(charted.get("identified",false)) and str(charted.get("label",""))==str(site.name),"Charted art identifies only the actually known site's name")
	for plan in [sighted,charted]:
		var recorder=ChartTest.ChartRecorder.new()
		var before: PackedByteArray=var_to_bytes(plan)
		Landmarks.draw(recorder,plan,true)
		check(recorder.invalid==0 and not recorder.prims.is_empty() and finite_rect(plan.bounds) and Rect2(plan.bounds).has_area(),"Knowledge-aware landmark draws finite bounded original geometry")
		check(before==var_to_bytes(plan),"Landmark draw leaves its plan unchanged")
	var far: Dictionary=Landmarks.plan(site,2,Vector2(640,400),0.08)
	check(int(far.lod)<int(charted.lod) and far.commands.size()<=charted.commands.size() and Rect2(far.bounds).size.length()<Rect2(charted.bounds).size.length(),"Landmark overview reduces detail and screen extent")
	var wreck: Dictionary={"id":"art054-wreck","hull":"tin_skiff","status":"unclaimed"}
	var wreck_before: PackedByteArray=var_to_bytes(wreck)
	var wreck_art: Dictionary=Landmarks.wreck_plan(wreck,Vector2(640,400),0.5)
	check(str(wreck_art.kind)=="wreck" and not wreck_art.commands.is_empty() and var_to_bytes(wreck)==wreck_before,"An actual unclaimed hull record resolves wreck art without changing recovery state")
	wreck.status="claimed"
	check(Landmarks.wreck_plan(wreck,Vector2(640,400),0.5).commands.is_empty(),"Claimed wrecks create no live recoverable artwork")
	check(var_to_bytes(sites)==frozen,"Landmark art preserves catalog coordinates, knowledge inputs and rewards")

func _initialize() -> void:
	started=Time.get_ticks_msec()
	call_deferred("run")

func _process(_delta: float) -> bool:
	# Root also supplies an external cap for synchronous setup/native stalls.
	if not finished and Time.get_ticks_msec()-started>=25000:
		check(false,"Cooperative 25s fixture deadline exceeded")
		finish()
	return false

func run() -> void:
	if not check(DisplayServer.get_name()=="headless","Root supplies headless, Dummy audio and synthetic APPDATA"):
		finish();return
	root.content_scale_size=Vector2i(1280,800);root.size=Vector2i(1280,800)
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	asset_cases(data)
	fleet_cases(data)
	var sites: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/island_sites.json")).sites
	landmark_cases(sites)
	# Exactly one actual Main and one seeded Campaign.new_game. Do not call
	# Main.new_game as well: that would construct another heavy career.
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.paused=true
	game.audio.enabled=false;game.music.enabled=false
	game.save_directory=OS.get_user_data_dir().path_join("campaign-art054-%d"%Time.get_ticks_usec())
	game.chart.queue_redraw()
	await process_frame;await process_frame
	if finished:return
	check(game.mode=="menu" and game.core.state.is_empty() and int(game.chart.presentation_us)>0,"Actual native title draw runs before creating any career or decorative fleet")
	var begun: Dictionary=game.core.new_game(54054)
	if check(bool(begun.get("ok",false)) and not game.core.state.is_empty(),"One seeded actual Main career is admitted"):
		await integration()
	if finished:return
	if is_instance_valid(game):game.queue_free()
	await process_frame
	if not finished:finish()

func integration() -> void:
	var c=game.core
	var chart=game.chart
	game.mode="campaign";game.selected_port=str(game.data.START.port)
	game.ui.close_modal();game.ui.build_hud()
	chart.center_camera();chart.scale_factor=chart.regional_scale()*chart.zoom
	var original: PackedByteArray=var_to_bytes(c.state)
	var map_before: PackedByteArray=var_to_bytes(game.data)
	var player: Dictionary=chart.campaign_player_art054()
	check(int(player.get("lod",2))<2,"Live Home keeps rich ordinary fleet art at this window's regional scale")
	var actual: Array=c.active_fleet()
	if not check(actual.size()==1 and player.vessels.size()==1 and int(player.roster_count)==1,"Actual one-boat start is drawn as exactly its one active boat"):return
	var point:=Vector2(c.state.position.x,c.state.position.y)
	check(str(player.vessels[0].uid)==str(actual[0].uid) and Vector2(player.vessels[0].center).distance_to(chart.project(point))<0.001,"Live Chart retains the actual player UID and physical projected center")
	check(chart.world_at(player.vessels[0].center).distance_to(point)<0.001,"Live richer art leaves projection and click inverse unchanged")
	var home: Dictionary=c.port(str(game.data.START.port))
	var home_bounds: Rect2=chart.campaign_harbor_bounds054(home)
	check(finite_rect(home_bounds) and home_bounds.has_area() and home_bounds.has_point(chart.project(Vector2(home.x,home.y))),"Harbor art bounds include the exact physical berth")
	chart.queue_redraw()
	await process_frame;await process_frame
	if finished:return
	var labels: Array=chart._map_labels
	check(labels.any(func(label):return str(label.text)=="YOUR FLOTILLA") and labels.any(func(label):return str(label.text)==str(home.name)),"Actual draw_campaign places both player and harbor labels at the shared home position")
	label_checks(labels,[Rect2(player.bounds).grow(5),home_bounds],"actual home")
	check(var_to_bytes(c.state)==original and var_to_bytes(game.data)==map_before,"Actual title/player/harbor drawing preserves the entire career and authored map")
	# The real active_fleet API owns reserve/sunk eligibility. Reuse this same
	# actual boat, restore exactly, and never append synthetic owned escorts.
	var boat: Dictionary=actual[0]
	var had_stored: bool=boat.has("storedPort")
	var stored_before: String=str(boat.get("storedPort",""))
	boat.storedPort=str(home.id)
	check(chart.campaign_player_art054().vessels.is_empty(),"A stored owned boat is absent from live traveling art")
	if had_stored:boat.storedPort=stored_before
	else:boat.erase("storedPort")
	boat.mothballed=true
	check(chart.campaign_player_art054().vessels.is_empty(),"A stood-down boat is absent from live traveling art")
	boat.mothballed=false;boat.sunk=true
	check(chart.campaign_player_art054().vessels.is_empty(),"A sunk boat is absent from live traveling art")
	boat.sunk=false
	check(var_to_bytes(c.state)==original,"Roster visibility cases restore the exact seeded career")
	game.click_chart(chart.project(Vector2(home.x,home.y)))
	check(str(game.selected_port)==str(home.id) and game.ui.modal_kind=="port","Actual Main.click_chart keeps physical home-harbor selection")
	game.ui.close_modal()
	await patrol_integration()
	if finished:return
	await site_integration()
	if finished:return
	check(var_to_bytes(game.data)==map_before,"Native art/selection checks leave authored hulls and geography unchanged")

func label_checks(labels: Array,art_bounds: Array,name_text: String) -> void:
	var usable: Rect2=Chart.chart_label_bounds(Vector2(1280,800))
	var safe: bool=true
	var separated: bool=true
	for i in range(labels.size()):
		var rect: Rect2=labels[i].rect
		safe=safe and usable.encloses(rect) and int(labels[i].font_size)>=14
		for art: Rect2 in art_bounds:separated=separated and not rect.grow(3).intersects(art)
		for j in range(i):separated=separated and not rect.grow(3).intersects(labels[j].rect)
	check(safe and not labels.is_empty(),name_text+" labels keep readable size inside the actual1280x800 HUD margins")
	check(separated,name_text+" labels avoid one another and the whole new boat/waterfront art")

func patrol_integration() -> void:
	var c=game.core
	var chart=game.chart
	var patrol: Dictionary={}
	for candidate in c.state.patrols:
		var owner: Dictionary=c.fleet_owner(str(candidate.id))
		var clear_of_berths: bool=c.state.ports.all(func(p):return c.distance(p,candidate)>300.0)
		if candidate.active and not candidate.get("hidden",false) and owner.get("active",false) and not owner.get("boats",[]).is_empty() and c.distance(c.state.position,candidate)>1800.0 and clear_of_berths:
			patrol=candidate;break
	if not check(not patrol.is_empty(),"One actual distant NPC owner supplies the native formation/picking fixture"):return
	chart.camera=Vector2(patrol.x,patrol.y);chart.scale_factor=0.5
	var before: PackedByteArray=var_to_bytes(c.state)
	var art: Dictionary=chart.campaign_patrol_art054(patrol)
	var owner: Dictionary=c.fleet_owner(str(patrol.id))
	var visible: Array=owner.boats.filter(func(b):return not b.get("sunk",false) and not b.get("mothballed",false) and not b.get("hidden",false) and str(b.get("storedPort","")).is_empty())
	check(int(art.roster_count)==visible.size() and art.vessels.size()==mini(5,visible.size()),"Live patrol formation represents its real visible owner's boats")
	var source_ids: Array=[]
	for boat in visible:source_ids.append(str(boat.get("uid",boat.get("id",""))))
	var actual_ids: bool=true
	for vessel in art.vessels:actual_ids=actual_ids and source_ids.has(str(vessel.uid))
	check(actual_ids,"Every drawn NPC vessel resolves to an existing owner boat identity")
	var hidden: Dictionary=patrol.duplicate(true);hidden.hidden=true
	check(chart.campaign_patrol_art054(hidden).vessels.is_empty(),"A hidden NPC contact reveals no fleet art")
	var inactive: Dictionary=patrol.duplicate(true);inactive.active=false
	check(chart.campaign_patrol_art054(inactive).vessels.is_empty(),"An inactive NPC contact reveals no fleet art")
	chart.queue_redraw()
	await process_frame;await process_frame
	if finished:return
	check(var_to_bytes(c.state)==before,"NPC art and actual campaign drawing preserve the owner roster and career")
	if not check(not art.vessels.is_empty(),"Actual NPC fixture has selectable boat art"):return
	var at: Vector2=chart.project(Vector2(patrol.x,patrol.y))
	var bow: float=float(Profiles.stations(visible[0].spec).back().x)*0.75
	var edge: Vector2=art.vessels[0].transform*Vector2(bow,0)
	check(edge.distance_to(at)>15.0 and Rect2(art.bounds).has_point(edge),"NPC hit fixture reaches visible art beyond the legacy15px marker radius")
	game.click_chart(edge)
	check(game.ui.modal_kind=="encounter" and game.mode=="campaign","Actual Main.click_chart selects expanded NPC art through the real encounter UI")
	game.ui.close_modal()

func site_integration() -> void:
	var c=game.core
	var chart=game.chart
	var site: Dictionary={}
	for candidate in c.state.exploration.catalog:
		if str(candidate.id)=="cinder_workshop_ruin":site=candidate;break
	if not check(not site.is_empty(),"Actual career retains the authored landmark catalog"):return
	chart.camera=Vector2(site.x,site.y);chart.scale_factor=0.5
	var saved_knowledge: Dictionary=c.state.exploration.duplicate(true)
	var record: Dictionary=c.state.exploration.sites.get(site.id,{}).duplicate(true)
	record.level=0;c.state.exploration.sites[site.id]=record
	var hidden: Dictionary=chart.campaign_site_art054(site,0)
	check(hidden.commands.is_empty() and not Rect2(hidden.bounds).has_area(),"Live Chart emits no art/hit bounds for the undiscovered site")
	chart.queue_redraw()
	await process_frame;await process_frame
	if finished:return
	check(not chart._map_labels.any(func(label):return str(label.text)==str(site.name)),"Actual unknown-site draw reveals no identifying chart label")
	# This synthetic profile changes only one knowledge record for native sighting
	# presentation; it grants no rewards, survey work, terrain or fleet resources.
	record.level=1;c.state.exploration.sites[site.id]=record
	game.selected_site=str(site.id)
	var before: PackedByteArray=var_to_bytes(c.state)
	var art: Dictionary=chart.campaign_site_art054(site,1)
	chart.queue_redraw()
	await process_frame;await process_frame
	if finished:return
	check(not str(art.label).is_empty() and str(art.label)!=str(site.name) and chart._map_labels.any(func(label):return str(label.text)==str(art.label)),"Actual sighted-site draw uses its observation label before identification")
	check(not chart._map_labels.any(func(label):return str(label.text)==str(site.name)),"Actual sighted-site chart does not leak the surveyed name")
	label_checks(chart._map_labels,[Rect2(art.bounds).grow(5)],"actual selected sighting")
	check(var_to_bytes(c.state)==before,"Actual sighted-landmark drawing preserves knowledge/rewards and all resources")
	var at: Vector2=chart.project(Vector2(site.x,site.y))
	var edge: Vector2=Vector2(art.center)+Vector2(art.commands[0].points[0])*float(art.scale)
	check(edge.distance_to(at)>22.0 and Rect2(art.bounds).has_point(edge),"Landmark hit fixture reaches visible art beyond the legacy22px marker radius")
	game.click_chart(edge)
	check(game.ui.modal_kind=="island_site" and str(game.selected_site)==str(site.id),"Actual Main.click_chart selects visible sighting art through the existing site UI")
	game.ui.close_modal()
	c.state.exploration=saved_knowledge

func finish() -> void:
	if finished:return
	if failures==0:check(Time.get_ticks_msec()-started<25000,"Fixture completes inside its cooperative 25s deadline")
	finished=true
	if is_instance_valid(game) and not game.is_queued_for_deletion():game.queue_free()
	var directory: String=OS.get_environment("GAME_TEST_ARTIFACTS")
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
		var file=FileAccess.open(directory.path_join("campaign-art054.json"),FileAccess.WRITE)
		check(file!=null,"Existing artifact directory accepts the bounded source-proof receipt")
		if file!=null:
			file.store_string(JSON.stringify({"checks":checks,"failures":failures,"elapsedMs":Time.get_ticks_msec()-started,"formations":summaries,"limits":"Native asset/layout/actual Main integration checks only. No visual, motion, gameplay, audio or FPS acceptance. Root must view actual exported title/player/NPC/landmark screens."}));file.close()
	print("campaign art054: %d checks, %d failures, %dms; native proof only, visual acceptance remains Root's"%[checks,failures,Time.get_ticks_msec()-started])
	quit(0 if failures==0 else 1)
