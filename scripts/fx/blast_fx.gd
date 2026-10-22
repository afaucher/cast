class_name BlastFx
extends RefCounted
## An explosive prop going up (ExplosiveProp, docs/design/hazards.md): the fireball's burst (Fx.explosion, with its
## "fireball" sound) made bigger, a white-hot core, a fire column, a shock ring out to the TRUE blast radius, the prop's
## own shards, a smoke plume, a strong shake and a scorch mark on the floor (Grime, fades like a fireball's).
## Cosmetic: every machine plays it at the blast's moment on its own clock; the randomness is GameWorld.fx_rng (inside
## Fx and PropDebris).

const FIRE := Color(1.0, 0.5, 0.12)
const CORE := Color(1.0, 0.95, 0.75)


static func play(pos: Vector3, radius: float, palette: Array[Color], height: float = 1.0) -> void:
	if GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return
	var c := pos + Vector3.UP * maxf(0.5, height * 0.5)
	Fx.explosion(c, radius, FIRE, "fireball")
	Fx.flash_sphere(c, radius * 0.55, Color(CORE.r, CORE.g, CORE.b, 0.95), 0.22)
	Fx.flash_sphere(c + Vector3.UP * radius * 0.35, radius * 0.6, Color(1.0, 0.42, 0.1, 0.75), 0.42)
	# the shock ring out to where the blast reaches, a second slower one behind it
	Fx.ring(pos, radius, Color(1.0, 0.72, 0.3, 0.95), 0.32, 0.0, false, 0.15)
	Fx.ring(pos, radius * 0.75, Color(1.0, 0.4, 0.12, 0.7), 0.55, 0.3, false, 0.1)
	# a column of fire and embers, the prop's own shards, and smoke that rolls up and hangs
	var fire: Array[Color] = [Color(1.0, 0.92, 0.5), FIRE, Color(0.85, 0.2, 0.06)]
	Fx.burst(c, fire, 40, 3.5 + radius, 0.16, 0.7, -2.0, Vector3.UP, 35.0)
	Fx.burst(c, fire, 30, 6.0 + radius * 1.5, 0.09, 0.9, 9.0, Vector3.UP, 160.0)
	if not palette.is_empty():
		PropDebris.burst(c, palette, 18, 1.4)
	var smoke: Array[Color] = [Color(0.16, 0.14, 0.13), Color(0.32, 0.29, 0.27), Color(0.45, 0.42, 0.4)]
	Fx.burst(c + Vector3.UP * 0.4, smoke, 26, 2.0, 0.42, 2.0, -1.0, Vector3.UP, 50.0, false)
	# (no "BOOM!" word over it any more: user, 2026-10-22, "Remove the 'BOOM' and 'LAVA' onscreen text")
	Fx.shake(0.55 + radius * 0.06)
	Grime.mark(Grime.SCORCH, pos, radius * 0.85)
