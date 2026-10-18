extends TestCase
## FORM 99 never needs scrolling: InvoiceScreen.fit_rows folds long invoices (each floor's earned lines into one
## row, then the damages into one row per culprit) without changing any total.


func setup() -> void:
	# A short invoice is left alone.
	var short_floors := [_floor(1, 3), _floor(2, 2)]
	var short_ded := [_ded("Wine rack", "Wick", 1200), _ded("Gold toilet", "Gasket", 15000)]
	var f := InvoiceScreen.fit_rows(short_floors, short_ded)
	eq((f["floors"] as Array), short_floors, "short: floors untouched")
	eq((f["deductions"] as Array), short_ded, "short: damages untouched")

	# The worst case: 3 floors x 5 kinds of line, 5 damage rows.
	var floors := [_floor(1, 5), _floor(2, 5), _floor(3, 5)]
	var ded := [_ded("Gold toilet", "Gasket", 15000), _ded("Wine rack", "Wick", 1200), _ded("Zen fountain", "Rebar", 900),
			_ded("Crystal lamp", "Wick", 600), _ded("3 other items", "various", 700)]
	f = InvoiceScreen.fit_rows(floors, ded)
	var out_floors: Array = f["floors"]
	var out_ded: Array = f["deductions"]
	eq(out_floors.size(), 3, "one section per floor")
	for sec: Dictionary in out_floors:
		eq((sec["rows"] as Array).size(), 1, "floor %d folded into one row" % int(sec["floor"]))
	eq(_earned(out_floors), _earned(floors), "earned total unchanged")
	check(3 + out_ded.size() <= InvoiceScreen.ROW_BUDGET, "fits the budget (%d rows)" % (3 + out_ded.size()))

	# Still too long: damages fold per culprit, biggest first, total unchanged.
	f = InvoiceScreen.fit_rows(floors, ded, 6)
	out_ded = f["deductions"]
	eq(out_ded.size(), 4, "one damage row per culprit (Gasket, Wick, Rebar, various)")
	eq(str(out_ded[0]["who"]), "Gasket", "biggest culprit first")
	eq(int(out_ded[1]["amount"]), 1800, "Wick's two items summed")
	eq(int(out_ded[1]["qty"]), 2, "Wick's item count")
	eq(_damages(out_ded), _damages(ded), "damage total unchanged")

	# The crew revival section (header + 3 rows) never folds, but it makes the earned / damage rows fold sooner.
	f = InvoiceScreen.fit_rows(short_floors, short_ded, InvoiceScreen.ROW_BUDGET, 4)
	eq((f["floors"] as Array), short_floors, "short + revivals: floors untouched")
	f = InvoiceScreen.fit_rows(floors, ded, InvoiceScreen.ROW_BUDGET, 4)
	out_floors = f["floors"]
	out_ded = f["deductions"]
	for sec: Dictionary in out_floors:
		eq((sec["rows"] as Array).size(), 1, "revivals: floor %d folded" % int(sec["floor"]))
	eq(_earned(out_floors), _earned(floors), "revivals: earned total unchanged")
	check(out_floors.size() + out_ded.size() + 4 <= InvoiceScreen.ROW_BUDGET, "earned + damage + 4 revival rows fit the budget (%d)" % (out_floors.size() + out_ded.size() + 4))
	eq(_damages(out_ded), _damages(ded), "revivals: damage total unchanged")
	finish()


func _floor(n: int, kinds: int) -> Dictionary:
	var rows: Array = []
	for i in kinds:
		rows.append({"label": "Line %d" % i, "qty": i + 1, "amount": 1000 * (i + 1)})
	return {"floor": n, "rows": rows}


func _ded(label: String, who: String, amount: int) -> Dictionary:
	return {"label": label, "who": who, "qty": 1, "amount": amount}


func _earned(floors: Array) -> int:
	var t := 0
	for sec: Dictionary in floors:
		for r: Dictionary in sec["rows"]:
			t += int(r["amount"])
	return t


func _damages(ded: Array) -> int:
	var t := 0
	for d: Dictionary in ded:
		t += int(d["amount"])
	return t
