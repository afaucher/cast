class_name BonesModel
extends GruntModel
## A crypt skeleton a ghost can possess (docs/design/haunted-build-plan.md, "H5 as built"; haunt-look.md: the dormant skeleton
## "slumped only", the risen one "today's grunt standing"): kind "bones" (BonesHost). Today's skeleton model (GruntModel).
##   DORMANT  (awake false) sat on the floor slumped back against the wall behind it, the skull dropped, the sword by its hand
##            (HauntPiece's slumped pose), its ember eyes out: dead bones, set dressing.
##   AWAKE    a ghost stands it up: the grunt's own idle, walk, wind-up, swing and war cry.
##   THE WAKE (wake()): from the slump to standing over WAKE_T (every part's transform eased between the two), the eyes lit.
## set_ghost(true) dresses it in the possessed look the user picked (HauntDress: the rim, the vapour body, the seep).

const WAKE_T := 1.4

var awake := true
var phase := 0.0
var _wake := 1.0
var _dormant := {}                  ## part name -> its slumped transform
var _ghost := {}
var _plain: ShaderMaterial


func _init() -> void:
	super._init()
	name = "BonesModel"
	monster_kind = "bones"
	_plain = _mat
	HauntPiece._pose_slumped(self)
	for n: String in PART_NAMES:
		_dormant[n] = (parts[n] as Node3D).transform
	apply_idle(0.0)


## Back to the slumped dead bones (no blend), the eyes out.
func set_dormant() -> void:
	awake = false
	_wake = 1.0
	_pose_dormant()
	_mat.set_shader_parameter("glow_gain", 0.0)


## A ghost stands it up over WAKE_T (`instant`: at once), the eyes lit.
func wake(instant: bool = false) -> void:
	awake = true
	_wake = 1.0 if instant else 0.0
	_mat.set_shader_parameter("glow_gain", GLOW_GAIN)
	apply_idle(_t, _speed)


func wake_k() -> float:
	return _wake


func set_ghost(on: bool) -> void:
	if on and _ghost.is_empty():
		_ghost = HauntDress.dress(self, phase)
		add_to_group(GhostLook.GROUP)
		if not awake:
			_mat.set_shader_parameter("glow_gain", 0.0)
	elif not on and not _ghost.is_empty():
		HauntDress.undress(self, _ghost, _plain)
		_ghost = {}
		remove_from_group(GhostLook.GROUP)


func is_ghost() -> bool:
	return not _ghost.is_empty()


func refresh() -> void:
	HauntDress.refresh(_ghost, phase)


func _process(delta: float) -> void:
	if _wake < 1.0 and not _downed:
		_wake = minf(1.0, _wake + delta / WAKE_T)
		if not idle_enabled:
			apply_idle(_t, _speed)
	super._process(delta)


func apply_idle(t: float, speed: float = 0.0) -> void:
	if _downed:
		return
	if not awake:
		_pose_dormant()
		return
	super.apply_idle(t, speed)
	if _wake < 1.0:
		var k := _wake * _wake * (3.0 - 2.0 * _wake)
		for n: String in PART_NAMES:
			var p := parts[n] as Node3D
			p.transform = (_dormant[n] as Transform3D).interpolate_with(p.transform, k)


func _pose_dormant() -> void:
	if _dormant.is_empty():
		return
	for n: String in PART_NAMES:
		(parts[n] as Node3D).transform = _dormant[n]


## No glow flare while it lies dormant (a wind-up never comes, but a hit flash re-poses it).
func _update_glow() -> void:
	if not awake:
		return
	super._update_glow()
