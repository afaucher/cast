extends TestCase
## Props fit where they stand (PropFitCheck over every model of ZFightModels and the menu garage; the user's 2026-10-21 prop
## pass: "lets audit our library to see if we have more of the same class of error"):
##  - LABELS: every Label3D's lettering lies on a face of its model, inside the face's edges and under nothing (the note
##    sign's NOTICE ran off its board, the wet-floor sign's words sat behind it, the lift's LIFT ran under its trims);
##  - WALL: every wall-placed piece (DECOR / PricedProp "place": "wall") reaches back to its footprint's back, which the wall
##    pose sets against the wall (the electrical panel hung a quarter metre off the wall: "this box on the wall is not on
##    the wall");
##  - ENDS: no rod, post, pipe or cable ends in mid-air unless it is listed here with its reason (the science room's pipe
##    run started and ended in the air; the server rack's cables stuck out stiff).
## The audit with pictures: tools/prop_sheet.tscn (every model, game angle and side), tools/site_walls.tscn (wall pieces on
## generated floors).

## Labels: model name prefix -> reason. Nothing else may have lettering off its face.
const LABEL_ALLOW := {
	"door/service/smashed": "the wreck: the torn-off leaves lie on each other, one leaf's stencil under the other",
}
## Wall pieces whose back is NOT at the footprint's back on purpose: kind -> reason.
const WALL_ALLOW := {
	"outfall": "SewerPlanner places it at a channel's end with its own offset (the pipe's mouth on the wall), not by a wall pose",
}
## Free ends that are meant: model name -> [how many, reason].
const ENDS_ALLOW := {
	"decor/bunk_bed": [1, "the ladder's rail tops stand free above the top bunk, as a bunk ladder's do"],
	"prop/gas_cylinders": [2, "the rack's two uprights end at their tops"],
	"decor/specimen_tank": [1, "the specimen vat (another agent's rework, 2026-10-21): reported, not changed here"],
	"prop/specimen_vat": [1, "the specimen vat (another agent's rework, 2026-10-21): reported, not changed here"],
	"van/closed": [5, "the mirror arms and the roof-rack rails' open ends"],
	"van/open_lit": [5, "the mirror arms and the roof-rack rails' open ends"],
	"elevator/service_wall/closed": [2, "the lamp cage's wires end at the bulb"],
	"elevator/service_wall/open": [2, "the lamp cage's wires end at the bulb"],
	"note/memo": [4, "the typed lines lie on the tilted memo"],
}
## Families the ends check covers (the props, set dressing and set pieces; not the creatures, the water's rings or the fx).
const ENDS_FAMILIES: Array[String] = ["decor/", "prop/", "pool/", "note/", "van/", "elevator/", "lobby/", "door/"]
const ENDS_SKIP: Array[String] = ["pool/eel", "pool/jellyfish", "pool/shark", "pool/specimen", "pool/ripple", "pool/steam",
		"pool/flames", "decor/shark_fin", "decor/candle"]


