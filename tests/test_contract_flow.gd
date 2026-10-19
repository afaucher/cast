extends TestCase
## The contract flow's rules: the job board, a contract's shape, HP/downed carry-over between floors and
## the reset between contracts, early cash-out pay (met objectives only, damages capped, never negative),
## extraction pay ($100 per follower, $10 per employee left alive), and the invoice matching the Ledger.


func setup() -> void:
	_check_board()
	_check_run_shape()
	await _check_carry_over()
	_check_cash_out_early()
	_check_pest_and_gates()
	_check_extraction()
	_check_invoice_matches_ledger()
	_check_incapacitated()
	_check_revival()
	_check_stars_and_text()
	finish()


# --- job board ---------------------------------------------------------------------------------

func _check_board() -> void:
	for board_seed in [0, 1, 7, 42, 99, 1234, 31337]:
		var offers := ContractBoard.offers(board_seed)
		eq(offers.size(), 3, "the board always offers 3 contracts (seed %d)" % board_seed)
		var ids := {}
		var seeds := {}
		var lo := 1.0
		var hi := 0.0
		for o in offers:
			ids[o.archetype_id] = true
			seeds[o.seed] = true
			lo = minf(lo, o.difficulty)
			hi = maxf(hi, o.difficulty)
		eq(ids.size(), 3, "3 distinct clients (seed %d)" % board_seed)
		eq(seeds.size(), 3, "3 distinct contract seeds (seed %d)" % board_seed)
		check(hi - lo >= 0.3, "a spread of difficulty (%.2f..%.2f)" % [lo, hi])
		var again := ContractBoard.offers(board_seed)
		for i in 3:
			eq(again[i].client_name, offers[i].client_name, "the board is deterministic per seed")
	check(ContractBoard.offers(1)[0].seed != ContractBoard.offers(2)[0].seed, "a new board gives new offers")
	var r := ContractBoard.run_for_seed(8075)
	eq(r.floor_seed(1), 8075, "--contract <seed>: floor 1 is exactly that dungeon seed")


func _check_run_shape() -> void:
	for run in ContractBoard.offers(3):
		eq(ContractRun.FLOOR_COUNT, 3, "3 floors")
		eq(run.floor_gates.size(), 3, "gate counts for 3 floors")
		eq(run.floor_employees.size(), 3, "staff counts for 3 floors")
		var kinds := {}
		for o in run.objectives:
			kinds[o["kind"]] = true
		check(kinds.has("gate") and kinds.has("origin") and kinds.has("pest"), "gates, the origin gate and the pest are objectives")
		check(run.contract_value > run.origin_pay, "the contract is worth more than its biggest line")
		check(run.pest == "everything" or MonsterFactory.KINDS.has(run.pest), "the pest is a kind or everything")
		check(str(run.story["event"]) != "" and str(run.story["origin"]) != "", "the story has an event and an origin room")
	var base := ContractRun.make("prepper", 11, 0.5)
	eq(base.gate_pay, 3000, "a prepper pays the standard $3,000 per gate")
	eq(base.origin_pay, 10000, "the origin gate is $10,000")
	check(ContractRun.make("founder", 11, 0.5).gate_pay > base.gate_pay, "a tech founder pays more per gate")
	check(ContractRun.make("guru", 11, 0.5).gate_pay < base.gate_pay, "a guru pays less per gate")
	var easy := ContractRun.make("prepper", 11, 0.1)
	var hard := ContractRun.make("prepper", 11, 0.9)
	check(hard.total_gates() > easy.total_gates(), "a harder job has more hellgates")


# --- HP / downed carry-over ------------------------------------------------------------------------

