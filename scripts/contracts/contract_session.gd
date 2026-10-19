class_name ContractSession
extends RefCounted
## The live state of one contract: which floor the crew is on, what carries over between floors, and
## the objective bookkeeping that turns events (a gate closed, a floor cleaned, employees extracted)
## into Ledger lines. No scene dependencies, so it is testable without a game running.
##
## Rules (docs/design/contracts.md decisions, ContractRun for the pay table):
##  - everything resets per contract: a new session starts the Ledger over and carries nothing;
##  - within a contract HP and downed state carry from floor to floor (save_carry / apply_carry);
##  - leaving early always works: only met objectives were paid, damage comes out of earnings
##    (capped at the contract value, that part never below $0) -- that is what Ledger.payout() does;
##  - the client is billed Ledger.REVIVAL_FEE for every hero still down at the end (finish(reason, downed)); that fee is
##    not capped or floored, so the net payout can go negative, but only through revival fees;
##  - employees pay only when extracted ($100 each); one left behind pays nothing;
##  - every real play is written to PlayLog (contract start, each floor's time, the end), passively.

const END_CASHED_OUT := "cashed_out"
const END_INCAPACITATED := "incapacitated"
## The meta a crew hero carries: the seat (1-3) it sits in. The carry is keyed by it, because two players may both play Wick.
const CREW_SEAT_META := "crew_seat"

var run: ContractRun
var floor_number := 1
var finished := false
var end_reason := ""
## crew seat (1-3) -> {"hp": float, "dead": bool}; a hero without a seat (tests, the arena) is keyed by its display_name
var carry: Dictionary = {}
## floor -> {gates_total, gates_closed, origin, origin_closed, employees, extracted, lost, pest_spawned, pest_paid}
var floors: Dictionary = {}
## [{name, cause, floor}] employees that died
var lost: Array[Dictionary] = []
var extracted_total := 0
## PlayLog: this contract's id and when (GameWorld.time) the crew arrived on the current floor (-1 = not on one).
var run_id := ""
var _floor_t0 := -1.0


## Who may write each var (see Net). The host runs the contract; `run` is built from the seed.
func net_fields() -> Dictionary:
	return {
		"run": Net.SPAWN,
		"floor_number": Net.OWNER, "finished": Net.OWNER, "end_reason": Net.OWNER,
		"carry": Net.OWNER, "floors": Net.OWNER, "lost": Net.OWNER, "extracted_total": Net.OWNER,
		"run_id": Net.LOCAL, "_floor_t0": Net.LOCAL,   # (PlayLog: each machine logs its own play)
	}


## Start a contract: the Ledger restarts at the contract value, nothing carries over.
static func begin(contract: ContractRun, start_floor: int = 1) -> ContractSession:
	var s := ContractSession.new()
	s.run = contract
	s.floor_number = clampi(start_floor, 1, ContractRun.FLOOR_COUNT)
	Ledger.begin_contract(contract.contract_value)
	Ledger.floor_number = s.floor_number
	s.run_id = "%s-%d" % [Time.get_datetime_string_from_system().replace(":", ""), contract.seed]
	PlayLog.contract_started(s.run_id, contract, s.floor_number)
	return s


## The crew takes the elevator down: the floor it leaves is logged now (PlayLog; the next floor resets the game clock),
## then the floor number moves on. Game calls this, not `floor_number += 1`.
func descend() -> void:
	_log_floor_done("elevator")
	floor_number += 1


## The crew arrives on floor `f` with what the site builder placed there.
func enter_floor(f: int, gates: int, has_origin: bool, employees: int, pest_spawned: int) -> void:
	_log_floor_done("elevator")
	_floor_t0 = GameWorld.time
	floor_number = f
	Ledger.floor_number = f
	floors[f] = {
		"gates_total": gates, "gates_closed": 0,
		"origin": has_origin, "origin_closed": false,
		"employees": employees, "extracted": 0, "lost": 0,
		"pest_spawned": pest_spawned, "pest_paid": false,
	}


func state(f: int = -1) -> Dictionary:
	return floors.get(floor_number if f < 0 else f, {})


# --- HP / downed carry-over --------------------------------------------------------------

## The key a hero's carry is filed under: its crew seat, else (a hero outside the crew) its name.
static func carry_key(hero: Hero) -> Variant:
	return hero.get_meta(CREW_SEAT_META, hero.display_name)


func save_carry(heroes: Array[Hero]) -> void:
	carry.clear()
	for h in heroes:
		if is_instance_valid(h):
			carry[carry_key(h)] = {"hp": h.hp, "dead": h.dead}


## Put a hero back as the previous floor left them: same HP, and downed if they were downed.
## Returns true if the hero is downed.
func apply_carry(hero: Hero) -> bool:
	var key: Variant = carry_key(hero)
	if not carry.has(key):
		return false
	var c: Dictionary = carry[key]
	if bool(c["dead"]):
		hero.hp = 0.0
		hero.die()
		return true
	hero.hp = clampf(float(c["hp"]), 1.0, hero.max_hp)
	hero._refresh_bar()
	return false


