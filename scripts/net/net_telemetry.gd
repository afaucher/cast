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
## packets that arrived), bytes per second, pending reliable bytes (blank: SteamMultiplayerPeer does not expose
## the connection's status), and hits taken (M4: hits this machine's own heroes took in that second). `link` is the
## crew's simulated link (M7: the host's Settings > Diagnostics choice, or a dev flag).
## Three worst-of-the-second columns for spotting a freeze (all measured on this machine over that second):
##   silence_ms  the longest stretch with nothing received from the other side (the host: its quietest client), including
##               one still going at the sample. About the sender's rate when all is well: ~35-85 ms on a floor (snapshots),
##               up to ~500 ms on the board (only pings and rows). A stretch that spans rows shows in each, growing (1517
##               then 1651 is one 1.65 s stretch). Blank with nobody to hear from.
##   frame_ms    this machine's longest frame (a hitch here is lag to everyone, and shows up as silence too).
##   snap_m      the biggest puppet correction: how far a puppet (a hero, or a host-owned actor on a client) was shown off the
##               course it was on the frame before (NetSession.off_course), in metres; teleports aside. Smooth motion is
##               centimetres. Blank when no puppet was shown that second.
##
## Two more sheets (M7), same rules (every machine writes its own, a client's rows are filed on the host under `from`,
## reliably this time: they are rare and must not go missing):
##   net_casts_<role>_...csv  one row per cast: `sent` on the caster's machine (the cast's moment on the shared clock, the
##                            voice onset and end, the recognition latency) and `applied` on every machine when its effect
##                            lands (how late). The host's file shows each cast arriving once on every machine.
##   net_hits_<role>_...csv   hits taken per player per minute (the "keep them level" check): one row per seat this machine
##                            owns, every HITS_WINDOW seconds: hits, damage, the minutes on a floor, hits per minute and what
##                            hit them. The host's file holds the whole crew: the host's seat, the AI seats, every client.

const DIR := "user://net"
const KEEP_FILES := 40      ## older telemetry files (per kind) are pruned when a new one opens
const COLUMNS: Array[String] = [
	"t", "role", "from", "seat", "crew",
	"rtt_ms", "rtt_min_ms", "jitter_ms", "clock_fix_ms", "quality",
	"bytes_out", "bytes_in", "pkts_out", "pkts_in", "events_out", "events_in", "gaps", "stale",
	"link", "link_held", "link_dropped", "pending_rel", "hits", "silence_ms", "frame_ms", "snap_m",
]
const CAST_COLUMNS: Array[String] = [
	"t", "role", "from", "seat", "kind", "cast", "spell", "power", "source", "label",
	"voice_start", "voice_end", "speech_ms", "recog_ms", "at", "late_ms",
]
const HIT_COLUMNS: Array[String] = [
	"t", "role", "from", "seat", "name", "who", "minute", "floor_s", "hits", "damage", "per_min", "sources",
]

## A CSV file of one kind (net_<kind>_<role>_<date>_<pid>.csv) with fixed columns.
class Sheet extends RefCounted:
	var columns: Array[String] = []
	var path := ""
	var rows := 0
	var peer_rows := 0
	var _file: FileAccess = null

	func _init(cols: Array[String]) -> void:
		columns = cols

	func open(dir: String, kind: String, role: String, stamp: String) -> bool:
		path = "%s/net_%s%s_%s_%d.csv" % [dir, kind, role, stamp, OS.get_process_id()]
		_file = FileAccess.open(path, FileAccess.WRITE)
		if _file == null:
			printerr("[Net] could not open telemetry at ", path)
			return false
		_file.store_line(",".join(columns))
		_file.flush()
		return true

	func close() -> void:
		if _file != null:
			_file.flush()
		_file = null

	func is_open() -> bool:
		return _file != null

	## A row in column order; a row of the wrong width (another build) is dropped, so a column never shifts.
	func write(row: Array) -> bool:
		if _file == null or row.size() != columns.size():
			return false
		var cells := PackedStringArray()
		for v: Variant in row:
			cells.append(str(v).replace(",", ";"))
		_file.store_line(",".join(cells))
		_file.flush()   # a session under investigation usually ends by being killed: keep the tail
		rows += 1
		return true

	## A client's row, on the host: `from` is the transport's peer id.
	func write_peer(peer: int, row: Array) -> bool:
		if row.size() != columns.size():
			return false
		var copy := row.duplicate()
		copy[columns.find("from")] = peer
		if write(copy):
			peer_rows += 1
			return true
		return false


## Where files go (tests use their own folder so they never crowd out real sessions).
var dir := DIR
var path := ""
var rows_written := 0
var peer_rows := 0
## M7: the cast sheet and the hits sheet (see the header).
var casts := Sheet.new(CAST_COLUMNS)
var hits := Sheet.new(HIT_COLUMNS)

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
	casts.open(dir, "casts_", role, stamp)
	hits.open(dir, "hits_", role, stamp)
	print("[Net] telemetry -> ", ProjectSettings.globalize_path(path))
	return true


func close() -> void:
	if _file != null:
		_file.flush()
	_file = null
	casts.close()
	hits.close()


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
	for kind in ["net_casts_", "net_hits_", "net_"]:
		var files: Array = []   # [modified time, path]
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".csv") or not f.begins_with(kind):
				continue
			if kind == "net_" and (f.begins_with("net_casts_") or f.begins_with("net_hits_")):
				continue
			var p := "%s/%s" % [dir, f]
			files.append([FileAccess.get_modified_time(p), p])
		if files.size() < KEEP_FILES:
			continue
		files.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
		for i in files.size() - KEEP_FILES + 1:
			DirAccess.remove_absolute(str(files[i][1]))
