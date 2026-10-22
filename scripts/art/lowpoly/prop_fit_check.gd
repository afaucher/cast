class_name PropFitCheck
extends RefCounted
## Fit checks on built models (tests/test_prop_fit.gd; pictures: tools/prop_sheet.tscn, tools/site_walls.tscn). Dev and test only;
## nothing in the game calls it. Three classes of error the user found on 2026-10-21:
##
##  LABELS  a Label3D's lettering must lie ON a face of its model: every glyph's ink (TextServer glyph boxes, plus the
##          outline) has a front face of the model right behind it (within ON_FACE) and nothing in front of it (within
##          PROBE along its normal). Catches lettering that floats off a tilted board, runs off the edge of its panel, sits
##          behind the face or under a trim.
##  WALL    a piece placed against a wall (RoomThemeDefs.DECOR / PricedProp "place": "wall") reaches the wall: the wall pose
##          puts the footprint's back ThemeGeo.GAP off the wall face (ThemeCtx.wall_pose_at), so the model's back (its
##          smallest z) must be at the footprint's back, -depth / 2, within WALL_TOL.
##  ENDS    a thin part (a rod, post or cable: one connected run of triangles, long and narrow) whose end touches no other
##          part and not the floor: a pipe or cable that stops in mid-air. A suspect list: an antenna ends in the air on purpose.
##
##   var ink := PropFitCheck.label_ink(label)              # Rect2 in the label's plane (its local x / y, metres)
##   for f in PropFitCheck.labels("prop/x", model, true): print(f)

const PROBE := 0.3            ## how far in front of a label a face may NOT be (and where the rays start)
const ON_FACE := 0.03         ## the face behind a label: at most this far behind it
const WALL_TOL := 0.08        ## a wall piece's back may stand this far in front of its footprint's back
const END_REACH := 0.03       ## a thin part's end touches something within its radius + this


## The lettering's ink box in the label's own plane (x right, y up, metres; Label3D draws at z = 0): the union of every
## glyph's box as the TextServer renders it, grown by the outline. Empty for an empty label.
static func label_ink(l: Label3D) -> Rect2:
	var boxes := glyph_boxes(l)
	if boxes.is_empty():
		return Rect2()
	var r: Rect2 = boxes[0]
	for b: Rect2 in boxes:
		r = r.merge(b)
	return r


## Every glyph's ink box (label plane, metres), laid out the way Label3D lays its lines out (alignment, offset, line
## spacing, autowrap width), grown by the outline.
static func glyph_boxes(l: Label3D) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var text := l.text.to_upper() if l.uppercase else l.text
	if text.strip_edges() == "":
		return out
	var font: Font = l.font if l.font != null else ThemeDB.fallback_font
	var ts := TextServerManager.get_primary_interface()
	var para := TextParagraph.new()
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF and l.width > 0.0:
		para.width = l.width
		para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	else:
		para.break_flags = TextServer.BREAK_MANDATORY
	para.add_string(text, font, l.font_size)
	var n := para.get_line_count()
	var total := 0.0
	for i in n:
		total += para.get_line_ascent(i) + para.get_line_descent(i)
	total += l.line_spacing * float(maxi(n - 1, 0))
	var y := 0.0
	match l.vertical_alignment:
		VERTICAL_ALIGNMENT_TOP: y = 0.0
		VERTICAL_ALIGNMENT_BOTTOM: y = total
		_: y = total * 0.5
	y += l.offset.y
	var grow := float(l.outline_size)
	for i in n:
		var w := para.get_line_width(i)
		var x := l.offset.x
		match l.horizontal_alignment:
			HORIZONTAL_ALIGNMENT_LEFT: x += 0.0
			HORIZONTAL_ALIGNMENT_RIGHT: x -= w
			_: x -= w * 0.5
		var base := y - para.get_line_ascent(i)
		for g: Dictionary in ts.shaped_text_get_glyphs(para.get_line_rid(i)):
			var fr: RID = g["font_rid"]
			var idx: int = g["index"]
			var adv := float(g["advance"]) * float(g.get("repeat", 1))
			if fr.is_valid() and idx != 0:
				var sz := Vector2i(int(g["font_size"]), 0)
				ts.font_render_glyph(fr, sz, idx)
				var off: Vector2 = ts.font_get_glyph_offset(fr, sz, idx)
				var gs: Vector2 = ts.font_get_glyph_size(fr, sz, idx)
				if gs.x > 0.0 and gs.y > 0.0:
					var go: Vector2 = g["offset"]
					# the TextServer's y runs down from the baseline; the label's runs up
					var p := Vector2(x + go.x + off.x, base - (go.y + off.y + gs.y))
					out.append(Rect2((p - Vector2(grow, grow)) * l.pixel_size, (gs + Vector2(grow, grow) * 2.0) * l.pixel_size))
			x += adv
		y -= para.get_line_ascent(i) + para.get_line_descent(i) + l.line_spacing
	return out


