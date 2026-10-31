extends TestCase
## The crypt pests look test (docs/design/crypt-pests-look.md, LOOK-DEV ONLY): every rat (RatModel) and ecto blob
## (EctoBlobModel) variant builds headless in its poses (a dog-sized rat whose tail lies on the floor and whose feet stand on
## it, rearing up for the tell and lunging for the bite; a see-through blob with no ink in the ghost colour, gathering up and
## lunging), the blob's slick (EctoplasmLook.trail) is the ectoplasm look's own, the gym's crypt entries ("pest:...") put
## plain cosmetic CryptPest nodes down that loop their poses, the Ghost colour redresses them, and the look lab's builders
## run headless.

const LAB := "res://scripts/art/lowpoly/crypt/crypt_pests_lab.gd"

var root: Node3D


func setup() -> void:
	GhostLook.reset()
	NecroLook.reset()
	_check_entries()
	_check_rats()
	_check_blobs()
	_check_trail()
	await _check_gym_spawns()
	await _check_lab()
	GhostLook.reset()
	NecroLook.reset()
	EctoplasmLook.clock = -1.0
	EctoBlobModel.clock = -1.0
	finish()


func _check_entries() -> void:
	check(GymSpawns.GROUPS.has("crypt"), "the crypt group is listed")
	var n := 0
	for r: Array in CryptPest.entries():
		var e := GymSpawns.find("crypt:" + CryptPest.key_of(r[0], r[1], r[2]))
		if check(not e.is_empty(), "crypt:pest:%s:%s:%s is a gym entry" % r):
			eq(str(e["skip"]), "", "it has a button")
			eq(str(e["group"]), "crypt", "in the crypt group")
			n += 1
	eq(n, 3 * 3 + 3 * 3, "three rats and three blobs, each in three poses")
	eq(CryptPest.label_of("rat", "grave", "bite"), "rat (grave): bite", "a rat's button label")
	eq(CryptPest.label_of("blob", "puddle", "crawl"), "ecto blob (puddle): crawl", "a blob's button label")


func _check_rats() -> void:
	for v: String in RatModel.VARIANTS:
		var m := RatModel.new(v)
		for p: String in RatModel.PART_NAMES:
			check(m.has_part(p), "%s has its %s" % [v, p])
		check(m.triangle_count() < 3000, "%s is a cheap model (%d tris)" % [v, m.triangle_count()])
		# dog-sized: about 0.4-0.5 at the hips, nose to rump about a metre, next to a hero of about 2
		var hip := (m.get_part("body") as Node3D).position.y
		check(hip > 0.35 and hip < 0.55, "%s: hips at %.2f (a dog's)" % [v, hip])
		var span := _span(m, ["body", "head"])
		check(span.size.z > 0.85 and span.size.z < 1.45, "%s: nose to rump %.2f" % [v, span.size.z])
		# the eyes: glowing in the ghost colour, or dark beads
		var ghost := str(RatModel.SPEC[v]["eyes"]) == "ghost"
		eq(_glows(m, NecroLook.glow_colour()), ghost, "%s: its eyes %s" % [v, "glow in the ghost colour" if ghost else "do not glow"])
		var mat := (m.get_part("body") as MeshInstance3D).material_override as ShaderMaterial
		eq(mat.shader.code.contains("ghost_rim"), float(RatModel.SPEC[v]["rim"]) > 0.0, "%s: the dead's rim only on the haunted one" % v)
		check(mat.next_pass != null, "%s keeps the ink outline" % v)
		# rest: feet on the floor, the tail lying on it (never under it)
		m.pose_preview("rest")
		for leg: String in ["leg_fl", "leg_fr", "leg_hl", "leg_hr"]:
			var foot := _foot_y(m, leg)
			check(absf(foot) < 0.09, "%s rest: %s's foot on the floor (%.3f)" % [v, leg, foot])
		check(_tail_tip_y(m) > -0.03 and _tail_tip_y(m) < 0.2, "%s rest: the tail lies on the floor (tip %.3f)" % [v, _tail_tip_y(m)])
		var head_rest := _local_origin(m, m.get_part("head")).y
		# running: the gallop moves the legs and the body
		m.apply_idle(0.42, RatModel.RUN_SPEED)
		var f1 := _local_origin(m, m.get_part("leg_fl")) + (m.get_part("leg_fl") as Node3D).basis * Vector3(0, -m.fl_len, 0)
		m.apply_idle(0.62, RatModel.RUN_SPEED)
		var f2 := _local_origin(m, m.get_part("leg_fl")) + (m.get_part("leg_fl") as Node3D).basis * Vector3(0, -m.fl_len, 0)
		check(f1.distance_to(f2) > 0.1, "%s runs: a front foot reaches and gathers (%.2f)" % [v, f1.distance_to(f2)])
		check(_tail_tip_y(m) > -0.03, "%s running: the tail stays off the floor's underside" % v)
		# the tell: reared up on its haunches, head up, jaw open
		m.pose_preview("windup", 1.0)
		check((m.get_part("body") as Node3D).rotation.x > 0.9, "%s reared up (pitch %.2f)" % [v, (m.get_part("body") as Node3D).rotation.x])
		check(_local_origin(m, m.get_part("head")).y > head_rest + 0.25, "%s reared: its head well up" % v)
		check((m.get_part("jaw") as Node3D).rotation.x < -0.8, "%s reared: its jaw open" % v)
		check(_tail_tip_y(m) > -0.03, "%s reared: the tail on the floor behind it" % v)
		for leg: String in ["leg_hl", "leg_hr"]:
			check(absf(_foot_y(m, leg)) < 0.09, "%s reared: stands on its hind feet (%s %.3f)" % [v, leg, _foot_y(m, leg)])
		# the bite: snapped forward
		m.pose_preview("swing", 1.0)
		check((m.get_part("body") as Node3D).position.z < -0.25, "%s bites: lunged forward" % v)
		m.free()


