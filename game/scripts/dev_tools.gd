extends CanvasLayer
## Visible, opt-in diagnostics. Mutating tools operate on laboratory fixtures only.
var host
var info: Label
var elapsed=0.0
var shown=false

func setup(game_host):
	host=game_host
	layer=20
	info=Label.new()
	info.position=Vector2(340,82)
	info.add_theme_font_size_override("font_size",13)
	info.add_theme_color_override("font_color",Color("dfbd7d"))
	info.add_theme_color_override("font_shadow_color",Color.BLACK)
	info.add_theme_constant_override("shadow_offset_x",1)
	info.add_theme_constant_override("shadow_offset_y",1)
	info.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(info)
	info.visible=false

func _process(dt: float):
	info.visible=shown and host.dev_enabled
	if not info.visible:return
	elapsed+=dt
	if elapsed<0.2:return
	elapsed=0
	var b: Dictionary=host.battle
	info.text="DEVELOPMENT · %s · physics %.2f ms\nF9 overlay · . single step · F6 repair/refill lab · F8 report\n%s"%[host.mode,host.simulation_us/1000.0,"Laboratory fixtures" if host.lab_active else "Read-only career diagnostics"]
	if not b.is_empty():
		info.text+="\nSeed %d · %.1f s · boats %d · shots %d · effects %d\nDeploy %d : %d / 300 · %s"%[host.lab_seed,b.time,b.ships.size(),b.projectiles.size(),b.effects.size(),b.deployment.player,b.deployment.enemy,"AI" if b.autopilot else "manual"]
		info.text+="\nAudio events %d · scheduled %d · peak voices %d / 32 · culled %d"%[host.audio.received,host.audio.scheduled,host.audio.peak_voices,host.audio.dropped]
		var ship: Dictionary=host.Battle.get_flagship(b)
		if not ship.is_empty():
			var status: Dictionary=host.Damage.get_status(ship)
			info.text+="\nHull %.0f · water %.0f L · in %.1f / bail %.1f L/s · repair %.1f cm²/s"%[ship.hp,ship.water,status.inflow,status.bailing,status.repair]

func refill():
	if not host.lab_active:
		host.ui.toast("Repair/refill is available only in the fleet laboratory.")
		return
	for ship in host.battle.ships:
		if ship.sunk:continue
		ship.hp=ship.maxHp;ship.water=0.0;ship.fire=0.0;ship.engine=1.0;ship.breaches=[]
		ship.ammo=float(ship.spec.ammoCapacity);ship.fuel=120.0;ship.supplies=20.0
	host.ui.toast("Laboratory fixtures repaired and resupplied.")

func snapshot():
	var folder=host.save_directory.get_base_dir().path_join("dev-reports")
	DirAccess.make_dir_recursive_absolute(folder)
	var file=FileAccess.open(folder.path_join("snapshot-%d.json"%Time.get_unix_time_from_system()),FileAccess.WRITE)
	if file==null:return
	var report: Dictionary={"version":host.Version.text(),"mode":host.mode,"lab":host.lab_active,"seed":host.lab_seed,"config":host.lab_config,"simulationUs":host.simulation_us}
	if not host.battle.is_empty():
		report["time"]=host.battle.time;report["deployment"]=host.battle.deployment
		report["ships"]=host.battle.ships.duplicate(true)
	file.store_string(JSON.stringify(report,"  "))
	host.ui.toast("Development report saved in dev-reports beside the game.")