func _check_carry_over() -> void:
	var run := ContractRun.make("prepper", 5, 0.5)
	var session := ContractSession.begin(run)
	var map := DungeonGen.generate(run.floor_seed(1))
	var world := Node3D.new()
	add_child(world)
	GameWorld.begin(map, world, 1)
	var start: Vector2i = map.cells_with_tag("start")[0]
	var heroes: Array[Hero] = [
		HeroFactory.spawn_hero(start, "Wick", Color.BLUE, "sword", null, HeroKit.WICK),
		HeroFactory.spawn_hero(start + Vector2i(1, 0), "Rebar", Color.ORANGE, "sword", null, HeroKit.REBAR),
		HeroFactory.spawn_hero(start + Vector2i(0, 1), "Gasket", Color.PURPLE, "sword", null, HeroKit.GASKET),
	]
	heroes[0].hp = 41.0
	heroes[1].apply_damage(9999.0)    # downed
	check(heroes[1].dead, "Rebar is downed")
	session.save_carry(heroes)
	session.floor_number = 2
	await frames(1)
	GameWorld.end()
	world.queue_free()
	await frames(2)

	# Floor 2: fresh heroes (the scene was rebuilt) get what floor 1 left them with.
	var map2 := DungeonGen.generate(run.floor_seed(2))
	var world2 := Node3D.new()
	add_child(world2)
	GameWorld.begin(map2, world2, 2)
	var s2: Vector2i = map2.cells_with_tag("start")[0]
	var fresh: Array[Hero] = [
		HeroFactory.spawn_hero(s2, "Wick", Color.BLUE, "sword", null, HeroKit.WICK),
		HeroFactory.spawn_hero(s2 + Vector2i(1, 0), "Rebar", Color.ORANGE, "sword", null, HeroKit.REBAR),
		HeroFactory.spawn_hero(s2 + Vector2i(0, 1), "Gasket", Color.PURPLE, "sword", null, HeroKit.GASKET),
	]
	near(fresh[0].hp, fresh[0].max_hp, 0.01, "a new floor's hero starts at full HP before the carry is applied")
	for h in fresh:
		session.apply_carry(h)
	near(fresh[0].hp, 41.0, 0.01, "Wick keeps his HP on the next floor")
	check(fresh[1].dead, "a hero downed on floor 1 arrives downed on floor 2")
	near(fresh[2].hp, fresh[2].max_hp, 0.01, "an untouched hero is still at full HP")
	check(not fresh[2].dead, "and still up")

	# A new contract resets everything: nothing carries, the Ledger starts over.
	Ledger.earn("Hellgate closed", 3000)
	Ledger.damage("Vase", 500)
	var next_run := ContractRun.make("guru", 6, 0.3)
	var next_session := ContractSession.begin(next_run)
	eq(next_session.floor_number, 1, "a new contract starts on floor 1")
	check(next_session.carry.is_empty(), "nothing carries into a new contract")
	eq(Ledger.lines.size(), 0, "the Ledger starts over")
	eq(Ledger.contract_value, next_run.contract_value, "the Ledger knows the new contract's value")
	var restart: Array[Hero] = [HeroFactory.spawn_hero(s2, "Wick", Color.BLUE, "sword", null, HeroKit.WICK)]
	check(not next_session.apply_carry(restart[0]) and is_equal_approx(restart[0].hp, restart[0].max_hp), "heroes of a new contract are healthy")
	GameWorld.end()
	world2.queue_free()
	await frames(1)


# --- pay rules ---------------------------------------------------------------------------------------

func _check_cash_out_early() -> void:
	var run := ContractRun.make("prepper", 21, 0.5)
	var s := ContractSession.begin(run)
	s.enter_floor(1, 2, false, 3, 10)
	s.gate_closed(false)                       # one of two gates on floor 1
	eq(Ledger.earned(), run.gate_pay, "a closed gate pays the gate rate")
	# Unmet objectives pay nothing: no pest pay, no second gate, no origin.
	s.finish(ContractSession.END_CASHED_OUT)
	eq(Ledger.earned(), run.gate_pay, "leaving early pays only the met objective (staff left behind pay nothing)")
	eq(Ledger.payout(), run.gate_pay, "no damage, no deduction")

	# Damage comes out of earnings, capped at the contract value, never below $0.
	var run2 := ContractRun.make("prepper", 22, 0.5)
	var s2 := ContractSession.begin(run2)
	s2.enter_floor(1, 2, false, 2, 10)
	s2.gate_closed(false)
	Ledger.damage("Gold toilet", 1000)
	eq(Ledger.payout(), run2.gate_pay - 1000, "damage is deducted from earnings")
	Ledger.damage("Zen fountain", run2.contract_value * 3)
	eq(Ledger.deducted(), run2.contract_value, "damage is capped at the contract value")
	s2.finish(ContractSession.END_CASHED_OUT)
	eq(Ledger.payout(), 0, "property damage alone never takes the pay below $0")

	# Leaving at once with nothing done: $0, not negative, even with damage.
	var s3 := ContractSession.begin(ContractRun.make("founder", 23, 0.4))
	s3.enter_floor(1, 1, false, 2, 10)
	Ledger.damage("Server rack", 3000)
	s3.finish(ContractSession.END_CASHED_OUT)
	eq(Ledger.payout(), 0, "cashing out with only damage pays $0")