func _check_blobs() -> void:
	for v: String in EctoBlobModel.VARIANTS:
		var b := EctoBlobModel.new(v)
		check(b.has_part("body"), "%s has its body" % v)
		eq(b.has_part("inside"), v == "jelly", "%s: things suspended in it (the bone jelly only)" % v)
		eq(b.has_part("eyes"), v == "puddle", "%s: the eyes on its hump (the puddle only)" % v)
		eq(b.has_part("face_eyes"), v == "faces", "%s: glowing eyes in its faces (the mass of faces only: the game's, H3b)" % v)
		eq(b.has_part("pod"), v != "puddle", "%s: a pseudopod for its lunge" % v)
		check(b.triangle_count() < 3000, "%s is a cheap model (%d tris)" % [v, b.triangle_count()])
		var body := b.get_part("body") as MeshInstance3D
		check(b.is_jelly(body), "%s: its body is the jelly" % v)
		var j := b.jelly
		check(j.next_pass == null, "%s: no ink outline (ectoplasm has none)" % v)
		check(float(j.get_shader_parameter("alpha")) < 0.8, "%s: see-through" % v)
		eq(j.get_shader_parameter("ecto"), GhostLook.COLOUR["pale blue"], "%s: in the ghost colour" % v)
		check(b.light != null and b.light.light_color == GhostLook.COLOUR["pale blue"], "%s: a small cold light of its own" % v)
		if v == "jelly":
			check(_glows(b, NecroLook.glow_colour()), "the bone jelly's skull: its sockets glow")
		if v == "puddle":
			check(b.sheet != null and b.sheet.is_in_group(EctoplasmLook.GROUP), "the puddle's sheet is the ectoplasm look's own")
			check(_glows(b, NecroLook.glow_colour()), "the puddle's eyes glow")
		if v == "faces":
			check(_glows(b, NecroLook.glow_colour()), "the mass of faces: its faces' eyes glow (H3b: they read at the game camera)")
		b.pose_preview("rest")
		var rest_h := body.scale.y
		# crawling squashes and stretches it
		b.apply_idle(0.37, EctoBlobModel.CRAWL_SPEED)
		var s1 := body.scale
		var p1 := body.position
		b.apply_idle(1.12, EctoBlobModel.CRAWL_SPEED)
		check(s1.distance_to(body.scale) + p1.distance_to(body.position) > 0.05, "%s crawls: a squash and stretch (the hump rolls)" % v)
		# the tell: gathered up tall, flaring
		b.pose_preview("windup", 1.0)
		check(body.scale.y > rest_h * 1.3, "%s gathers up (%.2f from %.2f)" % [v, body.scale.y, rest_h])
		check(float(j.get_shader_parameter("flare")) > 0.5, "%s flares in the tell" % v)
		# the lunge: thrown forward
		b.pose_preview("swing", 1.0)
		check(body.position.z < -0.2, "%s lunges forward (%.2f)" % [v, body.position.z])
		if b.has_part("pod"):
			check((b.get_part("pod") as Node3D).visible and (b.get_part("pod") as Node3D).scale.z > 0.9, "%s: the pseudopod out" % v)
			b.pose_preview("rest")
			check(not (b.get_part("pod") as Node3D).visible, "%s: the pseudopod in at rest" % v)
		b.free()
	GhostLook.colour = "ecto green"
	var g := EctoBlobModel.new("jelly")
	eq(g.jelly.get_shader_parameter("ecto"), GhostLook.COLOUR["ecto green"], "ecto green follows the ghosts")
	g.free()
	GhostLook.reset()