func setup() -> void:
	timeout_sec = 240.0
	_self_test()
	var t0 := Time.get_ticks_msec()
	var label_hits := {}
	var end_counts := {}
	for e in ZFightModels.models():
		var nm := String(e["name"])
		var n: Node3D = (e["make"] as Callable).call()
		add_child(n)
		var ground := bool(e["ground"])
		var found := PropFitCheck.labels(nm, n, ground)
		if not found.is_empty():
			var key := _prefix(LABEL_ALLOW, nm)
			if key == "":
				check(false, "lettering off its face:\n   " + "\n   ".join(found))
			else:
				label_hits[key] = true
		if nm.begins_with("decor/") or nm.begins_with("prop/"):
			var kind := nm.get_slice("/", 1)
			var w := PropFitCheck.wall_back(kind, n, nm.begins_with("prop/"))
			if w != "" and not WALL_ALLOW.has(kind):
				check(false, "wall piece off the wall: " + w)
		for fam in ENDS_FAMILIES:
			if nm.begins_with(fam) and not ENDS_SKIP.has(nm):
				var ends := PropFitCheck.free_ends(nm, n, true)
				var allowed: Array = ENDS_ALLOW.get(nm, [0, ""])
				if not ends.is_empty():
					end_counts[nm] = ends.size()
				check(ends.size() <= int(allowed[0]), "parts ending in mid-air (%d, allowed %d: %s):\n   %s" % [ends.size(),
						int(allowed[0]), allowed[1], "\n   ".join(ends)])
				break
		remove_child(n)
		n.free()
	for kind: String in WALL_ALLOW:
		var m := DecorModels.build(kind) if RoomThemeDefs.is_decor(kind) else PropModels.build(kind)
		check(PropFitCheck.wall_back(kind, m, not RoomThemeDefs.is_decor(kind)) != "", "WALL_ALLOW '%s' is not needed any more: remove it" % kind)
		m.free()
	for key: String in LABEL_ALLOW:
		check(label_hits.has(key), "LABEL_ALLOW '%s' matches nothing any more: remove it" % key)
	for nm: String in ENDS_ALLOW:
		check(int(end_counts.get(nm, 0)) == int(ENDS_ALLOW[nm][0]), "ENDS_ALLOW '%s' expects %d free ends, found %d: update it" % [
				nm, int(ENDS_ALLOW[nm][0]), int(end_counts.get(nm, 0))])
	# the menu garage's lettering (paper signs, the corn sign, the invoice) in every mood
	for mood: String in ["dawn", "night", "after"]:
		var bd: Node3D = ZFightModels.MenuBackdropScript.new()
		bd.set("mood", mood)
		add_child(bd)
		await get_tree().process_frame
		var found := PropFitCheck.labels("menu/" + mood, bd, false, false)
		check(found.is_empty(), "menu lettering off its face:\n   " + "\n   ".join(found))
		bd.queue_free()
	print("prop_fit: %d ms" % (Time.get_ticks_msec() - t0))
	finish()


func _prefix(table: Dictionary, nm: String) -> String:
	for key: String in table:
		if nm.begins_with(key):
			return key
	return ""


## The checks themselves on hand-made cases: lettering on a board passes, lettering wider than its board, floating in
## front of it or hidden behind it fails; a box flush with its footprint's back passes, one standing off fails; a rod
## between two boxes passes, one ending in the air fails.
func _self_test() -> void:
	for c: Array in [[0.002, 1.2, true, "on the board"], [0.002, 0.3, false, "wider than the board"],
			[0.12, 1.2, false, "floating in front"], [-0.03, 1.2, false, "behind the board"]]:
		var root := Node3D.new()
		var s := LowPoly.Soup.new(1, 0.0)
		PropModels.box(s, Vector3(float(c[1]), 0.4, 0.05), Vector3(0, 1.0, -0.025), Color(0.5, 0.5, 0.5))
		var mi := MeshInstance3D.new()
		mi.mesh = s.to_mesh()
		root.add_child(mi)
		var l := Label3D.new()
		l.text = "NOTICE"
		l.font_size = 40
		l.pixel_size = 0.004
		l.position = Vector3(0, 1.0, float(c[0]))
		root.add_child(l)
		var found := PropFitCheck.labels("self", root)
		check(found.is_empty() == bool(c[2]), "self-test label %s: %s" % [c[3], str(found)])
		root.free()
	var ink := Label3D.new()
	ink.text = "I"
	ink.font_size = 100
	ink.pixel_size = 0.01
	ink.outline_size = 0
	var r := PropFitCheck.label_ink(ink)
	check(r.size.y > 0.6 and r.size.y < 0.85 and r.size.x < 0.3, "self-test: the ink of an I is about a cap high and narrow (%s)" % r)
	ink.free()
	var ends := Node3D.new()
	var s2 := LowPoly.Soup.new(1, 0.0)
	PropModels.box(s2, Vector3(0.3, 0.3, 0.3), Vector3(0, 0.15, 0), Color(0.5, 0.5, 0.5))
	PropModels.box(s2, Vector3(0.3, 0.3, 0.3), Vector3(1.2, 1.15, 0), Color(0.5, 0.5, 0.5))
	PropModels.rod(s2, Vector3(0, 0.3, 0), Vector3(1.2, 1.0, 0), 0.03, 0.03, 6, Color(0.8, 0.2, 0.2))
	PropModels.rod(s2, Vector3(0, 0.3, 0.1), Vector3(-0.5, 1.2, 0.4), 0.03, 0.03, 6, Color(0.2, 0.8, 0.2))
	var mi2 := MeshInstance3D.new()
	mi2.mesh = s2.to_mesh()
	ends.add_child(mi2)
	var fe := PropFitCheck.free_ends("self", ends)
	check(fe.size() == 1 and fe[0].contains("(-0.5"), "self-test: only the rod into the air has a free end: %s" % str(fe))
	ends.free()
