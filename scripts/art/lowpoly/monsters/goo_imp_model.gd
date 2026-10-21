class_name GooImpModel
extends "res://scripts/art/lowpoly/monsters/goo_imp_blockouts.gd".DripImp
## The goo imp's game model (MonsterDefs kind "goo_imp", scripts/monsters/goo_imp.gd; docs/design/goo-imp.md, "As built"):
## look-dev's Gloop (`drip`, GooImpBlockouts), the user's pick, in the bile goo: pale axolotl pink, red gills, a goo cap
## running down its head, drips, a puddle at its feet, a ball welling up in its cupped hands. With the monster hooks:
##   windup(t)       the throw's tell: the right hand takes the ball back over its head and the ball SWELLS to about the size
##                   of the thrown ball (BALL_TELL)
##   attack_swing()  the throw: the arm flings forward and the ball is GONE from its hands; it wells up again over REGROW s
## The look-dev's worry (goo-imp.md §3, §6.1): a Gloop pack is a glowing smear that can read "buffed" rather than ranged. So
## the tell flares little (glow_flare is low: the body's goo does not pulse), the ball in the hand grows to the size of the
## one that flies, and the hands are empty right after a throw: "it throws that". The landing marker (GooBall) does the rest.

## The rigid parts the game animates (test_monster_models).
const PART_NAMES: Array[String] = ["body", "head", "gill_l", "gill_r", "arm_l", "arm_r", "leg_l", "leg_r", "tail", "ball",
	"cap", "coat", "puddle", "drips_l", "drips_r"]
const BILE := Color(0.80, 1.0, 0.16)
const BALL_TELL := 2.0           ## the hand ball's scale at the end of the tell (about the thrown ball's size)
const REGROW := 0.45             ## seconds for a new ball to well up after a throw

var _regrow := 1.0               ## 0 right after a throw -> 1 (the ball is back)


func _init() -> void:
	super(BILE)
	monster_kind = "goo_imp"
	glow_flare = 0.15


func attack_swing() -> void:
	_regrow = 0.0
	super.attack_swing()


func set_downed(downed: bool) -> void:
	_regrow = 1.0
	super.set_downed(downed)


func _process(delta: float) -> void:
	if _regrow < 1.0 and not _downed:
		_regrow = minf(1.0, _regrow + delta / REGROW)
	super._process(delta)


## Where the ball sits in its hand now (world).
func ball_point() -> Vector3:
	return (parts["ball"] as Node3D).global_position


func apply_idle(t: float, speed: float = 0.0) -> void:
	super.apply_idle(t, speed)
	if _downed:
		return
	var k := lerpf(1.0, BALL_TELL, wind_e()) * _regrow
	(parts["ball"] as Node3D).scale = Vector3.ONE * maxf(k, 0.001)


func pose_preview(kind: String, k: float = 1.0) -> void:
	_regrow = 0.0 if kind == "swing" else 1.0
	super.pose_preview(kind, k)
