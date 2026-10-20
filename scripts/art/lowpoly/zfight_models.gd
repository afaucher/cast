class_name ZFightModels
extends RefCounted
## Every model builder and every composition ZFightCheck scans (tests/test_zfight.gd; tools/zfight_scan.tscn writes the
## full ranked report). Dev / test only; nothing in the game calls it.
##
## MODELS: one entry per thing a builder can make, {name, make: Callable -> Node3D, ground: bool}. `ground`: it stands
## on the hex floor (its origin is the floor top), so it is also checked against an upward plane at y = 0.
## STACKS: models placed together the way the game places them (mail package stacks, the van on its chalk circle,
## the summoning circle on its rug). Only fights BETWEEN the placed models are new there (each one alone is a MODEL).
## Whole scenes (a generated floor with its decor vignettes, priced props, notes, package stacks and the monster under each
## gate room (HellgateBeast) against the real hex terrain and walls; the menu garage) are scan_site() and scan_menu().
##
##   for e in ZFightModels.models(): ...
##   var found := await ZFightModels.scan(self)     # every model and stack: Array of findings (ZFightCheck) + "scene"

const PoolProps := preload("res://scripts/art/lowpoly/props/pool_props.gd")
const SharkModels := preload("res://scripts/art/lowpoly/props/shark_models.gd")
const MenuBackdropScript := preload("res://scripts/ui/menu_backdrop.gd")
const HealerBlockouts := preload("res://scripts/art/lowpoly/monsters/healer_blockouts.gd")
const CoolerCarriers := preload("res://scripts/art/lowpoly/monsters/cooler_carriers.gd")

const BIT_KINDS: Array[String] = ["skull", "tub", "lid", "pickle", "flap", "plank"]
const POOL_KINDS: Array[String] = ["shark", "eel", "jellyfish", "specimen", "ladder", "catwalk", "gantry", "ripple", "steam",
		"flames", "lifebuoy", "drain_grate", "hazard_sign", "valve_wheel", "pipe_run", "lab_bench", "stair_rail"]
const LOBBY_KINDS: Array[String] = ["bench", "palm", "directory", "service_sign", "extinguisher", "keep_clear", "pallet", "runner"]
const LOOKS: Array[String] = ["service", "fancy"]
static var verbose := false           ## scan() prints each entry's time
const FORMS: Array[String] = ["wall", "column"]


