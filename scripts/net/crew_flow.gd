class_name CrewFlow
extends Node
## The shared run's state machine (docs/design/networking-build-plan.md M1): child "Flow" of the Session
## autoload, so it (and what it knows) survives the scene reloads the game does for the board and the floors.
## Gameplay code (game.gd) only ASKS it and listens to its signals; every message here rides Session's
## reliable events, kinds "crew.*".
##
##   BOARD     the host rolls the board seed and sends it (crew.board {seed, hi}); every machine draws the same
##             three offers (ContractBoard.offers(seed)), read-only for clients. The host's highlighted card
##             follows along (crew.hi {i}).
##   LICENSE   the host takes a job (crew.job {archetype, seed, difficulty}); everyone builds the contract and
##             opens their OWN license checkout. Signing it is the "ready" step: a client sends
##             crew.signed {spells}; the host keeps "signed" and "spells" on the roster entry and sends the
##             roster, so every machine sees who is still signing ("waiting for <name>").
##   LOADING   everyone has signed: the host sends crew.load. Each machine builds the floor from the contract
##             seed behind a load barrier (world frozen), computes the floor CHECKSUM (NetFloor) and reports
##             crew.ready {sums}. The host compares: a client whose checksum differs is sent out with the
##             reason "Desync: different floor" (logged on the host with the parts that differ).
##   PENDING   all remaining members are ready: the host sends crew.go {start_at, floor_start}.
##             start_at is a time on the shared clock a little ahead (START_LEAD), so every machine has the
##             message before it happens; the van arrival and the unfreeze begin there on every machine.
##   FLOOR     floor_started(elapsed) fired. From crew.go on, a client's GameWorld.time is slewed toward
##             host_time() - floor_start (the host's floor clock), so a time stamp in a scheduled effect
##             means the same moment everywhere (to within a frame plus the link: the clock's own accuracy).
##
## floor_start is defined from the HOST's GameWorld.time at the moment it sends crew.go (host_time() minus
## GameWorld.time), not by resetting the host's clock: nothing the host stamped during the build (cooldowns,
## timers) changes. A client JUMPS once, when crew.go arrives, then slews; so on a client any time stamp made
## before crew.go is in its own pre-floor time and must not be used for gameplay (nothing in M1 does).
##
##   NEXT      (M3) the crew took the elevator down (NetObjects' first-to-choose exit): the host sends crew.next and every
##             machine reloads onto the next floor of the same contract and goes through the barrier again (LOADING:
##             build, checksum, crew.ready, crew.go), with no board and no license (`floor_change` is true).
##   BACK      (M5) ANY player can take the whole crew back to the host's board: a client's "Abandon contract" is
##             crew.abandon and its "Next contract" on the invoice is crew.again, both client -> host; the host's game
##             does it (abandon_requested / again_requested) exactly as for its own press, and its new board's
##             crew.board brings everyone (with `note`, e.g. "c1 abandoned the job", shown on every board).
##
## The host is the only one that decides; clients only draw what they are told. A client that leaves, or is
## sent out, just stops being waited for.
##
##   JOINING   (M6) a player who says hello while the crew is on a job is in the roster with `joining` true until it has
##             taken a seat (NetJoin): nobody waits for it (no license to sign, no barrier to report to), it gets none of the
##             barrier's events (crew.job / load / next / go: it would build a floor it is not on), and the game builds
##             its seat as the AI's. It arrives on a running floor through NetJoin's late-join snapshot; a joiner during a
##             floor change waits for the next floor to start, one on the invoice waits for the next board (which every
##             member gets, and which makes it an ordinary member).

signal board_changed()                     ## the host's board seed or highlighted card
signal job_changed()                       ## the host took a job: open the license checkout
signal load_requested()                    ## everyone signed: build the floor behind the barrier, then report_built()
signal waiting_changed()                   ## who we're waiting on changed (signed / ready flags, phase)
signal floor_started(elapsed: float)       ## start_at reached on the shared clock; `elapsed` seconds past it
signal abandon_requested(peer: int)        ## host (M5): a client's "Abandon contract" (the whole crew goes back to the board)
signal again_requested(peer: int)          ## host (M5): a client's "Next contract" on the invoice (the same)

