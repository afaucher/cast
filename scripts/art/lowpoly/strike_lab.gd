extends "res://scripts/art/lowpoly/anim_lab.gd"
## The MoveFeel profiles side by side (docs/design/animation-research.md "As built"): LOOK-DEV ONLY. One lane per
## profile, each lane a real Hero with its faceted model played by the GAME's code under that lane's profile (HeroGait,
## HeroFeel, Hero.melee and its hit area). MoveFeel is one global table, so the lab switches the lane's profile in and
## steps each hero itself (its own _process / _physics_process are off). The clips and the strips are the anim lab's.
##
##   godot --path . --fixed-fps 60 --resolution 1920x1080 -- --scene res://scenes/strike_lab.tscn --hero gasket
##         --clip attack|startstop|strafe --shot <abs.png> [--profiles grounded,grounded_anim] [--strike follow|wind|both]
##         [--zoom close|game] [--frames-dir <abs dir>]
##   ... --clip held [--held <spell>]  stand, walk, stop, swing, cast with a spell's component in the hand (default heal)
##   ... --overlay --shot <abs.png>   the primary's hit area on the floor and the weapon's swept path, top-down, per lane
##                                    (and the numbers, printed: "overlay ...")
##
## --profiles a,b,...      the lanes (default grounded,grounded_anim)
## --strike follow|wind|both   the heavy hitters' strike (HeroFeel.style); both: grounded, then grounded_anim with each

const DOWN_TIMES := [0.283, 0.3, 0.317, 0.35, 0.4, 0.467, 0.55, 0.7]   ## the attack strip (the click is at 0.30)
const HELD_TIMES := [0.2, 0.55, 0.8, 1.2, 1.3, 1.45, 1.7, 2.0]         ## the held clip: rest, walk, walk, swing x2, rest, cast, after
## The points of each weapon the overlay tracks: [part, part-local point]; the first is the one the numbers quote.
const TRACK := {
	"wick": [["weapon", Vector3(0, 0, 0)], ["weapon", Vector3(0, 0.81, 0.34)], ["weapon", Vector3(0, -0.81, 0.34)]],
	"gasket": [["weapon", Vector3(0, 1.43, 0)], ["weapon", Vector3(0, 1.78, 0)], ["weapon", Vector3(0, 0.9, 0)]],
	"rebar": [["glove_r", Vector3(0, -0.04, -0.38)], ["glove_l", Vector3(0, -0.04, -0.38)], ["glove_r", Vector3.ZERO], ["glove_l", Vector3.ZERO]],
}
const HIT_HEIGHT := 1.6        ## a weapon point above this (from the floor) passes over a grunt: drawn faint, not counted
const GRUNT_R := 0.38          ## the grunt's radius: the area it can be hit in is the shape grown by this
const OVERLAY_CLICK := 6

var profiles: Array[String] = []
var styles: Array[String] = []
var dummies: Array[Actor] = []
var _swing_dir := Vector3.ZERO


