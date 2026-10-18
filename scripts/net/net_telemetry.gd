class_name NetTelemetry
extends RefCounted
## Passive network telemetry (networking.md "Day-one infrastructure" item 7), ported from Bridge to
## Friendship's net_telemetry.gd: ONE CSV ROW PER SECOND PER MACHINE, so a trend ("it gets worse over time")
## can be read afterwards. It diagnoses nothing and has no thresholds.
##
## - Every machine writes its own file: user://net/net_<role>_<date>_<pid>.csv (the path is printed when the
##   session starts).
## - A client also sends each finished row to the host, UNRELIABLY, and the host files it in its own CSV under
##   `from` (the peer id the transport reports, never the one in the row). So the host's file holds the whole
##   crew. A row that doesn't arrive is a GAP, never a zero: read a gap as "missing".
## - Event columns are rates over the last second; state columns are levels at the sample.
## - No marker key and no review screen: Cast's playtest data is passive. (Bridge's F4 "mark" was dropped.)
##
## Columns (networking.md item 7): RTT, jitter (computed ourselves), a quality figure (the share of unreliable
## packets that arrived), bytes per second, pending reliable bytes (blank until the Steam status is wired in
## M7), and hits taken (M4: hits this machine's own heroes took in that second).

const DIR := "user://net"
const KEEP_FILES := 40      ## older telemetry files are pruned when a new one opens
const COLUMNS: Array[String] = [
	"t", "role", "from", "seat", "crew",
	"rtt_ms", "rtt_min_ms", "jitter_ms", "clock_fix_ms", "quality",
	"bytes_out", "bytes_in", "pkts_out", "pkts_in", "events_out", "events_in", "gaps", "stale",
	"link", "link_held", "link_dropped", "pending_rel", "hits",
]

## Where files go (tests use their own folder so they never crowd out real sessions).
var dir := DIR
var path := ""
var rows_written := 0
var peer_rows := 0

var _file: FileAccess = null


## Open a fresh file for this session. Returns false when it can't be written.
func open(role: String) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	_prune()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	path = "%s/net_%s_%s_%d.csv" % [dir, role, stamp, OS.get_process_id()]
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		printerr("[Net] could not open telemetry at ", path)
		return false
	_file.store_line(",".join(COLUMNS))
	_file.flush()
	print("[Net] telemetry -> ", ProjectSettings.globalize_path(path))
	return true


func close() -> void:
	if _file != null:
		_file.flush()
	_file = null


func is_open() -> bool:
	return _file != null


## This machine's row.
func write_row(row: Array) -> void:
	if _file == null or row.size() != COLUMNS.size():
		return
	_write(row)
	rows_written += 1


## A client's row, on the host. `from` is overwritten with the transport's peer id. A row of the wrong width
## (another build) is dropped, so a column can never silently shift.
func note_peer_row(peer: int, row: Array) -> void:
	if _file == null or row.size() != COLUMNS.size():
		return
	var copy := row.duplicate()
	copy[COLUMNS.find("from")] = peer
	_write(copy)
	peer_rows += 1


func _write(row: Array) -> void:
	var cells := PackedStringArray()
	for v: Variant in row:
		cells.append(str(v).replace(",", ";"))
	_file.store_line(",".join(cells))
	_file.flush()   # a session under investigation usually ends by being killed: keep the tail


func _prune() -> void:
	var files: Array = []   # [modified time, path]
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("net_") and f.ends_with(".csv"):
			var p := "%s/%s" % [dir, f]
			files.append([FileAccess.get_modified_time(p), p])
	if files.size() < KEEP_FILES:
		return
	files.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	for i in files.size() - KEEP_FILES + 1:
		DirAccess.remove_absolute(str(files[i][1]))
