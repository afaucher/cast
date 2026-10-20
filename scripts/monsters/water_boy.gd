class_name WaterBoy
extends Monster
## The Water Boy, the enemy healer (docs/design/enemy-healer-options.md §7 and §3 A; combat-proposals.md §3, "As built"):
## a goblin sports medic wheeling the office water cooler on a hand truck. "Water break!" It never attacks: it keeps back
## and heals its pack, so it is the crew's priority target (the AI allies rank it up: Monster.is_priority_target).
##
## BEHAVIOUR (host). Awareness as every monster (monster.gd). In a fight:
##   KEEP BACK   it stands KEEP_MIN-KEEP_MAX from the nearest hero, on the far side of its pack (the pack's centre plus
##               BEHIND, seen from that hero), and walks there at SPEED (the truck is slow)
##   THE TELL    POUR_TELL (0.8 s): it raises the whistle (a wind-up: the monsters' orange pulse too)
##   THE PULSE   rings run out to PULSE_RADIUS and every monster inside but itself gets +PULSE_HEAL (imps included; never a
##               hero, an employee or a chicken). Only when one of them is hurt; then POUR_COOLDOWN
## COUNTERS: a shove or a daze during the tell cancels the pour (Monster._on_interrupted: the wind-up drops; then FUMBLE
## before it tries again); it has
## little HP (HP); it cannot climb a +2 ledge with the truck.
##
## ONLINE: a host-owned actor with no state of its own beyond a monster's. The tell IS the monsters' wind-up channel:
## world.windup carries it (a client shows the whistle from the stream's telegraph) and world.unwind calls it off; at the
## strike moment each client runs the pulse on its own screen (Monster.net_strike: the rings), and the heals apply only
## where Net.resolves says, so only on the host, which owns every monster; the HP rides the stream. A late joiner: a
## monster's keyframe (a pour under way is skipped, under a second).

const HP := 30.0
const SPEED := 2.4
const AGGRO := 8.0
const KEEP_MIN := 6.0
const KEEP_MAX := 9.0
const BEHIND := 2.0               ## how far behind its pack's centre it likes to stand (seen from the nearest hero)
const PACK_RADIUS := 10.0         ## the monsters this close count as its pack
const POUR_TELL := 0.8
const POUR_COOLDOWN := 5.0
const PULSE_RADIUS := 5.0
const PULSE_HEAL := 15.0
const HURT_MIN := 1.0             ## pours only when a monster in reach misses at least this much HP
const FUMBLE := 1.5               ## a pour called off (a shove, a daze): it fumbles the whistle this long before trying again
const ARRIVE := 0.6
const BILE := Color(0.80, 1.0, 0.16)      ## the enemy chartreuse (enemy-healer-options.md §1: never the Heal spell's mint)
const BILE_HOT := Color(0.93, 1.0, 0.55)

## Rings this screen showed (tests).
var pulses := 0
## Host: what the last pulse healed: [[actor, hp restored]] (tests).
var last_heals: Array = []


func _init() -> void:
	super._init()
	kind = "water_boy"
	display_name = "Water Boy"
	max_hp = HP
	move_speed = SPEED
	radius = 0.45
	can_climb = false              # (the hand truck)
	aggro_range = AGGRO
	attack_damage = 0.0
	attack_windup = POUR_TELL
	attack_cooldown = POUR_COOLDOWN
	attack_start_range = 0.0
	stop_distance = 0.0
	employee_chance = 0.0
	bar_height = 2.4
	bar_width = 0.9


func net_fields() -> Dictionary:
	var f := super()
	f.merge({"pulses": Net.LOCAL, "last_heals": Net.PRIVATE})
	return f


func is_priority_target() -> bool:
	return true


## The primitive fallback body (Monster.use_proto_visuals): a goblin in a white polo behind a cooler on a hand truck.
func _build_visual(root: Node3D) -> void:
	var skin := _mat(Color(0.55, 0.62, 0.24))
	var polo := _mat(Color(0.93, 0.92, 0.88))
	var cap := _mat(Color(0.82, 0.3, 0.14))
	var steel := _mat(Color(0.72, 0.75, 0.78))
	var water := _mat(BILE, 2.5)
	_cyl(root, 0.18, 0.2, 0.55, Vector3(0.0, 0.85, 0.15), polo)
	_sphere(root, 0.17, Vector3(0.0, 1.3, 0.1), skin)
	_cyl(root, 0.19, 0.19, 0.08, Vector3(0.0, 1.45, 0.1), cap)
	_box(root, Vector3(0.44, 0.84, 0.4), Vector3(0.0, 0.5, -0.75), steel)
	_cyl(root, 0.22, 0.22, 0.5, Vector3(0.0, 1.17, -0.75), water)


# --- Host AI ------------------------------------------------------------------------------------------------------