func _ready() -> void:
	hero_kind = arg(args, "--hero", "wick")
	clip = arg(args, "--clip", "attack")
	zoom = arg(args, "--zoom", "close")
	frames_dir = arg(args, "--frames-dir")
	MoveFeel.reset()
	SpinSweep.dev_frames = int(arg(args, "--spin-frames", "0"))   # (Gasket's grounded_anim spin: try another turn speed)
	var strike := arg(args, "--strike", HeroFeel.FOLLOW)
	for p in arg(args, "--profiles", "grounded,grounded_anim").split(","):
		if strike == "both" and p == MoveFeel.GROUNDED_ANIM and hero_kind != "wick":   # (Wick has one bash)
			profiles.append_array([p, p])
			styles.append_array([HeroFeel.FOLLOW, HeroFeel.WIND])
		else:
			profiles.append(p)
			styles.append(strike if strike != "both" else HeroFeel.FOLLOW)
	var overlay := args.has("--overlay")
	if overlay:
		_plain_floor()
	else:
		build_arena(30, 24, 27, 1)
	var yaw := deg_to_rad(YAW)
	_right = Vector3(cos(yaw), 0, -sin(yaw))
	_up = -Vector3(sin(yaw), 0, cos(yaw))
	_gap = {"wick": 3.4, "gasket": 3.6, "rebar": 4.4}[hero_kind]
	if zoom == "game":
		_gap *= 0.85
	_origin = -_right * 6.0 + _up * 1.0 if clip == "startstop" or clip == "turn" else Vector3.ZERO
	_swing_dir = Vector3(0, 0, -1) if overlay else _right
	if clip == "held":
		_swing_dir = (-_up - _right * 0.6).normalized()
	for i in profiles.size():
		_use(i)
		var model := _make_model()
		var h := HeroFactory.spawn_hero(Vector2i.ZERO, _lane_name(i), LANE_COLORS[mini(i, LANE_COLORS.size() - 1)], "sword", model, hero_kind)
		h.global_position = _lane_pos(i)
		h.snap_to_ground()
		h.set_process(false)
		h.set_physics_process(false)
		if h._name_label != null:
			h._name_label.visible = false   # (the strips and the overlay say which lane is which)
		var held := arg(args, "--held", "heal" if clip == "held" else "")
		if held != "":
			h.spell_slots = [held] as Array[String]   # (the component shows in the hand)
		heroes.append(h)
		feels.append(null)
		if clip == "attack" and not overlay:
			var d := TrainingDummy.new()
			d.max_hp = 100000.0
			d.shove_mult = 0.0
			GameWorld.spawn(d, h.global_position + _swing_dir * 1.3)
			d.snap_to_ground()
			dummies.append(d)
	_use(0)
	make_camera()
	if overlay:
		_overlay()
		return
	_aim_camera()
	if args.has("--clipcheck"):
		_clipcheck()
	elif shot_path != "":
		_record()
	else:
		_loop()


func _lane_name(i: int) -> String:
	var n := profiles[i]
	if n == MoveFeel.GROUNDED_ANIM and hero_kind != "wick" and (styles.count(HeroFeel.WIND) > 0):
		n += " (%s)" % styles[i]
	return n


## Lane i's profile (and strike style) is the active one.
func _use(i: int) -> void:
	MoveFeel.local_id = profiles[i]
	MoveFeel.mode = profiles[i]
	HeroFeel.style = styles[i]


func _lane_pos(i: int) -> Vector3:
	if args.has("--overlay"):
		return Vector3((i - (profiles.size() - 1) * 0.5) * 5.0, 0.0, 0.0)
	return _origin + _right * (i - (profiles.size() - 1) * 0.5) * _gap


func _aim_camera() -> void:
	var mid := Vector3.ZERO
	for h in heroes:
		mid += h.global_position
	mid /= maxf(1.0, heroes.size())
	var hh := 1.2 if hero_kind != "rebar" else 1.6
	aim(YAW, PITCH if zoom == "game" else CLOSE_PITCH, 24.0 if zoom == "game" else (9.5 if hero_kind == "rebar" else 8.0) + 1.5 * (profiles.size() - 2), mid + Vector3(0, hh, 0))


func _clip_def() -> Array:
	if clip == "attack":
		return [0.75, DOWN_TIMES]
	if clip == "held":
		return [2.1, HELD_TIMES]
	return CLIPS[clip]


## The "held" clip: stand, walk right, stop, a melee swing, a cast (where the held component sits through each pose).
func _input_at(t: float) -> Array:
	if clip == "held":   # (facing the camera three-quarters, so both hands show)
		return [_right if t >= 0.3 and t < 1.0 else Vector3.ZERO, _swing_dir]
	return super._input_at(t)


## The crop follows the hero, a little toward the swing in the attack clip (the dummy and the weapon stay in frame).
func _crop(img: Image, i: int) -> Image:
	var size := _crop_size(img.get_height())
	if clip == "attack":
		size.x = int(size.x * 1.35)
	var top := heroes[i].global_position + Vector3(0, {"wick": 1.3, "gasket": 1.25, "rebar": 1.8}[hero_kind] as float, 0)
	if clip == "attack":
		top += _swing_dir * 0.55
	var vp := get_viewport().get_visible_rect().size
	var c := camera.unproject_position(top) * Vector2(img.get_width() / vp.x, img.get_height() / vp.y)
	var r := Rect2i(int(c.x) - size.x / 2, int(c.y) - size.y / 2, size.x, size.y)
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var out := img.get_region(r)
	if out.get_size() != size:
		var pad := Image.create(size.x, size.y, false, out.get_format())
		pad.blit_rect(out, Rect2i(Vector2i.ZERO, out.get_size()), Vector2i.ZERO)
		out = pad
	if zoom == "game":
		out.resize(size.x * 2, size.y * 2, Image.INTERPOLATE_NEAREST)
	return out


