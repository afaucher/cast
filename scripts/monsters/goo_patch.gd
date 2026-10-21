class_name GooPatch
extends Node3D
## A goo patch (docs/design/goo-imp.md, "As built"): what a goo imp's ball leaves where it missed, on dry ground. RADIUS
## across, it lasts LIFE seconds (drying out over the last DRY_TIME) and:
##   SLOWS   everyone whose feet are on it, crew and monsters alike (heroes, monsters, employees, chickens; not a shark, not
##           anyone in the air): walking speed x SLOW while on it (Actor.effective_speed asks speed_mult). The Damp-style
##           LOCAL rule: derived from where the actor stands and the patches every screen has, so nothing travels for it.
##   BURNS   a fireball's blast on it (FireballSpell -> fire_at) LIGHTS it: it burns FIRE_TIME s and every FIRE_TICK hurts
##           whoever stands in it (FIRE_DAMAGE, the lighter is the source; a hero's fire never takes a hero below 1 HP, as
##           Burning). It does NOT set anyone Burning: no fire spread (the user, goo-imp.md §6.6). Then it is burnt off (a
##           scorch mark).
##   WASHES  Damp's drizzle on it (Damp._burst -> wash_at) REMOVES it; Damp's own wet floor is what is left (§6.7). A lit
##           patch goes out the same way.
##
## NETWORKING (networking.md: a host-arbitrated world object, made during play; NetObjects "RUNTIME OBJECTS"). The host's
## ball decides the patch (GooBall) and the host announces it (Net.announce -> obj.new {k "goo_patch"}); every client builds
## the same patch (net_copy). The host decides its two changes (fire_at / wash_at act only on patches this machine owns)
## and tells everyone `obj.goo {id, st, t, by}` (net_link / net_event): lit at shared time t by `by`, or washed. Every
## machine then runs the patch on its own clock: the slow (LOCAL, above), the burn's ticks on the actors it resolves
## (Net.resolves: each hero's own machine, the host for the rest), the drying and the burn-out. A late joiner gets every
## live patch with its state (late_join_state, section `new`, rebuilt as obj.new would).

signal changed

const KIND := "goo_patch"            ## NetObjects.RUNTIME_OBJECTS
const GROUP := "goo_patches"
const RADIUS := 0.8                  ## the user: "about 0.8 radius, 5 s ... as shown is fine until I play it"
const LIFE := 5.0
const DRY_TIME := 0.6                ## it shrinks away over its last this-many seconds
const SLOW := 0.5                    ## walking speed on goo (pool water is 0.75)
const SLOW_ID := "goo"               ## the hit's slow (Actor modifier, STAT_MOVE_SPEED): GooBall
const FEET_DY := 0.6                 ## feet this far above or below the patch are not in it
const FIRE_TIME := 3.0               ## a lit patch burns this long (the build's call: goo-imp.md §6.6 proposed ~3 s)
const FIRE_TICK := 0.5
const FIRE_DAMAGE := 4.0             ## per tick: 8 a second, 24 over the whole burn; an imp (12 HP) lasts 1.5 s in it
const WASH_TIME := 0.25
const STATE_GOO := 0
const STATE_LIT := 1
const STATE_WASHED := 2

## The live patches on this machine (Actor.effective_speed asks every frame: an empty list costs nothing).
static var _live: Array[GooPatch] = []

var radius := RADIUS
## Its birth on this machine's clock (the host's GameWorld.time, converted on a client).
var start_time := -1.0
var look_seed := 1
## Lit: the moment on this machine's clock (-1 = not lit) and who lit it (the burn's damage source).
var lit_at := -1.0
var lit_by: Node = null
var washed := false

## This screen: burn ticks run so far, and the burn damage this machine applied (tests).
var burns_applied := 0
var _ticks := 0
var _end := 0.0
var _gone_at := INF
var _bed: MeshInstance3D = null
var _flames: Array[MeshInstance3D] = []
var _flame_base: Array[Vector3] = []
var _light: OmniLight3D = null


## Who may write each var (see Net). Host-arbitrated: where and when it is are SPAWN (the obj.new row), its two changes the
## host's (obj.goo), the rest every screen's own.
func net_fields() -> Dictionary:
	return {
		"radius": Net.SPAWN, "start_time": Net.SPAWN, "look_seed": Net.SPAWN,
		"lit_at": Net.OWNER, "lit_by": Net.OWNER, "washed": Net.OWNER,
		"burns_applied": Net.LOCAL, "_ticks": Net.LOCAL, "_end": Net.LOCAL, "_gone_at": Net.LOCAL,
		"_bed": Net.LOCAL, "_flames": Net.LOCAL, "_flame_base": Net.LOCAL, "_light": Net.LOCAL,
	}