static func models() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind: String in RoomThemeDefs.DECOR.keys():
		var params := {}
		if kind == "neon_sign":
			params = {"text": "EVIL", "color": Color(1, 0.2, 0.15)}
		out.append({"name": "decor/" + kind, "make": DecorModels.build.bind(kind, params), "ground": true})
	for kind: String in PropModels.HEIGHTS.keys():
		out.append({"name": "prop/" + kind, "make": PropModels.build.bind(kind), "ground": true})
		out.append({"name": "prop_rubble/" + kind, "make": PropModels.rubble.bind(kind), "ground": true})
	for kind: String in PackageModels.KINDS:
		for sd in [1, 2, 3]:
			out.append({"name": "package/%s#%d" % [kind, sd], "make": PackageModels.box.bind(kind, sd), "ground": true})
	for kind: String in BIT_KINDS:
		out.append({"name": "package_bit/" + kind, "make": _bit.bind(kind), "ground": true})
	out.append({"name": "van/closed", "make": _van.bind(0.0, 0.0), "ground": true})
	out.append({"name": "van/open_lit", "make": _van.bind(1.0, 1.0), "ground": true})
	out.append({"name": "van_rug", "make": func() -> Node3D: return VanRug.new(4.4), "ground": true})
	out.append({"name": "van_circle", "make": _circle.bind(2.9), "ground": true})
	for look in LOOKS:
		for form in FORMS:
			out.append({"name": "elevator/%s_%s/closed" % [look, form], "make": _elevator.bind(look, form, 0.0), "ground": true})
			out.append({"name": "elevator/%s_%s/open" % [look, form], "make": _elevator.bind(look, form, 1.0), "ground": true})
		for kind in LOBBY_KINDS:
			out.append({"name": "lobby/%s/%s" % [look, kind], "make": ElevatorLobbyProps.build.bind(kind, look, {}), "ground": true})
	out.append({"name": "hellgate", "make": HellgateModel.make.bind(false), "ground": true})
	out.append({"name": "hellgate/origin", "make": HellgateModel.make.bind(true), "ground": true})
	for style: String in OfficeDoorModel.STYLES:
		for w in [3.0, 4.58]:   # (square across a narrow corridor, and the longest common chord across a bend)
			for st: Array in [["shut", 0.0, false], ["half", 0.5, false], ["open", 1.0, false], ["smashed", 0.0, true]]:
				out.append({"name": "door/%s/%s/w%.1f" % [style, st[0], w], "make": _door.bind(style, w, float(st[1]), bool(st[2])), "ground": true})
	for style: String in EmployeeModel.STYLES:
		for v in [0, 1, 2]:
			out.append({"name": "employee/%s#%d" % [style, v], "make": func() -> Node3D: return EmployeeModel.new(style, v), "ground": true})
	out.append({"name": "hero/wick", "make": func() -> Node3D: return WickModel.new(), "ground": true})
	out.append({"name": "hero/gasket", "make": func() -> Node3D: return GasketModel.new(), "ground": true})
	out.append({"name": "hero/rebar", "make": func() -> Node3D: return RebarModel.new(), "ground": true})
	for kind: String in MonsterModels.KINDS + MonsterModels.DESIGN_KINDS:
		out.append({"name": "monster/" + kind, "make": MonsterModels.make.bind(kind), "ground": true})
	# the Pavise Crossbowman look (lab only, docs/design/pavise-read-test.md): both crossbow carry styles in every shield
	# state, reloading, and planted with arrows stuck in it
	for c: String in PaviseModel.CARRY_STYLES:
		for st: String in PaviseModel.STATES:
			out.append({"name": "pavise/%s/%s" % [c, st], "make": _pavise.bind(c, st, 1.0 if st == "planted" else 0.0, false), "ground": true})
		out.append({"name": "pavise/%s/reloading" % c, "make": _pavise.bind(c, "planted", 0.0, false), "ground": true})
		out.append({"name": "pavise/%s/arrows" % c, "make": _pavise.bind(c, "planted", 1.0, true), "ground": true})
	out.append({"name": "chicken", "make": func() -> Node3D: return ChickenModel.new(), "ground": true})
	for id: String in SpellBook.SPELLS:
		out.append({"name": "component/" + id, "make": ComponentProps.make.bind(id, false), "ground": true})
	for kind: String in POOL_KINDS:
		out.append({"name": "pool/" + kind, "make": PoolProps.build.bind(kind, {}), "ground": false})
	# the sharks (docs/design/sharks.md, lab-only for now): the imp's own seat is checked here without it, the imp against
	# the shark in STACKS (the swarmer model alone is monster/swarmer)
	for v: String in SharkModels.VARIANTS:
		out.append({"name": "shark/" + v, "make": _shark.bind(v), "ground": false})
	# the sewer gator (docs/design/sewer-concept.md, phase 1): every bend, jaws shut and open; it walks on land too
	for bend: float in Gator.BENDS:
		for jaw: float in [0.0, 1.0]:
			out.append({"name": "gator/bend%d/jaw%d" % [roundi(bend), roundi(jaw)], "make": Gator.model_for.bind(bend, jaw), "ground": true})
	# the enemy healer blockouts (docs/design/enemy-healer-options.md, healer_lab only)
	for kind: String in HealerBlockouts.KINDS:
		out.append({"name": "healer/" + kind, "make": HealerBlockouts.build.bind(kind), "ground": true})
	for kind: String in CoolerCarriers.KINDS:
		out.append({"name": "carrier/" + kind, "make": CoolerCarriers.build.bind(kind), "ground": true})
	for fmt: String in NoteCopy.FORMATS:
		out.append({"name": "note/" + fmt, "make": NoteModels.build.bind(fmt, Color(0.5, 0.5, 0.55)), "ground": true})
	return out


## {name, make: Callable -> Array of [item name, Node3D (placed by its own transform)], ground}
static func stacks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# mail: the box on top is the same kind or a small one (SiteBuilder), lifted by height_of(), twisted up to 11 degrees
	for base: String in PackageModels.KINDS:
		var tops: Array[String] = [base]
		if base != "small":
			tops.append("small")
		for top in tops:
			out.append({"name": "package_stack/%s+%s" % [base, top], "make": _stack.bind([base, top], [0.0, 0.0]), "ground": true})
			out.append({"name": "package_stack/%s+%s/twist7" % [base, top], "make": _stack.bind([base, top], [0.0, 7.0]), "ground": true})
		out.append({"name": "package_stack/%s+%s+small" % [base, base], "make": _stack.bind([base, base, "small"], [0.0, 0.0, 0.0]), "ground": true})
	out.append({"name": "van_on_circle", "make": _van_on_circle, "ground": true})
	out.append({"name": "shark_rider", "make": _shark_rider, "ground": false})
	out.append({"name": "summoning_circle_on_rug", "make": _summoning_on_rug, "ground": true})
	return out