func _check_pest_and_gates() -> void:
	var run := ContractRun.make("supervillain", 31, 0.8)
	run.pest = "swarmer"
	var s := ContractSession.begin(run)
	s.enter_floor(1, 2, false, 2, 12)
	# A floor is clean only when every gate is closed AND no pest-kind monster is left.
	eq(s.check_clean(0), 0, "not clean while a gate is open")
	s.gate_closed(false)
	eq(s.check_clean(0), 0, "not clean while the second gate is open")
	s.gate_closed(false)
	eq(s.gates_open(), 0, "both gates closed")
	eq(s.check_clean(3), 0, "not clean while pests remain")
	var pay := s.check_clean(0)
	eq(pay, run.pest_floor_pay[0], "a clean floor pays its share of the pest objective")
	eq(s.check_clean(0), 0, "and only once")
	eq(s.gate_closed(false), 0, "a stray third gate does not pay")
	# Floor 3 needs the origin gate too.
	s.enter_floor(3, 0, true, 2, 20)
	eq(s.check_clean(0), 0, "floor 3 is not clean while the origin gate is open")
	eq(s.gate_closed(true), run.origin_pay, "the origin gate pays the origin rate")
	eq(s.gate_closed(true), 0, "the origin gate pays once")
	eq(s.check_clean(0), run.pest_floor_pay[2], "floor 3 is clean once the origin gate is closed and the pests are gone")
	var gates_and_pest := 2 * run.gate_pay + run.origin_pay + run.pest_floor_pay[0] + run.pest_floor_pay[2]
	eq(Ledger.earned(), gates_and_pest, "the Ledger holds exactly the met objectives")
	# A floor that never held a pest pays nothing (nothing to exterminate).
	s.enter_floor(2, 1, false, 2, 0)
	s.gate_closed(false)
	eq(s.check_clean(0), 0, "a floor with no pests has no pest bonus")


func _check_extraction() -> void:
	var run := ContractRun.make("influencer", 41, 0.5)
	var s := ContractSession.begin(run)
	s.enter_floor(1, 1, false, 4, 10)
	eq(s.employees_alive(), 4, "four employees on the floor")
	var paid := s.extract(3)
	eq(paid, 300, "extraction pays $100 per follower")
	eq(Ledger.earned(), 300, "and the Ledger agrees")
	eq(s.employees_alive(), 1, "extracted employees are no longer 'alive on site'")
	s.employee_lost("Pearl (valet)", "Rebar")
	eq(s.employees_alive(), 0, "a lost employee is not alive")
	eq(s.lost.size(), 1, "the loss is recorded with its cause")
	s.finish(ContractSession.END_CASHED_OUT)
	eq(Ledger.earned(), 300, "an employee lost pays nothing, extracted ones paid $100 and none are left to pay $10")

	# Employees left behind on an earlier floor still count as alive at the end.
	var s2 := ContractSession.begin(ContractRun.make("influencer", 42, 0.5))
	s2.enter_floor(1, 1, false, 3, 10)
	s2.extract(1)
	s2.enter_floor(2, 1, false, 2, 10)
	eq(s2.employees_alive(), 4, "an escort elsewhere counts as alive")
	s2.finish(ContractSession.END_CASHED_OUT)
	eq(Ledger.earned(), 100, "$100 for the extracted one, nothing for the four left behind")
	s2.finish(ContractSession.END_CASHED_OUT)
	eq(Ledger.earned(), 100, "finishing twice pays once")


# --- the invoice -------------------------------------------------------------------------------------------

