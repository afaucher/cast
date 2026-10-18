class_name NetGameTest
extends NetTest
## NetTest plus the real game scene on every process: the shared-run tests (M1) put a game.gd node under the test
## and drive it through its own screens (the job board, the license checkout), exactly as a player would.
##
## Every process runs the SAME script with its role; the host is the judge (see NetTest). Helpers here: make_game()
## (a game with the test seams: no mic, scene changes recorded instead of done), the screens, the shared clock as the
## wall clock sees it (`truth()`: all the processes of a test share this machine's clock), and signing a license.

const GAME_SCRIPT := preload("res://scripts/app/game.gd")

var game: Node3D = null
## Every scene the game asked for (the menu when the crew ends, "" for the job board), in order.
var scene_changes: Array[String] = []

## Each seat's license, by test index (0 = the host): different on purpose, so a mix-up shows.
const LICENSES := [["heal", "corn"], ["fireball", "armor"], ["tentacles", "teeth"]]


## A game scene with the test seams. `extra` adds to its opts (the dev flags). `fresh` false keeps the contract in
## progress (the game's static state), as a scene reload does.
func make_game(extra: Dictionary = {}, fresh: bool = true) -> Node3D:
	if fresh:
		GAME_SCRIPT.reset_flow()
	var g: Node3D = GAME_SCRIPT.new()
	var o := {"no_mic": true, "van_intro": true}
	o.merge(extra, true)
	g.set("opts", o)
	g.set("scene_changer", func(p: String) -> void:
		scene_changes.append(p)
		if follow_reloads and p == "":
			_reload_game.call_deferred())
	add_child(g)
	game = g
	return g


## M3: when true, a scene reload the game asks for ("": the elevator down, the board) is DONE: the game node is replaced by a
## new one with the same flags and the contract in progress, exactly as reload_current_scene() would.
var follow_reloads := false
## How many reloads were followed.
var reloads := 0


func _reload_game() -> void:
	if game == null:
		return
	var o: Dictionary = (game.get("opts") as Dictionary).duplicate()
	var old := game
	game = null
	remove_child(old)
	old.free()
	await get_tree().process_frame
	reloads += 1
	make_game(o, false)


func board() -> JobBoard:
	return game.get("_board") as JobBoard if game != null else null


func picker() -> SpellPicker:
	return game.get("_picker") as SpellPicker if game != null else null


func flow() -> CrewFlow:
	return Session.flow


## The shared clock as this machine's wall clock says it is (all the processes share one machine's clock).
func truth() -> float:
	if Session.is_host():
		return Session.host_time()
	return Time.get_unix_time_from_system() - Session.host_unix_epoch


## The offers on a board as one comparable string.
static func offers_signature(offers: Array[ContractRun]) -> String:
	var parts: PackedStringArray = []
	for r in offers:
		parts.append("%s|%s|%s|%d|%d|%s" % [r.invoice_number, r.client_name, r.pest, r.contract_value, r.seed, r.story["event"]])
	return "\n".join(parts)


## A contract as one comparable string.
static func run_signature(r: ContractRun) -> String:
	return "%s|%s|%d|%.4f|%d|%s" % [r.invoice_number, r.archetype_id, r.seed, r.difficulty, r.contract_value, r.story["event"]]


## Tick two spells on the license requisition and sign it (await it): the name stamp holds SpellPicker.SIGN_HOLD as it
## does for a player, and this returns once the form has gone in (picked). False if there is no requisition open or it
## did not sign.
func sign_license(ids: Array) -> bool:
	var p := picker()
	if p == null:
		return false
	for id: String in ids:
		p.toggle(id)
	var went := [false]
	p.picked.connect(func(_s: Array[String]) -> void: went[0] = true)
	if not p.confirm():
		return false
	await until(func() -> bool: return went[0], p.sign_hold + 5.0)
	return went[0]


func my_license() -> Array:
	return LICENSES[index]


## Wait until the game has a board / a checkout / a running floor.
func wait_board(seconds: float = 20.0) -> bool:
	return await until(func() -> bool: return board() != null, seconds)


func wait_picker(seconds: float = 20.0) -> bool:
	return await until(func() -> bool: return picker() != null, seconds)


func wait_floor(seconds: float = 30.0) -> bool:
	return await until(func() -> bool: return game != null and bool(game.get("_floor_begun")), seconds)


## The hero this machine controls, and the seat it sits in.
func my_hero() -> Hero:
	return game.get("player") as Hero


func hero_at(seat: int) -> Hero:
	return (game.get("heroes_by_seat") as Dictionary).get(seat) as Hero


# --- M2: heroes walking, and what each machine saw of the others ------------------------------------------------