const BOARD := "board"
const LICENSE := "license"
const LOADING := "loading"
const PENDING := "pending"
const FLOOR := "floor"
const IDLE := "idle"

const START_LEAD := 0.5      ## seconds between crew.go and the floor start, so every machine has it in time
const SLEW := 0.05           ## the floor clock moves at most 5% faster or slower while catching up
const SNAP_SEC := 1.0        ## ... and an error this big is set outright

var phase := IDLE
var board_seed := -1
var board_hi := 0
## A short line the host's board carries for everyone (M5: who abandoned the job; "" for none).
var board_note := ""
## The job the host took: {archetype, seed, difficulty}.
var job: Dictionary = {}
## On the shared clock (host_time seconds): when the floor starts, and the epoch of the floor clock.
var start_at := 0.0
var floor_start := 0.0
var floor_known := false
## This machine's own floor checksum (NetFloor.checksum), once built.
var local_sums: Dictionary = {}
## Host: [{peer, name, parts}] for every client sent out for building a different floor.
var desyncs: Array = []
## Test seam: added to the job's seed on THIS machine only, to build a different floor on purpose.
var debug_seed_shift := 0
## How far this machine's GameWorld.time was from the floor clock when crew.go arrived (seconds).
var first_adjust := 0.0
## The barrier in progress is a floor change (the elevator down, M3), not the contract's first floor.
var floor_change := false
## Host (M6): the job is over (the invoice is up): a joiner waits for the next board.
var job_ended := false
## Host (M6): the floor number and the seat table this floor was built with at its barrier ([{seat, character, peer, name}],
## after any seat a departed player had went back to the AI), so a late joiner builds the same floor (the same checksum).
var floor_n := 0
var floor_seats: Array = []

var _session: NetSession = null
var _sums: Dictionary = {}          ## host: peer -> checksum dict
var _local_signed := false
var _local_ready := false
var _started := false
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session = get_parent() as NetSession
	if _session == null:
		return
	_session.event_received.connect(_on_event)
	_session.roster_changed.connect(_on_roster_changed)
	_session.peer_joined.connect(_on_peer_joined)
	_session.session_started.connect(func(_as_host: bool) -> void: reset())
	_session.session_ended.connect(func(_reason: String) -> void: reset())


## Forget the run (a session started or ended).
func reset() -> void:
	phase = IDLE
	board_seed = -1
	board_hi = 0
	board_note = ""
	job = {}
	start_at = 0.0
	floor_start = 0.0
	floor_known = false
	local_sums = {}
	desyncs = []
	first_adjust = 0.0
	floor_change = false
	job_ended = false
	floor_n = 0
	floor_seats = []
	_sums = {}
	_local_signed = false
	_local_ready = false
	_started = false
	_busy = false


func _hosting() -> bool:
	return _session != null and _session.hosting and _session.online()


func _client() -> bool:
	return _session != null and _session.is_client()


## The roster entry for a peer ({} when unknown).
func _entry(peer: int) -> Dictionary:
	return _session.roster.get(peer, {}) as Dictionary


# --- Board -------------------------------------------------------------------------------------------

## Host: the board (re)opened with this seed. Clients draw the same offers. Also run after "back to the board".
## `note` is a short line every board shows (who abandoned the job), "" for none.
func host_board(seed_value: int, highlight: int = 0, note: String = "") -> void:
	if not _hosting():
		return
	phase = BOARD
	floor_change = false
	job_ended = false
	board_seed = seed_value
	board_hi = highlight
	board_note = note
	job = {}
	_clear_run_state()
	_session.set_members(0, {"signed": false, "ready": false, "spells": [], "joining": false})   # (M6: a joiner is a member now)
	_session.send_event(0, "crew.board", {"seed": seed_value, "hi": highlight, "note": note})
	board_changed.emit()
	waiting_changed.emit()


## Host: the highlighted card moved.
func host_highlight(index: int) -> void:
	if not _hosting() or phase != BOARD or index == board_hi:
		return
	board_hi = index
	_session.send_event(0, "crew.hi", {"i": index})
	board_changed.emit()