## Lettering findings for every non-billboard Label3D under `root` (the model's own space), against the model's faces
## (and the floor at y = 0 when `ground`). Labels facing down (never seen from above) are skipped. `covered` false: a face
## in front of the lettering is not a finding (a whole scene, where another thing may stand in front of a sign).
static func labels(model_name: String, root: Node3D, ground: bool = false, covered: bool = true) -> Array[String]:
	var out: Array[String] = []
	var found := root.find_children("*", "Label3D", true, false)
	if found.is_empty():
		return out
	var ts := ZFightCheck.TriSet.new()
	ts.add_node(root, ts.add_item(model_name))
	if ground:
		ts.add_ground(0.0)
	for l: Label3D in found:
		if l.billboard != BaseMaterial3D.BILLBOARD_DISABLED or not l.is_visible_in_tree():
			continue
		var xf := _rel(root, l)
		var nrm := xf.basis.z.normalized()
		if nrm.y < -0.3:
			continue
		var boxes := glyph_boxes(l)
		if boxes.is_empty():
			continue
		# only the faces near the lettering can be hit
		var ink := label_ink(l)
		var span := AABB(xf * Vector3(ink.position.x, ink.position.y, 0.0), Vector3.ZERO)
		for p: Vector2 in [Vector2(ink.end.x, ink.position.y), ink.end, Vector2(ink.position.x, ink.end.y)]:
			span = span.expand(xf * Vector3(p.x, p.y, 0.0))
		span = span.grow(PROBE + ON_FACE + 0.05)
		var near := PackedInt32Array()
		for i in ts.count():
			if not (ts.flags[i] & ZFightCheck.F_LABEL) and span.intersects(AABB(ts.pa[i], Vector3.ZERO).expand(ts.pb[i]).expand(ts.pc[i]).grow(0.001)):
				near.append(i)
		var off := 0
		var cover := 0
		var total := 0
		var worst := 0.0
		for b in boxes:
			var inset := b.size * 0.08
			for p: Vector2 in [b.get_center(), b.position + inset, Vector2(b.end.x - inset.x, b.position.y + inset.y),
					b.end - inset, Vector2(b.position.x + inset.x, b.end.y - inset.y)]:
				var q := xf * Vector3(p.x, p.y, 0.0)
				var t := first_hit(ts, q + nrm * PROBE, -nrm, near)
				total += 1
				if t == INF or t > PROBE + ON_FACE:
					off += 1
					worst = maxf(worst, t - PROBE if t != INF else 1.0)
				elif t < PROBE - 0.003 and covered:
					cover += 1
		if off > 0 or cover > 0:
			out.append("%s: \"%s\" (%.2f x %.2f m) %d of %d ink points not on a face%s, %d covered" % [model_name,
					l.text.replace("\n", "|"), ink.size.x * xf.basis.x.length(), ink.size.y * xf.basis.y.length(), off, total,
					" (%.3f behind)" % worst if worst < 1.0 and off > 0 else "", cover])
	return out


## The wall finding for a placed row's model (empty when it is not a wall row or its back reaches the footprint's back).
## `kind`: a DECOR kind or a PricedProp kind (`priced`).
static func wall_back(kind: String, model: Node3D, priced: bool) -> String:
	var depth := 0.0
	if priced:
		var row := PricedProp.placement(kind)
		if str(row.get("place", "")) != "wall":
			return ""
		depth = (row["foot"] as Vector2).y
	else:
		var row := RoomThemeDefs.decor(kind)
		if str(row.get("place", "")) != "wall":
			return ""
		depth = float(row["d"])
	var ts := ZFightCheck.TriSet.new()
	ts.add_node(model, ts.add_item(kind))
	var back := INF
	for i in ts.count():
		if ts.flags[i] & ZFightCheck.F_LABEL:
			continue
		back = minf(back, minf(ts.pa[i].z, minf(ts.pb[i].z, ts.pc[i].z)))
	var gap := back + depth * 0.5
	if gap <= WALL_TOL:
		return ""
	return "%s: its back is %.2f in front of its footprint's back (depth %.2f): it stands %.2f off the wall" % [kind, gap, depth,
			gap + ThemeGeo.GAP]


