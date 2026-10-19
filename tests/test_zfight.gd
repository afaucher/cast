extends TestCase
## No model z-fights (ZFightCheck over every builder in ZFightModels, the menu garage and a generated floor): two visible
## faces that are coplanar, face the same way and overlap flicker as the camera moves. A finding counts when its shown
## severity (overlap area, weighted down for faces of one paint and for faces that only slant through each other, times
## the share a camera can see) is at least SEVERE_CM2. The full ranked report: tools/zfight_scan.tscn.
##
## ALLOW: known offenders, each with a reason and a budget (the sum of its findings' shown cm2). A listed model that
## gets worse fails, and so does an entry nothing needs any more (remove it). Adding one is a design decision: report it.

## One pixel at the game's default zoom (CameraRig size 24 over 1080 lines: 2.2 cm a pixel, 4.9 cm2).
const SEVERE_CM2 := 5.0
const SLACK := 1.1

## Model name prefix (ZFightModels names) -> [budget cm2, reason]. The longest matching prefix applies.
const ALLOW := {
	# The elevator is stacked slabs: the jambs' and the shaft's faces overlap flush (STEEL_DK on STEEL, MARBLE_K on WOOD)
	# over square metres. In game it stands in a notch of the hex wall, which hides part of it. Separating the layers is
	# an art pass on elevator_model.gd: pending the user's decision.
	"elevator/service_wall/": [23308.0, "jamb and shaft slabs flush (pending decision)"],
	"elevator/fancy_wall/": [5651.0, "jamb and shaft slabs flush (pending decision)"],
	"elevator/service_column/": [369.0, "roof frame bars flush, one paint (pending decision)"],
	"elevator/fancy_column/": [208.0, "roof trim rings flush, one paint (pending decision)"],
	# The lobby props are lab-only (elevator_lab); the game does not place them.
	"lobby/fancy/keep_clear": [624.0, "lab-only: the stripes of the KEEP CLEAR box overlap on the floor"],
	"lobby/service/keep_clear": [624.0, "lab-only: the stripes of the KEEP CLEAR box overlap on the floor"],
	"lobby/fancy/directory": [180.0, "lab-only: the header bar flush with the board's back"],
	"lobby/service/directory": [180.0, "lab-only: the header bar flush with the board's back"],
	"lobby/fancy/service_sign": [31.0, "lab-only: two Label3D lines overlap"],
	"lobby/service/service_sign": [31.0, "lab-only: two Label3D lines overlap"],
	# Same paint, emissive: the crack bars cross on the floor; a flicker between two equal glows (pending decision).
	"hellgate": [1019.0, "crack bars overlap, one emissive colour (pending decision)"],
	# Pool room props (PoolView): trim flush with the deck (pending decision).
	"pool/catwalk": [106.0, "the yellow edge strips flush with the deck's ends (pending decision)"],
	"pool/gantry": [56.0, "two beams flush (pending decision)"],
	"pool/valve_wheel": [26.0, "the wheel's spokes flush with its rim (pending decision)"],
	# Decor and priced props left for the user (small, exact-coplanar trim pieces).
	"decor/summoning_circle": [91.0, "chalk strokes overlap at the star's points, one colour"],
	"decor/neon_sign": [40.0, "the backing's rail flush with the board (pending decision)"],
	"decor/weight_bench": [30.0, "pad and frame flush (pending decision)"],
	"decor/pool_lounger": [19.0, "slats flush with the frame (pending decision)"],
	"decor/yoga_mat": [6.0, "the mat's stripe flush with the mat (pending decision)"],
	"prop/shark_tank": [62.0, "the fin decal flush with the front glass; the lid bars flush, one paint (pending decision)"],
	"prop/projector": [64.0, "the lens hood flush with the body (pending decision)"],
	# Monsters and heroes are being reworked in other branches: their owners take these.
	"monster/archer": [90.0, "quiver slabs overlap (monsters' owner)"],
	"monster/swarmer": [35.0, "head slab flush with a limb (monsters' owner)"],
	"hero/wick": [44.0, "jacket trim and quiver arrows overlap (heroes' owner)"],
	# The dark bottom band slants through the dented box sides: a still seam, no flicker on the GPU (tools/zfight_shots).
	"package/": [12.0, "bottom band through the dented sides (a still seam)"],
}