## True when `hero` was down as the crew left the previous floor: its body stays behind there (user, 2026-10-18: "in
## co-op they would want to watch, but not have their corpse follow us"), so on this floor it neither rides the
## elevator nor shows. Every machine saves its own carry, so each knows (a puppet's `dead` is replicated).
func carried_down(hero: Hero) -> bool:
	var c: Variant = carry.get(carry_key(hero))
	return c is Dictionary and bool((c as Dictionary).get("dead", false))


# --- Objectives ----------------------------------------------------------------------------

## A hellgate was closed. Pays the small-gate rate, or the origin rate for the origin gate.
## Returns the pay (0 if it was a stray, already-paid or unknown gate).
func gate_closed(origin: bool, who: Node = null) -> int:
	var st := state()
	if st.is_empty():
		return 0
	if origin:
		if not bool(st["origin"]) or bool(st["origin_closed"]):
			return 0
		st["origin_closed"] = true
		Ledger.earn("ORIGIN gate closed", run.origin_pay, who)
		return run.origin_pay
	if int(st["gates_closed"]) >= int(st["gates_total"]):
		return 0
	st["gates_closed"] = int(st["gates_closed"]) + 1
	Ledger.earn("Hellgate closed", run.gate_pay, who)
	return run.gate_pay


func gates_open(f: int = -1) -> int:
	var st := state(f)
	if st.is_empty():
		return 0
	var open: int = int(st["gates_total"]) - int(st["gates_closed"])
	if bool(st["origin"]) and not bool(st["origin_closed"]):
		open += 1
	return open


## A floor is CLEAN when its gates are all closed and no pest-kind monster is left alive on it.
## Call with the current pest count; pays this floor's share of the pest objective once.
## A floor that never had any pest on it pays nothing (nothing to exterminate).
func check_clean(pest_alive: int, who: Node = null) -> int:
	var st := state()
	if st.is_empty() or bool(st["pest_paid"]) or int(st["pest_spawned"]) <= 0:
		return 0
	if pest_alive > 0 or gates_open() > 0:
		return 0
	st["pest_paid"] = true
	var pay: int = int(run.pest_floor_pay[floor_number - 1])
	Ledger.earn("Pest cleared (%s)" % ClientArchetype.pest_name(run.pest), pay, who)
	return pay


func floor_clean(f: int = -1) -> bool:
	var st := state(f)
	return not st.is_empty() and bool(st["pest_paid"])


func employee_lost(emp_name: String, cause: String) -> void:
	var st := state()
	if not st.is_empty():
		st["lost"] = int(st["lost"]) + 1
	lost.append({"name": emp_name, "cause": cause, "floor": floor_number})


## `count` followers rode the elevator out: $100 each (instead of the $10 for being alive).
func extract(count: int, who: Node = null) -> int:
	var paid := 0
	for _i in maxi(0, count):
		Ledger.earn("Employee extracted", ContractRun.EMPLOYEE_EXTRACTED, who)
		paid += ContractRun.EMPLOYEE_EXTRACTED
	var st := state()
	if not st.is_empty():
		st["extracted"] = int(st["extracted"]) + maxi(0, count)
	extracted_total += maxi(0, count)
	return paid


func employees_spawned() -> int:
	var n := 0
	for f in floors:
		n += int(floors[f]["employees"])
	return n


## Employees still alive and not extracted, over every floor visited (an escort elsewhere counts).
func employees_alive() -> int:
	return maxi(0, employees_spawned() - lost.size() - extracted_total)


## Close the contract: bills the revival fee for each hero in `downed_heroes`
## (display names of the heroes still down), stops the Ledger. Idempotent.
func finish(reason: String, downed_heroes: Array[String] = []) -> void:
	if finished:
		return
	finished = true
	end_reason = reason
	for hero_name in downed_heroes:
		Ledger.revival(hero_name)
	Ledger.end_contract()
	_log_floor_done(reason)
	PlayLog.contract_ended(run_id, run, floor_number, reason, extracted_total, lost.size())


## PlayLog: the floor the crew is on is done (it left by the elevator, or the contract ended there).
func _log_floor_done(reason: String) -> void:
	if _floor_t0 < 0.0 or not floors.has(floor_number):
		return
	PlayLog.floor_done(run_id, run, floor_number, GameWorld.time - _floor_t0, reason, floors[floor_number])
	_floor_t0 = -1.0


func payout() -> int:
	return Ledger.payout()


# --- Online (M3): the host keeps the books, a client shows them ----------------------------------------------

## What a client needs to show the objectives as the host has them (NetObjects sends it on every change).
func mirror_state() -> Dictionary:
	return {"floor": floor_number, "state": state().duplicate(), "lost": lost.duplicate(true), "extracted": extracted_total}


## The host's bookkeeping, on a client.
func apply_mirror(d: Dictionary) -> void:
	var f := int(d.get("floor", floor_number))
	var st := d.get("state", {}) as Dictionary
	if not st.is_empty():
		floors[f] = st.duplicate()
	lost.clear()
	for e: Variant in d.get("lost", []) as Array:
		lost.append((e as Dictionary).duplicate())
	extracted_total = int(d.get("extracted", extracted_total))
