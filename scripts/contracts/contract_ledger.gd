extends Node
## Autoload "Ledger": the money record of the current contract. Everything that
## earns or costs money reports here; the invoice reads it.
##
## Payout rule (docs/design/contracts.md): damages are capped at the contract's
## value and come out of earnings; pay never goes below $0.
##   payout = max(0, earned - min(damages, contract_value))

signal changed
signal line_added(line: Dictionary)

## {kind: "earn"|"damage", label, amount (int dollars, positive), who (hero name or ""), floor}
var lines: Array[Dictionary] = []
var contract_value := 0
var floor_number := 1
var active := false


## Who may write each var (see Net). The host owns the money record; everyone else receives it.
func net_fields() -> Dictionary:
	return {
		"lines": Net.OWNER, "contract_value": Net.OWNER, "floor_number": Net.OWNER, "active": Net.OWNER,
	}


func begin_contract(value: int) -> void:
	lines.clear()
	contract_value = maxi(0, value)
	floor_number = 1
	active = true
	changed.emit()


func end_contract() -> void:
	active = false
	changed.emit()


## Money earned (an objective met, an employee extracted, ...).
func earn(label: String, amount: int, who: Node = null) -> void:
	_add("earn", label, amount, who)


## Property damage. `culprit` is whatever caused it (a hero, a monster, or null);
## the invoice names heroes and calls everything else "demons" / "unknown".
func damage(label: String, amount: int, culprit: Node = null) -> void:
	_add("damage", label, amount, culprit)


func earned() -> int:
	return _sum("earn")


func damages() -> int:
	return _sum("damage")


## Damages that actually come off the pay (capped at the contract value).
func deducted() -> int:
	return mini(damages(), contract_value)


func payout() -> int:
	return maxi(0, earned() - deducted())


## Damage per culprit name, for the invoice's blame section.
func damage_by_who() -> Dictionary:
	var out := {}
	for l in lines:
		if l["kind"] == "damage":
			out[l["who"]] = int(out.get(l["who"], 0)) + int(l["amount"])
	return out


static func culprit_name(n: Node) -> String:
	if n == null or not is_instance_valid(n):
		return "unknown"
	var a := n as Actor
	if a == null:
		return "unknown"
	if a.team == GameWorld.TEAM_MONSTERS:
		return "demons"
	return a.display_name


func _add(kind: String, label: String, amount: int, who: Node) -> void:
	if amount <= 0:
		return
	var line := {"kind": kind, "label": label, "amount": amount, "who": culprit_name(who) if who != null else "", "floor": floor_number}
	lines.append(line)
	line_added.emit(line)
	changed.emit()


func _sum(kind: String) -> int:
	var t := 0
	for l in lines:
		if l["kind"] == kind:
			t += int(l["amount"])
	return t
