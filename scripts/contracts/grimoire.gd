class_name Grimoire
extends Hellgate
## The grimoire: a haunted contract's source, on its last floor (docs/design/haunted-build-plan.md, "H6 as built";
## new-themes.md "The mission": "pulsing out the dead until it is slammed shut or burned"). A physical object, never text: a
## shut book with a live eye on its cover, on a stone altar in the story's room (GrimoireModel "altar", the user's pick).
##
## It is a HELLGATE in shape (it extends Hellgate, so its spawner, its phases, its phase-change shove and its networking are
## the origin gate's: the gate track of the snapshot, world.phase / world.shove / world.spawn / world.die):
##   DORMANT  the book shut, the eye on its cover darting about, the candles and a dim circle lit. A hero within
##            ACTIVATE_RANGE (12), a hit or a monster's alarm wakes it (Hellgate's rule).
##   AWAKE    the book flies open and pulses out the dead: a burst every `spawn_interval` (the pages flare first, then 2-6 of
##            the dead family rise in a ring 3-4 cells out: skeletons and zombies, crypt rats in its last phase), up to its
##            cap of living spawns. Its numbers come from its own table below (difficulty and depth, the hellgate's pressure).
##   PHASES   by HP, as the origin gate: open (> 66 %), weakened (<= 66 %), failing (<= 33 %): each faster, bigger bursts and a
##            higher cap. Each phase change winds up (SHOVE_WINDUP) and blasts the crew back (the origin gate's shove) AND
##            stands every unburnt zombie body within RAISE_RADIUS back up at full HP (Zombie.raise: burn them first).
##   CLOSED   at 0 HP. Hit it shut and it is SLAMMED SHUT (the cover slams, the eye dies, the chain round it, every light out);
##            if it was on fire when it went it is BURNED (charred, smoking). Fire is the fast way: a fireball always lights
##            its pages (fire_at, before the blast lands) and a fire on it burns BURN_MULT times as hard (Burning). Damp
##            puts it out, as any fire. Closing stops its spawns (HellgateEvents.stop_spawns, as the origin gate's) and pays
##            the grimoire objective (game.gd, ContractSession.grimoire_closed). The shut book stays on its altar.
##
## Online: an owned actor of the host's in the hellgate's shape. Its OWNER vars are the gate's (the GATE entry of the
## snapshot) plus `burnt` (world.burn {id}, sent after its world.die when it closed burning). A late joiner gets a living one
## from the keyframe and a closed one as a gone id shown shut, then the snapshot's `books` rows (NetWorld.book_states) char it.

## A burning grimoire closed (on its owner, after `closed`): online the host tells everyone (world.burn).
signal burnt_down

# ============================ TUNING TABLE (every number lives here) ============================
# Lerped on the hellgate's pressure p (Hellgate.pressure: difficulty and depth) from the EASY end (p = 0) to the HARD end.
const BOOK_HP_EASY := 450.0
const BOOK_HP_HARD := 750.0
const BOOK_INTERVAL_EASY := 12.0  ## seconds between bursts
const BOOK_INTERVAL_HARD := 5.5
const BOOK_BURST_EASY := 2.0      ## the dead per burst
const BOOK_BURST_HARD := 4.0
const BOOK_CAP_EASY := 5.0        ## max living spawns
const BOOK_CAP_HARD := 12.0
# Per phase (open, weakened, failing)
const BOOK_PHASE_INTERVAL_MULT: Array[float] = [1.0, 0.75, 0.55]
const BOOK_PHASE_BURST_BONUS: Array[float] = [0.0, 1.0, 2.0]
const BOOK_PHASE_CAP_BONUS: Array[float] = [0.0, 2.0, 4.0]
## The dead a burst deals, per phase {kind: weight} (the haunted family: skeletons, zombies, crypt rats).
const KIND_WEIGHTS: Array[Dictionary] = [
	{"grunt": 3.0, "zombie": 2.0},
	{"grunt": 3.0, "zombie": 3.0},
	{"grunt": 2.0, "zombie": 3.0, "crypt_rat": 2.0},
]
const RAISE_RADIUS := 9.0        ## a phase change stands up every unburnt zombie body this close
const BURN_MULT := 6.0           ## a fire on its pages: 18 HP a second (a fire's usual 3)
const FIRE_SECONDS := Burning.DURATION_MAX   ## a fireball over it lights it for this long (no roll)
const BOOK_RADIUS := 2.2         ## its altar's footprint (heroes cannot stand in it)
# ================================================================================================

const NAME := "Grimoire"
const STAND := "altar"
## Its altar faces the game camera (the camera looks along -X -Z at yaw 45): the front, the runner and the skulls to the
## screen, whatever room it is in.
const FACING := -0.75 * PI
## The book's state in each phase (GrimoireModel).
const PHASE_STATES: Array[String] = ["open", "weakened", "failing"]

var yaw := 0.0                    ## which way the altar faces (FACING: its reader's side to the game camera)
var burnt := false                ## closed while on fire: burned, not slammed shut
var raised_total := 0             ## bodies its phase changes stood back up
var book: GrimoireModel = null
var _burn_seen := false           ## (the owner: it was on fire as the killing blow landed)


