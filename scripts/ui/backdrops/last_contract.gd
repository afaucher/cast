class_name LastContract
extends RefCounted
## A tiny memory of how the last finished contract went, so the main menu's garage can show the morning after
## a bad job (MenuBackdrop mood "after") and its "JOBS SINCE LAST CORN INCIDENT" sign. Presentation only: nothing
## reads it for gameplay, and the Game records it once, when the invoice is built. The last result lives as long as
## the process; the streak is saved (user://garage.cfg) so the sign keeps counting between sessions. Test runs don't save.
##
##   LastContract.record(invoice)        # Game._end_contract
##   LastContract.was_bad()              # damages over AFTER_DAMAGE_RATIO of the contract's value, the crew went down,
##                                       # corporate had to revive anyone (crew revival fees), or the net payout was negative
##   LastContract.clean_jobs()           # finished contracts in a row that were not bad; a bad one puts it back to 0

## A job went badly when the damages reach this share of the contract's value.
const AFTER_DAMAGE_RATIO := 0.5

static var has_result := false
static var damages := 0
static var contract_value := 0
static var incapacitated := false
static var revival_fees := 0
static var payout := 0

const SAVE_PATH := "user://garage.cfg"
## Off in test runs (tests may switch it on, with their own path, to check the file).
static var persist := not OS.get_cmdline_user_args().has("--run-test")
static var save_path := SAVE_PATH
static var _clean_jobs := -1   ## -1 = not loaded yet


## Remember a finished contract from its invoice (ContractInvoice.build).
static func record(invoice: Dictionary) -> void:
	has_result = true
	damages = int(invoice.get("damages", 0))
	contract_value = int(invoice.get("contract_value", 0))
	incapacitated = str(invoice.get("reason", "")) == ContractSession.END_INCAPACITATED
	revival_fees = int(invoice.get("revival_fees", 0))
	payout = int(invoice.get("payout", 0))
	_clean_jobs = 0 if was_bad() else clean_jobs() + 1
	_save()


## Finished contracts in a row that were not bad (the garage's corn sign). Loaded from disk the first time.
static func clean_jobs() -> int:
	if _clean_jobs < 0:
		_clean_jobs = 0
		var cfg := ConfigFile.new()
		if persist and cfg.load(save_path) == OK:
			_clean_jobs = maxi(0, int(cfg.get_value("garage", "clean_jobs", 0)))
	return _clean_jobs


static func _save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.load(save_path)
	cfg.set_value("garage", "clean_jobs", _clean_jobs)
	cfg.save(save_path)


## True when the last contract ended in a mess: the whole crew incapacitated, any crew member left down (a
## revival fee was billed), a negative net payout, or damages over the threshold.
static func was_bad() -> bool:
	if not has_result:
		return false
	return incapacitated or revival_fees > 0 or payout < 0 or float(damages) >= float(contract_value) * AFTER_DAMAGE_RATIO


static func clear() -> void:
	has_result = false
	damages = 0
	contract_value = 0
	incapacitated = false
	revival_fees = 0
	payout = 0
	_clean_jobs = -1
