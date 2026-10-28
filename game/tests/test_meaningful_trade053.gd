extends SceneTree
## Root-run only. One actual Main career; controlled supply fixture, not a profit guarantee.
const Money = preload("res://scripts/money.gd")
var game
var checks: int = 0
var failures: int = 0
var started: int = 0
var finished: bool = false

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL meaningful trade053: " + message)
	return ok

func descendants(node: Node) -> Array:
	var result: Array = [node]
	for child in node.get_children(): result.append_array(descendants(child))
	return result

func visible_text() -> String:
	var result: Array[String] = []
	for node in descendants(game.ui.overlay):
		if (node is Label or node is Button) and node.is_visible_in_tree(): result.append(str(node.text))
	return "\n".join(result)

func press(prefix: String, within: Node = null) -> bool:
	for node in descendants(game.ui.overlay if within == null else within):
		if node is Button and node.is_visible_in_tree() and str(node.text).begins_with(prefix):
			if not check(not node.disabled, "Enabled native control: " + prefix): return false
			node.pressed.emit()
			return true
	check(false, "Native control exists: " + prefix)
	return false

func market_row(good: String):
	for node in descendants(game.ui.overlay):
		if node is Label and str(node.text) == str(game.core.Goods.ITEMS[good].name): return node.get_parent()
	return null

func set_quantity(qty: int) -> bool:
	for node in descendants(game.ui.overlay):
		if node is SpinBox:
			node.value = qty
			return check(game.ui.trade_qty == qty, "Native quantity signal selects %d real lots" % qty)
	return check(false, "Market has its existing quantity control")

func move_logs(source: Dictionary, destination: Dictionary) -> void:
	# Controlled scarcity moves finite stock between actual harbors; no minting.
	destination.stocks.logs = float(destination.stocks.logs) + float(source.stocks.logs)
	source.stocks.logs = 0.0

