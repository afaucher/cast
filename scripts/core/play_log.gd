class_name PlayLog
extends RefCounted
## A passive record of every real play (user, 2026-10-18: "make sure every play generates them"): one row per contract
## start, per floor finished and per contract end, appended to user://play_log.csv. Nothing on screen, no keys. Each
## machine writes its own (online the host's rows are the authoritative books). Test runs don't write.
##
## Columns: time (wall clock), run (one id per contract), event (contract | floor | end), client, site, difficulty,
## floor, floor_s (game seconds spent on that floor; the solo pause stops the game clock), reason (how it ended),
## earned, damages, revivals, payout, extracted, lost, gates_closed, gates_total, role (solo | host | client), crew.

const PATH := "user://play_log.csv"
const HEADER := "time,run,event,client,site,difficulty,floor,floor_s,reason,earned,damages,revivals,payout,extracted,lost,gates_closed,gates_total,role,crew"

## Off in test runs (tests may switch it on to check the rows).
static var enabled := not OS.get_cmdline_user_args().has("--run-test")
static var path := PATH


static func contract_started(run_id: String, contract: ContractRun, start_floor: int) -> void:
	_row(run_id, "contract", contract, start_floor, -1.0, "", {})


static func floor_done(run_id: String, contract: ContractRun, f: int, seconds: float, reason: String, fl: Dictionary) -> void:
	_row(run_id, "floor", contract, f, seconds, reason, fl)


static func contract_ended(run_id: String, contract: ContractRun, f: int, reason: String, extracted: int, lost: int) -> void:
	_row(run_id, "end", contract, f, -1.0, reason, {"extracted": extracted, "lost": lost})


static func _row(run_id: String, event: String, contract: ContractRun, f: int, seconds: float, reason: String, fl: Dictionary) -> void:
	if not enabled or contract == null:
		return
	var money := event == "end"
	var cells: Array = [
		Time.get_datetime_string_from_system(), run_id, event, _csv(contract.client_name), contract.site_type,
		"%.2f" % contract.difficulty, f, "%.1f" % seconds if seconds >= 0.0 else "", reason,
		Ledger.earned() if money else "", Ledger.damages() if money else "", Ledger.revival_fees() if money else "",
		Ledger.payout() if money else "",
		fl.get("extracted", ""), fl.get("lost", ""), fl.get("gates_closed", ""), fl.get("gates_total", ""),
		_role(), Session.roster.size() if Session.online() else 1,
	]
	var fresh := not FileAccess.file_exists(path)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if not fresh else FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	if fresh:
		file.store_line(HEADER)
	file.store_line(",".join(cells.map(func(c: Variant) -> String: return str(c))))
	file.close()


static func _role() -> String:
	if not Session.online():
		return "solo"
	return "host" if Net.is_host() else "client"


static func _csv(s: String) -> String:
	return "\"%s\"" % s.replace("\"", "'") if s.contains(",") or s.contains("\"") else s
