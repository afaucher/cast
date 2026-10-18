class_name ContractRun
extends RefCounted
## One generated contract (a job card): client, site type, story, pest, difficulty, three floors,
## the paid objectives and the contract value. Pure data; deterministic per (archetype, seed, difficulty).
##
## Pay (docs/design/contracts.md; the base rates are the dispatch standard, the client's pay_scale
## multiplies the first three and everything is rounded to $100):
##   close a small hellgate (floors 1-2) ......... $3,000 each        (GATE_PAY)
##   close the ORIGIN gate (floor 3) ............. $10,000             (ORIGIN_PAY)
##   exterminate the pest ........................ $10,000 in total    (PEST_PAY) -- x1.4 for "everything"
##       paid per floor as that floor becomes clean: 30% / 30% / 40%
##       (clean = every hellgate on the floor closed AND no pest-kind monster left alive on it)
##   employees ................................... $100 each extracted (one left behind pays nothing)
## contract_value = the most the crew could earn = every objective + every employee extracted.
## It is the cap on property damage (payout = max(0, earned - min(damages, contract_value)) - revival_fees; the
## revival fee, $10,000 per hero down at the end, is not capped, see Ledger).

const FLOOR_COUNT := 3
const GATE_PAY := 3000
const ORIGIN_PAY := 10000
const PEST_PAY := 10000
const EVERYTHING_MULT := 1.4
const PEST_SPLIT: Array[float] = [0.3, 0.3, 0.4]   ## share of the pest pay per floor (floor 1, 2, 3)
const EMPLOYEE_EXTRACTED := 100

var seed := 0
var archetype_id := "prepper"
var client_name := ""
var company := ""
var site_type := "bunker"
var difficulty := 0.5                 ## 0..1
var pest := "everything"              ## a MonsterFactory kind or "everything"
var story: Dictionary = {}
var invoice_number := ""
## Small hellgates per floor (index 0 = floor 1). The origin gate is separate (floor FLOOR_COUNT).
var floor_gates: Array[int] = []
var floor_employees: Array[int] = []
var gate_pay := GATE_PAY
var origin_pay := ORIGIN_PAY
var pest_pay := PEST_PAY              ## the total over all floors
var pest_floor_pay: Array[int] = []
## {kind: "gate"|"origin"|"pest", floor: int, pay: int, label: String}
var objectives: Array[Dictionary] = []
var contract_value := 0


## Who may write each var (see Net). Built identically on every machine from (archetype, seed,
## difficulty) by make(), then never written.
func net_fields() -> Dictionary:
	return {
		"seed": Net.SPAWN, "archetype_id": Net.SPAWN, "client_name": Net.SPAWN, "company": Net.SPAWN,
		"site_type": Net.SPAWN, "difficulty": Net.SPAWN, "pest": Net.SPAWN, "story": Net.SPAWN,
		"invoice_number": Net.SPAWN, "floor_gates": Net.SPAWN, "floor_employees": Net.SPAWN,
		"gate_pay": Net.SPAWN, "origin_pay": Net.SPAWN, "pest_pay": Net.SPAWN,
		"pest_floor_pay": Net.SPAWN, "objectives": Net.SPAWN, "contract_value": Net.SPAWN,
	}