# --------------------------------------------------------------------------- builders

static func _door(style: String, w: float, k: float, smashed: bool) -> Node3D:
	var d := OfficeDoorModel.make(style, w, 1.5)
	d.set_open(k, 1.0)
	if smashed:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		d.show_broken(1.0, rng)
	return d


static func _bit(kind: String) -> Node3D:
	var n := PackageModels.bit(kind, 3)
	n.position.y = PackageModels.rest_height(kind)
	return n


static func _van(door: float, lights: float) -> Node3D:
	var v := VanModel.new()
	v.set_door_open(door)
	v.set_lights(lights)
	return v


static func _circle(r: float) -> Node3D:
	var c := VanCircle.new(r)
	c.settle()
	return c


static func _elevator(look: String, form: String, door: float) -> Node3D:
	var e := ElevatorModel.new(look, form)
	e.set_door_open(door)
	return e


static func _stack(kinds: Array, twists: Array) -> Array:
	var items := []
	var lift := 0.0
	for i in kinds.size():
		var box := PackageModels.box(String(kinds[i]), 11 + i * 7)
		var holder := Node3D.new()
		holder.rotation_degrees.y = float(twists[i])
		holder.add_child(box)
		box.position.y = lift
		items.append(["box%d_%s" % [i, kinds[i]], holder])
		lift += PackageModels.height_of(String(kinds[i]))
	return items


## A Pavise Crossbowman look (lab only) with one crossbow carry style, in one shield state at `aim` (planted: 0 =
## reloading, 1 = aiming, locked); `arrows`: 9 stuck in the front.
static func _pavise(carry: String, state: String, aim: float, arrows: bool) -> Node3D:
	var m := PaviseModel.new(carry)
	m.pose_state(state, aim, 0.0, 0.6, aim >= 1.0)
	if arrows:
		m.set_stuck(9)
	return m


## A shark at rest; the imp variant without its rider (the rider is the swarmer model, checked on its own).
static func _shark(variant: String) -> Node3D:
	var s := SharkModels.build(variant)
	var r := s.get_node_or_null("Body/Rider")
	if r != null:
		r.get_parent().remove_child(r)
		r.free()
	return s


## The imp in its saddle against the shark it rides (the Body is at the identity at rest, so the rider's own transform
## places it).
static func _shark_rider() -> Array:
	var s := SharkModels.build("imp")
	var r := s.get_node("Body/Rider") as Node3D
	r.get_parent().remove_child(r)
	return [["shark", s], ["imp", r]]


static func _van_on_circle() -> Array:
	return [["van", _van(1.0, 0.0)], ["circle", _circle(2.9)]]


static func _summoning_on_rug() -> Array:
	var circle := DecorModels.build("summoning_circle", {"radius": 2.1})
	var rug := VanRug.new(2.1 + 0.55)
	rug.set_garage(false)
	return [["summoning_circle", circle], ["rug", rug]]


# --------------------------------------------------------------------------- scanning

## One model on its own (plus the floor when it stands on it). `node` must have been in the tree for a frame (Label3D
## lays out its text deferred).
static func check_model(model_name: String, node: Node3D, ground: bool) -> Array[Dictionary]:
	var ts := ZFightCheck.TriSet.new()
	var it := ts.add_item(model_name)
	ts.add_node(node, it, node.transform)
	if ground:
		ts.add_ground(0.0)
	return _tag(ts.find(false), model_name)


## Placed models: only the fights between two of them (or one of them and the floor).
static func check_items(scene_name: String, items: Array, ground: bool) -> Array[Dictionary]:
	var ts := ZFightCheck.TriSet.new()
	for it: Array in items:
		var n := it[1] as Node3D
		ts.add_node(n, ts.add_item(String(it[0])), n.transform)
	if ground:
		ts.add_ground(0.0)
	return _tag(ts.find(true), scene_name)


