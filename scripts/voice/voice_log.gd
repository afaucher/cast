class_name VoiceLog
extends RefCounted
## Passive playtest log of every utterance, appended to user://voice_log.csv by
## VoiceCaster. No UI and no player effort: one row per finished utterance
## (what the recognizer heard and what, if anything, fired).

const DEFAULT_PATH := "user://voice_log.csv"
const COLUMNS := ["time", "clock", "session", "uid", "source", "final", "heard", "spell", "power",
	"label", "signals", "mode", "trigger"]

var path := DEFAULT_PATH
var session := ""
var enabled := true
var _uid := 0


func _init(log_path: String = DEFAULT_PATH) -> void:
	path = log_path
	session = new_session_id()


static func new_session_id() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d-%02d%02d%02d-%03d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"], Time.get_ticks_msec() % 1000]


## Append one row. `row` keys are COLUMNS (missing ones are blank). Returns the uid.
func add(row: Dictionary) -> int:
	_uid += 1
	if not enabled:
		return _uid
	var r := row.duplicate()
	r["uid"] = _uid
	r["session"] = session
	r["time"] = Time.get_datetime_string_from_system()
	var is_new := not FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.WRITE if is_new else FileAccess.READ_WRITE)
	if f == null:
		push_warning("VoiceLog: cannot write %s" % path)
		return _uid
	if is_new:
		f.store_csv_line(PackedStringArray(COLUMNS))
	else:
		f.seek_end()
	f.store_csv_line(_to_line(r))
	f.close()
	return _uid


static func _to_line(r: Dictionary) -> PackedStringArray:
	var line := PackedStringArray()
	for c in COLUMNS:
		line.append(str(r.get(c, "")))
	return line


## Every row in the file as Dictionaries keyed by COLUMNS.
static func read_all(log_path: String = DEFAULT_PATH) -> Array:
	var out: Array = []
	if not FileAccess.file_exists(log_path):
		return out
	var f := FileAccess.open(log_path, FileAccess.READ)
	if f == null:
		return out
	var header := f.get_csv_line()
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() < 2:
			continue
		var d := {}
		for i in header.size():
			d[header[i]] = line[i] if i < line.size() else ""
		out.append(d)
	return out
