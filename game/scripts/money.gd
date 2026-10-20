extends RefCounted
## Integer bronze cash transfers. Debt and unpaid wages are liabilities, not coins.

static func move(source: Dictionary, source_key: String, destination: Dictionary, destination_key: String, amount: int, reason: String = "", ledger: Array = []) -> bool:
	if amount < 0 or source.get(source_key, 0) < amount:
		return false
	if is_same(source, destination) and source_key == destination_key:
		return true
	source[source_key] = int(source.get(source_key, 0)) - amount
	destination[destination_key] = int(destination.get(destination_key, 0)) + amount
	if amount > 0 and not reason.is_empty():
		ledger.push_front({"reason":reason,"cash":amount,"from":source_key,"to":destination_key})
		if ledger.size() > 60:
			ledger.resize(60)
	return true

static func port_total(port: Dictionary) -> int:
	var amount: int = 0
	for key in ["cash", "householdPurse", "expertPurse", "governmentPurse"]:
		amount += int(port.get(key, 0))
	for order in port.get("buildQueue", []):
		amount += int(order.get("escrow", 0))
	return amount

static func total(state: Dictionary) -> int:
	var amount: int = int(state.get("coins", 0)) + int(state.get("crewPurse", 0))
	for port in state.get("ports", []):
		amount += port_total(port)
	for owner in state.get("fleetOwners", []):
		amount += int(owner.get("coins", 0)) + int(owner.get("crewPurse", 0))
	amount += int(state.get("activeContract", {}).get("escrow", 0))
	return amount
