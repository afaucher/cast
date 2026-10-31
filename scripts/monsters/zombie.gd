class_name Zombie
extends Monster
## The haunted contracts' zombie (docs/design/haunted-build-plan.md, H3; new-themes.md "Zombies and acolytes", decided; its
## look: necro-look.md, ZombieModel's mourner and digger). The dead family's slow melee shamble: it shuffles after the crew,
## winds up a long, readable grab and swipes the cone in front of it (Monster's melee). Slow and tough: more HP than a
## skeleton, half its speed.
##
## A ZOMBIE THAT DIES STAYS DOWN AS A BODY (the user, 2026-10-29: "if they get knocked down the acolyte can bring them back").
## Its downed state is Actor.dead, as a downed hero's is: every query and verb that skips the dead skips a body (no target, no
## hit, no blocking, no pest count: it leaves the "monsters" group), but the node stays on the floor lying face down
## (ZombieModel.pose_rise(0): greyed, the motes rising off it say "it can get up") and the downed query finds it
## (GameWorld.downed_in_radius, Actor.is_downed). It never gets up by itself.
##   RAISED   Actor.revive (the verb; the body's owner applies it, the host: Net.resolves) stands it back up at `to_hp`:
##            Coffee's splash (Combat.revive_radius, any team, CoffeeSpell.ZOMBIE_HP) and, from H4, an acolyte (raise(): full
##            HP). It pushes up on its arms over RISE_TIME (helpless meanwhile, on every screen), then fights as before. Heal
##            and Revive stay allies-only (their team filter). To revisit before the milestone ends: whether Heal raises them.
##   BURNT    Actor.burn_body (the verb; the body's owner): a fire reaching the body (a fireball's blast over it,
##            Burning.on_blast; Burning.ignite on a body) or going down while on fire chars it (ZombieModel charred: char
##            black, ember cracks, smoke instead of motes), and a burnt body can never be raised (_can_revive false: out of the
##            downed query). Burning is useful, never required.
## Its component drops are rolled the first time it goes down only (a raised zombie drops nothing again).
## Online (an owned actor, a host monster): `dead` rides world.die / world.rise and `burnt` world.burn (NetWorld); a late joiner
## gets every body (where it lies, which way, burnt or not) from the snapshot's `bodies` (NetWorld.body_states). Its look
## (mourner or digger) is SPAWN: a hash of its spawn cell, the same on every machine.

## The body was charred (burn_body on its owner). Online the host tells everyone (world.burn).
signal burnt_down

const HP := 70.0
const SPEED := 1.5
const DAMAGE := 12.0
const WINDUP := 0.7
const COOLDOWN := 1.8
const AGGRO := 7.0
const REACH := 1.35           ## strike reach (the target's radius is added on top)
const START_RANGE := 1.45     ## the wind-up starts at this centre distance
const ARC_DEG := 110.0
## Seconds from the raise until it stands and acts (it pushes up on its arms meanwhile, on every screen).
const RISE_TIME := 1.4
## How far a body reaches past its feet lying face down (its head and flung arm): it falls away from a wall this close.
const LIE_LEN := 1.3
## One zombie in this many is the digger (by its spawn cell); the rest are the mourner (the user's "the zombie").
const DIGGER_EVERY := 3

var variant := "mourner"          ## ZombieModel's: "mourner" or "digger" (variant_for its spawn cell)
var burnt := false                ## a charred body: it stays down for good
var raises := 0                   ## times this machine showed it stand back up (tests, the gym)
var _dropped := false             ## its component drops were rolled (the first time down)
var _rise_t := -1.0               ## seconds into the stand-up (-1: not rising)


func _init() -> void:
	super._init()
	kind = "zombie"
	display_name = "Zombie"
	max_hp = HP
	move_speed = SPEED
	radius = 0.4
	aggro_range = AGGRO
	attack_damage = DAMAGE
	attack_windup = WINDUP
	attack_cooldown = COOLDOWN
	attack_reach = REACH
	attack_start_range = START_RANGE
	attack_arc_deg = ARC_DEG
	stop_distance = 1.0
	bar_height = 2.1
	bar_width = 0.9