## A bot walking this machine's hero, if started.
var bot: NetBot = null
## Recording: every frame, this machine's own hero ([host_time, x, y, z] flattened) and what each puppet is showing
## ([render_time, x, y, z, host_time] flattened, per seat). The owner's ring is the TRUTH the viewers' series are held to.
var recording := false
var ring := PackedFloat64Array()
var seen: Dictionary = {}
## The heroes this machine streams that are not its own (the host's AI seats): seat -> ring.
var live_rings: Dictionary = {}

const FLOOR_OPTS := {"spells": "heal,corn"}
## A walking hero's top speed in units per second (Hero.move_speed 4.5, a little over for rounding).
const WALK_SPEED := 4.6


func my_seat() -> int:
	return int(Session.local_entry().get("seat", 0))


## Everyone gets to a running floor: the host waits for the crew, takes offer 1 (the game's own --net-wait / --spells
## dev flags, as run.ps1 -Crew does) and every machine signs. False (and a failed check) when anyone does not get there.
func enter_floor(seed_value: int, contract: int = 1, extra: Dictionary = {}) -> bool:
	var opts: Dictionary = FLOOR_OPTS.duplicate()
	opts.merge(extra, true)
	if is_host():
		if not check(await until(func() -> bool: return Session.roster.size() == peers, 20.0), "all %d join" % peers):
			return false
		opts.merge({"seed": seed_value, "contract": contract, "net_wait": peers}, true)
		make_game(opts)
	else:
		if not check(await connect_client() == "", "joined"):
			return false
		make_game(opts)
	return check(await wait_floor(45.0), "the floor starts")


## Hero sync on (the floor has started and this machine's van arrival is over).
func wait_sync(seconds: float = 20.0) -> bool:
	return check(await until(func() -> bool: return Session.snap.active, seconds), "the hero sync is running")


## Start the scripted walk (NetBot) on this machine's hero.
func start_bot() -> NetBot:
	if bot != null:
		bot.queue_free()
	bot = NetBot.new()
	game.add_child(bot)
	var hero := my_hero()
	var controller := game.get("controller") as PlayerController
	bot.start(hero, controller, NetBot.route_from(game.get("map") as HexMap, hero.current_cell(), 7, hero.can_climb))
	return bot


func record(on: bool) -> void:
	if on:
		ring = PackedFloat64Array()
		seen = {}
		live_rings = {}
	recording = on


func _process(delta: float) -> void:
	super._process(delta)
	if not recording or game == null or Session.snap == null:
		return
	var now := Session.host_time()
	var me := my_hero()
	if me != null:
		var p := me.global_position
		ring.append_array(PackedFloat64Array([now, p.x, p.y, p.z]))
	for seat in Session.snap.puppet_seats():
		var pp := Session.snap.puppet(seat)
		if pp.shown == null:
			continue
		var q := pp.hero.global_position
		var series: PackedFloat64Array = seen.get(seat, PackedFloat64Array())
		series.append_array(PackedFloat64Array([pp.render_t, q.x, q.y, q.z, now]))
		seen[seat] = series
	for seat in Session.snap.live_seats():
		if seat == my_seat():
			continue
		var h := hero_at(seat)
		var lr: PackedFloat64Array = live_rings.get(seat, PackedFloat64Array())
		lr.append_array(PackedFloat64Array([now, h.global_position.x, h.global_position.y, h.global_position.z]))
		live_rings[seat] = lr


## Where a recorded ring ([t, x, y, z]*) had the hero at time `t` (linear between frames); Vector3.INF outside it.
static func ring_at(r: PackedFloat64Array, t: float) -> Vector3:
	var n := r.size() >> 2
	if n < 2 or t < r[0] or t > r[(n - 1) * 4]:
		return Vector3.INF
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if r[mid * 4] <= t:
			lo = mid
		else:
			hi = mid
	var t0 := r[lo * 4]
	var t1 := r[hi * 4]
	var u := 0.0 if t1 <= t0 else (t - t0) / (t1 - t0)
	var a := Vector3(r[lo * 4 + 1], r[lo * 4 + 2], r[lo * 4 + 3])
	var b := Vector3(r[hi * 4 + 1], r[hi * 4 + 2], r[hi * 4 + 3])
	return a.lerp(b, u)


