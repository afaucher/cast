class_name GhostBody
extends Node3D
## LOOK-DEV ONLY (docs/design/ghost-look.md): one ghost for the look test, a plain cosmetic node (not an Actor: no HP, no
## AI, no collision, nothing networked). The gym spawns them ("ghost: skeleton", "ghost: armour", "ghost: wisp";
## GymSpawns "ghost") and the look lab poses them. Every GhostBody is in GhostLook.GROUP, so the gym's switches redress
## them all live (refresh).
##   skeleton  today's grunt model (GruntModel, idling on its own clock) in the ghost look: the possessed host
##   armour    a suit of armour on its stand (ArmourModel), still: the possessed antique
##   wisp      a free ghost: a translucent glowing head with a trailing tail, drifting in a slow figure eight round the
##             spot it was put down (DRIFT_R), bobbing, with a small light in its colour
## Looks only: the pulse phase and the wisp's start on its loop come from GameWorld.fx_rng.

const KINDS: Array[String] = ["skeleton", "armour", "wisp"]
const HOVER := 1.15               ## the wisp's head height over the floor
const DRIFT_R := 1.6              ## the figure eight's half width
const DRIFT_RATE := 0.33          ## rad / s round the loop (about 19 s a lap)
const TAIL := 5                   ## tail puffs behind the head
const TAIL_STEP := 0.2            ## between puffs, straight back from the head's heading
const WISP_COLOUR := Color(1, 1, 1)
const EYE := Color(0.04, 0.04, 0.05)

var kind := "skeleton"
var model: LowPolyModel           ## skeleton / armour
var base: ShaderMaterial          ## the body material every part shares (the toon body, or the wisp's glow)
var phase := 0.0                  ## the pulse's phase
var drift := true                 ## the wisp moves on its own (the lab poses it with pose_wisp instead)
var t := 0.0                      ## the wisp's time on its loop
var head: MeshInstance3D
var puffs: Array[MeshInstance3D] = []
var light: OmniLight3D


static func make(k: String) -> GhostBody:
	var g := GhostBody.new()
	g.kind = k if KINDS.has(k) else "skeleton"
	g._build()
	return g


func _init() -> void:
	name = "GhostBody"
	add_to_group(GhostLook.GROUP)


func _ready() -> void:
	if GameWorld.fx_rng != null and drift:
		phase = GameWorld.fx_rng.randf_range(0.0, TAU)
		t = GameWorld.fx_rng.randf_range(0.0, TAU / DRIFT_RATE)
	refresh()
	if kind == "wisp":
		pose_wisp(t)


func _build() -> void:
	name = "Ghost_" + kind
	match kind:
		"wisp":
			_build_wisp()
		"armour":
			model = ArmourModel.new()
			add_child(model)
			_take_parts()
		_:
			model = GruntModel.new()
			add_child(model)
			_take_parts()


## The host's parts all wear one fresh ghost toon body (the model's own material is dropped; the monster glow hook keeps
## working on it).
func _take_parts() -> void:
	base = GhostLook.body_material()
	for p: MeshInstance3D in model.parts.values():
		p.material_override = base
	model._mat = base


## Redress for GhostLook's switches as they are now.
func refresh() -> void:
	if base == null:
		return
	GhostLook.dress(base, kind == "wisp", phase)
	if light != null:
		var s := GhostLook.strength_now()
		light.light_color = GhostLook.color_now()
		light.light_energy = float(s["light"])
		light.visible = float(s["light"]) > 0.0


func _process(delta: float) -> void:
	if kind == "wisp" and drift:
		t += delta
		pose_wisp(t)


# --- the wisp -------------------------------------------------------------------------------------------------------------

func _build_wisp() -> void:
	base = GhostLook.wisp_material()
	head = MeshInstance3D.new()
	head.name = "head"
	head.mesh = _head_soup().to_mesh(0.0)
	head.material_override = base
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(head)
	for i in TAIL:
		var p := MeshInstance3D.new()
		p.name = "puff_%d" % i
		var r := 0.2 * pow(0.8, float(i))
		p.mesh = LowPoly.boulder(Vector3(r, r * 0.9, r), 0, 0.12, WISP_COLOUR, 611 + i, 0.04).to_mesh(0.0)
		p.material_override = base
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		puffs.append(p)
	light = OmniLight3D.new()
	light.name = "WispLight"
	light.omni_range = 2.8
	light.omni_attenuation = 1.6
	light.light_specular = 0.0
	light.shadow_enabled = false
	head.add_child(light)


## The head: a faceted dome drawn up to a soft point at the back, with two dark eye hollows and a small round mouth on its
## front (-Z), tipped up a little so the steep game camera sees the face.
func _head_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(601, 0.04)
	MonsterModel.blob(s, Vector3.ZERO, Vector3(0.27, 0.31, 0.27), WISP_COLOUR, 602, 0.08, 1)
	s.merge(LowPoly.cylinder(0.18, 0.0, 0.26, 6, WISP_COLOUR, 603, 0.02), LowPoly.at(Vector3(0, 0.26, 0.10), Vector3(35.0, 0, 0)))
	for x: float in [-0.095, 0.095]:
		MonsterModel.blob(s, Vector3(x, 0.08, -0.215), Vector3(0.06, 0.085, 0.05), EYE, 604 + int(x * 20.0), 0.05, 0, Vector3(-30.0, 0, 0))
	MonsterModel.blob(s, Vector3(0, -0.07, -0.245), Vector3(0.04, 0.05, 0.04), EYE, 607, 0.05, 0, Vector3(-20.0, 0, 0))
	return s


## A point on the drift loop at time `time` (local: round the node's origin), the head's height bobbing on it.
func drift_point(time: float) -> Vector3:
	var a := time * DRIFT_RATE
	return Vector3(sin(a) * DRIFT_R, HOVER + 0.10 * sin(time * 1.7), sin(2.0 * a) * DRIFT_R * 0.45)


## Pose the wisp at `time` on its loop: the head on the loop facing along it, the tail puffs straight back from its heading,
## sinking, a sideways wave running down them.
func pose_wisp(time: float) -> void:
	if head == null:
		return
	var p := drift_point(time)
	var ahead := drift_point(time + 0.1) - p
	ahead.y = 0.0
	var fwd := ahead.normalized() if ahead.length() > 0.0001 else Vector3.FORWARD
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	head.position = p
	head.rotation = Vector3(0.0, atan2(-fwd.x, -fwd.z), 0.0)
	for i in puffs.size():
		var k := float(i + 1)
		var q := p - fwd * (0.12 + TAIL_STEP * k) + side * (0.06 * k * sin(time * 2.4 - k * 0.9))
		q.y = p.y - 0.1 - 0.08 * k
		puffs[i].position = q