func _check_invoice_matches_ledger() -> void:
	var run := ContractRun.make("guru", 51, 0.6)
	var s := ContractSession.begin(run)
	s.enter_floor(1, 2, false, 3, 10)
	s.gate_closed(false)
	s.gate_closed(false)
	s.check_clean(0)
	s.extract(2)
	Ledger.damage("Zen fountain", 900)
	Ledger.damage("Crystal lamp", 600)
	Ledger.damage("Crystal lamp", 600)
	s.enter_floor(2, 1, false, 3, 10)
	s.gate_closed(false)
	s.finish(ContractSession.END_CASHED_OUT)
	var inv := ContractInvoice.build(s)
	eq(int(inv["earned"]), Ledger.earned(), "the invoice's earned total is the Ledger's")
	eq(int(inv["payout"]), Ledger.payout(), "the invoice's net payout is the Ledger's payout")
	eq(int(inv["damages"]), 2100, "the damages line adds up")
	var floors_sum := 0
	for sec: Dictionary in inv["floors"]:
		var sub := 0
		for r: Dictionary in sec["rows"]:
			sub += int(r["amount"])
		eq(sub, int(sec["subtotal"]), "each floor's rows add up to its subtotal")
		floors_sum += sub
	eq(floors_sum, int(inv["earned"]), "the floor sections add up to the earned total")
	var ded_sum := 0
	for d: Dictionary in inv["deductions"]:
		ded_sum += int(d["amount"])
	eq(ded_sum, int(inv["damages"]), "the itemised deductions add up to the damages")
	eq(int(inv["earned"]) - int(inv["deducted"]), int(inv["payout"]), "earned - deducted = net payout")
	eq(inv["capped"], false, "damage below the contract value is not capped")
	var crystal := 0
	for d: Dictionary in inv["deductions"]:
		if d["label"] == "Crystal lamp":
			crystal = int(d["qty"])
	eq(crystal, 2, "identical damage lines are grouped with a quantity")

	# Capped: the deduction stops at the contract value and the net payout is $0.
	var run2 := ContractRun.make("prepper", 52, 0.5)
	var s2 := ContractSession.begin(run2)
	s2.enter_floor(1, 1, false, 2, 10)
	s2.gate_closed(false)
	Ledger.damage("Gold toilet", run2.contract_value + 5000)
	s2.finish(ContractSession.END_CASHED_OUT)
	var inv2 := ContractInvoice.build(s2)
	eq(inv2["capped"], true, "damage over the contract value is capped on the invoice")
	eq(int(inv2["deducted"]), run2.contract_value, "the deduction is the contract value")
	eq(int(inv2["payout"]), 0, "net payout $0")
	eq(int(inv2["payout"]), Ledger.payout(), "and it still matches the Ledger")
	check(int(inv2["damages"]) > int(inv2["deducted"]), "the invoice shows the uncapped damage too")

	# Blame is per hero (a real hero actor named in the line).
	var hero := Actor.new()
	hero.display_name = "Wick"
	var s3 := ContractSession.begin(ContractRun.make("prepper", 53, 0.5))
	s3.enter_floor(1, 1, false, 2, 10)
	Ledger.damage("Wine rack", 1200, hero)
	s3.finish(ContractSession.END_CASHED_OUT)
	var inv3 := ContractInvoice.build(s3)
	eq(str((inv3["blame"] as Array)[0]["who"]), "Wick", "the invoice names the culprit")
	eq(str((inv3["deductions"] as Array)[0]["who"]), "Wick", "and the itemised line carries it")
	hero.free()


func _check_incapacitated() -> void:
	var run := ContractRun.make("supervillain", 61, 0.7)
	var s := ContractSession.begin(run)
	s.enter_floor(1, 2, false, 3, 10)
	s.gate_closed(false)
	Ledger.damage("Throne", 500)
	s.finish(ContractSession.END_INCAPACITATED)
	var inv := ContractInvoice.build(s)
	eq(str(inv["reason"]), ContractSession.END_INCAPACITATED, "the invoice says why the contract ended")
	eq(int(inv["stars"]), 1, "an incapacitated crew gets one star")
	eq(str(inv["footer"]), str(ClientArchetype.get_data("supervillain")["footers"]["incap"]), "and the client's incapacitated footer")
	eq(int(inv["earned"]), run.gate_pay, "it still shows what was earned so far")
	eq(int(inv["payout"]), run.gate_pay - 500, "minus the damage")