func _step(f: int) -> void:
	var inp := _input_at(f * DT)
	var mv: Vector3 = inp[0]
	var aim_dir: Vector3 = inp[1]
	for i in heroes.size():
		_use(i)
		var h := heroes[i]
		if h.is_helpless():
			h.climbing = false
		elif mv.length() > 0.01:
			h.move(mv, DT)
		h.face_point(h.global_position + aim_dir * 5.0)
		_lane_events(f, i)
		h._physics_process(DT)
		h._process(DT)
	_use(0)
	_aim_camera()


func _lane_events(f: int, i: int) -> void:
	var at := func(s: float) -> bool: return f == int(roundf(s * 60.0))
	var h := heroes[i]
	match clip:
		"attack":
			if at.call(0.3) or at.call(0.9):
				_swing(i)
		"held":
			if at.call(1.2):
				_swing(i)
			if at.call(1.55):
				h._cast_pose()
		"hit":
			if at.call(0.3):
				h.apply_damage(12.0, null)
			if at.call(1.0):
				h.shove(-_right, 2.2, null)


func _swing(i: int) -> void:
	var h := heroes[i]
	h._ready_at.erase(Hero.KEY_MELEE)
	if i < dummies.size():
		dummies[i].heal(dummies[i].max_hp)
	_attack(h)


## The attack the lab plays: the primary, or with --secondary the RMB one (Gasket's spin, Wick's tap arrow, Rebar's bowl).
func _attack(h: Hero) -> void:
	if args.has("--secondary"):
		h._ready_at.erase(Hero.KEY_RANGED)
		h.shoot(_swing_dir)
	else:
		h.melee(_swing_dir)


## The area the overlay draws: the primary's, or the secondary's (Hero.spin_area; a projectile's has none).
func _area_of(h: Hero) -> Dictionary:
	if args.has("--secondary"):
		return h.spin_area() if h.secondary_kind == "spin" else {}
	return h.melee_area()


## --clipcheck: play the clip and print, per lane, the deepest the arms sink into the body (PoseClip) and on which frames.
func _clipcheck() -> void:
	await wait_frames(3)
	var worst: Array[float] = []
	var at: Array[String] = []
	for i in heroes.size():
		worst.append(0.0)
		at.append("")
	for f in int(_clip_def()[0] * 60.0):
		_step(f)
		await get_tree().process_frame
		for i in heroes.size():
			var d: Array = PoseClip.depth(heroes[i].visual_override as LowPolyModel, hero_kind)
			if float(d[0]) > 0.0:
				print("clip %s %s frame %d (%.3f s): %.3f %s" % [hero_kind, _lane_name(i), f, f * DT, float(d[0]), str(d[1])])
			if float(d[0]) > worst[i]:
				worst[i] = float(d[0])
				at[i] = "frame %d %s" % [f, str(d[1])]
	for i in heroes.size():
		print("clipcheck %s %s: deepest %.3f (%s)" % [hero_kind, _lane_name(i), worst[i], at[i]])
	finish()


# --- The overlay: the hit area and the weapon's path, top-down ----------------------------------------------------------

## A flat map with a plain dark floor and a half-unit grid (the measuring paper), a sun and an even fill.
func _plain_floor() -> void:
	map = HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 14):
		map.set_cell(c, 0)
	GameWorld.begin(map, self, 1)
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	plane.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.16, 0.17, 0.2)
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plane.material_override = pmat
	plane.position.y = map.ground_height(Vector3.ZERO) - 0.005
	add_child(plane)
	var grid := SurfaceTool.new()
	grid.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(-40, 41):
		var x := k * 0.5
		var w := 0.012 if k % 2 != 0 else 0.022
		for v: Vector3 in [Vector3(x - w, 0, -20), Vector3(x + w, 0, -20), Vector3(x + w, 0, 20), Vector3(x - w, 0, -20), Vector3(x + w, 0, 20), Vector3(x - w, 0, 20),
				Vector3(-20, 0, x - w), Vector3(20, 0, x - w), Vector3(20, 0, x + w), Vector3(-20, 0, x - w), Vector3(20, 0, x + w), Vector3(-20, 0, x + w)]:
			grid.set_normal(Vector3.UP)
			grid.add_vertex(v + Vector3.UP * (plane.position.y + 0.003))
	var gi := MeshInstance3D.new()
	gi.mesh = grid.commit()
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.albedo_color = Color(0.26, 0.28, 0.33)
	gi.material_override = gmat
	add_child(gi)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment.ambient_light_energy = 0.8
	add_child(env)


