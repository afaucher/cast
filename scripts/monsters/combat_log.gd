class_name CombatLog
extends RefCounted
## A passive record of how fights start and grow (docs/design/monster-awareness.md, "What to measure"), appended to
## user://combat_log.csv. Nothing on screen, no keys. Written by the machine that runs the monsters (the host, or solo);
## a client's monsters are copies and never report. Test runs don't write (tests may switch it on to check the rows).
## Rows are buffered and written every FLUSH_EVERY game seconds (or when the buffer fills), so a hard quit loses at most
## the last few seconds.
##
## Columns: time (wall clock), seed (the floor's), floor_s (seconds on the floor), restless (R then), event, kind, state,
## dist, secs, count, value, detail. Events:
##   facing     the first tick of a floor: count = idle monsters, value = share with a wall within 2 hexes ahead
##   first_hit  a monster's first hit taken from the crew: kind, state (idle / suspicious / alert / search / chase /
##              attack / return), dist = attacker to victim, detail = the attacker
##   suspect    a "?" ended: state = fight (it confirmed) or calm, secs = how long it lasted
##   fight      an engagement ended (no monster fighting for FIGHT_GAP s): count = peak monsters fighting at once,
##              secs = its length, value = monsters that took part
##   kill       a monster died: kind, state at death, secs = since its first hit (-1 if never hit by the crew)
##   noise      a spell's sound: kind = corn / fireball / teeth / tentacles, count = monsters that heard it
##   visitor    a restless skeleton extended its patrol into the next room
## Step 2 (monster-awareness.md, "Step 2 as built"):
##   scout      the goblin scout: state = sighted (dist = to the hero he saw) / stopped (detail: how: killed, soaked;
##              silent before his fuse caught) / launch (count = monsters the alarm woke, value = hellgates woken,
##              detail = scouts sent running; secs = since the sighting) / dud (soaked with the fuse lit) / yell
##              (count = monsters his shout woke)
##   practice   an archer's target-practice arrow landed: state = what it hit (prop, hero, other, nothing), dist = archer
##              to prop, value = the HP the prop lost, detail = the prop
##   brawl      a restless brute fight began: state = start, detail = the rival's kind
##   brawl_end  it ended: state = why (done, far, lost: on its own; sighting, hit, noise, shout, pack, rival_<state>: the
##              crew broke it up), secs = its length, count = slams
## The new monsters (combat-proposals.md §2 / §3, "As built"):
##   block      a Pavise's shield stopped a hit (the machine that resolved it; on a client's hit that is the client, which
##              writes no log, so the host's rows are the host's and the AI's hits): state = melee / shot / arrow / blast,
##              dist = attacker to the pavise, detail = the attacker
##   pulse      a Water Boy poured: count = monsters healed, value = HP restored in all

const PATH := "user://combat_log.csv"
const HEADER := "time,seed,floor_s,restless,event,kind,state,dist,secs,count,value,detail"
const FLUSH_EVERY := 10.0
const FLUSH_ROWS := 40
const FIGHT_GAP := 3.0            ## an engagement ends after this long with nobody fighting
const FIGHT_TICK := 0.25          ## how often fighters are counted (game seconds)
const SPELL_NOISES := ["corn", "fireball", "teeth", "tentacles"]

## Off in test runs (tests may switch it on to check the rows).
static var enabled := not OS.get_cmdline_user_args().has("--run-test")
static var path := PATH

static var _rows: PackedStringArray = []
static var _flushed_at := 0.0
static var _floor_key := 0
static var _tick_at := -INF
static var _fight_since := -1.0
static var _fight_last := -1.0
static var _fight_peak := 0
static var _fighters: Dictionary = {}    ## instance id -> true: monsters that fought in the open engagement


## Every simulated monster calls this each physics frame; it does its work at most every FIGHT_TICK.
static func tick() -> void:
	if not enabled or GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return
	var now := GameWorld.time
	if now - _tick_at < FIGHT_TICK:
		return
	_tick_at = now
	var key := GameWorld.root.get_instance_id()
	if key != _floor_key:
		_end_fight()
		_floor_key = key
		# The floor's world goes away (the next floor, the menu, quitting): close the open fight and write the rows.
		GameWorld.root.tree_exiting.connect(func() -> void: CombatLog.close_floor(), CONNECT_ONE_SHOT)
		_facing_row()
	var fighting := 0
	for n in GameWorld.root.get_tree().get_nodes_in_group("monsters"):
		if not n.dead and Net.simulates(n) and n.is_aggro():
			fighting += 1
			_fighters[n.get_instance_id()] = true
	if fighting > 0:
		if _fight_since < 0.0:
			_fight_since = now
		_fight_peak = maxi(_fight_peak, fighting)
		_fight_last = now
	elif _fight_since >= 0.0 and now - _fight_last >= FIGHT_GAP:
		_end_fight()
	if not _rows.is_empty() and (now - _flushed_at >= FLUSH_EVERY or _rows.size() >= FLUSH_ROWS):
		flush()


static func first_hit(m: Monster, attacker: Actor, state_name: String) -> void:
	if not enabled:
		return
	_row("first_hit", m.kind, state_name, GameWorld.flat_distance(m.global_position, attacker.global_position), -1.0, -1, "", attacker.display_name)