## A new patch at `at` (on the floor there) born at `start` (this machine's clock). The owner announces it (Net.announce).
static func make(at: Vector3, start: float, seed_value: int = 0) -> GooPatch:
	var p := GooPatch.new()
	p.start_time = start
	p.look_seed = seed_value if seed_value != 0 else 1 + absi(hash(Vector3i(roundi(at.x * 10.0), roundi(at.z * 10.0), roundi(start * 10.0)))) % 9973
	GameWorld.spawn(p, at)
	return p


# --- Asking (every machine) -----------------------------------------------------------------------------------------

## Walking speed multiplier for `a` from the patches under its feet (1.0 off the goo). Actor.effective_speed.
static func speed_mult(a: Actor) -> float:
	if _live.is_empty() or a == null or not affects(a) or a.is_airborne():
		return 1.0
	for p in _live:
		if is_instance_valid(p) and p.covers(a.global_position, a.radius * 0.5):
			return SLOW
	return 1.0


## Who goo sticks to: heroes, monsters (not a shark: it swims), employees and chickens. Never a prop, a crate or a gate.
static func affects(a: Actor) -> bool:
	if a.team == GameWorld.TEAM_HEROES:
		return true
	if a is Monster:
		return not a.is_in_group("sharks")
	return a.is_in_group("employees") or a.is_in_group("chickens")


## Is `pos` (a body `slack` wide) on this patch right now?
func covers(pos: Vector3, slack: float = 0.0) -> bool:
	if washed or GameWorld.time >= _end:
		return false
	return GameWorld.flat_distance(pos, global_position) <= radius + slack and absf(pos.y - global_position.y) <= FEET_DY


## Any live patch under `pos` (GooBoots).
static func covers_any(pos: Vector3, slack: float = 0.0) -> bool:
	for p in _live:
		if is_instance_valid(p) and p.covers(pos, slack):
			return true
	return false


static func live() -> Array[GooPatch]:
	var out: Array[GooPatch] = []
	for p in _live:
		if is_instance_valid(p) and not p.washed:
			out.append(p)
	return out


func is_lit() -> bool:
	return lit_at >= 0.0 and not washed


func state_code() -> int:
	return STATE_WASHED if washed else (STATE_LIT if lit_at >= 0.0 else STATE_GOO)


# --- What changes it (the owner decides) ----------------------------------------------------------------------------

## A fireball's blast at `pos` (radius `r`, from `source`): every patch it reaches that this machine owns lights.
## FireballSpell's blast runs on every machine; only the owner's patches (the host's online) are decided here.
static func fire_at(pos: Vector3, r: float, source: Node) -> int:
	var n := 0
	for p in _live.duplicate():
		if not is_instance_valid(p) or p.washed or p.lit_at >= 0.0 or not Net.owns(p):
			continue
		if GameWorld.flat_distance(p.global_position, pos) <= r + p.radius:
			p.light(GameWorld.time, source)
			n += 1
	return n


## Damp's drizzle at `pos` (radius `r`): every patch it reaches that this machine owns is washed away.
static func wash_at(pos: Vector3, r: float) -> int:
	var n := 0
	for p in _live.duplicate():
		if not is_instance_valid(p) or p.washed or not Net.owns(p):
			continue
		if GameWorld.flat_distance(p.global_position, pos) <= r + p.radius:
			p.wash()
			n += 1
	return n


## Light it at `at` (this machine's clock) by `by`. The owner's decision, or a client showing the host's (obj.goo).
func light(at: float, by: Node) -> void:
	if washed or lit_at >= 0.0:
		return
	lit_at = at
	lit_by = by
	_ticks = 0
	_end = maxf(_end, at + FIRE_TIME)
	_show_fire()
	changed.emit()


## Wash it away (Damp). The owner's decision, or a client showing the host's (obj.goo).
func wash() -> void:
	if washed:
		return
	washed = true
	_gone_at = GameWorld.time + WASH_TIME
	_clear_fire()
	changed.emit()
	if GameWorld.root != null and GameWorld.root.is_inside_tree():
		var fizz: Array[Color] = [Color(0.92, 0.96, 1.0), GooSoups.hot(GooSoups.BILE)]
		Fx.burst(global_position + Vector3.UP * 0.2, fizz, 10, 1.4, 0.08, 0.6, -1.2, Vector3.UP, 60.0, false)


# --- Life ----------------------------------------------------------------------------------------------------------------

func _ready() -> void:
	add_to_group(GROUP)
	if start_time < 0.0:
		start_time = GameWorld.time
	_end = start_time + LIFE
	if lit_at >= 0.0:
		_end = maxf(_end, lit_at + FIRE_TIME)
	_bed = GooSoups.patch(radius, look_seed)
	add_child(_bed)
	_bed.position = Vector3(0, 0.01, 0)
	_bed.rotation.y = float(look_seed % 628) * 0.01
	_bed.scale = Vector3.ONE * 0.3
	if lit_at >= 0.0:
		_show_fire()
	_look(GameWorld.time)