## Thin parts with an end that touches nothing (see ENDS above): "name: <colour> part, length L, free end at (x, y, z)".
static func free_ends(model_name: String, root: Node3D, ground: bool = true) -> Array[String]:
	var out: Array[String] = []
	# every triangle of every visible mesh, down faces too (ZFightCheck drops those: never seen, but a rod can end on one)
	var pa := PackedVector3Array()
	var pb := PackedVector3Array()
	var pc := PackedVector3Array()
	var cols := PackedColorArray()
	var pieces := {}
	var surf := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var xf := _rel(root, mi)
		for si in mi.mesh.get_surface_count():
			surf += 1
			var arrays := mi.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var vc: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var tcount := (idx.size() if not idx.is_empty() else v.size()) / 3
			# pieces: triangles joined by shared corners (union-find over the corner keys)
			var parent := PackedInt32Array()
			parent.resize(tcount)
			var owner := {}
			var base := pa.size()
			for t in tcount:
				parent[t] = t
				var ids := [t * 3, t * 3 + 1, t * 3 + 2] if idx.is_empty() else [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]]
				var q: Array[Vector3] = [xf * v[ids[0]], xf * v[ids[1]], xf * v[ids[2]]]
				pa.append(q[0])
				pb.append(q[1])
				pc.append(q[2])
				cols.append(Color(vc[ids[0]].r, vc[ids[0]].g, vc[ids[0]].b).linear_to_srgb() if not vc.is_empty() else Color.GRAY)
				for p in q:
					var k := ZFightCheck.TriSet.corner_key(p)
					if owner.has(k):
						var ra := _find(parent, t)
						var rb := _find(parent, int(owner[k]))
						if ra != rb:
							parent[ra] = rb
					else:
						owner[k] = t
			for t in tcount:
				var key := Vector2i(surf, _find(parent, t))
				if not pieces.has(key):
					pieces[key] = []
				(pieces[key] as Array).append(base + t)
	var boxes := {}
	for key in pieces:
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for t: int in pieces[key]:
			for q: Vector3 in [pa[t], pb[t], pc[t]]:
				lo = lo.min(q)
				hi = hi.max(q)
		boxes[key] = AABB(lo, hi - lo)
	for key in pieces:
		var tris: Array = pieces[key]
		var pts: Array[Vector3] = []
		var c := Vector3.ZERO
		for t: int in tris:
			for q: Vector3 in [pa[t], pb[t], pc[t]]:
				pts.append(q)
				c += q
		c /= float(pts.size())
		var a := c
		for q in pts:
			if q.distance_to(c) > a.distance_to(c):
				a = q
		var b := a
		for q in pts:
			if q.distance_to(a) > b.distance_to(a):
				b = q
		var length := a.distance_to(b)
		if length < 0.2:
			continue
		var r := 0.0
		for q in pts:
			r = maxf(r, q.distance_to(Geometry3D.get_closest_point_to_segment_uncapped(q, a, b)))
		if length < 5.0 * r or r > 0.12:
			continue
		var ax := (b - a) / length
		for end: Vector3 in [a, b]:
			var e := Vector3.ZERO
			var n := 0
			for q in pts:
				if absf((q - end).dot(ax)) <= r + 0.005:
					e += q
					n += 1
			e /= float(maxi(n, 1))
			if ground and e.y <= r + 0.04:
				continue
			var reach := r + END_REACH
			var touched := false
			for other in pieces:
				if other == key or not (boxes[other] as AABB).grow(reach).has_point(e):
					continue
				for t: int in pieces[other]:
					if _tri_dist(e, pa[t], pb[t], pc[t]) <= reach:
						touched = true
						break
				if touched:
					break
			if not touched:
				out.append("%s: %s part, length %.2f, free end at (%.2f, %.2f, %.2f)" % [model_name,
						"#" + cols[tris[0]].to_html(false), length, e.x, e.y, e.z])
	return out


## The first front face (not a label) along d from o: its distance, INF when none. `only`: the triangles to try (all
## when empty).
static func first_hit(ts: ZFightCheck.TriSet, o: Vector3, d: Vector3, only: PackedInt32Array = PackedInt32Array()) -> float:
	var best := INF
	var idx := only
	if idx.is_empty():
		idx.resize(ts.count())
		for i in ts.count():
			idx[i] = i
	for i in idx:
		if ts.flags[i] & ZFightCheck.F_LABEL:
			continue
		if ts.nrm[i].dot(d) >= 0.0 and not (ts.flags[i] & ZFightCheck.F_DOUBLE):
			continue
		var hit: Variant = Geometry3D.ray_intersects_triangle(o, d, ts.pa[i], ts.pb[i], ts.pc[i])
		if hit != null:
			best = minf(best, ((hit as Vector3) - o).dot(d))
	return best


## `node`'s transform in `root`'s space (neither needs to be in the tree).
static func _rel(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


static func _tri_dist(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return INF
	n = n.normalized()
	var d := (p - a).dot(n)
	var q := p - n * d
	var c0 := (b - a).cross(q - a).dot(n)
	var c1 := (c - b).cross(q - b).dot(n)
	var c2 := (a - c).cross(q - c).dot(n)
	if (c0 >= 0.0 and c1 >= 0.0 and c2 >= 0.0) or (c0 <= 0.0 and c1 <= 0.0 and c2 <= 0.0):
		return absf(d)
	return minf(p.distance_to(Geometry3D.get_closest_point_to_segment(p, a, b)), minf(
			p.distance_to(Geometry3D.get_closest_point_to_segment(p, b, c)), p.distance_to(Geometry3D.get_closest_point_to_segment(p, c, a))))
