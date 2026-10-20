class_name ChickenSpell
extends SpellDef
## Chicken: four chickens burst out where you aim and peck everyone for nothing (Chicken, scripts/spells/chicken.gd).

const ID := "chicken"
const FOLLOWS := false


## The flock lands (every machine, at the cast's moment): a feather cloud at the aim point on every screen, and the chickens
## from the HOST only (Net.is_host: solo too). They are host-owned actors like monsters: a client gets them from the world
## stream (NetWorld `world.spawn`), so a client's own cast never spawns any here. Power does not change the flock.
static func cast(_caster: Actor, _power: float, target: Vector3, _start: float, _extra: Dictionary) -> Node:
	ChickenFx.cast_cloud(target)
	if Net.is_host():
		Chicken.flock(target)
	return null
