class_name Teeth
extends RefCounted
## The Teeth spell ("cast teeth"). Every living actor of ANY team around the aim point (heroes,
## the caster and monsters alike) is afflicted: TeethFx sprouts too many teeth on it, they grow for
## 1 to 2 s (stronger casts grow faster), then POP. Design record: docs/design/spells.md.
##
##   Teeth.cast(caster, power, point)          # afflict everyone within SpellBook.teeth_radius(power)
##   Teeth.cancel_on(actor)                    # the dentist (a heal calls this); true if teeth were pulled
##   Teeth.is_afflicted(actor)
##
## The pop (TeethFx's on_pop):
##   - the carrier takes 25 * power;
##   - everyone else within 1.5 of the carrier (any team) takes 10 * power and is shoved 1.2 outward
##     through Combat.shove_radius, credited to the caster;
##   - damage caused by a hero never takes a hero below 1 HP (the everyone-spell friendly-fire floor);
##   - a carrier that died before the pop still pops at its last spot, for the splash only;
##   - pops never afflict anyone (no chains of new teeth), but a pop can of course kill another
##     carrier, whose own teeth still pop on schedule.
## Re-casting on an afflicted actor replaces its affliction (the old one never pops). A heal pulls the
## teeth (TeethFx.cancel): no pop for that victim.
##
## Nothing here is a node. The effect is moved from the victim to the world root right after it
## starts, so it keeps running, and pops, even when the carrier dies or is freed first; the pop
## position is then the last one the effect followed.

const META_AFFLICTION := "teeth_affliction"
const META_FX := "teeth_fx"          ## set by TeethFx itself; kept in step here after the move to the world root


## One carrier's pending pop. Held by the on_pop callable and by the victim's metadata.
class Affliction extends RefCounted:
	var carrier: WeakRef = null
	var caster: WeakRef = null
	var caster_team := GameWorld.TEAM_HEROES
	var power := 1.0
	var fx: WeakRef = null
	var active := true           ## false once popped, pulled or replaced


## Afflict everyone near `pos`. Returns the afflicted actors. Used by SpellBook.cast.
static func cast(caster: Actor, power: float, pos: Vector3) -> Array[Actor]:
	power = clampf(power, SpellBook.MIN_POWER, 1.0)
	var radius := SpellBook.teeth_radius(power)
	var grow := SpellBook.teeth_grow_time(power)
	var out: Array[Actor] = []
	for a in GameWorld.actors_in_radius(pos, radius):
		if afflict(a, caster, power, grow) != null:
			out.append(a)
	var col := SpellBook.color_of("teeth")
	Fx.ring(pos, radius, Color(col.r, col.g, col.b, 0.85), 0.6, 0.0, true, 0.3)
	return out


## Sprout teeth on one actor. Replaces any affliction it already has. Returns the effect, or null.
static func afflict(victim: Actor, caster: Actor, power: float, grow_time: float) -> TeethFx:
	if victim == null or not is_instance_valid(victim) or victim.dead or not victim.is_inside_tree():
		return null
	if GameWorld.root == null or not is_instance_valid(GameWorld.root):
		return null
	var old: Variant = _affliction_of(victim)
	if old is Affliction:
		(old as Affliction).active = false     # replaced: the old teeth never pop
	var aff := Affliction.new()
	aff.carrier = weakref(victim)
	aff.caster = weakref(caster) if caster != null else null
	aff.caster_team = caster.team if caster != null else GameWorld.TEAM_HEROES
	aff.power = power
	var fx := TeethFx.afflict(victim, grow_time, func() -> void: _on_pop(aff))
	if fx == null:
		return null
	aff.fx = weakref(fx)
	# Detach from the victim: the effect keeps following it while it lives, and pops either way.
	fx.reparent(GameWorld.root, false)
	victim.set_meta(META_AFFLICTION, aff)
	victim.set_meta(META_FX, fx)
	fx.cancelled.connect(func() -> void: _end(aff))
	return fx


static func is_afflicted(actor: Actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var aff: Variant = _affliction_of(actor)
	return aff is Affliction and (aff as Affliction).active


## The dentist: pull the teeth off `actor` before they pop. True if there was something to pull.
static func cancel_on(actor: Actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var aff: Variant = _affliction_of(actor)
	if not (aff is Affliction) or not (aff as Affliction).active:
		return false
	var fx: TeethFx = (aff as Affliction).fx.get_ref() as TeethFx if (aff as Affliction).fx != null else null
	if fx == null or not fx.cancel():
		return false
	_end(aff as Affliction)
	return true


static func _affliction_of(actor: Actor) -> Variant:
	return actor.get_meta(META_AFFLICTION) if actor.has_meta(META_AFFLICTION) else null


## An affliction is over (popped, pulled or replaced).
static func _end(aff: Affliction) -> void:
	aff.active = false
	var victim: Actor = aff.carrier.get_ref() as Actor if aff.carrier != null else null
	if victim != null and _affliction_of(victim) == aff:
		victim.remove_meta(META_AFFLICTION)


static func _on_pop(aff: Affliction) -> void:
	if not aff.active:
		return
	var fx: TeethFx = aff.fx.get_ref() as TeethFx if aff.fx != null else null
	var carrier: Actor = aff.carrier.get_ref() as Actor if aff.carrier != null else null
	var caster: Actor = aff.caster.get_ref() as Actor if aff.caster != null else null
	# Where it pops: the effect has been following the carrier, and stays at its last spot if it is gone.
	var pos := Vector3.ZERO
	if carrier != null and carrier.is_inside_tree():
		pos = carrier.global_position
	elif fx != null:
		pos = fx.global_position
	elif carrier != null:
		pos = carrier.global_position
	_end(aff)
	Grime.mark(Grime.TEETH, pos, 1.0)   # a few tooth bits that fade after 30 s
	MonsterSenses.noise(pos, MonsterSenses.NOISE_TEETH, "teeth")   # (only the monsters this machine runs hear)
	var power := aff.power
	var src: Node = caster
	var carrier_alive := carrier != null and not carrier.dead
	if carrier_alive:
		Fx.attach_hit_feedback(carrier)
		_hurt(carrier, SpellBook.teeth_damage(power), aff.caster_team, src)
	# The splash: everyone else near the carrier, any team (including other carriers).
	var splash := SpellBook.teeth_splash_damage(power)
	for a in GameWorld.actors_in_radius(pos, SpellBook.TEETH_SPLASH_RADIUS):
		if a == carrier:
			continue
		Fx.attach_hit_feedback(a)
		_hurt(a, splash, aff.caster_team, src)   # (_hurt asks Combat.resolves: the pop runs on every screen)
	Combat.shove_radius(pos, SpellBook.TEETH_SPLASH_RADIUS, SpellBook.TEETH_SHOVE, src, -1, carrier)


## Damage with the friendly-fire floor: a hero's spell never takes a hero below 1 HP.
static func _hurt(victim: Actor, amount: float, caster_team: int, src: Node) -> float:
	if victim.dead or amount <= 0.0 or not Combat.resolves(victim, src):
		return 0.0   # (online: the victim's machine decides a hero, the caster's the rest)
	if victim.team == GameWorld.TEAM_HEROES and caster_team == GameWorld.TEAM_HEROES:
		var room := victim.hp - 1.0
		if room <= 0.0:
			return 0.0
		amount = minf(amount, room / maxf(victim.damage_taken_mult(), 0.0001))
	return victim.apply_damage(amount, src)