func _overlay() -> void:
	var n := heroes.size()
	aim(0.0, -89.0, maxf(5.6, 5.0 * n / 1.7), Vector3(0, 0, -0.9))
	await wait_frames(4)
	# pass 1: one swing per lane (straight up the screen), every tracked point every frame
	var paths: Array = []           # lane -> [frame] -> [points (hero-relative: x lateral right, y height, z forward)]
	var impact: Array[int] = []
	for i in n:
		paths.append([])
		impact.append(-1)
	var t0 := Engine.get_process_frames()
	var proj: Array = []            # lane -> the projectile its secondary launched (an arrow, a boulder), or null
	var ppaths: Array = []          # lane -> [frame] -> its hero-relative position (or null)
	for i in n:
		proj.append(null)
		ppaths.append([])
	for f in 60:
		for i in n:
			_use(i)
			var h := heroes[i]
			h.face_point(h.global_position + _swing_dir * 5.0)
			if f == OVERLAY_CLICK:
				var before := _projectiles()
				_attack(h)
				for p in _projectiles():
					if not before.has(p) and p.get("source") == h:
						proj[i] = p
			h._physics_process(DT)
			h._process(DT)
		_use(0)
		await get_tree().process_frame
		for i in n:
			(paths[i] as Array).append(_points(heroes[i]))
			var alive: bool = proj[i] != null and is_instance_valid(proj[i])
			(ppaths[i] as Array).append(_rel(heroes[i], (proj[i] as Node3D).global_position) if alive else null)
	_ppaths = ppaths
	for i in n:
		var fe: HeroFeel = heroes[i]._feel
		if (fe.strikes > 0 or fe.secondaries > 0) and fe.impact_frame >= 0:
			impact[i] = fe.impact_frame - t0
		elif args.has("--secondary") and heroes[i].secondary_kind == "spin":   # the model's own spin: when the sweep is done
			impact[i] = OVERLAY_CLICK + _sweep_frames(paths[i])
		else:   # the model's own swing: the frame the first point is farthest forward (low enough to hit)
			var best := -INF
			for f in range(OVERLAY_CLICK, (paths[i] as Array).size()):
				var p: Vector3 = paths[i][f][0]
				if p.y < HIT_HEIGHT and p.z > best:
					best = p.z
					impact[i] = f
	# the numbers, and the marks on the floor
	for i in n:
		_use(i)
		var line := _report_secondary(i, paths[i], impact[i]) if args.has("--secondary") else _report(i, paths[i], impact[i])
		_draw_area(heroes[i])
		_draw_path(heroes[i], paths[i], impact[i])
		for f in mini(OVERLAY_CLICK + 14, (ppaths[i] as Array).size()):
			var pp: Variant = ppaths[i][f]
			if pp != null:   # the projectile's first frames, cyan
				_dot(heroes[i], Vector2((pp as Vector3).x, (pp as Vector3).z), 0.07, Color(0.3, 1.0, 1.0, 1.0))
		var lab := Label3D.new()
		lab.text = "%s  %s\n%s" % [hero_kind.capitalize(), _lane_name(i), line]
		lab.font_size = 36
		lab.pixel_size = 0.0055
		lab.outline_size = 8
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.position = heroes[i].global_position + Vector3(0, 0.3, 1.6)
		add_child(lab)
	# pass 2: the same swing again, each lane frozen on its impact frame (the pose that goes with the marks)
	for h in heroes:
		if "_swing_next_right" in h.visual_override:
			h.visual_override.set("_swing_next_right", true)   # (Rebar's model alternates fists: the right one again)
	for f in 60:
		for i in n:
			if f > impact[i]:
				heroes[i].process_mode = Node.PROCESS_MODE_DISABLED
				continue
			_use(i)
			var h := heroes[i]
			h._ready_at.erase(Hero.KEY_MELEE)
			if f == OVERLAY_CLICK:
				_attack(h)
			h._physics_process(DT)
			h._process(DT)
		_use(0)
		await get_tree().process_frame
	var img := await grab(4)
	var vp := img.get_size()
	var unit := vp.y / camera.size
	var w := int(unit * (5.0 * n))
	var r := Rect2i(vp.x / 2 - w / 2, int(vp.y * 0.5 - unit * 2.5), w, int(unit * 5.9)).intersection(Rect2i(Vector2i.ZERO, vp))
	var out := img.get_region(r)
	out.convert(Image.FORMAT_RGB8)
	var k := minf(1.0, 900.0 / out.get_width())
	out.resize(int(out.get_width() * k), int(out.get_height() * k), Image.INTERPOLATE_LANCZOS)
	save_shot(out, shot_path)
	finish()


