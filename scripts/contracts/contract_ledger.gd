extends Node
## Autoload "Ledger": the money record of the current contract. Everything that
## earns or costs money reports here; the invoice reads it.
##
## Payout rule (docs/design/contracts.md): damages are capped at the contract's
## value and come out of earnings, and that part never goes below $0. Then corporate bills the client
## REVIVAL_FEE for every hero still down when the contract ends: not capped, not floored, so the net
## payout can go negative, but only through revival fees.
##   payout = max(0, earned - min(damages, contract_value)) - revival_fees

signal changed
signal line_added(line: Dictionary)

## What corporate bills the client for each crew member who is down when the contract ends.
const REVIVAL_FEE := 10000

## {kind: "earn"|"damage"|"revival", label, amount (int dollars, positive), who (hero name or ""), floor}
var lines: Array[Dictionary] = []
var contract_value := 0
var floor_number := 1
var active := false
## Online, on a client (M3): the host's Ledger is the one; this one only takes the host's lines (mirror_line) and drops
## every local write, so nothing is billed or paid twice. Set by the game for a client's shared run; end_contract clears it.
var mirror := false


## Who may write each var (see Net). The host owns the money record; everyone else receives it.
func net_fields() -> Dictionary:
	return {
		"lines": Net.OWNER, "contract_value": Net.OWNER, "floor_number": Net.OWNER, "active": Net.OWNER,
		"mirror": Net.LOCAL,   # this machine's role (a client mirrors the host's lines: obj.ledger)
	}


func begin_contract(value: int) -> void:
	lines.clear()
	contract_value = maxi(0, value)
	floor_number = 1
	active = true
	changed.emit()


func end_contract() -> void:
	active = false
	mirror = false
	changed.emit()


## A line the host wrote (client, M3: NetObjects, `obj.ledger`).
func mirror_line(line: Dictionary) -> void:
	var l := line.duplicate()
	lines.append(l)
	line_added.emit(l)
	changed.emit()


## Every line the host has written so far, at once (M6: a late joiner's Ledger, from the host's snapshot). Replaces what
## this mirror held (lines that arrived before the snapshot are in it too). No line_added: nothing new was earned.
func mirror_all(all_lines: Array, value: int, floor_n: int) -> void:
	lines.clear()
	for l: Variant in all_lines:
		lines.append((l as Dictionary).duplicate())
	contract_value = maxi(0, value)
	floor_number = floor_n
	active = true
	changed.emit()


## Money earned (an objective met, an employee extracted, ...).
func earn(label: String, amount: int, who: Node = null) -> void:
	_add("earn", label, amount, who)


## Property damage. `culprit` is whatever caused it (a hero, a monster, or null);
## the invoice names heroes and calls everything else "demons" / "unknown".
func damage(label: String, amount: int, culprit: Node = null) -> void:
	_add("damage", label, amount, culprit)


## Corporate revives a hero who is down at the end of the contract; the client is billed. `hero_name` is the
## hero's display name. Not capped by the contract value.
func revival(hero_name: String, amount: int = REVIVAL_FEE) -> void:
	if amount <= 0 or mirror:
		return
	var line := {"kind": "revival", "label": "Revival - %s" % hero_name, "amount": amount, "who": hero_name, "floor": floor_number}
	lines.append(line)
	line_added.emit(line)
	changed.emit()


func earned() -> int:
	return _sum("earn")


func damages() -> int:
	return _sum("damage")


## Damages that actually come off the pay (capped at the contract value).
func deducted() -> int:
	return mini(damages(), contract_value)


## Total revival fees (uncapped).
func revival_fees() -> int:
	return _sum("revival")


## The earned-minus-capped-damages part, which never goes below $0 (revival fees come off after it).
func payout_before_revival() -> int:
	return maxi(0, earned() - deducted())


## Net payout: can be negative, only through revival fees.
func payout() -> int:
	return payout_before_revival() - revival_fees()


## Damage per culprit name, for the invoice's blame section.
func damage_by_who() -> Dictionary:
	var out := {}
	for l in lines:
		if l["kind"] == "damage":
			out[l["who"]] = int(out.get(l["who"], 0)) + int(l["amount"])
	return out


static func culprit_name(n: Node) -> String:
	if n != null and is_instance_valid(n) and n.has_method("blamed"):
		n = n.call("blamed")   # (an explosive prop's blast: whoever set it off)
	if n == null or not is_instance_valid(n):
		return "unknown"
	var a := n as Actor
	if a == null:
		return "unknown"
	if a.team == GameWorld.TEAM_MONSTERS:
		return "demons"
	return a.display_name


func _add(kind: String, label: String, amount: int, who: Node) -> void:
	if amount <= 0 or mirror:
		return   # (a client's Ledger takes the host's lines only)
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