## Host: the host took this offer. Everyone builds the contract and opens their license checkout.
func host_pick(run: ContractRun) -> void:
	if not _hosting():
		return
	phase = LICENSE
	floor_change = false
	job_ended = false
	board_note = ""
	job = {"archetype": run.archetype_id, "seed": run.seed, "difficulty": run.difficulty}
	_clear_run_state()
	_session.set_members(0, {"signed": false, "ready": false, "spells": []})
	_to_members("crew.job", job)
	job_changed.emit()
	waiting_changed.emit()
	_check_progress()


## Host: the crew takes the elevator down. Everyone builds the next floor behind the barrier (LOADING, then crew.go as
## for the first floor); the game reloads its scene and reports again (report_built).
func host_next_floor() -> void:
	if not _hosting():
		return
	phase = LOADING
	floor_change = true
	_clear_run_state()
	_local_signed = true
	_session.set_members(0, {"ready": false})
	_to_members("crew.next", {})
	waiting_changed.emit()


## Host (M6): the job ended (the invoice is up). A joiner waits for the next board.
func host_job_ended() -> void:
	if _hosting():
		job_ended = true


## Host (M6): the floor that just passed its barrier: its number and the seat table it was built with.
func note_floor(n: int, seats: Array) -> void:
	floor_n = n
	floor_seats = seats.duplicate(true)


## The late joiner (M6, NetJoin): this machine is on the crew's running floor now. The job, and the floor clock as crew.go
## would have set it (one jump of GameWorld.time, then the slew); the floor starts on the next frame (start_at has passed).
func join_floor(the_job: Dictionary, start: float, epoch: float) -> void:
	var sums := local_sums   # (this machine's own checksum of the floor it built: kept)
	job = the_job.duplicate()
	floor_change = false
	board_note = ""
	_clear_run_state()
	local_sums = sums
	_local_signed = true
	_local_ready = true
	_receive_go(start, epoch)


## True for a roster entry that is still joining (M6): nobody waits for it.
static func is_joining(e: Dictionary) -> bool:
	return bool(e.get("joining", false))


## The contract this machine builds from the job (null before one is known). debug_seed_shift applies here only.
func job_run() -> ContractRun:
	if job.is_empty():
		return null
	return ContractRun.make(str(job["archetype"]), int(job["seed"]) + debug_seed_shift, float(job["difficulty"]))


# --- Back to the board (M5): anyone can take the crew there ---------------------------------------------

## Client: this player abandons the contract for the whole crew (the host does it and every machine follows its board).
func request_abandon() -> void:
	if _client():
		_session.send_event(1, "crew.abandon", {})


## Client: this player pressed "Next contract" on the invoice: the whole crew goes back to the host's board.
func request_again() -> void:
	if _client():
		_session.send_event(1, "crew.again", {})


# --- License checkout (the ready step) ----------------------------------------------------------------

## This player signed their license for these spells.
func sign(spells: Array[String]) -> void:
	if _session == null or not _session.online():
		return
	_local_signed = true
	if _hosting():
		_session.set_members(1, {"signed": true, "spells": spells.duplicate()})
		_check_progress()
	else:
		_session.send_event(1, "crew.signed", {"spells": spells})
	waiting_changed.emit()


## This machine finished building the floor behind the barrier; `sums` is NetFloor.checksum().
func report_built(sums: Dictionary) -> void:
	if _session == null or not _session.online():
		return
	local_sums = sums
	_local_ready = true
	if _hosting():
		_sums[1] = sums
		_session.set_members(1, {"ready": true})
		_check_progress()
	else:
		_session.send_event(1, "crew.ready", {"sums": sums})
	waiting_changed.emit()


# --- Waiting -------------------------------------------------------------------------------------------

## The roster flag the current phase waits on ("signed" in the checkout, "ready" while loading).
func _wait_key() -> String:
	match phase:
		LICENSE:
			return "signed"
		LOADING:
			return "ready"
	return ""


