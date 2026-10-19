class_name DazeFx
extends RefCounted
## The look of a daze (the brute's direct slam, Actor.daze). Cosmetic only: every screen plays it from the hero's daze
## modifier (the owner's, or the one NetStatus announced), so nothing here travels or decides anything.
##
##   DazeFx.stars(top)            # a ring of little yellow stars to hang over a head at height `top`; the hero spins it
##   DazeFx.spin(stars, t)        # turn and bob the ring at time t
##   DazeFx.callout(actor, top)   # the "*bonk*" word and a few sparks over the head, once, when the daze lands
##
## The hero's model sways while the stars spin (Hero._process).

const STAR_COLOR := Color(1.0, 0.86, 0.25)
const CALLOUT_COLOR := Color(1.0, 0.82, 0.3)
const STAR_COUNT := 3
const RING_RADIUS := 0.45
const STAR_SIZE := 0.2            ## outer radius of one star (readable at the default zoom)
const SPIN_RATE := 7.0            ## radians per second
const CALLOUT := "*bonk*"

static var _star_mesh: ArrayMesh = null
static var _star_mat: StandardMaterial3D = null


## A Node3D named "DazeStars" holding STAR_COUNT billboard stars around a ring, `top` above the parent's origin.
static func stars(top: float) -> Node3D:
	var root := Node3D.new()
	root.name = "DazeStars"
	root.position = Vector3(0, top + 0.05, 0)   # round the crown, under the HP bar (top + 0.4)
	for i in STAR_COUNT:
		var a := TAU * float(i) / float(STAR_COUNT)
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh()
		mi.material_override = _material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(cos(a), 0.0, sin(a)) * RING_RADIUS
		mi.set_meta("no_flash", true)
		root.add_child(mi)
	return root


## Turn the ring and bob each star a little (`t` is GameWorld.time).
static func spin(ring: Node3D, t: float) -> void:
	if ring == null:
		return
	ring.rotation.y = t * SPIN_RATE
	var i := 0
	for c in ring.get_children():
		var n := c as Node3D
		if n != null:
			n.position.y = 0.05 * sin(t * 9.0 + float(i) * 2.1)
		i += 1


## The callout as the daze lands: "*bonk*" rising off the head, and a small spray of star-coloured sparks.
static func callout(actor: Node3D, top: float) -> void:
	if actor == null or not actor.is_inside_tree():
		return
	var head := actor.global_position + Vector3(0, top + 0.5, 0)
	Fx.number(head, CALLOUT, CALLOUT_COLOR, 0.8)
	var sparks: Array[Color] = [STAR_COLOR, Color(1.0, 1.0, 0.85)]
	Fx.burst(head - Vector3(0, 0.3, 0), sparks, 10, 2.2, 0.06, 0.4, 3.0, Vector3.UP, 110.0)


## A flat five-point star in the XY plane (the material billboards it).
static func _mesh() -> ArrayMesh:
	if _star_mesh != null:
		return _star_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for k in 10:
		var a := PI * 0.5 + TAU * float(k) / 10.0
		var r := STAR_SIZE if k % 2 == 0 else STAR_SIZE * 0.45
		pts.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
	for k in 10:
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(pts[k])
		st.add_vertex(pts[(k + 1) % 10])
	_star_mesh = st.commit()
	return _star_mesh


static func _material() -> StandardMaterial3D:
	if _star_mat != null:
		return _star_mat
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.render_priority = 10
	m.albedo_color = STAR_COLOR
	_star_mat = m
	return m