static func suspect_ended(m: Monster, secs: float, fought: bool) -> void:
	if not enabled:
		return
	_row("suspect", m.kind, "fight" if fought else "calm", -1.0, secs, -1, "", "")


static func kill(m: Monster, state_name: String, since_first_hit: float) -> void:
	if not enabled:
		return
	_row("kill", m.kind, state_name, -1.0, since_first_hit, -1, "", "")


static func noise(kind: String, heard: int) -> void:
	if not enabled or not SPELL_NOISES.has(kind):
		return
	_row("noise", kind, "", -1.0, -1.0, heard, "", "")


static func visitor(m: Monster) -> void:
	if not enabled:
		return
	_row("visitor", m.kind, "", -1.0, -1.0, -1, "", "")


static func scout(m: Monster, what: String, dist: float = -1.0, secs: float = -1.0, count: int = -1, value: String = "", detail: String = "") -> void:
	if not enabled:
		return
	_row("scout", m.kind, what, dist, secs, count, value, detail)


static func practice(archer: Variant, prop: Variant, dist: float, dealt: float, hit: Variant) -> void:
	if not enabled:
		return
	var what := "nothing"
	if hit != null and is_instance_valid(hit):
		what = "prop" if hit == prop else ("hero" if hit.team == GameWorld.TEAM_HEROES else "other")
	var label := str(prop.display_name) if prop != null and is_instance_valid(prop) else ""
	_row("practice", "archer", what, dist, -1.0, -1, "%.1f" % dealt, label)


static func brute_fight(lead: Monster, rival: Variant) -> void:
	if not enabled:
		return
	_row("brawl", lead.kind, "start", GameWorld.flat_distance(lead.global_position, rival.global_position), -1.0, -1, "", str(rival.kind))


static func brute_fight_end(lead: Variant, reason: String, secs: float, slams: int) -> void:
	if not enabled:
		return
	_row("brawl_end", "brute", reason, -1.0, secs, slams, "", "")


static func block(m: Monster, hit_kind: String, source: Node) -> void:
	if not enabled:
		return
	var a := source as Node3D
	var dist := GameWorld.flat_distance(m.global_position, a.global_position) if a != null and is_instance_valid(a) else -1.0
	_row("block", m.kind, hit_kind, dist, -1.0, -1, "", str(source.get("display_name")) if source != null and is_instance_valid(source) else "")


static func pulse(m: Monster, healed: int, restored: float) -> void:
	if not enabled:
		return
	_row("pulse", m.kind, "", -1.0, -1.0, healed, "%.1f" % restored, "")


## The floor is going away: close the open fight and write everything.
static func close_floor() -> void:
	if not enabled:
		return
	_end_fight()
	flush()


## Write the buffered rows now (a fight that has been quiet for FIGHT_GAP is closed first).
static func flush() -> void:
	_flushed_at = GameWorld.time
	if _fight_since >= 0.0 and GameWorld.time - _fight_last >= FIGHT_GAP:
		_end_fight()
	if _rows.is_empty():
		return
	var fresh := not FileAccess.file_exists(path)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if not fresh else FileAccess.WRITE)
	if file == null:
		_rows.clear()
		return
	file.seek_end()
	if fresh:
		file.store_line(HEADER)
	for r in _rows:
		file.store_line(r)
	file.close()
	_rows.clear()


## Forget the open engagement and the floor (tests).
static func reset() -> void:
	_rows.clear()
	_floor_key = 0
	_tick_at = -INF
	_fight_since = -1.0
	_fight_last = -1.0
	_fight_peak = 0
	_fighters.clear()


static func _facing_row() -> void:
	var idle := 0
	var walled := 0
	for n in GameWorld.root.get_tree().get_nodes_in_group("monsters"):
		if n.dead or not Net.simulates(n) or n.state != Monster.State.IDLE:
			continue
		idle += 1
		if MonsterSenses.wall_ahead(n, n.facing):
			walled += 1
	if idle > 0:
		_row("facing", "", "", -1.0, -1.0, idle, "%.3f" % (float(walled) / float(idle)), "")


static func _end_fight() -> void:
	if _fight_since >= 0.0:
		_row("fight", "", "", -1.0, maxf(0.0, _fight_last - _fight_since) + FIGHT_TICK, _fight_peak, str(_fighters.size()), "")
	_fight_since = -1.0
	_fight_last = -1.0
	_fight_peak = 0
	_fighters.clear()


static func _row(event: String, kind: String, state: String, dist: float, secs: float, count: int, value: String, detail: String) -> void:
	var cells: Array = [
		Time.get_datetime_string_from_system(), GameWorld.rng.seed, "%.1f" % MonsterSenses.floor_seconds(),
		"%.2f" % MonsterSenses.restlessness(), event, kind, state,
		"%.2f" % dist if dist >= 0.0 else "", "%.2f" % secs if secs >= 0.0 else "", count if count >= 0 else "", value,
		detail.replace(",", " ").replace("\"", "'"),
	]
	_rows.append(",".join(cells.map(func(c: Variant) -> String: return str(c))))
