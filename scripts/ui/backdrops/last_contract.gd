class_name LastContract
extends RefCounted
## A tiny memory of how the last finished contract went, so the main menu's garage can show the morning after
## a bad job (MenuBackdrop mood "after"). Presentation only: nothing reads it for gameplay, nothing is saved to
## disk (it lives as long as the process), and the Game records it once, when the invoice is built.
##
##   LastContract.record(invoice)        # Game._end_contract
##   LastContract.was_bad()              # damages over AFTER_DAMAGE_RATIO of the contract's value, the crew went down,
##                                       # corporate had to revive anyone (crew revival fees), or the net payout was negative
##   LastContract.corn_incidents         # corn casts in the last contract; nothing counts them yet, so it stays 0

## A job went badly when the damages reach this share of the contract's value.
const AFTER_DAMAGE_RATIO := 0.5

static var has_result := false
static var damages := 0
static var contract_value := 0
static var incapacitated := false
static var revival_fees := 0
static var payout := 0
static var corn_incidents := 0


## Remember a finished contract from its invoice (ContractInvoice.build).
static func record(invoice: Dictionary) -> void:
	has_result = true
	damages = int(invoice.get("damages", 0))
	contract_value = int(invoice.get("contract_value", 0))
	incapacitated = str(invoice.get("reason", "")) == ContractSession.END_INCAPACITATED
	revival_fees = int(invoice.get("revival_fees", 0))
	payout = int(invoice.get("payout", 0))


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
	corn_incidents = 0