static func make(archetype: String, run_seed: int, diff: float) -> ContractRun:
	var r := ContractRun.new()
	if not ClientArchetype.has(archetype):
		archetype = "prepper"
	var d := ClientArchetype.get_data(archetype)
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed * 2654435761 + ClientArchetype.IDS.find(archetype) * 97 + 13
	r.seed = run_seed
	r.archetype_id = archetype
	r.site_type = str(d["site"])
	r.difficulty = clampf(diff, 0.0, 1.0)
	var who := ClientArchetype.roll_name(archetype, rng)
	r.client_name = str(who["name"])
	r.company = str(who["company"])
	r.story = ContractStory.roll(archetype, rng)
	r.pest = _roll_pest(d, rng)
	r.invoice_number = "INV-%05d-%s" % [absi(run_seed) % 100000, archetype.substr(0, 2).to_upper()]
	# Hellgates by difficulty: floor 1 has one (two on a hard job), floor 2 two (three on a very hard one).
	r.floor_gates = [2 if r.difficulty >= 0.5 else 1, 3 if r.difficulty >= 0.75 else 2, 0]
	var emp: Array = d["employees"]
	r.floor_employees = []
	for _f in FLOOR_COUNT:
		r.floor_employees.append(clampi(rng.randi_range(int(emp[0]), int(emp[1])), 2, 4))
	var scale: float = float(d["pay_scale"])
	r.gate_pay = ClientArchetype.round_pay(GATE_PAY * scale)
	r.origin_pay = ClientArchetype.round_pay(ORIGIN_PAY * scale)
	var pest_total: float = PEST_PAY * scale * (EVERYTHING_MULT if r.pest == "everything" else 1.0)
	r.pest_pay = ClientArchetype.round_pay(pest_total)
	r._build_objectives()
	return r


static func _roll_pest(d: Dictionary, rng: RandomNumberGenerator) -> String:
	if rng.randf() < float(d["everything_chance"]):
		return "everything"
	var kinds: Array[String] = []
	for k: String in d["pests"]:
		if k != "everything" and not kinds.has(k):
			kinds.append(k)
	return kinds[rng.randi_range(0, kinds.size() - 1)]


func _build_objectives() -> void:
	objectives.clear()
	pest_floor_pay.clear()
	var paid := 0
	for f in FLOOR_COUNT:
		var share := ClientArchetype.round_pay(pest_pay * PEST_SPLIT[f]) if f < FLOOR_COUNT - 1 else pest_pay - paid
		paid += share
		pest_floor_pay.append(share)
	for f in FLOOR_COUNT:
		for i in floor_gates[f]:
			objectives.append({"kind": "gate", "floor": f + 1, "pay": gate_pay, "label": "Close hellgate (floor %d)" % (f + 1)})
		if f == FLOOR_COUNT - 1:
			objectives.append({"kind": "origin", "floor": f + 1, "pay": origin_pay, "label": "Close the ORIGIN gate (floor %d)" % (f + 1)})
		objectives.append({"kind": "pest", "floor": f + 1, "pay": pest_floor_pay[f], "label": "%s (floor %d)" % [pest_label(), f + 1]})
	contract_value = 0
	for o in objectives:
		contract_value += int(o["pay"])
	contract_value += total_employees() * EMPLOYEE_EXTRACTED


func floor_seed(floor_n: int) -> int:
	if floor_n <= 1:
		return seed
	return (seed * 7919 + floor_n * 104729 + 17) & 0x7fffffff


func total_gates() -> int:
	var n := 0
	for g in floor_gates:
		n += g
	return n


func total_employees() -> int:
	var n := 0
	for e in floor_employees:
		n += e
	return n


func pest_label() -> String:
	if pest == "everything":
		return "Exterminate everything"
	return "Exterminate %s" % ClientArchetype.pest_name(pest)


## 1..5 difficulty stars for the job card.
func difficulty_stars() -> int:
	return clampi(1 + int(floorf(difficulty * 5.0)), 1, 5)


func archetype_title() -> String:
	return ClientArchetype.title_of(archetype_id)


## The objective summary a job card prints: [{label, pay_text, note}], pay in whole dollars (text).
func card_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	lines.append({"label": "Close %d hellgates" % (floor_gates[0] + floor_gates[1]), "pay": gate_pay, "each": true})
	lines.append({"label": "Close the ORIGIN gate", "pay": origin_pay, "each": false})
	lines.append({"label": pest_label(), "pay": pest_pay, "each": false})
	lines.append({"label": "Staff: %d to extract" % total_employees(), "pay": EMPLOYEE_EXTRACTED, "each": true})
	return lines


static func money(amount: int) -> String:
	var neg := amount < 0
	var s := str(absi(amount))
	var out := ""
	var n := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		n += 1
		if n % 3 == 0 and i > 0:
			out = "," + out
	return ("-$" if neg else "$") + out
