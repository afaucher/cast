class_name ContractInvoice
extends RefCounted
## Builds the end-of-job invoice (the summary screen's data) from a finished ContractSession and the
## Ledger. Everything the screen prints comes from here, so the totals provably match the Ledger:
##   earned (sum of the floor sections) - deducted (damages capped at the contract value) = payout.

const MONTHS: Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const VENDOR := "Cast Budget Sorcery"
const MAX_DEDUCTION_ROWS := 5
const STAR_3_RATIO := 0.66
const STAR_2_RATIO := 0.33


static func build(session: ContractSession) -> Dictionary:
	var run := session.run
	var d := ClientArchetype.get_data(run.archetype_id)
	var earned := Ledger.earned()
	var damages := Ledger.damages()
	var deducted := Ledger.deducted()
	var payout := Ledger.payout()
	var inv := {
		"number": run.invoice_number,
		"archetype": run.archetype_id,
		"date": _date(),
		"client": run.client_name,
		"company": run.company,
		"address": str(d["address"]),
		"tagline": str(d["tagline"]),
		"dept": str(d["dept"]),
		"site": str(d["site_name"]),
		"vendor": VENDOR,
		"reason": session.end_reason,
		"floor_reached": session.floor_number,
		"contract_value": run.contract_value,
		"earned": earned,
		"damages": damages,
		"deducted": deducted,
		"capped": damages > run.contract_value,
		"payout": payout,
		"floors": _floor_sections(),
		"deductions": _deduction_rows(),
		"blame": _blame(),
		"employees": {
			"total": session.employees_spawned(),
			"extracted": session.extracted_total,
			"alive": session.employees_alive(),
			"lost": session.lost.size(),
			"lost_causes": _lost_causes(session),
		},
	}
	inv["stars"] = stars_for(payout, run.contract_value, session.end_reason)
	inv["footer"] = footer_for(run.archetype_id, int(inv["stars"]), session.end_reason)
	return inv


## 1-3 stars: the share of the contract's value the crew took home (and never more than 1 star when
## the whole crew went down).
static func stars_for(payout: int, contract_value: int, reason: String) -> int:
	if reason == ContractSession.END_INCAPACITATED or contract_value <= 0:
		return 1
	var ratio := float(payout) / float(contract_value)
	if ratio >= STAR_3_RATIO:
		return 3
	if ratio >= STAR_2_RATIO:
		return 2
	return 1


static func footer_for(archetype_id: String, stars: int, reason: String) -> String:
	var f: Dictionary = ClientArchetype.get_data(archetype_id)["footers"]
	if reason == ContractSession.END_INCAPACITATED:
		return str(f["incap"])
	return str(f["good"] if stars >= 3 else (f["mid"] if stars == 2 else f["bad"]))


## [{floor, rows: [{label, qty, amount}], subtotal}] for floors that have earnings, in order.
static func _floor_sections() -> Array[Dictionary]:
	var by_floor: Dictionary = {}
	var order: Array[int] = []
	for l in Ledger.lines:
		if l["kind"] != "earn":
			continue
		var f: int = int(l["floor"])
		if not by_floor.has(f):
			by_floor[f] = {"rows": [] as Array[Dictionary], "index": {}}
			order.append(f)
		var sec: Dictionary = by_floor[f]
		var idx: Dictionary = sec["index"]
		var key := str(l["label"])
		if idx.has(key):
			var row: Dictionary = (sec["rows"] as Array[Dictionary])[int(idx[key])]
			row["qty"] = int(row["qty"]) + 1
			row["amount"] = int(row["amount"]) + int(l["amount"])
		else:
			idx[key] = (sec["rows"] as Array[Dictionary]).size()
			(sec["rows"] as Array[Dictionary]).append({"label": key, "qty": 1, "amount": int(l["amount"])})
	order.sort()
	var out: Array[Dictionary] = []
	for f in order:
		var rows: Array[Dictionary] = by_floor[f]["rows"]
		var sub := 0
		for r in rows:
			sub += int(r["amount"])
		out.append({"floor": f, "rows": rows, "subtotal": sub})
	return out


## Damage lines grouped by (item, culprit), biggest first, with the tail folded into one "other" row.
static func _deduction_rows() -> Array[Dictionary]:
	var grouped: Dictionary = {}
	for l in Ledger.lines:
		if l["kind"] != "damage":
			continue
		var who: String = str(l["who"]) if str(l["who"]) != "" else "unknown"
		var key := "%s|%s" % [l["label"], who]
		if grouped.has(key):
			var row: Dictionary = grouped[key]
			row["qty"] = int(row["qty"]) + 1
			row["amount"] = int(row["amount"]) + int(l["amount"])
		else:
			grouped[key] = {"label": str(l["label"]), "who": who, "qty": 1, "amount": int(l["amount"])}
	var rows: Array[Dictionary] = []
	for k in grouped:
		rows.append(grouped[k])
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["amount"]) > int(b["amount"]))
	if rows.size() > MAX_DEDUCTION_ROWS:
		var keep: Array[Dictionary] = rows.slice(0, MAX_DEDUCTION_ROWS - 1)
		var rest := 0
		var n := 0
		for i in range(MAX_DEDUCTION_ROWS - 1, rows.size()):
			rest += int(rows[i]["amount"])
			n += int(rows[i]["qty"])
		keep.append({"label": "%d other items" % (rows.size() - MAX_DEDUCTION_ROWS + 1), "who": "various", "qty": n, "amount": rest})
		rows = keep
	return rows


## [{who, amount}] biggest culprit first (the team pot stays shared; this is credit and blame).
static func _blame() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var by: Dictionary = Ledger.damage_by_who()
	for who: String in by:
		out.append({"who": who if who != "" else "unknown", "amount": int(by[who])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["amount"]) > int(b["amount"]))
	return out


## "corn x2, Wick x1" style cause summary for the employees-lost line.
static func _lost_causes(session: ContractSession) -> String:
	var counts: Dictionary = {}
	for l in session.lost:
		counts[str(l["cause"])] = int(counts.get(str(l["cause"]), 0)) + 1
	var parts: Array[String] = []
	for c: String in counts:
		parts.append(c if int(counts[c]) == 1 else "%s x%d" % [c, counts[c]])
	return ", ".join(parts)


static func _date() -> String:
	var t := Time.get_date_dict_from_system()
	return "%s %d, %d" % [MONTHS[int(t["month"]) - 1], int(t["day"]), int(t["year"])]
