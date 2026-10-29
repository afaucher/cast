class_name NecroBody
extends Node3D
## LOOK-DEV ONLY (docs/design/necro-look.md): one necro-family figure for the look test, a plain cosmetic node (not an
## Actor: no HP, no AI, no collision, nothing networked). The gym spawns them (GymSpawns "necro") and the look lab poses
## them. Every NecroBody is in GhostLook.GROUP, so the gym's "Ghost colour" and the necro rows (NecroLook.pick) redress them
## live (refresh: a rebuild, since the glow is painted on).
##   zombie    mourner | digger   stand (idling), shamble (walking a short line and back), rising (lying, pushing up on
##                                its arms and sinking back, on a loop), burnt (charred, down for good)
##   acolyte   cowl | mask        idle, raise (raising a zombie in front of it, on a loop), flee (running a line and back,
##                                looking over its shoulder)
##   grimoire  lectern | altar    its state follows the gym's "Grimoire" row (NecroLook.grimoire), or `state` when set
## `live` false (the lab) holds a still instead: pose_still().
## Looks only: the loop phases come from GameWorld.fx_rng.

const KINDS: Array[String] = ["zombie", "acolyte", "grimoire"]
const VARIANTS := {"zombie": ["mourner", "digger"], "acolyte": ["cowl", "mask"], "grimoire": ["lectern", "altar"]}
const POSES := {"zombie": ["stand", "shamble", "rising", "burnt"], "acolyte": ["idle", "raise", "flee"], "grimoire": ["state"]}
const SHAMBLE_LEN := 2.6            ## the shamble's line, there and back
const FLEE_LEN := 5.0
const RISE_LOOP := 7.0              ## lie, push up, hold, sink (s)
const RAISE_LOOP := 7.0             ## arms up, hold, down, rest (s)
const RAISED_AT := Vector3(-1.5, 0.0, -0.9)   ## where an acolyte's raised zombie lies (in front, to its left: screen right)

var kind := "zombie"
var variant := "mourner"
var pose := "stand"
var state := ""                    ## grimoire: "" follows NecroLook.grimoire
var live := true
var t := 0.0
var model: Node3D                  ## ZombieModel / AcolyteModel / GrimoireModel
var raised: ZombieModel            ## an acolyte's raised zombie (pose "raise")
var _built := ""


static func make(k: String, v: String, p: String) -> NecroBody:
	var b := NecroBody.new()
	b.kind = k if KINDS.has(k) else "zombie"
	var vs: Array = VARIANTS[b.kind]
	b.variant = v if vs.has(v) else str(vs[0])
	var ps: Array = POSES[b.kind]
	b.pose = p if ps.has(p) else str(ps[0])
	b.name = "Necro_%s_%s_%s" % [b.kind, b.variant, b.pose]
	b._rebuild()
	return b


## Every gym entry: [kind, variant, pose].
static func entries() -> Array[Array]:
	var out: Array[Array] = []
	for k: String in KINDS:
		for v: String in VARIANTS[k]:
			for p: String in POSES[k]:
				out.append([k, v, p])
	return out


static func key_of(k: String, v: String, p: String) -> String:
	return "%s:%s:%s" % [k, v, p]


static func label_of(k: String, v: String, p: String) -> String:
	return "grimoire: %s" % v if k == "grimoire" else "%s (%s): %s" % [k, v, p]


func _init() -> void:
	add_to_group(GhostLook.GROUP)


func _ready() -> void:
	if live and GameWorld.fx_rng != null:
		t = GameWorld.fx_rng.randf_range(0.0, 7.0)
	if live:
		pose_at(t)


func grimoire_state() -> String:
	return state if state != "" else NecroLook.grimoire


func _signature() -> String:
	return "%s|%s|%s" % [NecroLook.glow_colour(), NecroLook.rim, grimoire_state() if kind == "grimoire" else ""]


## Redress for the switches now (GhostLook.refresh_all): rebuilt when the colour, the rim or the grimoire's state changed.
func refresh() -> void:
	if _signature() != _built:
		_rebuild()