func _enter_tree() -> void:
	if not _live.has(self):
		_live.append(self)


func _exit_tree() -> void:
	_live.erase(self)


func _physics_process(_delta: float) -> void:
	var t := GameWorld.time
	if t >= _gone_at:
		queue_free()
		return
	if washed:
		return
	if lit_at >= 0.0:
		var due := mini(int(floor((t - lit_at) / FIRE_TICK + 0.0001)), int(round(FIRE_TIME / FIRE_TICK)))
		while _ticks < due:
			_ticks += 1
			_burn()
		if t >= lit_at + FIRE_TIME and _gone_at == INF:
			_burn_out()
		return
	if t >= _end:
		_gone_at = t
		queue_free()


func _process(_delta: float) -> void:
	_look(GameWorld.time)
	if washed or GameWorld.time >= _end:
		return
	for a in GameWorld.actors_in_radius(global_position, radius):   # (cosmetic: the goo on the feet of whoever stands in it)
		if affects(a) and not a.is_airborne() and covers(a.global_position, a.radius * 0.5):
			GooBoots.show_on(a)


## One tick of the burn: everyone standing in it whose damage this machine decides (Net.resolves) is hurt.
func _burn() -> void:
	var src: Node = lit_by if lit_by != null and is_instance_valid(lit_by) else null
	var src_actor := src as Actor
	for a in GameWorld.actors_in_radius(global_position, radius):
		if a.dead or not affects(a) or a.is_airborne() or absf(a.global_position.y - global_position.y) > FEET_DY:
			continue
		if not Net.resolves(a):
			continue   # (its owner's machine burns it: a hero's player, the host for everyone else)
		var amount := FIRE_DAMAGE
		if a.team == GameWorld.TEAM_HEROES and src_actor != null and src_actor.team == GameWorld.TEAM_HEROES:
			amount = minf(amount, (a.hp - 1.0) / maxf(a.damage_taken_mult(), 0.0001))   # (a hero's fire never downs a hero)
		if amount > 0.0:
			a.apply_damage(amount, src)
			burns_applied += 1
	if GameWorld.root != null and GameWorld.root.is_inside_tree():
		var embers: Array[Color] = [GooSoups.FIRE_INNER, GooSoups.FIRE_OUTER]
		Fx.burst(global_position + Vector3.UP * 0.4, embers, 4, 1.4, 0.06, 0.5, -1.5, Vector3.UP, 50.0)


## The burn is over: the goo is burnt off, a scorch mark stays (Grime, cosmetic).
func _burn_out() -> void:
	_gone_at = GameWorld.time + 0.4
	_end = GameWorld.time
	_clear_fire()
	Grime.mark(Grime.SCORCH, global_position, radius)


# --- The look (every screen) ---------------------------------------------------------------------------------------------

func _look(t: float) -> void:
	if _bed == null:
		return
	var grow := clampf((t - start_time) / 0.15, 0.0, 1.0)
	var k := lerpf(0.3, 1.0, grow)
	if washed:
		k *= clampf((_gone_at - t) / WASH_TIME, 0.0, 1.0)
	elif lit_at >= 0.0:
		if t >= lit_at + FIRE_TIME:
			k *= clampf((_gone_at - t) / 0.4, 0.0, 1.0)
	else:
		k *= clampf((_end - t) / DRY_TIME, 0.0, 1.0)
	_bed.scale = Vector3(maxf(k, 0.001), 1.0, maxf(k, 0.001))
	if _flames.is_empty():
		return
	var fade := clampf((lit_at + FIRE_TIME - t) / 0.6, 0.2, 1.0)
	for i in _flames.size():
		var b: Vector3 = _flame_base[i]
		var f := 0.75 + 0.3 * sin(t * 11.0 + b.x) + 0.15 * sin(t * 23.0 + b.x * 2.0)
		_flames[i].scale = Vector3(1.1 + 0.12 * sin(t * 9.0 + b.x), b.y * f * fade, 1.1 + 0.12 * cos(t * 9.0 + b.x))
	if _light != null:
		_light.light_energy = (2.0 + 0.6 * sin(t * 17.0)) * fade


