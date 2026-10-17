extends TestCase
## Ledger payout rule: damages capped at contract value, taken from earnings, never negative.


func setup() -> void:
	Ledger.begin_contract(10000)
	Ledger.earn("Hellgate closed", 3000)
	Ledger.earn("Employee extracted", 100)
	Ledger.damage("Wine rack", 1200)
	eq(Ledger.earned(), 3100, "earned")
	eq(Ledger.damages(), 1200, "damages")
	eq(Ledger.payout(), 1900, "payout = earned - damages")
	Ledger.damage("Gold toilet", 50000)
	eq(Ledger.deducted(), 10000, "deductions capped at contract value")
	eq(Ledger.payout(), 0, "never negative")
	Ledger.begin_contract(5000)
	eq(Ledger.lines.size(), 0, "new contract clears the ledger")
	Ledger.damage("Vase", 900)
	eq(Ledger.payout(), 0, "leaving early with damage and nothing earned pays $0, owes nothing")
	eq(Ledger.damage_by_who().get("", -1), 900, "unattributed damage grouped")
	finish()