## Corporate revives every hero still down at the end and bills the client $10,000 each, uncapped.
func _check_revival() -> void:
	# An incapacitated ending: all three heroes down.
	var run := ContractRun.make("supervillain", 62, 0.7)
	var s := ContractSession.begin(run)
	s.enter_floor(1, 2, false, 3, 10)
	s.gate_closed(false)
	Ledger.damage("Throne", 500)
	s.finish(ContractSession.END_INCAPACITATED, ["Wick", "Rebar", "Gasket"])
	var inv := ContractInvoice.build(s)
	eq(int(inv["revival_fees"]), 3 * Ledger.REVIVAL_FEE, "an incapacitated ending bills 3 x $10,000")
	eq((inv["revivals"] as Array).size(), 3, "one revival row per downed hero")
	eq(str((inv["revivals"] as Array)[0]["who"]), "Wick", "named")
	eq(int(inv["payout"]), run.gate_pay - 500 - 30000, "payout = earned - damage - revival fees")
	check(int(inv["payout"]) < 0, "so the net payout is negative")
	eq(int(inv["payout"]), Ledger.payout(), "and it matches the Ledger")
	eq(int(inv["stars"]), 1, "one star")

	# A cash-out with one ally down.
	var run2 := ContractRun.make("prepper", 63, 0.5)
	var s2 := ContractSession.begin(run2)
	s2.enter_floor(1, 2, false, 3, 10)
	s2.gate_closed(false)
	s2.finish(ContractSession.END_CASHED_OUT, ["Gasket"])
	var inv2 := ContractInvoice.build(s2)
	eq(int(inv2["revival_fees"]), 10000, "a cash-out with one ally down bills $10,000")
	eq((inv2["revivals"] as Array).size(), 1, "one revival row")
	eq(int(inv2["payout"]), run2.gate_pay - 10000, "payout = earned - $10,000")

	# Nobody down: no fee, no rows, and the pay is unchanged.
	var s3 := ContractSession.begin(ContractRun.make("prepper", 64, 0.5))
	s3.enter_floor(1, 1, false, 2, 10)
	s3.finish(ContractSession.END_CASHED_OUT)
	var inv3 := ContractInvoice.build(s3)
	eq(int(inv3["revival_fees"]), 0, "nobody down: no revival fee")
	check((inv3["revivals"] as Array).is_empty(), "and no revival rows")

	# Finishing twice bills once; revival fees are not capped by the contract value.
	var run4 := ContractRun.make("prepper", 65, 0.5)
	var s4 := ContractSession.begin(run4)
	s4.enter_floor(1, 1, false, 2, 10)
	Ledger.damage("Gold toilet", run4.contract_value * 2)
	s4.finish(ContractSession.END_INCAPACITATED, ["Wick", "Rebar", "Gasket"])
	s4.finish(ContractSession.END_INCAPACITATED, ["Wick", "Rebar", "Gasket"])
	eq(Ledger.revival_fees(), 30000, "finishing twice bills once")
	eq(Ledger.deducted(), run4.contract_value, "damages are still capped at the contract value")
	eq(Ledger.payout(), -30000, "damages floor the pay at $0, then the revival fees come off in full")


func _check_stars_and_text() -> void:
	eq(ContractInvoice.stars_for(0, 10000, ContractSession.END_CASHED_OUT), 1, "no money, one star")
	eq(ContractInvoice.stars_for(4000, 10000, ContractSession.END_CASHED_OUT), 2, "a third of the value, two stars")
	eq(ContractInvoice.stars_for(9000, 10000, ContractSession.END_CASHED_OUT), 3, "most of the value, three stars")
	eq(ContractInvoice.stars_for(9000, 10000, ContractSession.END_INCAPACITATED), 1, "a wiped crew is one star")
	eq(ContractRun.money(1234567), "$1,234,567", "money formatting")
	eq(ContractRun.money(-1200), "-$1,200", "negative money")
	eq(ContractRun.money(0), "$0", "zero")
	# The text of the generated clients is deadpan corporate: no diner, kitchen or corn flavour in the tables.
	var blob := str(ClientArchetype.DATA).to_lower()
	for banned in ["diner", "kitchen", "bookshelf", " corn"]:
		check(not blob.contains(banned), "no '%s' in the client tables" % banned)