## Names of the OTHER crew members the current phase is still waiting on.
func waiting_names() -> Array[String]:
	var out: Array[String] = []
	var key := _wait_key()
	if key == "" or _session == null:
		return out
	for e: Dictionary in _session.crew():
		if int(e["peer"]) != _session.local_id() and not bool(e.get(key, false)) and not is_joining(e):
			out.append(str(e["name"]))
	return out


## What to say while this player waits: "License signed. Waiting for Sam, Alex..." and the like ("" = nothing).
func waiting_text() -> String:
	var names := waiting_names()
	var who := ", ".join(names)
	match phase:
		LICENSE:
			if not _local_signed:
				return ""
			return "License signed. Waiting for %s..." % who if not names.is_empty() else "License signed. Loading the floor..."
		LOADING:
			if floor_change and _local_ready and names.is_empty():
				return "Everyone is in. Starting..."
			return "Loading the floor. Waiting for %s..." % who if not names.is_empty() else "Everyone is in. Starting..."
		PENDING:
			return "Everyone is in. Starting..."
	return ""


# --- Messages ----------------------------------------------------------------------------------------

func _on_event(from: int, kind: String, data: Dictionary, _stamp: float) -> void:
	if not kind.begins_with("crew."):
		return
	if _hosting():
		_host_event(from, kind, data)
	elif from == 1:
		_client_event(kind, data)


func _host_event(from: int, kind: String, data: Dictionary) -> void:
	if not _session.roster.has(from):
		return
	match kind:
		"crew.signed":
			if phase != LICENSE:
				return
			var spells: Array[String] = []
			for s: Variant in data.get("spells", []) as Array:
				if SpellBook.is_available(str(s)) and not spells.has(str(s)):
					spells.append(str(s))
			if spells.size() != SpellPicker.PICK_COUNT:
				push_warning("[Net] %s signed %d spells: ignored" % [str(_entry(from).get("name", from)), spells.size()])
				return
			_session.set_members(from, {"signed": true, "spells": spells})
			_check_progress()
		"crew.ready":
			if phase != LOADING:
				return
			_sums[from] = data.get("sums", {}) as Dictionary
			_session.set_members(from, {"ready": true})
			_check_progress()
		"crew.abandon":
			if phase != BOARD and phase != IDLE and not is_joining(_entry(from)):
				abandon_requested.emit(from)
		"crew.again":
			if not is_joining(_entry(from)):
				again_requested.emit(from)


func _client_event(kind: String, data: Dictionary) -> void:
	match kind:
		"crew.board":
			phase = BOARD
			floor_change = false
			board_seed = int(data.get("seed", -1))
			board_hi = int(data.get("hi", 0))
			board_note = str(data.get("note", ""))
			job = {}
			_clear_run_state()
			board_changed.emit()
			waiting_changed.emit()
		"crew.hi":
			board_hi = int(data.get("i", 0))
			board_changed.emit()
		"crew.job":
			phase = LICENSE
			floor_change = false
			board_note = ""
			job = data.duplicate()
			_clear_run_state()
			job_changed.emit()
			waiting_changed.emit()
		"crew.load":
			phase = LOADING
			load_requested.emit()
			waiting_changed.emit()
		"crew.next":
			phase = LOADING
			floor_change = true
			_clear_run_state()
			_local_signed = true
			load_requested.emit()
			waiting_changed.emit()
		"crew.go":
			_receive_go(float(data.get("start_at", 0.0)), float(data.get("floor_start", 0.0)))


## Host: a new member on the board gets the board (the offers and the highlighted card) at once. (M6: one who joined
## mid-job is NetJoin's until the next board.)
func _on_peer_joined(peer: int) -> void:
	if _hosting() and phase == BOARD and board_seed >= 0 and not is_joining(_entry(peer)):
		_session.send_event(peer, "crew.board", {"seed": board_seed, "hi": board_hi, "note": board_note})


func _on_roster_changed() -> void:
	waiting_changed.emit()
	if _hosting():
		_check_progress()


func _clear_run_state() -> void:
	_sums = {}
	local_sums = {}
	_local_signed = false
	_local_ready = false
	_started = false
	floor_known = false
	start_at = 0.0