func setup() -> void:
	timeout_sec = 180.0
	var t0 := Time.get_ticks_msec()
	_self_test()
	ZFightCheck.visibility_floor_cm2 = SEVERE_CM2     # smaller ones can never count: skip their rays
	var found: Array[Dictionary] = []
	found.append_array(await ZFightModels.scan(self))
	var t_models := Time.get_ticks_msec() - t0
	found.append_array(await ZFightModels.scan_menu(self, "dawn"))
	found.append_array(await ZFightModels.scan_site(self, "prepper", 38, 1))
	ZFightCheck.visibility_floor_cm2 = 0.0
	print("zfight: models and stacks %d ms, with the menu and a floor %d ms" % [t_models, Time.get_ticks_msec() - t0])
	var per_scene := {}
	for f in found:
		if float(f["shown_cm2"]) < SEVERE_CM2:
			continue
		var sc := String(f["scene"])
		if not per_scene.has(sc):
			per_scene[sc] = []
		(per_scene[sc] as Array).append(f)
	# the scenes the user named must be clean: the van and both kinds of box stack
	for named: String in ["van", "decor/crate_stack", "package_stack/"]:
		for sc: String in per_scene:
			check(not sc.begins_with(named), "%s z-fights: %s" % [sc, _lines(per_scene[sc])])
	var used := {}
	var totals := {}
	for sc: String in per_scene:
		var key := _allow_key(sc)
		var total := 0.0
		for f: Dictionary in per_scene[sc]:
			total += float(f["shown_cm2"])
		if key == "":
			check(false, "%s z-fights (%.1f cm2 shown):\n%s" % [sc, total, _lines(per_scene[sc])])
			continue
		used[key] = true
		totals[key] = maxf(float(totals.get(key, 0.0)), total)
		var budget := float(ALLOW[key][0])
		check(total <= budget * SLACK + 0.5, "%s z-fights more than its allowance (%.1f > %.1f cm2, %s):\n%s" % [
				sc, total, budget, ALLOW[key][1], _lines(per_scene[sc])])
	for key: String in ALLOW:
		check(used.has(key), "allowlist entry '%s' matches nothing any more: remove it (%s)" % [key, ALLOW[key][1]])
	print("zfight: %d findings, %d scenes over %.1f cm2 (all allowlisted: %s), %d ms" % [found.size(), per_scene.size(),
			SEVERE_CM2, str(totals), Time.get_ticks_msec() - t0])
	finish()


func _allow_key(scene_name: String) -> String:
	var best := ""
	for key: String in ALLOW:
		if scene_name.begins_with(key) and key.length() > best.length():
			best = key
	return best


func _lines(list: Array) -> String:
	var out := PackedStringArray()
	for f: Dictionary in list:
		out.append("   " + ZFightCheck.describe(f))
	out.append("   (the code behind each piece: tools/zfight_scan.tscn --only <name>)")
	return "\n".join(out)


## The detector itself, on hand-made cases: flush faces of two colours fight, 2 mm apart they do not, back to back
## they do not, one paint is weighted down, and a fight sealed inside a box is hidden.
func _self_test() -> void:
	var cases := {
		"flush": [_plate_on_box(0.0, Color(0.9, 0.7, 0.2)), true],
		"2mm": [_plate_on_box(0.002, Color(0.9, 0.7, 0.2)), false],
		"back_to_back": [_plate_on_box(-0.05, Color(0.9, 0.7, 0.2)), false],
	}
	for case_name: String in cases:
		var node: Node3D = cases[case_name][0]
		var ts := ZFightCheck.TriSet.new()
		ts.add_node(node, ts.add_item(case_name), node.transform)
		var worst := 0.0
		for f in ts.find(false):
			worst = maxf(worst, float(f["shown_cm2"]))
		if bool(cases[case_name][1]):
			check(worst >= 100.0, "self-test %s: a flush 0.36 m plate should fight (%.1f cm2)" % [case_name, worst])
		else:
			check(worst < SEVERE_CM2, "self-test %s: should not fight (%.1f cm2)" % [case_name, worst])
		node.free()
	# one paint: found, flagged same look, weighted down
	var same := _plate_on_box(0.0, Color(0.25, 0.3, 0.6))
	var ts2 := ZFightCheck.TriSet.new()
	ts2.add_node(same, ts2.add_item("same"), same.transform)
	var found2 := ts2.find(false)
	check(not found2.is_empty() and bool(found2[0]["same_look"]), "self-test: one paint is found and marked same look")
	same.free()
	# sealed: the same flush pair inside a closed box, which hides it from every camera direction
	var sealed := _plate_on_box(0.0, Color(0.9, 0.7, 0.2))
	var shell := MeshInstance3D.new()
	shell.mesh = LowPoly.box(Vector3(0.7, 0.4, 0.7), Color(0.4, 0.4, 0.4), 5, 0.0, 1, 0.0).to_mesh()
	shell.position = Vector3(0, 0.15, 0)
	sealed.add_child(shell)
	var ts3 := ZFightCheck.TriSet.new()
	ts3.add_node(sealed, ts3.add_item("sealed"), sealed.transform)
	var found3 := ts3.find(false)
	check(not found3.is_empty() and float(found3[0]["visible"]) == 0.0 and float(found3[0]["shown_cm2"]) < SEVERE_CM2,
			"self-test: a flush pair no camera can see is found but not counted")
	sealed.free()


## A 0.5 box (top at y 0.3) and a 0.36 plate whose top is `gap` above the box's top (negative: the plate sits on it).
static func _plate_on_box(gap: float, plate: Color) -> Node3D:
	var s := LowPoly.Soup.new(3, 0.0)
	s.merge(LowPoly.box(Vector3(0.5, 0.3, 0.5), Color(0.25, 0.3, 0.6)), LowPoly.at(Vector3(0, 0.15, 0)))
	if gap >= 0.0:
		s.merge(LowPoly.box(Vector3(0.36, 0.05, 0.36), plate), LowPoly.at(Vector3(0, 0.3 + gap - 0.025, 0)))
	else:
		s.merge(LowPoly.box(Vector3(0.36, 0.05, 0.36), plate), LowPoly.at(Vector3(0, 0.3 + 0.025, 0)))
	var mi := MeshInstance3D.new()
	mi.mesh = s.to_mesh()
	mi.material_override = PropModels.material()
	var root := Node3D.new()
	root.add_child(mi)
	return root