func _rebuild() -> void:
	_built = _signature()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	raised = null
	match kind:
		"grimoire":
			model = GrimoireModel.make(variant, grimoire_state(), t)
		"acolyte":
			model = AcolyteModel.new(variant)
			if pose == "raise":
				raised = ZombieModel.new("mourner")
				raised.idle_enabled = false
				raised.position = RAISED_AT
				add_child(raised)
		_:
			model = ZombieModel.new(variant, pose == "burnt")
	add_child(model)
	if not live:
		pose_still()
	elif is_inside_tree():
		pose_at(t)


func _process(delta: float) -> void:
	if not live:
		return
	t += delta
	pose_at(t)


## The live loop at time `time` (the gym).
func pose_at(time: float) -> void:
	match kind:
		"zombie":
			var z := model as ZombieModel
			match pose:
				"rising", "burnt":
					z.idle_enabled = false
					z.pose_rise(rise_at(time) if pose == "rising" else 0.0)
				"shamble":
					z.idle_enabled = true
					_walk_line(time, ZombieModel.WALK_SPEED, SHAMBLE_LEN)
				_:
					z.idle_enabled = true
		"acolyte":
			var a := model as AcolyteModel
			a.idle_enabled = true
			match pose:
				"raise":
					var k := raise_at(time)
					a.set_raise(k)
					if raised != null:
						raised.pose_rise(clampf(k * 1.15 - 0.1, 0.0, 1.0))
				"flee":
					_walk_line(time, AcolyteModel.RUN_SPEED, FLEE_LEN)


## There and back along the figure's own front (local -Z), turning at each end; the model reads its speed from the motion.
func _walk_line(time: float, speed: float, length: float) -> void:
	var lap := 2.0 * length / speed
	var u := fposmod(time, lap) / lap
	var out := u < 0.5
	var d := (u * 2.0 if out else 2.0 - u * 2.0) * length
	model.position = Vector3(0.0, 0.0, -d)
	model.rotation.y = 0.0 if out else PI


## The rising loop: lying 2.5 s, pushing up 2 s, held 1.7 s (trembling), sinking 0.8 s.
static func rise_at(time: float) -> float:
	var u := fposmod(time, RISE_LOOP)
	if u < 2.5:
		return 0.0
	if u < 4.5:
		return (u - 2.5) / 2.0
	if u < 6.2:
		return 1.0 - 0.03 * absf(sin(u * 23.0))
	return 1.0 - (u - 6.2) / 0.8


## The raising loop: arms up over 1 s, held 4 s, down 1 s, resting 1 s.
static func raise_at(time: float) -> float:
	var u := fposmod(time, RAISE_LOOP)
	if u < 1.0:
		return u
	if u < 5.0:
		return 1.0
	if u < 6.0:
		return 6.0 - u
	return 0.0


## The lab's still for the pose: standing, mid-shamble, about to rise (k 0.85), burnt flat, idle, raising (arms up, its
## zombie mostly up), mid-flight, an open grimoire's frozen moment.
func pose_still() -> void:
	match kind:
		"zombie":
			var z := model as ZombieModel
			z.idle_enabled = false
			match pose:
				"rising":
					z.pose_rise(0.85)
				"burnt":
					z.pose_rise(0.0)
				"shamble":
					z.apply_idle(0.45, ZombieModel.WALK_SPEED)
				_:
					z.apply_idle(0.6, 0.0)
		"acolyte":
			var a := model as AcolyteModel
			a.idle_enabled = false
			match pose:
				"raise":
					a.set_raise(1.0)
					a.apply_idle(0.6, 0.0)
					if raised != null:
						raised.pose_rise(0.7)
				"flee":
					a.apply_idle(0.25, AcolyteModel.RUN_SPEED)
				_:
					a.set_raise(0.0)
					a.apply_idle(0.6, 0.0)
		"grimoire":
			(model as GrimoireModel).freeze_at(1.1)