func _tick_chase(delta: float) -> void:
	if not _validate_target(delta):
		return
	var hero := _nearest_any_hero()
	if hero == null:
		hero = target
	if GameWorld.time >= _next_attack_time and _someone_hurt():
		_begin_windup(scaled_cooldown(POUR_TELL))
		return
	var spot := keep_spot(hero)
	if GameWorld.flat_distance(global_position, spot) > ARRIVE:
		_nav_to(spot, delta)
	else:
		_prog_t = 0.0
		face_point(hero.global_position)


## Where it wants to stand: KEEP_MIN-KEEP_MAX from `hero`, on the far side of its pack (see the header).
func keep_spot(hero: Actor) -> Vector3:
	var hp := hero.global_position
	var c := _pack_centre()
	var away := c - hp
	away.y = 0.0
	if away.length() < 0.5:
		away = global_position - hp
		away.y = 0.0
	if away.length() < 0.01:
		away = -facing
	var d := clampf(GameWorld.flat_distance(hp, c) + BEHIND, KEEP_MIN, KEEP_MAX)
	var spot := hp + away.normalized() * d
	var map := GameWorld.map
	if map != null and (is_nan(map.ground_height(spot)) or map.wall_at(spot)):
		# No floor there (a wall, a pit): back straight away from the hero instead, within the band.
		var mine := global_position - hp
		mine.y = 0.0
		var md := clampf(mine.length(), KEEP_MIN, KEEP_MAX)
		spot = hp + (mine.normalized() if mine.length() > 0.01 else away.normalized()) * md
	spot.y = global_position.y
	return spot


## The centre of the living monsters within PACK_RADIUS (not itself); its own spot when alone.
func _pack_centre() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for m in get_tree().get_nodes_in_group("monsters"):   # (duck-typed: see Monster._alert_pack)
		if m == self or m.dead or m.kind == kind:
			continue
		if GameWorld.flat_distance(m.global_position, global_position) <= PACK_RADIUS:
			sum += m.global_position
			n += 1
	return sum / n if n > 0 else global_position


func _nearest_any_hero() -> Actor:
	var best: Actor = null
	var best_d := INF
	for h in heroes():
		if not is_instance_valid(h) or h.dead:
			continue
		var d := GameWorld.flat_distance(global_position, h.global_position)
		if d < best_d:
			best = h
			best_d = d
	return best


## A monster within the pulse's reach (not itself) misses HURT_MIN or more.
func _someone_hurt() -> bool:
	for m in get_tree().get_nodes_in_group("monsters"):
		if m == self or m.dead:
			continue
		if GameWorld.flat_distance(m.global_position, global_position) <= PULSE_RADIUS + m.radius and m.hp <= m.max_hp - HURT_MIN:
			return true
	return false


## A shove, a stagger or a daze during the tell calls the pour off (Monster), and it fumbles a moment (FUMBLE).
func _on_interrupted() -> void:
	if state == State.ATTACK and Net.owns(self):
		_next_attack_time = maxf(_next_attack_time, GameWorld.time + FUMBLE)
	super._on_interrupted()


# --- The pulse (every screen: the host's strike, a client's from world.windup) --------------------------------------

func _strike() -> void:
	pulse()


## Rings out to PULSE_RADIUS; +PULSE_HEAL to every monster inside but itself, applied where Net.resolves says (the host).
func pulse() -> void:
	var pos := global_position
	last_heals = []
	var healed := 0
	var restored := 0.0
	for a in GameWorld.actors_in_radius(pos, PULSE_RADIUS, GameWorld.TEAM_MONSTERS):
		if a == self or a.dead:
			continue
		var missing := a.max_hp - a.hp
		if missing > 0.5:
			Fx.number(a.global_position + Vector3.UP * 2.2, "+%d" % int(round(minf(missing, PULSE_HEAL))), BILE_HOT, 0.9)
		if not Net.resolves(a):
			continue   # (online: the host heals its monsters; a client only shows the rings and the numbers)
		var got := a.heal(PULSE_HEAL)
		if got > 0.0:
			healed += 1
			restored += got
			last_heals.append([a, got])
	_show_pulse(pos)
	if Net.owns(self):
		CombatLog.pulse(self, healed, restored)


func _show_pulse(pos: Vector3) -> void:
	pulses += 1
	if GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return
	Fx.ring(pos, PULSE_RADIUS, BILE, 0.55)
	Fx.ring(pos, PULSE_RADIUS * 0.8, BILE_HOT, 0.8, 0.0, false, 0.1)
	var jug := pos + Vector3.UP * 1.3 + Vector3(facing.x, 0.0, facing.z).normalized() * 0.9   # (the cooler rides in front of it)
	var water: Array[Color] = [BILE, BILE_HOT]
	Fx.burst(jug, water, 18, 3.0, 0.08, 0.6, 9.0, Vector3.UP, 50.0)


## A puppet's pour when its wind-up event was missed: the rings (the host healed).
func _on_strike_visual() -> void:
	_show_pulse(global_position)