## The blob's slick: the ectoplasm look's film along a path, see-through, no ink, narrowing to its old end.
func _check_trail() -> void:
	var pts: Array[Vector3] = []
	for i in 13:
		pts.append(Vector3(0.1 * sin(float(i)), 0.0, 3.0 - 0.25 * float(i)))
	var tr := EctoplasmLook.trail("film", pts, 1.0, 3)
	check(tr.is_in_group(EctoplasmLook.GROUP), "the slick is in the ectoplasm group")
	var mats := EctoplasmLook.materials_of(tr)
	check(not mats.is_empty(), "it has its sheet")
	for m in mats:
		check(m.next_pass == null, "no ink outline")
	var sheet: MeshInstance3D = null
	for c in tr.get_children():
		if c.name.begins_with("Sheet"):
			sheet = c
	if check(sheet != null, "a sheet mesh"):
		var a := sheet.mesh.get_aabb()
		check(a.size.z > 2.6 and a.size.x < 1.8 and a.size.y < 0.2, "it runs along the path, flat (%s)" % a)
		# narrowing: the old end (high z) is thinner than the new end
		var verts: PackedVector3Array = sheet.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var old_w := 0.0
		var new_w := 0.0
		for p in verts:
			if p.z > 2.6:
				old_w = maxf(old_w, absf(p.x))
			elif p.z < 0.4 and p.z > -0.2:
				new_w = maxf(new_w, absf(p.x))
		check(old_w < new_w * 0.7, "narrowing to its old end (%.2f vs %.2f)" % [old_w, new_w])
	EctoplasmLook.set_wash(tr, 0.5)
	for m in EctoplasmLook.materials_of(tr):
		near(float(m.get_shader_parameter("wash")), 0.5, 0.0001, "Damp's wash reaches it")
	tr.free()


func _check_gym_spawns() -> void:
	root = Node3D.new()
	add_child(root)
	var map := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 9):
		map.set_cell(c, 0).tag = "room:0"
	GameWorld.begin(map, root, 3)
	var made := {}
	for r: Array in CryptPest.entries():
		var key := CryptPest.key_of(r[0], r[1], r[2])
		var out := GymSpawns.spawn(GymSpawns.find("crypt:" + key), Vector3.ZERO, 1, null, null)
		if check(out.size() == 1 and out[0] is CryptPest, "%s spawns one CryptPest" % key):
			var p := out[0] as CryptPest
			made[key] = p
			check(not (out[0] is Actor) and p.is_in_group(GhostLook.GROUP), "a cosmetic node in the ghost group")
			check(p.get_parent() == GameWorld.root, "under the world")
			eq(p.models.size(), CryptPest.PACK if r[2] == "pack" else 1, "%s: its models" % key)
			eq(p.trail != null, r[2] == "crawl", "%s: a slick only when crawling" % key)
	await frames(2)
	if made.size() != CryptPest.entries().size():
		return
	var runner: CryptPest = made["pest:rat:runner:run"]
	runner.pose_at(0.2)
	var p0 := runner.models[0].position
	runner.pose_at(0.6)
	check(runner.models[0].position.distance_to(p0) > 1.0, "the rat gallops its line")
	var pack: CryptPest = made["pest:rat:sewer:pack"]
	pack.pose_at(0.0)
	var q0 := pack.models[0].position
	pack.pose_at(0.5)
	check(pack.models[0].position.distance_to(q0) > 1.0, "the pack runs its loop")
	var crawler: CryptPest = made["pest:blob:jelly:crawl"]
	check(crawler.trail.is_in_group(EctoplasmLook.GROUP), "the crawler's slick is ectoplasm")
	crawler.pose_at(0.5)
	var c0 := crawler.models[0].position
	crawler.pose_at(2.5)
	check(crawler.models[0].position.distance_to(c0) > 0.8, "the blob crawls its line (slowly)")
	var biter: CryptPest = made["pest:rat:grave:bite"]
	biter.pose_at(CryptPest.BITE_LOOP - 1.4)
	check(biter.models[0].wind_e() > 0.3, "the biter rears up before it bites")
	# the Ghost colour redresses them
	check(GhostLook.pick("ghost_colour", "ecto green"), "pick ecto green")
	var blob := (made["pest:blob:faces:rest"] as CryptPest).models[0] as EctoBlobModel
	eq(blob.jelly.get_shader_parameter("ecto"), GhostLook.COLOUR["ecto green"], "the blobs turn ecto green live")
	check(_glows((made["pest:rat:runner:run"] as CryptPest).models[0], GhostLook.COLOUR["ecto green"]), "so do the runner's eyes")
	GhostLook.reset()
	GhostLook.refresh_all()
	root.queue_free()
	await frames(2)