var _ppaths: Array = []


## The projectiles in the world (arrows, bolts, boulders).
func _projectiles() -> Array:
	var out := []
	for c in GameWorld.root.get_children():
		if c is Projectile or c is BowlBoulder:
			out.append(c)
	return out


## `w` relative to the hero (x: to its right, y: up from the floor, z: forward along the swing).
func _rel(h: Hero, w: Vector3) -> Vector3:
	var fwd := _swing_dir
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var d := w - h.global_position
	return Vector3(d.dot(side), d.y, d.dot(fwd))


## Frames after the click until the weapon's first point has swept 330 degrees round the hero (a spin).
func _sweep_frames(path: Array) -> int:
	var total := 0.0
	var prev := INF
	for f in range(OVERLAY_CLICK, path.size()):
		var p: Vector3 = path[f][0]
		var a := atan2(p.x, p.z)
		if prev != INF:
			total += absf(wrapf(a - prev, -PI, PI))
		prev = a
		if total >= deg_to_rad(330.0):
			return f - OVERLAY_CLICK
	return path.size() - OVERLAY_CLICK


## The secondary's numbers (a spin: the wrench head's reach round her and how long the sweep takes; a projectile: where it
## appears against where the bow or the hand is).
func _report_secondary(i: int, path: Array, imp: int) -> String:
	var h := heroes[i]
	if h.secondary_kind == "spin":
		var area := _area_of(h)
		var lo := INF
		var hi := 0.0
		for f in range(OVERLAY_CLICK, mini(path.size(), OVERLAY_CLICK + 40)):
			var p: Vector3 = path[f][0]
			if p.y < HIT_HEIGHT and Vector2(p.x, p.z).length() > 1.0:
				lo = minf(lo, Vector2(p.x, p.z).length())
				hi = maxf(hi, Vector2(p.x, p.z).length())
		var sweep := _sweep_frames(path)
		print("overlay %s %-24s spin: the head sweeps %d frames after the click at %.2f..%.2f from her, %.2f up; area %s, grunt area %.2f u2" % [
			hero_kind, _lane_name(i), sweep, lo, hi, (path[mini(imp, path.size() - 1)][0] as Vector3).y, str(area), _area_size(area, GRUNT_R)])
		return "the wrench sweeps round %d frames after the hits\nhead %.1f..%.1f out / area %.1f, grunt area %.1f u2" % [
			sweep, lo, hi, float(area["reach"]), _area_size(area, GRUNT_R)]
	var pp: Array = _ppaths[i]
	var spawn := -1
	for f in pp.size():
		if pp[f] != null:
			spawn = f
			break
	if spawn < 0:
		return "no projectile"
	var at: Vector3 = pp[spawn]
	var hand: Vector3 = path[spawn][0]
	var rel: Vector3 = path[imp][0]
	print("overlay %s %-24s %s: appears frame +%d at fwd %.2f side %+.2f up %.2f; the %s is then at fwd %.2f side %+.2f up %.2f (%.2f away); its release pose is frame +%d at fwd %.2f side %+.2f up %.2f" % [
		hero_kind, _lane_name(i), h.secondary_kind, spawn - OVERLAY_CLICK, at.z, at.x, at.y, "bow" if hero_kind == "wick" else "hand",
		hand.z, hand.x, hand.y, at.distance_to(hand), imp - OVERLAY_CLICK, rel.z, rel.x, rel.y])
	return "%s appears +%d frames, %.1f from the %s\nthe release pose comes +%d frames\n" % [h.secondary_kind, spawn - OVERLAY_CLICK,
		at.distance_to(hand), "bow" if hero_kind == "wick" else "hand", imp - OVERLAY_CLICK]