# --- Host: the barrier -------------------------------------------------------------------------------

func _all_flag(key: String) -> bool:
	for e: Dictionary in _session.roster.values():
		if not bool(e.get(key, false)) and not is_joining(e):
			return false
	return not _session.roster.is_empty()


## Host: an event to every crew member that is not still joining (M6: the barrier's events are for the crew on the job).
func _to_members(kind: String, data: Dictionary) -> void:
	for p: int in _session.roster:
		if p != 1 and not is_joining(_entry(p)):
			_session.send_event(p, kind, data)


func _check_progress() -> void:
	if _busy or not _hosting():
		return
	_busy = true
	match phase:
		LICENSE:
			if _all_flag("signed"):
				phase = LOADING
				_to_members("crew.load", {})
				load_requested.emit()
				waiting_changed.emit()
		LOADING:
			_judge()
	_busy = false


## Host, loading: compare every reported checksum with the host's own, send out the ones that differ, and
## start the floor once every remaining member has reported.
func _judge() -> void:
	if not _sums.has(1):
		return   # the host is still building; its checksum is the reference
	var mine: Dictionary = _sums[1]
	for p: int in _session.roster.keys():
		if p == 1 or not _sums.has(p):
			continue
		var theirs: Dictionary = _sums[p]
		if str(theirs.get("all", "")) == str(mine.get("all", "")):
			continue
		var parts := NetFloor.differing_parts(mine, theirs)
		var who := str(_entry(p).get("name", p))
		var keys: Array = []
		if parts.has("plan"):
			var a: Dictionary = mine.get("plan_keys", {})
			var b: Dictionary = theirs.get("plan_keys", {})
			for k: String in a:
				if str(a[k]) != str(b.get(k, "")):
					keys.append(k)
		print("[Net] DESYNC: %s built a different floor (differs: %s%s; ours %s, theirs %s; %d vs %d cells, %d vs %d actors)" % [
			who, ", ".join(parts), (" / plan fields: " + ", ".join(keys)) if not keys.is_empty() else "",
			str(mine.get("all", "")), str(theirs.get("all", "")),
			int(mine.get("cells", 0)), int(theirs.get("cells", 0)), int(mine.get("actors", 0)), int(theirs.get("actors", 0))])
		desyncs.append({"peer": p, "name": who, "parts": parts})
		_sums.erase(p)
		_session.kick(p, NetSession.DESYNC)
	for p: int in _session.roster.keys():
		if not _sums.has(p) and not is_joining(_entry(p)):
			return   # someone is still building
	_send_go()


func _send_go() -> void:
	var lead := START_LEAD if _session.roster.size() > 1 else 0.0
	start_at = _session.host_time() + lead
	floor_start = _session.host_time() - GameWorld.time
	floor_known = true
	phase = PENDING
	_started = false
	_to_members("crew.go", {"start_at": start_at, "floor_start": floor_start})
	waiting_changed.emit()


func _receive_go(start: float, epoch: float) -> void:
	start_at = start
	floor_start = epoch
	floor_known = true
	phase = PENDING
	_started = false
	first_adjust = (_session.host_time() - floor_start) - GameWorld.time
	GameWorld.time = _session.host_time() - floor_start   # one jump, then slewing
	waiting_changed.emit()


# --- Every frame -----------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if phase == PENDING and not _started and _session != null and _session.online() and _session.host_time() >= start_at:
		_started = true
		phase = FLOOR
		floor_started.emit(_session.host_time() - start_at)
		waiting_changed.emit()


## Runs after GameWorld's own _physics_process (the autoload above Session in the tree), so the correction is
## applied to this frame's time.
func _physics_process(delta: float) -> void:
	if not floor_known or not _client() or _session == null:
		return
	var err := floor_time() - GameWorld.time
	if absf(err) > SNAP_SEC:
		GameWorld.time += err
	else:
		var step := SLEW * delta
		GameWorld.time += clampf(err, -step, step)


## The floor clock as the shared clock says it should read now: host_time() - floor_start.
func floor_time() -> float:
	return _session.host_time() - floor_start if _session != null else 0.0
