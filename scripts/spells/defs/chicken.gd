class_name ChickenSpell
extends SpellDef
## Chicken: four chickens scatter from the aim point and peck everything for nothing; a pecked monster chases its chicken
## (Chicken, scripts/spells/chicken.gd; decided by the user 2026-10-18, docs/design/spells.md).

const ID := "chicken"
const FOLLOWS := false

## Its row in SpellBook.SPELLS (name, cooldown, colour, description, spoken word, component, available).
const ROW := {
	"name": "Chicken", "cooldown": 14.0, "color": Color(0.94, 0.33, 0.27),
	"desc": "Four chickens burst out where you aim and peck EVERYONE for zero. A pecked monster forgets you and chases its chicken, which does not last long.", "word": "chicken",
	"component": "Chicken feather", "available": true,
}


## The flock lands (every machine, at the cast's moment): a feather cloud at the aim point on every screen, and the chickens
## from the HOST only (Net.is_host: solo too). They are host-owned actors like monsters: a client gets them from the world
## stream (NetWorld `world.spawn`), so a client's own cast never spawns any here. Power does not change the flock.
static func cast(_caster: Actor, _power: float, target: Vector3, _start: float, _extra: Dictionary) -> Node:
	ChickenFx.cast_cloud(target)
	if Net.is_host():
		Chicken.flock(target)
	return null