## The tracked points of `h`'s weapon now, relative to the hero (x: to its right, y: up from the floor, z: forward).
func _points(h: Hero) -> Array:
	var m := h.visual_override as LowPolyModel
	var fwd := _swing_dir
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var out := []
	for t: Array in TRACK[hero_kind]:
		var part := m.parts[t[0]] as Node3D
		var w: Vector3 = part.global_transform * (t[1] as Vector3) - h.global_position
		out.append(Vector3(w.dot(side), w.y, w.dot(fwd)))
	return out


func _report(i: int, path: Array, imp: int) -> String:
	var h := heroes[i]
	var area := _area_of(h)
	var low := 0
	var inside := 0
	var reach := 0.0
	var lat_min := INF
	var lat_max := -INF
	for f in range(OVERLAY_CLICK, mini(path.size(), OVERLAY_CLICK + 30)):
		for p: Vector3 in path[f]:
			if p.y >= HIT_HEIGHT:
				continue
			low += 1
			reach = maxf(reach, p.z)
			lat_min = minf(lat_min, p.x)
			lat_max = maxf(lat_max, p.x)
			if _in_area(area, p.x, p.z, 0.0):
				inside += 1
	var ip: Vector3 = path[imp][0] if imp >= 0 else Vector3.ZERO
	print("overlay %s %-24s impact frame +%d at fwd %.2f side %+.2f up %.2f | low path: reach %.2f, side %+.2f..%+.2f, %d%% inside the area | area %s, grunt area %.2f u2" % [
		hero_kind, _lane_name(i), imp - OVERLAY_CLICK, ip.z, ip.x, ip.y, reach, lat_min, lat_max,
		roundi(100.0 * inside / maxf(1.0, low)), str(area), _area_size(area, GRUNT_R)])
	var far := float(area["far"]) + maxf(float(area["radius"]), float(area.get("end_radius", 0.0))) if str(area["shape"]) == "lane" else float(area["reach"])
	return "impact +%d frames, %.1f ahead, %+.1f aside\n%s\nweapon reach %.1f / area %.1f\ngrunt hit area %.2f u2" % [
		imp - OVERLAY_CLICK, ip.z, ip.x, "inside the area" if _in_area(area, ip.x, ip.z, 0.0) else "OUTSIDE the area", reach, far,
		_area_size(area, GRUNT_R)]


static func _in_area(area: Dictionary, x: float, z: float, grow: float) -> bool:
	if str(area["shape"]) == "lane":
		var q := Vector2(x, z)
		var end := float(area.get("end_radius", 0.0))
		if end > 0.0 and q.distance_to(Vector2(0, float(area["far"]))) <= end + grow:
			return true
		return Geometry2D.get_closest_point_to_segment(q, Vector2(0, float(area["near"])), Vector2(0, float(area["far"]))).distance_to(q) <= float(area["radius"]) + grow
	var v := Vector2(x, z)
	if v.length() > float(area["reach"]) + grow:
		return false
	if v.length() < 0.001 or float(area["arc"]) >= 360.0:
		return true
	return absf(rad_to_deg(Vector2(0, 1).angle_to(v))) <= float(area["arc"]) * 0.5