## A viewer's series ([render_t, x, y, z, now]*) held against the owner's ring: {n, max_err, mean_err, max_step,
## max_excess} over the frames the ring covers (from `skip` seconds after its start: the puppet's buffer fills first).
## Flat distances. max_step is the biggest move between two frames; max_excess is the same less what a hero could
## really walk in the time between those frames (WALK_SPEED x the frames' real gap), so a frame hitch is not a snap.
static func series_error(owner_ring: PackedFloat64Array, series: PackedFloat64Array, skip: float = 0.5) -> Dictionary:
	var n := 0
	var worst := 0.0
	var total := 0.0
	var max_step := 0.0
	var max_excess := 0.0
	var prev := Vector2.INF
	var prev_now := 0.0
	if owner_ring.size() < 8:
		return {"n": 0, "max_err": INF, "mean_err": INF, "max_step": INF, "max_excess": INF}
	var t_lo := owner_ring[0] + skip
	for i in floori(float(series.size()) / 5.0):
		var q := Vector2(series[i * 5 + 1], series[i * 5 + 3])
		var t := series[i * 5]
		var now := series[i * 5 + 4]
		var inside := t >= t_lo
		if inside and prev != Vector2.INF:
			var step := q.distance_to(prev)
			max_step = maxf(max_step, step)
			max_excess = maxf(max_excess, step - WALK_SPEED * (now - prev_now))
		prev = q
		prev_now = now
		if not inside:
			continue
		var truth := ring_at(owner_ring, t)
		if truth == Vector3.INF:
			continue
		var e := q.distance_to(Vector2(truth.x, truth.z))
		worst = maxf(worst, e)
		total += e
		n += 1
	return {"n": n, "max_err": worst, "mean_err": total / maxf(float(n), 1.0), "max_step": max_step, "max_excess": max_excess}


## The wire's counts for the snapshot packets this process got: [accepted, stale, gaps].
func snap_wire() -> Array:
	var ts: Array = Session.wire.type_stats.get(NetWire.T_SNAP, [0, 0, 0])
	return [int(ts[0]), int(ts[1]), int(ts[2])]


## Every client's peer id (host only).
func client_peers() -> Array[int]:
	var out: Array[int] = []
	for p: int in Session.roster:
		if p != 1:
			out.append(p)
	return out


# --- M5: the contract flow (exits, the invoice, the board, pause) ----------------------------------------------

## Put `hero` (this machine's own) on `cell`, on the ground.
func place_hero(hero: Hero, cell: Vector2i) -> void:
	var map := game.get("map") as HexMap
	var lv := map.ground_level(Hex.to_world(cell))
	hero.global_position = Hex.to_world(cell, 0.0 if is_nan(lv) else lv)
	hero.snap_to_ground()


## A floor cell exactly `dist` cells from `c` at about its level (Vector2i.MAX when there is none).
func cell_at(c: Vector2i, dist: int) -> Vector2i:
	var map := game.get("map") as HexMap
	var base: HexMap.Cell = map.get_cell(c)
	for n in Hex.range_cells(c, dist):
		var cell: HexMap.Cell = map.get_cell(n)
		if Hex.distance(n, c) == dist and cell != null and cell.type == HexMap.Tile.FLOOR and base != null and absi(cell.level - base.level) <= 1:
			return n
	return Vector2i.MAX


## The pause key (Esc) as the game's own input handler gets it.
func press_esc() -> void:
	var ev := InputEventAction.new()
	ev.action = "pause"
	ev.pressed = true
	game.call("_unhandled_input", ev)


## A value as one canonical string (sorted keys), to compare what two machines show.
static func canon(v: Variant) -> String:
	return JSON.stringify(v, "", true)


## The invoice on screen (canonical), "" when there is none.
func invoice_text() -> String:
	var inv: Dictionary = game.get("_last_invoice")
	return "" if inv.is_empty() else canon(inv)


## Every Ledger line (canonical).
static func ledger_text() -> String:
	return canon(Ledger.lines)


## The crew member named `who` ("host", "c1", ...): its peer id, 0 when absent.
static func peer_named(who: String) -> int:
	for e: Dictionary in Session.crew():
		if str(e["name"]) == who:
			return int(e["peer"])
	return 0


# --- M6: a player who joins a crew already on the job ------------------------------------------------------------

## A flag the processes of one run share: a file in user:// (one directory for every process of the project), named by the
## run's port. A late joiner is not connected yet, so it cannot be sent a command: the host raises a flag instead.
func flag_path(flag: String) -> String:
	return "user://net_tests/flag_%d_%s" % [port, flag]


func raise_flag(flag: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://net_tests")
	var f := FileAccess.open(flag_path(flag), FileAccess.WRITE)
	if f != null:
		f.store_string(str(Time.get_unix_time_from_system()))
		f.close()


func clear_flag(flag: String) -> void:
	if FileAccess.file_exists(flag_path(flag)):
		DirAccess.remove_absolute(flag_path(flag))


## Wait for a flag raised AFTER `since` (unix seconds; a stale file from an earlier run on the same port does not count).
func wait_flag(flag: String, since: float, seconds: float) -> bool:
	return await until(func() -> bool:
		if not FileAccess.file_exists(flag_path(flag)):
			return false
		var f := FileAccess.open(flag_path(flag), FileAccess.READ)
		if f == null:
			return false
		var t := float(f.get_as_text())
		f.close()
		return t >= since, seconds)


## Every host-owned actor alive here (NetJoin.living_ids) as a comparable string.
static func living_text() -> String:
	return str(NetJoin.living_ids())