## Make a grimoire standing on `cell`. opts: difficulty 0..1, depth 1..3, yaw (radians), max_hp optional. Null without a
## world.
static func place(cell: Vector2i, opts: Dictionary = {}) -> Grimoire:
	if GameWorld.root == null:
		push_warning("Grimoire.place: no world")
		return null
	var g := Grimoire.new()
	g.configure(opts)
	g.name = NAME
	var level := 0.0
	var map := GameWorld.map
	if map != null:
		var l := map.ground_level(Hex.to_world(cell))
		if not is_nan(l):
			level = l
	g._rng.seed = hash(Vector3i(cell.x, cell.y, 977))
	GameWorld.spawn(g, Hex.to_world(cell, level))
	return g


## The spawn numbers of a grimoire: {pressure, interval, burst, cap, rate, hp} (Hellgate.profile's shape).
static func book_profile(difficulty_value: float, depth_value: int, phase_value: int = 0) -> Dictionary:
	var p := Hellgate.pressure(difficulty_value, depth_value)
	var ph := clampi(phase_value, 0, BOOK_PHASE_INTERVAL_MULT.size() - 1)
	var interval := lerpf(BOOK_INTERVAL_EASY, BOOK_INTERVAL_HARD, p) * BOOK_PHASE_INTERVAL_MULT[ph]
	var n := maxi(1, roundi(lerpf(BOOK_BURST_EASY, BOOK_BURST_HARD, p) + BOOK_PHASE_BURST_BONUS[ph]))
	var cap := maxi(1, roundi(lerpf(BOOK_CAP_EASY, BOOK_CAP_HARD, p) + BOOK_PHASE_CAP_BONUS[ph]))
	return {"pressure": p, "interval": interval, "burst": n, "cap": cap, "rate": float(n) / interval,
			"hp": lerpf(BOOK_HP_EASY, BOOK_HP_HARD, p)}


## Every open grimoire in the current world.
static func open_books() -> Array[Grimoire]:
	var out: Array[Grimoire] = []
	for g in Hellgate.open_gates():
		if g is Grimoire:
			out.append(g as Grimoire)
	return out


## A fireball is about to blow at `pos` (FireballSpell, before its blast's damage lands): every grimoire it covers catches
## fire, no roll (its pages burn), so a fireball that finishes one burns it. Its owner lights it (Net.resolves).
static func fire_at(pos: Vector3, radius: float, source: Node) -> void:
	for g in open_books():
		if not Net.resolves(g) or GameWorld.flat_distance(g.global_position, pos) > radius + g.radius:
			continue
		Burning.ignite(g, source, FIRE_SECONDS)


func configure(opts: Dictionary) -> void:
	difficulty = clampf(float(opts.get("difficulty", 0.5)), 0.0, 1.0)
	depth = clampi(int(opts.get("depth", ContractRun.FLOOR_COUNT)), 1, 3)
	origin = true   # (the floor's source: the origin gate's phases, ring and bar)
	pest = ""
	yaw = float(opts.get("yaw", 0.0))
	var prof := book_profile(difficulty, depth, 0)
	max_hp = float(opts["max_hp"]) if opts.has("max_hp") else float(prof["hp"])
	hp = max_hp
	team = GameWorld.TEAM_MONSTERS
	shove_mult = 0.0
	radius = BOOK_RADIUS
	display_name = NAME
	move_speed = 0.0
	_apply_profile()


func _init() -> void:
	display_name = NAME
	radius = BOOK_RADIUS
	origin = true


## Who may write each var (see Net); Hellgate's and Actor's come from super(). The host runs it, as a hellgate.
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"yaw": Net.SPAWN,                 # (from the plan)
		"burnt": Net.OWNER,               # world.burn (NetWorld), after its world.die; a late joiner: `books`
		"_burn_seen": Net.PRIVATE,        # (the owner's note at the killing blow)
		"raised_total": Net.PRIVATE,      # (a count for the tests)
		"book": Net.LOCAL,
	})
	return f


func is_closed() -> bool:
	return dead


# --- Overrides of the hellgate --------------------------------------------------------------------------------

func _profile_now() -> Dictionary:
	return book_profile(difficulty, depth, phase)


func _weights_now() -> Dictionary:
	return KIND_WEIGHTS[clampi(phase, 0, KIND_WEIGHTS.size() - 1)]


func is_flammable() -> bool:
	return true


func burn_mult() -> float:
	return BURN_MULT


## The owner notes whether the killing blow found it on fire (Burning's own tick, or any hit while it burned): the fire
## ends with the death (Burning's "died"), so it is asked now.
func _on_damaged(amount: float, source: Node) -> void:
	if hp <= 0.0 and not dead and Net.owns(self):
		_burn_seen = Burning.is_burning(self)
	super(amount, source)


## The phase change's blast: the origin gate's shove, then every unburnt zombie body near it stands back up (its owner, the
## host, raises it: Zombie.raise, full HP; online world.rise). Only where it is simulated (a client shows world.shove).
func _fire_shove() -> void:
	super()
	_raise_bodies()