func exercise() -> void:
	var c = game.core
	var origin: String = str(c.current_port().id)
	var destination: String = "sawtooth_mill"
	var supply: int = Money.total(c.state)
	game.ui.open_port("Market")
	if not press("Trade opportunities"): return
	check(game.ui.modal_kind == "trade_intel" and "Visit another harbor" in visible_text(), "Market entry opens the useful no-remote-quotes state")
	if not press("Return to Market"): return
	# A seeded past-visit quote and controlled missing input isolate the supply
	# consequence. The purchase, current voyage, sale and paid day are real APIs.
	move_logs(c.port(destination), c.port(origin))
	c.TradeIntel.observe(c.state, c.port(destination), floori(float(c.state.day)))
	game.ui.open_port("Market")
	var frozen: String = JSON.stringify(c.state)
	if not press("Trade opportunities"): return
	check(game.ui.modal_kind == "trade_intel" and JSON.stringify(c.state) == frozen, "Comparing dated opportunities spends nothing and preserves the career")
	check("nominal net" in visible_text() and "conservative net" in visible_text(), "Actual trade chart separates nominal and conservative estimates")
	if not press("Costs, price uncertainty & quantity limits"): return
	var offer: Dictionary = c.TradeIntel.opportunities(c)[0]
	var quantity_text: String = "Saleable aboard %d" % int(offer.localStockLimit) if offer.mode == "carried" else "Quantity limits: " + str(offer.quantityLimitReason)
	check(quantity_text in visible_text() and ("recorded buyer limit %d lots" % int(offer.buyerLiquidity)) in visible_text(), "Expanded native quantity explanation matches actual aboard/local bounds and the dated finite buyer limit")
	for text in ["Funding before departure", "Allowance:", "not a probability"]:
		check(text in visible_text(), "Expanded native estimate explains " + text)
	frozen = JSON.stringify(c.state)
	if not press("Select Sawtooth Mill & review voyage"): return
	check(game.ui.modal_kind == "expedition" and game.selected_port == destination, "Review signal selects the real destination and opens existing preparation")
	check(JSON.stringify(c.state) == frozen, "Review neither buys, loads fuel, charts nor departs")
	game.ui.open_port("Market")
	if not set_quantity(3): return
	var line = market_row("logs")
	if not check(line != null and c.cargo_weight() + 9.0 <= c.capacity(), "Finite logs fit the actual traveling hold with current food"): return
	var captain: int = int(c.state.coins)
	var business: int = int(c.port(origin).cash)
	var stock: float = float(c.port(origin).stocks.logs)
	var carried: float = float(c.state.cargo.logs)
	var price: int = c.Economy.price(c.port(origin), "logs", "buy")
	var fuel: float = float(c.state.fleet[0].fuel)
	if not press("Buy ", line): return
	if not check(float(c.state.cargo.logs) == carried + 3.0, "Native Buy purchases exactly three physical input lots"): return
	check(int(c.state.coins) == captain - price * 3 and int(c.port(origin).cash) == business + price * 3, "Purchase pays the real stock-derived price into the actual seller purse")
	check(float(c.port(origin).stocks.logs) == stock - 3.0 and Money.total(c.state) == supply, "Purchase consumes finite origin stock and conserves all purses")
	check(float(c.state.fleet[0].fuel) == fuel, "Buying cargo gives no free working fuel")
	game.ui.CampaignUI.expedition(game.ui)
	if not press("Chart course to Sawtooth Mill"): return
	if not check(not c.state.path.is_empty(), "Explicit sail action creates a real navigable water route"): return
	var departure: Dictionary = c.state.position.duplicate()
	var steps: int = 0
	while not c.state.path.is_empty() and steps < 240:
		c.step(0.25)
		steps += 1
		if steps % 16 == 0:
			await process_frame
			if finished: return
	game.sync_economy()
	if not check(c.state.path.is_empty() and c.current_port().get("id", "") == destination, "Actual Campaign movement arrives at the chosen market within a bounded voyage"): return
	check(c.distance(departure, c.state.position) > 100.0 and float(c.state.fleet[0].fuel) < fuel, "Delivery travels the chart and consumes that boat's loaded fuel")
	check(Money.total(c.state) == supply and int(c.state.fleet[0].crew) == int(game.data.START.crew), "Voyage preserves real sailors and the global coin supply")
	# Re-establish the disclosed shortage if an actual economy day elapsed at sea.
	move_logs(c.port(destination), c.port(origin))
	var unsupplied: Dictionary = c.port(destination).duplicate(true)
	var control_total: int = Money.port_total(unsupplied)
	c.Economy.tick_ports([unsupplied], 1.0, {"interport_trade": false})
	check(float(unsupplied.lastProduction.timber) == 0.0 and Money.port_total(unsupplied) == control_total, "Same actual paid recipe cannot make timber without opening logs; detached control conserves its purses")
	game.ui.open_port("Market")
	if not press("Local input needs & supply consequences"): return
	var local_need: Dictionary = c.TradeIntel.report(c, destination).needs.logs
	check(float(local_need.observedNeed) > 0.0 and "local stock gap" in visible_text() and str(local_need.needPurpose) in visible_text() and "paid labor" in visible_text(), "Expanded destination Market presents its current dated input need, real recipe purpose and paid supply consequence")
	# The legal public transaction path must refuse a buyer with no funds.
	var buyer: Dictionary = c.port(destination)
	var buyer_cash: int = int(buyer.cash)
	if not check(Money.move(buyer, "cash", buyer, "governmentPurse", buyer_cash), "Fixture temporarily escrows the finite buyer purse"): return
	frozen = JSON.stringify(c.state)
	check(not c.trade(destination, "logs", 3, "sell").ok and JSON.stringify(c.state) == frozen, "An unfunded real buyer cannot take goods or create sale proceeds")
	if not check(Money.move(buyer, "governmentPurse", buyer, "cash", buyer_cash), "Fixture restores exactly the same buyer coins"): return
	game.ui.open_port("Market")
	if not set_quantity(3): return
	line = market_row("logs")
	if not check(line != null, "Actual destination Market offers the existing Sell control"): return
	captain = int(c.state.coins); business = int(buyer.cash)
	carried = float(c.state.cargo.logs)
	price = c.Economy.price(buyer, "logs", "sell")
	if not press("Sell ", line): return
	if not check(float(c.state.cargo.logs) == carried - 3.0 and float(buyer.stocks.logs) == 3.0, "Native Sell delivers exactly the purchased logs into the working inventory"): return
	check(int(c.state.coins) == captain + price * 3 and int(buyer.cash) == business - price * 3 and Money.total(c.state) == supply, "Sale is paid at the current price by the actual finite buyer purse")
	var wages: int = int(c.Economy.daily_upkeep(c.state.fleet).wages)
	var food: float = float(c.state.cargo.food)
	var crew_purse: int = int(c.state.crewPurse)
	if not press("Wait one day"): return
	buyer = c.port(destination)
	check(float(buyer.lastProduction.timber) > 0.0 and float(buyer.lastProduction.timber) <= 3.001, "Delivered opening logs enable actual paid timber production bounded by those input lots")
	check(int(buyer.lastPayroll.business) > 0 and int(buyer.lastPayroll.byOccupation.get("carpenter", 0)) > 0, "This actual harbor production day pays finite business and carpenter payroll")
	check(int(c.state.crewPurse) == crew_purse + wages - mini(crew_purse + wages, c.crew_count() * 12), "Real waiting day pays the existing sailors and accounts for their shore spending")
	check(float(c.state.cargo.food) < food and int(c.state.wageArrears) == 0 and Money.total(c.state) == supply, "Production day consumes real rations, pays upkeep and conserves every global purse")
	print("meaningful trade053 controlled supply fixture: paid logs delivery enables timber; cost projections remain estimates")

func _initialize() -> void:
	started = Time.get_ticks_msec()
	call_deferred("run")

func _process(_delta: float) -> bool:
	# Root also supplies an external 25s process cap for synchronous native stalls.
	if not finished and Time.get_ticks_msec() - started >= 20000:
		check(false, "Cooperative 20s fixture deadline exceeded")
		finish()
	return false

func run() -> void:
	if not check(DisplayServer.get_name() == "headless", "Root supplies headless, muted Dummy audio and synthetic APPDATA"):
		finish(); return
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false); game.set_physics_process(false)
	game.audio.enabled = false; game.music.enabled = false
	game.save_directory = OS.get_user_data_dir().path_join("meaningful-trade053-%d" % Time.get_ticks_usec())
	await process_frame
	if finished: return
	game.new_game(); game.paused = true
	if check(not game.core.state.is_empty() and game.mode == "campaign", "Actual Main starts its own isolated career"):
		await exercise()
	if finished: return
	if is_instance_valid(game): game.queue_free()
	await process_frame
	if not finished: finish()

func finish() -> void:
	if finished: return
	if failures == 0: check(Time.get_ticks_msec() - started < 20000, "Fixture completes inside its cooperative 20s deadline")
	finished = true
	if is_instance_valid(game) and not game.is_queued_for_deletion(): game.queue_free()
	print("meaningful trade053: %d checks, %d failures, %dms; native controls, controlled supply fixture" % [checks, failures, Time.get_ticks_msec() - started])
	quit(0 if failures == 0 else 1)
