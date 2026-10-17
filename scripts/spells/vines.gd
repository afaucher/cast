class_name Vines
extends Node3D
## The Vines spell ("cast vines"). After a short TELEGRAPH (game time) thorny vines burst out of the floor at
## this node's position and ROOT everyone within the radius for about two seconds: heroes, the caster, monsters
## and employees alike (the area rule). A rooted actor can still attack and cast, but it cannot walk and it cannot
## be shoved: Actor.shove ignores it, so tentacles, the bowl, the spin, a melee nudge, a teeth pop's shove and a
## shove into a priced prop all do nothing to it. No damage.
##
## The root is the "vines" modifier with Actor.STAT_ROOT, applied through Combat.modify_radius (so the actor's
## owner applies it). The look is VinesFx (the burst at the aim point, a variant of the tentacles kit in green with
## thorns) plus a VineWrap around each rooted actor's legs.
##
## Combos (docs/design/spells.md): vines then teeth, and nobody escapes the pop; vines are the counter to your
## own shove spells.
##
## Networking (networking.md, "Scheduled effect"): one cast event; every machine runs the burst from these SPAWN
## params and `start_time`. The root itself is a status each target's owner applies and replicates (`_modifiers`
## is OWNER on Actor); the vines and wraps are cosmetic.

const TELEGRAPH := 0.3

var power := 1.0
var source_team := GameWorld.TEAM_HEROES
var caster: Actor = null
## The cast's GameWorld.time. The Net layer stamps it so every machine runs the same schedule; -1 = start now.
var start_time := -1.0

var _burst_done := false
var _fx: VinesFx = null


func _ready() -> void:
	if start_time < 0.0:
		start_time = GameWorld.time
	_fx = VinesFx.new()
	_fx.radius = SpellBook.vines_radius(power)
	_fx.telegraph = TELEGRAPH
	_fx.hold = SpellBook.vines_duration(power)
	_fx.power = power
	_fx.start_time = start_time
	add_child(_fx)


## Who may write each var (see Net). A scheduled effect: params SPAWN, state recomputed locally.
func net_fields() -> Dictionary:
	return {
		"power": Net.SPAWN, "source_team": Net.SPAWN,
		"caster": Net.SPAWN,      # will travel as an entity id in the cast event
		"start_time": Net.SPAWN,
		"_burst_done": Net.LOCAL, "_fx": Net.LOCAL,
	}


func _physics_process(_delta: float) -> void:
	var t := GameWorld.time - start_time
	if not _burst_done and t >= TELEGRAPH:
		_burst()
	elif _burst_done and t >= TELEGRAPH + SpellBook.vines_duration(power) + VinesFx.RETRACT + 0.1:
		queue_free()


func _burst() -> void:
	_burst_done = true
	var dur := SpellBook.vines_duration(power)
	for a in Combat.modify_radius(global_position, SpellBook.vines_radius(power), "vines", 1.0, dur, Actor.STAT_ROOT):
		VineWrap.attach(a, dur)
