class_name GhostSpell
extends SpellDef
## Ghost: GHOST FORM, cast on yourself (docs/design/haunted-build-plan.md "H7" and "H7 as built"; new-themes.md "Ghosts").
## The user (2026-10-28 / 10-31): ghost form "makes ghosts easier, not possible"; a whole-body transform ("For now"); "ghost form
## makes it so that you can pass through regular enemies, because you can walk through them[.] So it's for fighting ghosts";
## "A hero in ghost form can be hit by regular enemies. You can pass through them but if you wind up in their attack[,] you get
## hit." The old "make an enemy lose its target" use is skipped.
##   - THE CASTER only, wherever the aim is (a self-buff: no target, no snap onto a teammate).
##   - For ghost_duration(power) seconds (6 to 10) the caster is in ghost form (Actor.is_ghost_form, the STAT_GHOST modifier MOD):
##     it and every regular monster walk through each other (Actor._walks_through: movement only); their blows land as ever,
##     and its own hits land as ever. A ghost (a Wisp) is no regular enemy: it bumps a ghost-form hero.
##   - THE EDGE AGAINST GHOSTS: a free ghost does not keep away from a hero in ghost form (Wisp._nearest_to_flee: it flees only
##     the others), and while this screen's own hero is in ghost form every free ghost on it shows clearly (WispModel.set_clear:
##     the "strong" look, its light up).
##   - Going down ends it (Hero._on_death).
## The look: the whole-body ghost form of the look test (GhostForm: the pale corpse in a warm ghost, never the enemy ghosts'
## cold colour), on every screen from the modifier (Hero._update_ghost_form), with a warm puff as it comes and goes.
##
## Networking: a STATUS of the caster (the shape of armor's and coffee's modifiers). The cast is an event that lands on every
## machine at the same moment (SpellBook.apply); only the caster's owner applies the modifier (Net.resolves), and NetStatus
## announces it (st "mods") to the other screens, which show the look from it; a late joiner gets it with the statuses
## (NetStatus.late_join_state, NetEvents.LATE_JOIN "statuses: replay"). The monsters' side of the walk-through runs where each
## monster runs (the host), from the caster's announced modifier. Nothing is rolled.

const ID := "ghost"
const FOLLOWS := false

## Its row in SpellBook.SPELLS (name, cooldown, colour, description, spoken word, component, available).
## Cooldown 20 s: up to 10 s of ghost form, so it is up at most half the time (the held slot: about 17 s).
const ROW := {
	"name": "Ghost", "cooldown": 20.0, "color": Color(0.74, 0.88, 1.0),
	"desc": "You turn into a ghost for ten seconds: you walk through monsters, but their blows still land. Ghosts stop running from you.",
	"word": "ghost", "component": "Ectoplasm", "available": true,
}

## What the recognizer hears as this spell's word: heard phrase -> match quality (Incantation's spell table; the GHOST note in
## its header has the measurements).
const VOICE := {
	"ghost": 1.0, "ghosts": 1.0,
}

## The modifier ghost form lives under (Actor.STAT_GHOST: presence only, the mult is unused).
const MOD := "ghost"
const GHOST_TIME_BASE := 6.0       ## seconds of ghost form at power ~0 ...
const GHOST_TIME_POWER := 4.0      ## ... plus this at power 1 (10 s)
## The ghost form's warm colour (GhostForm.WARM: never the enemy ghosts' cold blue or ecto green), for the puff.
const PUFF := Color(1.0, 0.86, 0.6)


## Seconds of ghost form a cast of `power` gives.
static func ghost_duration(power: float) -> float:
	return GHOST_TIME_BASE + GHOST_TIME_POWER * clampf(power, SpellBook.MIN_POWER, 1.0)


## On every machine at the cast's moment: the caster's owner puts it in ghost form (the rest see it from the announced status).
static func cast(caster: Actor, power: float, _target: Vector3, start: float, _extra: Dictionary) -> Node:
	if Net.resolves(caster):
		transform(caster, ghost_duration(power) - maxf(0.0, GameWorld.time - start))
	return null


## The owner: `a` in ghost form for `seconds` (a fresh cast refreshes it, never stacks). The verb is set_modifier.
static func transform(a: Actor, seconds: float) -> void:
	if a == null or not is_instance_valid(a) or a.dead or seconds <= 0.0:
		return
	a.set_modifier(MOD, 1.0, seconds, Actor.STAT_GHOST)


## True when `a` is a hero this screen plays (is_player) in ghost form: this screen sees free ghosts clearly.
static func sees_ghosts(a: Actor) -> bool:
	return a is Hero and (a as Hero).is_player and not a.dead and a.is_ghost_form()


## The warm puff as the ghost form comes (`on`) or goes, on every screen (cosmetic: Fx's own dice).
static func puff(a: Actor, top: float, on: bool) -> void:
	if a == null or not a.is_inside_tree():
		return
	var at := a.global_position + Vector3.UP * top * 0.5
	if on:
		Fx.burst(at, [PUFF, Color(1, 1, 1)] as Array[Color], 22, 2.6, 0.1, 0.8, -0.9, Vector3.UP, 160.0)
	else:
		Fx.burst(at, [PUFF] as Array[Color], 12, 1.6, 0.08, 0.6, -0.6, Vector3.UP, 120.0)


# --- The component: Ectoplasm (ComponentProps.make builds it, and holds it in a hero's hand) ---

## How strongly the prop's own colour glows (the neon variant of the shared material).
const GLOW := 0.16
const ECTO := Color(0.66, 0.84, 0.98)
const ECTO_LIGHT := Color(0.86, 0.95, 1.0)
const ECTO_DEEP := Color(0.46, 0.64, 0.86)


## A quivering glob of pale ectoplasm: a lumpy body, a smaller lobe on top, a drip hanging off one side with a bead at its
## end, and two faint pale flecks.
static func component_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(971, 0.06)
	s.merge(LowPoly.boulder(Vector3(0.24, 0.16, 0.21), 1, 0.16, ECTO, 972, 0.05), LowPoly.at(Vector3(0.0, -0.04, 0.0)))
	s.merge(LowPoly.boulder(Vector3(0.14, 0.11, 0.13), 1, 0.14, ECTO_LIGHT, 973, 0.05), LowPoly.at(Vector3(-0.05, 0.1, 0.02)))
	s.merge(LowPoly.boulder(Vector3(0.10, 0.07, 0.09), 0, 0.14, ECTO_DEEP, 974, 0.05), LowPoly.at(Vector3(0.13, 0.03, -0.06)))
	s.merge(LowPoly.cylinder(0.045, 0.02, 0.16, 5, ECTO, 975, 0.01), LowPoly.at(Vector3(0.17, -0.16, 0.06), Vector3(0, 0, 12)))
	s.merge(LowPoly.boulder(Vector3(0.045, 0.055, 0.045), 0, 0.1, ECTO_LIGHT, 976, 0.04), LowPoly.at(Vector3(0.19, -0.26, 0.06)))
	s.merge(LowPoly.boulder(Vector3(0.03, 0.02, 0.02), 0, 0.1, ECTO_LIGHT, 977), LowPoly.at(Vector3(0.06, 0.06, 0.17)))
	s.merge(LowPoly.boulder(Vector3(0.025, 0.018, 0.02), 0, 0.1, ECTO_LIGHT, 978), LowPoly.at(Vector3(-0.11, -0.02, 0.17)))
	return s