## Who may write each var (see Net); Monster's come from super().
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"variant": Net.SPAWN,          # from its spawn cell on every machine (variant_for)
		"burnt": Net.OWNER,            # world.burn (NetWorld); a late joiner: `bodies`
		"raises": Net.LOCAL,
		"_dropped": Net.PRIVATE,       # the owner rolls the drops
		"_rise_t": Net.LOCAL,          # the stand-up's look, from world.rise on every machine
	})
	return f


func _ready() -> void:
	variant = variant_for(Hex.from_world(global_position))
	if model == null and not Monster.use_proto_visuals:
		model = ZombieModel.new(variant)
	super._ready()


## The look a zombie spawned on `cell` wears: the digger one in DIGGER_EVERY, else the mourner (a hash: no dice).
static func variant_for(cell: Vector2i) -> String:
	return "digger" if absi(hash([cell.x, cell.y, "zombie_look"])) % DIGGER_EVERY == 0 else "mourner"


## Down on the floor as a body (burnt or not).
func is_body() -> bool:
	return dead and is_inside_tree() and not is_queued_for_deletion() and state == State.DEAD and _has_ground()


## The H4 hook: an acolyte raises this body at full health (Actor.revive: the owner applies it; online the host).
func raise() -> bool:
	return revive(max_hp)


# --- Down, up, burnt -------------------------------------------------------------------------------------------------

## Going down while on fire burns the body (the fire itself ends with the death: Burning's "died").
func die() -> void:
	var on_fire := not dead and not Net.is_copy(self) and Burning.is_burning(self)
	var culprit := Burning.culprit(self) if on_fire else null
	super.die()
	if on_fire and dead:
		burn_body(culprit)


## Down: the body stays (no topple, no fade, no free). Monster's bookkeeping (out of "monsters", the kill in the combat log,
## the neighbours hear it) on every death; the drops only the first time.
func _on_death() -> void:
	if not _has_ground():
		super._on_death()   # (it fell into a pit or sank in lava: no body is left, it goes like any monster)
		return
	var was := state_name()
	state = State.DEAD
	_rise_t = -1.0
	remove_from_group("monsters")
	if Net.owns(self):
		if not _dropped:
			_dropped = true
			SpellComponents.drop_for(self)
		CombatLog.kill(self, was, GameWorld.time - _first_hit_at if _first_hit_at >= 0.0 else -1.0)
		if not is_frozen():
			MonsterSenses.noise(global_position, MonsterSenses.NOISE_DEATH, "death")
	_end_windup()
	_telegraph = 0.0
	if _bar != null:
		_bar.visible = false
	_apply_tint(Color.WHITE, 0.0)
	_lie_down()


func _can_revive() -> bool:
	return not burnt and _has_ground()


## Standing again (the owner's revive, or a copy told so: world.rise): back among the monsters, pushing up on its arms over
## RISE_TIME. The owner holds its AI meanwhile (a stagger) and lets it fight from where it rose.
func _on_revived(_cursed: bool) -> void:
	state = State.IDLE
	target = null
	_telegraph = 0.0
	raises += 1
	if not is_in_group("monsters"):
		add_to_group("monsters")
	if _visual != null:
		facing = Vector3(-sin(_visual.rotation.y), 0.0, -cos(_visual.rotation.y))   # (it gets up the way it lies: no spin)
	if model != null:
		model.set_downed(false)
		(model as ZombieModel).pose_rise(0.0)
	else:
		_visual.rotation.x = -PI * 0.5
	_rise_t = 0.0
	_update_bar()
	if Net.owns(self):
		home = global_position
		_home_set = true
		_prog_pos = global_position
		_clear_path()
		_next_attack_time = GameWorld.time + RISE_TIME
		stagger(RISE_TIME)


func _burns_down() -> bool:
	return not burnt and _has_ground()


func _burn_down(_source: Node) -> void:
	burnt = true
	_char()
	burnt_down.emit()


## A copy (world.burn, or a late joiner's `bodies`): the owner charred this body.
func net_burn() -> void:
	if burnt or not dead:
		return
	burnt = true
	_char()


## A late joiner's body (NetWorld.apply_bodies, after Net.remote_die): where it lies, which way, burnt or not.
func net_body(pos: Vector3, yaw: float, is_burnt: bool) -> void:
	global_position = pos
	facing = Vector3(-sin(yaw), 0.0, -cos(yaw))
	if _visual != null:
		_visual.rotation.y = yaw
	if is_burnt:
		net_burn()


