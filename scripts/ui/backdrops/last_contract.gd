class_name LastContract
extends RefCounted
## A tiny memory of how the last finished contract went, so the main menu's garage can show the morning after
## a bad job (MenuBackdrop mood "after"). Presentation only: nothing reads it for gameplay, nothing is saved to
## disk (it lives as long as the process), and the Game records it once, when the invoice is built.
##
##   LastContract.record(invoice)        # Game._end_contract
##   LastContract.was_bad()              # damages over AFTER_DAMAGE_RATIO of the contract's value, or the crew went down
##   LastContract.corn_incidents         # corn casts in the last contract; nothing counts them yet, so it stays 0

## A job went badly when the damages reach this share of the contract's value.
const AFTER_DAMAGE_RATIO := 0.5

static var has_result := false
static var damages := 0
static var contract_value := 0
static var incapacitated := false
static var corn_incidents := 0


## Remember a finished contract from its invoice (ContractInvoice.build).
static func record(invoice: Dictionary) -> void:
	has_result = true
	damages = int(invoice.get("damages", 0))
	contract_value = int(invoice.get("contract_value", 0))
	incapacitated = str(invoice.get("reason", "")) == ContractSession.END_INCAPACITATED


## True when the last contract ended in a mess: the whole crew incapacitated, or damages over the threshold.
static func was_bad() -> bool:
	if not has_result:
		return false
	return incapacitated or float(damages) >= float(contract_value) * AFTER_DAMAGE_RATIO


static func clear() -> void:
	has_result = false
	damages = 0
	contract_value = 0
	incapacitated = false
	corn_incidents = 0