## Lit: the bed turns to charred goo with embers, and flames (Burning's) stand all over it with a warm light.
func _show_fire() -> void:
	if not is_inside_tree() or not _flames.is_empty():
		return
	if _bed != null:
		var sc := _bed.scale
		var rot := _bed.rotation
		_bed.queue_free()
		_bed = GooSoups.patch(radius, look_seed, true)
		add_child(_bed)
		_bed.position = Vector3(0, 0.01, 0)
		_bed.rotation = rot
		_bed.scale = sc
	var rng := RandomNumberGenerator.new()
	rng.seed = look_seed   # (cosmetic: never GameWorld.rng)
	for i in 12:
		var a := rng.randf_range(0.0, TAU)
		var d := radius * sqrt(rng.randf()) * 0.95
		var big := i % 3 != 2
		var m := MeshInstance3D.new()
		m.mesh = GooSoups.flame_mesh(big)
		m.material_override = GooSoups.flame_mat(big)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s := rng.randf_range(0.7, 1.2) * (1.0 - 0.35 * d / radius)
		m.position = Vector3(cos(a) * d, 0.03, sin(a) * d)
		m.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.0, TAU), rng.randf_range(-0.2, 0.2))
		add_child(m)
		_flames.append(m)
		_flame_base.append(Vector3(rng.randf_range(0.0, TAU), s, 0.0))
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = radius * 3.0 + 2.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.0, 0)
	add_child(_light)
	if GameWorld.root != null and GameWorld.root.is_inside_tree():
		Fx.ring(global_position, radius + 0.3, Color(1.0, 0.55, 0.15, 0.8), 0.4)


func _clear_fire() -> void:
	for m in _flames:
		if is_instance_valid(m):
			m.queue_free()
	_flames.clear()
	_flame_base.clear()
	if _light != null and is_instance_valid(_light):
		_light.queue_free()
	_light = null


# --- The net-object contract (NetObjects) ---------------------------------------------------------------------------------

## Net ids: runtime objects are numbered as they are made (NetObjects.adopt); this only keeps NetFloor's order total.
func net_order() -> int:
	return 3


## A client's copy keeps its clock running (the burn's ticks on its own hero, the drying, the look); it decides nothing.
func net_make_copy() -> void:
	set_meta(Net.COPY_META, true)


## The host: the patch lit or washed goes to everyone as `obj.goo {id, st, t, by}`.
func net_link(objects: NetObjects, id: int) -> void:
	objects.link(changed, _net_changed.bind(objects, id))


func _net_changed(objects: NetObjects, id: int) -> void:
	objects.tell("obj.goo", {"id": id, "st": state_code(), "t": objects.host_stamp(lit_at) if lit_at >= 0.0 else 0.0,
		"by": NetFloor.id_of(lit_by) if lit_by != null and is_instance_valid(lit_by) else 0})
	objects.count("goo_out")


## A client: the host lit it (st 1, at shared time t, by `by`) or washed it (st 2).
func net_event(kind: String, data: Dictionary, objects: NetObjects) -> void:
	if kind != "obj.goo":
		return
	objects.count("goo_in")
	_apply_state(int(data.get("st", STATE_GOO)), float(data.get("t", 0.0)), int(data.get("by", 0)), objects)


func _apply_state(st: int, t: float, by: int, objects: NetObjects) -> void:
	match st:
		STATE_LIT:
			light(objects.local_stamp(t), NetRegistry.node(by))
		STATE_WASHED:
			wash()


## The host: what a client needs to build it (obj.new): where, its birth (shared clock), its size and look, its state.
func net_spawn_row(objects: NetObjects) -> Array:
	return [global_position, objects.host_stamp(start_time), radius, look_seed, state_code(),
		objects.host_stamp(lit_at) if lit_at >= 0.0 else 0.0, NetFloor.id_of(lit_by) if lit_by != null and is_instance_valid(lit_by) else 0]


## A client: the host's patch from its row, on this machine's clock.
static func net_copy(row: Array, objects: NetObjects) -> Node:
	if row.size() < 7 or GameWorld.root == null:
		return null
	var p := GooPatch.new()
	p.start_time = objects.local_stamp(float(row[1]))
	p.radius = float(row[2])
	p.look_seed = int(row[3])
	if int(row[4]) == STATE_LIT:
		p.lit_at = objects.local_stamp(float(row[5]))
		p.lit_by = NetRegistry.node(int(row[6]))
	if int(row[4]) == STATE_WASHED:
		return null
	GameWorld.spawn(p, row[0])
	return p


## The host: a late joiner's row: the patch as obj.new would build it, with its state now.
func late_join_state(objects: NetObjects, id: int) -> Dictionary:
	if washed or GameWorld.time >= _end:
		return {}
	return {"new": [id, KIND, net_spawn_row(objects)]}


## The late joiner: a patch it already has (never, as built: it builds the floor fresh) takes the host's state.
func apply_late_join(section: String, row: Array, objects: NetObjects) -> void:
	if section != "new" or row.size() < 3:
		return
	var r := row[2] as Array
	if r != null and r.size() >= 7:
		_apply_state(int(r[4]), float(r[5]), int(r[6]), objects)