## The floor area (u^2) a target of radius `r` can stand in and be hit (its centre within the shape grown by r; a wedge
## only grows outward: Combat tests the centre's angle).
static func _area_size(area: Dictionary, r: float) -> float:
	if str(area["shape"]) == "lane":
		if float(area.get("end_radius", 0.0)) > 0.0:   # (a lane and a disc: counted on a 1 cm grid)
			var big := maxf(float(area["radius"]), float(area["end_radius"])) + r
			var n := 0
			var step := 0.01
			var z := float(area["near"]) - big
			while z <= float(area["far"]) + big:
				var x := -big
				while x <= big:
					if _in_area(area, x, z, r):
						n += 1
					x += step
				z += step
			return n * step * step
		var rr := float(area["radius"]) + r
		return (float(area["far"]) - float(area["near"])) * 2.0 * rr + PI * rr * rr
	var rr2 := float(area["reach"]) + r
	return float(area["arc"]) / 360.0 * PI * rr2 * rr2


func _draw_area(h: Hero) -> void:
	var area := _area_of(h)
	var col := Color(1.0, 0.85, 0.3)
	if area.is_empty():   # (a projectile: no area of its own here)
		_line(h, _circle(Vector2.ZERO, h.radius, 24), Color(0.9, 0.9, 0.95, 0.8), 0.02)
		return
	_fill(h, _outline(area, 0.0), Color(col, 0.28))
	_line(h, _outline(area, 0.0), Color(col, 0.95), 0.035)
	_line(h, _outline(area, GRUNT_R), Color(col, 0.45), 0.018)
	var end := float(area.get("end_radius", 0.0))
	if end > 0.0:   # (the smash's disc round the landing)
		var c := Vector2(0, float(area["far"]))
		_fill(h, _circle(c, end, 32), Color(col, 0.28))
		_line(h, _circle(c, end, 32), Color(col, 0.95), 0.035)
		_line(h, _circle(c, end + GRUNT_R, 32), Color(col, 0.45), 0.018)
	_line(h, _circle(Vector2.ZERO, h.radius, 24), Color(0.9, 0.9, 0.95, 0.8), 0.02)


## The area's outline in hero space (x side, y forward), grown by `grow` (HitAreaShape: the test gym's overlay draws the same).
func _outline(area: Dictionary, grow: float) -> PackedVector2Array:
	return HitAreaShape.outline(area, grow)


static func _circle(c: Vector2, r: float, n: int) -> PackedVector2Array:
	return HitAreaShape.circle(c, r, n)


func _world(h: Hero, p: Vector2, y: float = 0.03) -> Vector3:
	var fwd := _swing_dir
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	return h.global_position + side * p.x + fwd * p.y + Vector3.UP * y


func _fill(h: Hero, pts: PackedVector2Array, col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	for k in pts.size():
		for v: Vector2 in [c, pts[k], pts[(k + 1) % pts.size()]]:
			st.set_normal(Vector3.UP)
			st.add_vertex(_world(h, v, 0.02))
	_mesh(st.commit(), col)


func _line(h: Hero, pts: PackedVector2Array, col: Color, width: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in pts.size():
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		var d := (b - a).normalized().orthogonal() * width * 0.5
		for v: Vector2 in [a - d, a + d, b + d, a - d, b + d, b - d]:
			st.set_normal(Vector3.UP)
			st.add_vertex(_world(h, v, 0.04))
	_mesh(st.commit(), col)


func _draw_path(h: Hero, path: Array, imp: int) -> void:
	for f in range(OVERLAY_CLICK, mini(path.size(), OVERLAY_CLICK + 40)):
		var before := f < imp
		var at := f == imp
		var k := clampf(float(f - imp) / 25.0, 0.0, 1.0)
		for j in (path[f] as Array).size():
			var p: Vector3 = path[f][j]
			var col := Color(0.35, 0.75, 1.0) if before else (Color.WHITE if at else Color(1.0, 0.55 - 0.3 * k, 0.2))
			var low := p.y < HIT_HEIGHT
			col.a = 1.0 if low else 0.3
			var r := (0.11 if at else 0.055) * (1.0 if j == 0 else 0.75)
			_dot(h, Vector2(p.x, p.z), r, col)


func _dot(h: Hero, c: Vector2, r: float, col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := _circle(c, r, 10)
	for k in pts.size():
		for v: Vector2 in [c, pts[k], pts[(k + 1) % pts.size()]]:
			st.set_normal(Vector3.UP)
			st.add_vertex(_world(h, v, 0.06))
	_mesh(st.commit(), col)


func _mesh(m: Mesh, col: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = col
	mat.no_depth_test = col.a > 0.9
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