func _raise_bodies() -> int:
	var n := 0
	for b in GameWorld.downed_in_radius(global_position, RAISE_RADIUS, GameWorld.TEAM_MONSTERS, true):
		if b is Zombie and Net.resolves(b) and (b as Zombie).raise():
			n += 1
	raised_total += n
	return n


# --- The look ----------------------------------------------------------------------------------------------------

func _build_look() -> void:
	var seed_phase := float(absi(hash(Vector2(global_position.x, global_position.z))) % 1000) / 100.0
	book = GrimoireModel.make(STAND, "dormant", seed_phase)
	book.rotation.y = yaw
	add_child(book)
	_bar_width = 3.0
	_bar_height = book.ui_height + 0.35


func _look_awake() -> void:
	if book == null:
		return
	book.set_state(PHASE_STATES[clampi(phase, 0, PHASE_STATES.size() - 1)])
	book.pulse(2.0)
	if fx_enabled:
		Fx.ring(global_position + Vector3.UP * 0.1, BOOK_RADIUS + 1.5, _ghost(0.9), 0.7, 0.0, true, 0.3)
		Fx.burst(global_position + Vector3.UP * 2.2, _ghosts(), 26, 3.5, 0.08, 0.9, -1.0, Vector3.UP, 70.0)


func _look_flare(k: float) -> void:
	if book != null:
		book.set_flare(k)


func _look_pulse(strength: float) -> void:
	if book != null:
		book.pulse(strength)


func _look_hurt() -> void:
	if book != null:
		book.pulse(0.35)


func _look_phase() -> void:
	if book != null and _active and not dead:
		book.set_state(PHASE_STATES[clampi(phase, 0, PHASE_STATES.size() - 1)])
		book.pulse(1.5)


func _look_shove() -> void:
	if book != null:
		book.pulse(1.0)
	if fx_enabled:
		# (the hellgate draws a red ring growing over the wind-up; the book a pale one)
		Fx.ring(global_position + Vector3.UP * 0.08, SHOVE_RADIUS, _ghost(0.75), SHOVE_WINDUP, 0.0, false, 0.15)


func _look_close() -> void:
	if book != null:
		book.close_look(burnt)


func _burst_fx(spawned: Array) -> void:
	if fx_enabled:
		for n: Variant in spawned:
			var m := n as Node3D
			if m != null and is_instance_valid(m):
				Fx.burst(m.global_position + Vector3.UP * 0.2, _ghosts(), 10, 2.2, 0.07, 0.7, -0.6, Vector3.UP, 50.0)
				Fx.ring(m.global_position + Vector3.UP * 0.05, 0.9, _ghost(0.8), 0.5, 0.0, false, 0.2)
	_look_pulse(1.6)
	if fx_enabled and not spawned.is_empty():
		Fx.ring(global_position + Vector3.UP * 0.1, radius + 1.2, _ghost(0.8), 0.5, 0.0, true, 0.5)


func _shove_fx() -> void:
	_look_pulse(2.5)
	if fx_enabled:
		Fx.ring(global_position + Vector3.UP * 0.1, SHOVE_RADIUS, _ghost(0.9), 0.55, 0.0, false, 0.3)
		Fx.burst(global_position + Vector3.UP * 1.8, _ghosts(), 40, 7.0, 0.1, 0.9, -0.5, Vector3.UP, 85.0)
		Fx.shake(0.35)


static func _ghost(alpha: float) -> Color:
	var c := NecroLook.glow_colour()
	return Color(c.r, c.g, c.b, alpha)


static func _ghosts() -> Array[Color]:
	var c := NecroLook.glow_colour()
	return [c, c.lightened(0.4), Color(0.85, 0.82, 0.70)]


# --- Puppet ---------------------------------------------------------------------------------------------------

## The host closed it burning (world.burn, after its world.die; a late joiner's `books`): charred here too.
func net_burn() -> void:
	if burnt:
		return
	burnt = true
	if dead and book != null:
		book.close_look(true)


# --- Closing -------------------------------------------------------------------------------------------------------

## Closed: it stops (and every other spawner on the floor with it, as the origin gate does), the shut book stays on its
## altar (an immovable blocker where the altar stands), and a burning one burns (the owner tells the others).
func _on_death() -> void:
	remove_from_group(GROUP)
	_shove_t = -1.0
	_telegraphing = false
	if Net.owns(self):
		burnt = _burn_seen
	HellgateEvents.stop_spawns()
	closed.emit(self)
	if _bar != null:
		_bar.visible = false
	_look_close()
	if fx_enabled:
		Fx.shake(0.3)
		Fx.burst(global_position + Vector3.UP * 2.0, _ghosts(), 30, 4.0, 0.09, 1.0, 2.0, Vector3.UP, 90.0)
	var block := DecorBlocker.new()
	block.name = "Altar"
	block.radius = BOOK_RADIUS
	add_child(block)
	if burnt and Net.owns(self):
		burnt_down.emit()