## The body's yaw (its Visual's turn: where it fell facing).
func body_yaw() -> float:
	return _visual.rotation.y if _visual != null else atan2(-facing.x, -facing.z)


## Which way it falls (a look): forward, unless a wall is within LIE_LEN that way (its head and arms would sink into it);
## then back, then either side.
func _lie_yaw(yaw: float) -> float:
	var map := GameWorld.map
	if map == null or not is_inside_tree():
		return yaw
	for turn: float in [0.0, PI, PI * 0.5, -PI * 0.5]:
		var y := yaw + turn
		if not map.blocks_point(global_position + Vector3(-sin(y), 0.0, -cos(y)) * LIE_LEN, 0.2):
			return y
	return yaw


## Floor under it (a body lies on it; one that went into a pit or lava leaves none).
func _has_ground() -> bool:
	var map := GameWorld.map
	if map == null or not is_inside_tree():
		return true
	var g := map.ground_height(global_position)
	return not is_nan(g) and global_position.y > g - 0.6


func _lie_down() -> void:
	if _visual != null:
		_visual.rotation.y = _lie_yaw(_visual.rotation.y)
	if model != null:
		model.set_downed(true)   # (ZombieModel._slump: face down, the motes; greyed, the eyes out)
		return
	if _visual != null:
		_visual.rotation.x = -PI * 0.5
		_visual.position.y = 0.2


## The charred look: the burnt ZombieModel in place of the body's (smoke, embers), lying as it fell.
func _char() -> void:
	var embers: Array[Color] = [Burning.INNER, Burning.OUTER]
	Fx.burst(global_position + Vector3.UP * 0.3, embers, 10, 1.6, 0.06, 0.7, -1.4, Vector3.UP, 60.0)
	if model == null:
		for e in _mats:
			(e[0] as StandardMaterial3D).albedo_color = Color(0.1, 0.08, 0.07)
		return
	if (model as ZombieModel).charred:
		return
	var old := model
	var ch := ZombieModel.new(variant, true)
	ch.transform = old.transform
	_visual.add_child(ch)
	model = ch
	old.queue_free()
	ch.set_downed(true)


func _process(delta: float) -> void:
	if _rise_t < 0.0:
		return
	if dead:
		_rise_t = -1.0
		return
	_rise_t += delta
	var k := clampf(_rise_t / RISE_TIME, 0.0, 1.0)
	if model != null:
		(model as ZombieModel).pose_rise(k)
	elif _visual != null:
		_visual.rotation.x = -PI * 0.5 * (1.0 - k)
		_visual.position.y = 0.0
	if k >= 1.0:
		_rise_t = -1.0
		if model != null:
			(model as ZombieModel).stand_up()


## True while it is pushing itself up (raised, not yet standing).
func is_rising() -> bool:
	return _rise_t >= 0.0


# --- The look without a model (Monster.use_proto_visuals) ------------------------------------------------------------

func _build_visual(root: Node3D) -> void:
	var skin := _mat(Color(0.56, 0.62, 0.48))
	var coat := _mat(Color(0.17, 0.16, 0.19))
	var eye := _mat(Color(0.7, 0.85, 1.0), 2.0)
	_box(root, Vector3(0.12, 0.7, 0.12), Vector3(-0.11, 0.35, 0.0), coat)
	_box(root, Vector3(0.12, 0.7, 0.12), Vector3(0.11, 0.35, 0.0), coat)
	_box(root, Vector3(0.42, 0.6, 0.24), Vector3(0.0, 1.0, 0.04), coat, Vector3(-14, 0, 0))
	_sphere(root, 0.16, Vector3(0.0, 1.42, -0.12), skin)
	_sphere(root, 0.03, Vector3(-0.06, 1.44, -0.27), eye)
	_sphere(root, 0.03, Vector3(0.06, 1.44, -0.27), eye)
	_box(root, Vector3(0.08, 0.6, 0.08), Vector3(0.26, 1.15, -0.28), skin, Vector3(-80, 0, 0))
	_box(root, Vector3(0.08, 0.6, 0.08), Vector3(-0.26, 0.95, 0.0), skin, Vector3(10, 0, 0))
