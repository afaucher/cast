class_name SpellDef
extends RefCounted
## One spell as a unit (docs/design/refactor-plan.md H2; docs/ARCHITECTURE.md, "Adding a spell"). Each spell is one script in
## scripts/spells/defs/ that extends SpellDef and is listed in SpellBook.DEFS. A def is never instanced: it holds only
## consts and static funcs, so it has no state to declare for co-op (test_net_contract).
##
## Every def has:
##   const ID := "heal"        the spell id (lowercase)
##   const ROW := {...}        its SpellBook.SPELLS row: "name", "cooldown", "color", "desc", "word", "component", "available"
##   const FOLLOWS := false    true for a support spell that follows the teammate the aim snapped onto (SpellBook.cast)
##   const GLOW := 0.1         how strongly its component prop's own colour glows (ComponentProps.make)
##   its tuning consts and the helpers derived from them (HealSpell.HEAL_BASE, HealSpell.heal_amount(power))
##   static func cast(caster, power, target, start, extra) -> Node
##       the effect, applied on every machine at the cast's moment (SpellBook.apply). `power` is already clamped to
##       [SpellBook.MIN_POWER, 1]; `target` is the resolved point (or where this screen has the followed teammate);
##       `start` is the cast's moment in GameWorld.time; `extra` is what cast_extra() returned on the caster's machine.
##       Returns the effect node it spawned, or null.
##   static func component_soup() -> LowPoly.Soup
##       its material component's faceted prop, about 0.5 units across, origin at its centre (ComponentProps.make adds the
##       spell-coloured glow material and the held halo)
## and may override (the defaults here do nothing):
##   static func cast_extra(caster, target) -> Dictionary
##       numbers fixed on the caster's machine at the moment of the cast and sent with it, so every machine runs the same
##       effect (the fireball's launch point, direction and reach).


static func cast(_caster: Actor, _power: float, _target: Vector3, _start: float, _extra: Dictionary) -> Node:
	push_error("SpellDef.cast: a spell def must define its own cast()")
	return null


static func cast_extra(_caster: Actor, _target: Vector3) -> Dictionary:
	return {}


static func component_soup() -> LowPoly.Soup:
	push_error("SpellDef.component_soup: a spell def must build its own component prop")
	return null