## The lab's builders, headless: the crypt it stands in, its stages on floor, a still of every variant and pose, a slick.
func _check_lab() -> void:
	var lab: Node3D = load(LAB).new()
	add_child(lab)
	await frames(2)
	var m: HexMap = lab.get("map")
	if check(m != null, "the lab built the crypt"):
		for k: String in ["chamber", "gallery", "shelf"]:
			var c := Hex.from_world(lab.get(k) as Vector3)
			check(m.cells.has(c) and m.cells[c].type != HexMap.Tile.WALL, "the %s stage is floor" % k)
	for v: String in RatModel.VARIANTS:
		for pose: String in ["rest", "run", "windup", "swing"]:
			var r: MonsterModel = lab.call("_pest", "rat", v, pose, lab.get("chamber"), Vector3.FORWARD)
			check(r is RatModel and not r.idle_enabled, "the lab stages the %s rat %s" % [v, pose])
	for v: String in EctoBlobModel.VARIANTS:
		for pose: String in ["rest", "crawl", "windup", "swing"]:
			var b: MonsterModel = lab.call("_pest", "blob", v, pose, lab.get("gallery"), Vector3.FORWARD)
			check(b is EctoBlobModel and not b.idle_enabled, "the lab stages the %s blob %s" % [v, pose])
	var tr: Node3D = lab.call("_slick", lab.get("gallery"), Vector3.FORWARD, 3.0, 5)
	check(tr != null and tr.is_in_group(EctoplasmLook.GROUP), "the lab lays a slick")
	lab.queue_free()
	await frames(2)


## The model-space bounds of the named parts' meshes.
func _span(model: Node3D, names: Array) -> AABB:
	var out := AABB()
	var first := true
	for nm: String in names:
		var part := (model as LowPolyModel).get_part(nm)
		var a := _xf(model, part) * part.mesh.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


func _foot_y(m: RatModel, leg: String) -> float:
	var part := m.get_part(leg)
	var length := m.fl_len if leg.begins_with("leg_f") else m.hl_len
	return (_xf(m, part) * Vector3(0, -length, 0)).y


func _tail_tip_y(m: RatModel) -> float:
	return (_xf(m, m.get_part("tail2")) * Vector3(0, 0, float(m.spec["tail"]) * 0.5)).y


## A node's transform in `model`'s own space (works outside the tree).
func _xf(model: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != model:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _local_origin(model: Node3D, n: Node3D) -> Vector3:
	return _xf(model, n).origin


## True when some face of `n`'s meshes is painted the glow (vertex alpha 0.5) in colour `col`'s hue.
func _glows(n: Node, col: Color) -> bool:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh as ArrayMesh
		if mesh == null:
			continue
		var cols = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		if cols == null:
			continue
		for c: Color in cols:
			if absf(c.a - MonsterMaterial.GLOW_ALPHA) < 0.01 and absf(c.h - col.h) < 0.06 and c.s > 0.1:
				return true
	return false
