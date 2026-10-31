class_name CryptPest
extends Node3D
## LOOK-DEV ONLY (docs/design/crypt-pests-look.md): one crypt pest for the look test, a plain cosmetic node (not an Actor:
## no HP, no AI, no collision, nothing networked). The gym spawns them (GymSpawns "crypt", "pest:<kind>:<variant>:<pose>")
## and the look lab poses them. The GAME's rat and blob are the monsters CryptRat and EctoBlob (haunted-build-plan.md "H3b as
## built": the gym's Monster group, "Crypt Rat" and "Ecto Blob"); this figure keeps the look test's record (every variant,
## the rat's rear-up tell). Every CryptPest is in GhostLook.GROUP, so the gym's "Ghost colour" (and "Necro rim", for the
## grave rat) redress it live (refresh: a rebuild, since the glow is painted on).
##   rat   sewer | runner | grave   run (galloping a line and back), bite (rearing up and biting on a loop), pack (six
##                                  rats galloping round a loop, the swarm)
##   blob  jelly | faces | puddle   rest (breathing), crawl (crawling a line and back over its slick), lunge (gathering up and
##                                  lunging on a loop)
## `live` false (the lab, the tests) holds a still instead: pose_still().
## Looks only: the loop phases come from GameWorld.fx_rng; the slick's shape from a seed drawn from it.

const KINDS: Array[String] = ["rat", "blob"]
const VARIANTS := {"rat": RatModel.VARIANTS, "blob": EctoBlobModel.VARIANTS}
const POSES := {"rat": ["run", "bite", "pack"], "blob": ["rest", "crawl", "lunge"]}
const RUN_LEN := 5.0                ## the gallop's line, there and back
const CRAWL_LEN := 3.0              ## the crawl's line (the slick runs its length)
const PACK := 6                     ## a pack (the swarmer imp's 5-6)
const PACK_R := 1.9                 ## the pack's loop
const BITE_LOOP := 3.2              ## rest, rear up (the tell), bite, settle (s)
const LUNGE_LOOP := 4.5

var kind := "rat"
var variant := "sewer"
var pose := "run"
var live := true
var t := 0.0
var models: Array[MonsterModel] = []   ## one, or the pack
var trail: Node3D                      ## the blob's slick (crawl)
var slick_seed := 7
var _built := ""
var _bit := false
var _phase: Array[float] = []          ## the pack's spread round its loop
var _radius: Array[float] = []


static func make(k: String, v: String, p: String) -> CryptPest:
	var b := CryptPest.new()
	b.kind = k if KINDS.has(k) else "rat"
	var vs: Array = VARIANTS[b.kind]
	b.variant = v if vs.has(v) else str(vs[0])
	var ps: Array = POSES[b.kind]
	b.pose = p if ps.has(p) else str(ps[0])
	b.name = "Pest_%s_%s_%s" % [b.kind, b.variant, b.pose]
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
	return "pest:%s:%s:%s" % [k, v, p]


static func label_of(k: String, v: String, p: String) -> String:
	return "%s (%s): %s" % ["rat" if k == "rat" else "ecto blob", v, p]


func _init() -> void:
	add_to_group(GhostLook.GROUP)


func _ready() -> void:
	if live and GameWorld.fx_rng != null:
		t = GameWorld.fx_rng.randf_range(0.0, 7.0)
		slick_seed = 1 + GameWorld.fx_rng.randi() % 9973
		if trail != null:
			_rebuild()
	if live:
		pose_at(t)


func _signature() -> String:
	return "%s|%s" % [GhostLook.color_now(), NecroLook.rim]


## Redress for the switches now (GhostLook.refresh_all): rebuilt when the ghost colour or the rim changed.
func refresh() -> void:
	if _signature() != _built:
		_rebuild()


func _rebuild() -> void:
	_built = _signature()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	models = []
	trail = null
	_phase = []
	_radius = []
	var n := PACK if pose == "pack" else 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 4101 + VARIANTS[kind].find(variant)
	for i in n:
		var m: MonsterModel = RatModel.new(variant) if kind == "rat" else EctoBlobModel.new(variant)
		m.idle_enabled = live
		if n > 1:
			m.offset_clock(rng.randf_range(0.0, 2.0))
			_phase.append(TAU * float(i) / float(n) * 0.4 + rng.randf_range(-0.12, 0.12))
			_radius.append(PACK_R + rng.randf_range(-0.45, 0.45))
		add_child(m)
		models.append(m)
	if kind == "blob" and pose == "crawl":
		var pts: Array[Vector3] = []
		for i in 25:
			var u := float(i) / 24.0
			pts.append(Vector3(0.12 * sin(u * 7.0), 0.0, -u * CRAWL_LEN))
		trail = EctoplasmLook.trail("film", pts, 1.0, slick_seed)
		add_child(trail)
		move_child(trail, 0)
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
	match pose:
		"run":
			_walk_line(models[0], time, RatModel.RUN_SPEED, RUN_LEN)
		"crawl":
			_walk_line(models[0], time, EctoBlobModel.CRAWL_SPEED, CRAWL_LEN)
		"pack":
			# round the loop, each on its own radius, a little in and out
			for i in models.size():
				var a := _phase[i] + time * RatModel.RUN_SPEED / PACK_R
				var r := _radius[i] + 0.2 * sin(time * 1.3 + float(i))
				models[i].position = Vector3(cos(a) * r, 0.0, sin(a) * r)
				var dir := Vector3(-sin(a), 0.0, cos(a))
				models[i].rotation.y = atan2(-dir.x, -dir.z)
		"bite", "lunge":
			var loop := BITE_LOOP if pose == "bite" else LUNGE_LOOP
			var u := fposmod(time, loop)
			var wind_at := loop - 1.8
			var m := models[0]
			if u < wind_at:
				_bit = false
				m.windup(0.0)
			elif u < wind_at + 0.8:
				m.windup((u - wind_at) / 0.8)
			elif not _bit:
				_bit = true
				m.windup(0.0)
				m.attack_swing()


## There and back along the figure's own front (local -Z), turning at each end; the model reads its speed from the motion.
func _walk_line(m: MonsterModel, time: float, speed: float, length: float) -> void:
	var lap := 2.0 * length / speed
	var u := fposmod(time, lap) / lap
	var out := u < 0.5
	var d := (u * 2.0 if out else 2.0 - u * 2.0) * length
	m.position = Vector3(0.0, 0.0, -d)
	m.rotation.y = 0.0 if out else PI


## The lab's still for the pose: mid-gallop, reared up (the bite's tell), the pack mid-loop, resting, mid-crawl at the end
## of its slick, gathered up (the lunge's tell).
func pose_still() -> void:
	for i in models.size():
		var m := models[i]
		m.idle_enabled = false
		m.pose_preview("windup" if pose == "bite" or pose == "lunge" else "rest", 1.0)
		match pose:
			"run", "pack":
				m.apply_idle(0.35 + 0.23 * float(i), RatModel.RUN_SPEED)
			"crawl":
				m.apply_idle(0.4, EctoBlobModel.CRAWL_SPEED)
				m.position = Vector3(0, 0, -CRAWL_LEN)
	if pose == "pack":
		pose_at(0.0)