static func _tag(found: Array[Dictionary], scene_name: String) -> Array[Dictionary]:
	for f in found:
		f["scene"] = scene_name
	return found


## Every model and stack under `parent` (built, a frame in the tree, checked, freed). `only`: names containing it.
static func scan(parent: Node, only: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var built: Array = []
	for e in models():
		if only != "" and not String(e["name"]).contains(only):
			continue
		var n: Node3D = (e["make"] as Callable).call()
		parent.add_child(n)
		built.append([e, n, null])
	for e in stacks():
		if only != "" and not String(e["name"]).contains(only):
			continue
		var items: Array = (e["make"] as Callable).call()
		var holder := Node3D.new()
		parent.add_child(holder)
		for it: Array in items:
			holder.add_child(it[1])
		built.append([e, holder, items])
	await parent.get_tree().process_frame
	for b: Array in built:
		var e: Dictionary = b[0]
		var t0 := Time.get_ticks_usec()
		if b[2] == null:
			out.append_array(check_model(String(e["name"]), b[1], bool(e["ground"])))
		else:
			out.append_array(check_items(String(e["name"]), b[2], bool(e["ground"])))
		if verbose:
			print("  %-44s %6.1f ms" % [e["name"], float(Time.get_ticks_usec() - t0) / 1000.0])
		(b[1] as Node).queue_free()
	return out


## A generated floor as the game spawns it (SiteBuilder: decor vignettes, priced props, notes, mail stacks) against the
## real terrain mesh (HexMapView: floor tops, wall faces). Only fights between two placed things or a thing and the
## terrain. The floor's monsters, employees and gates move and are checked as models.
static func scan_site(parent: Node, archetype: String, seed_value: int, floor_n: int) -> Array[Dictionary]:
	var run := ContractRun.make(archetype, seed_value, 0.5)
	var map := DungeonGen.generate(run.floor_seed(floor_n))
	var plan := SiteBuilder.plan(map, run, floor_n, PricedProp.catalog(run.site_type))
	var root := Node3D.new()
	root.name = "ZFightSite"
	parent.add_child(root)
	GameWorld.begin(map, root, seed_value)
	var site := SiteBuilder.spawn(map, run, plan)
	var view := HexMapView.new()
	view.name = "Terrain"
	root.add_child(view)
	view.build(map)
	await parent.get_tree().process_frame
	var ts := ZFightCheck.TriSet.new()
	var groups: Array = [site.decor, site.props, site.hazards, site.packages, site.notes, site.beasts]   # (beasts: the monster under each gate room)
	for g: Array in groups:
		for n in g:
			if n is Node3D and is_instance_valid(n):
				var nn := n as Node3D
				ts.add_node(nn, ts.add_item("%s %s" % [nn.name, _xz(nn.global_position)]), nn.global_transform)
	ts.add_node(view, ts.add_item("terrain", true), view.global_transform)
	ts.trim_terrain()
	var found := _tag(ts.find(true), "site/%s#%d/floor%d" % [archetype, seed_value, floor_n])
	GameWorld.end()
	root.queue_free()
	return found


## The menu's garage (MenuBackdrop: the van on its chalk circle, the boxes, the desk, the signs on the walls, the crew)
## against its own terrain. Only fights between two placed things or a thing and the terrain / walls.
static func scan_menu(parent: Node, mood: String = "dawn") -> Array[Dictionary]:
	var bd: Node3D = MenuBackdropScript.new()
	bd.set("mood", mood)
	parent.add_child(bd)
	await parent.get_tree().process_frame
	var ts := ZFightCheck.TriSet.new()
	for c in bd.get_children():
		if not (c is Node3D):
			continue
		var cn := c as Node3D
		if cn.name == "Terrain":
			ts.add_node(cn, ts.add_item("terrain", true), cn.transform)
		elif cn.name == "Mood":
			for m in cn.get_children():
				if m is Node3D:
					ts.add_node(m, ts.add_item("mood/" + String(m.name)), cn.transform * (m as Node3D).transform)
		else:
			ts.add_node(cn, ts.add_item("%s %s" % [cn.name, _xz(cn.position)]), cn.transform)
	ts.trim_terrain()
	var found := _tag(ts.find(true), "menu/" + mood)
	bd.queue_free()
	return found


static func _xz(p: Vector3) -> String:
	return "(%.1f, %.1f)" % [p.x, p.z]
