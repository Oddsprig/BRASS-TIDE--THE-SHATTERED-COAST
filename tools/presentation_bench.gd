extends SceneTree
## Actual Main/Chart CPU command-building timings, serialized and headless; no GPU FPS claim.
const Main=preload("res://scripts/main.gd")
const Lab=preload("res://scripts/fleet_lab.gd")
func _initialize():call_deferred("run")
func run():
	var game=Main.new();root.add_child(game)
	await process_frame
	game.lab_config=Lab.preset(game.data,"full_300");game.start_lab()
	Engine.max_fps=0
	var start: int=Time.get_ticks_msec()
	var drawing: Array=[];var simulation: Array=[]
	for i in range(120):
		await process_frame
		drawing.append(game.chart.presentation_us);simulation.append(game.simulation_us)
		if i%30==0:print("PRESENTATION FRAME ",i," elapsed ",Time.get_ticks_msec()-start,"ms draw ",game.chart.presentation_us,"us simulation ",game.simulation_us,"us")
		if Time.get_ticks_msec()-start>15000:push_error("Presentation CPU fixture exceeded15seconds");quit(1);return
	drawing.sort();simulation.sort()
	print("PRESENTATION CPU: 120 Main frames / ",game.battle.ships.size()," boats; draw median ",drawing[60],"us p95 ",drawing[114],"us; simulation p95 ",simulation[114],"us; ",Time.get_ticks_msec()-start,"ms total. No GPU FPS measurement.")
	game.return_to_title();game.queue_free();await process_frame
	quit(0)
