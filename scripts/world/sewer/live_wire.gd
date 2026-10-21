class_name LiveWire
extends Node3D
## The live wire + water (combat-proposals.md §4.1; docs/design/sewer-concept.md, phase 1). An electrical panel (the priced
## prop "electrical_panel", $250, HP 1: any hit breaks it) hangs on a wall near the water with its cable. When it BREAKS
## (billed to whoever broke it, like any prop) the torn cable swings down into the water (DROP_T, 0.6 s) and shocks
## everyone standing in water within REACH_CELLS (5, user 2026-10-20: "lets just have it distance based") hex cells of
## where it lands: SHOCK_DAMAGE (12, x1.5 on the soaked: a wader is always soaked, 18) and a DAZE_T (0.6 s) daze, both
## sides alike. Then the cable pulses PULSE_DAMAGE (6, x1.5 soaked) every PULSE_EVERY (1.5 s) for PULSE_FOR (6 s) and the
## breaker trips: one use. Dry ground is safe, and so is water farther than REACH_CELLS from the drop. The shock's damage is
## credited to whoever broke the panel (a gator it kills bills them).
##
## Networking (sewer phase 2, "Phase 2 as built"): the panel is a host-arbitrated object; a client's hit on it is a request
## and the host breaks it and bills it once. Its break is `obj.break {id, t, by}` (PricedProp: the moment on the shared clock
## and the culprit), and the drop and the shock are a SCHEDULED EFFECT from that moment (the panel's broke_at): every machine
## runs the cable, the shock and the pulses on its own clock and applies each hit only where it resolves, decided by the
## panel (Combat.hits_in_radius with the panel as the decider: a hero by its owner, everything else by the host, as an
## explosive prop's blast; the daze by the target's owner, Net.resolves). The damage is credited to the breaker on every
## machine. The arcs reach everyone in the water on every screen (the look). A late joiner gets a broken panel by its gone id
## and then its `breaks` row (PricedProp.break_synced): the wire takes the host's moment and skips the shocks already past,
## so a dead wire lies dark in the water and a live one pulses on at the same beats. Nothing else travels.
##
##   var w := LiveWire.attach(panel, drop_point, sewer_view)   # a child of the panel: the fog hides it with the panel

const PropModelsScript := preload("res://scripts/art/lowpoly/props/prop_models.gd")
const SewerProps := preload("res://scripts/art/lowpoly/props/sewer_props.gd")

const DROP_T := 0.6
const REACH_CELLS := 5
const SHOCK_DAMAGE := 12.0
const SOAKED_MULT := 1.5
const DAZE_T := 0.6
const PULSE_DAMAGE := 6.0
const PULSE_EVERY := 1.5
const PULSE_FOR := 6.0
const ARC_LIFE := 0.22
const LINKS := 9
const HANG_END := Vector3(0.15, 0.45, 0.9)   ## the cable's end before the break (model space: PropModels' panel)

var panel: PricedProp = null         ## the panel it hangs from (spawn data)
var drop_point := Vector3.ZERO       ## where the cable lands in the water (spawn data, world)
var drop_cell := Vector2i.ZERO
var broke_at := -1.0                 ## GameWorld.time the panel broke (-1: whole); every machine from the break it sees
var shocks := 0                      ## shocks and pulses fired (tests)
var last_hits: Array[Actor] = []     ## who the last shock or pulse hit (tests, the log)
var view: SewerView = null           ## the water's flash
var _culprit: WeakRef = null
var _links: Array[MeshInstance3D] = []
var _end_glow: MeshInstance3D = null


## Who may write each var (see Net). The panel and the drop point are spawn data; the rest follows from the panel's break
## on every machine (a scheduled effect) or is this screen's look.
func net_fields() -> Dictionary:
	return {
		"panel": Net.SPAWN, "drop_point": Net.SPAWN, "drop_cell": Net.SPAWN,
		"broke_at": Net.LOCAL, "shocks": Net.LOCAL, "last_hits": Net.LOCAL, "_culprit": Net.PRIVATE,
		"view": Net.LOCAL, "_links": Net.LOCAL, "_end_glow": Net.LOCAL,
	}


## The live wire of `p` (an electrical panel), its cable landing at `drop` (world, in the water).
static func attach(p: PricedProp, drop: Vector3, sewer_view: SewerView = null) -> LiveWire:
	var w := LiveWire.new()
	w.name = "LiveWire"
	w.panel = p
	w.drop_point = drop
	w.drop_cell = Hex.from_world(drop)
	w.view = sewer_view
	p.add_child(w)
	p.broken.connect(w._on_broken)
	p.break_synced.connect(w._on_synced)
	return w


## Where a panel standing at `pos` (X/Z) facing `face` drops its cable: the first water along its front within 3.5, else
## the nearest water within 6. Vector3.INF when there is none.
static func drop_point_for(map: HexMap, pos: Vector2, face: Vector2) -> Vector3:
	var f := face.normalized()
	var t := 0.6
	while t <= 3.5:
		var q := pos + f * t
		if map.water_at(Vector3(q.x, 0.0, q.y)):
			var at := q + f * 0.35
			if not map.water_at(Vector3(at.x, 0.0, at.y)):
				at = q
			var y := map.water_surface(Vector3(at.x, 0.0, at.y))
			return Vector3(at.x, (y if not is_nan(y) else 0.0) - HexMap.WATER_DEPTH, at.y)
		t += 0.1
	var best := Vector3.INF
	var best_d := INF
	var here := Hex.from_world(Vector3(pos.x, 0.0, pos.y))
	for c in Hex.range_cells(here, 4):
		var w := Hex.to_world(c)
		if not map.water_at(w):
			continue
		var d := Vector2(w.x, w.z).distance_to(pos)
		if d < best_d:
			best_d = d
			best = Vector3(w.x, float(map.get_cell(c).pool_level) * Hex.LEVEL_HEIGHT, w.z)
	return best


func _ready() -> void:
	_build_cable()
	_pose_cable(0.0)
	set_physics_process(false)


func is_live() -> bool:
	return broke_at >= 0.0 and GameWorld.time - broke_at < DROP_T + PULSE_FOR + 0.05


## The panel broke: the cable drops from the break's moment (the panel's broke_at: on a copy, the host's, from obj.break).
func _on_broken(p: PricedProp, culprit: Node) -> void:
	if broke_at >= 0.0:
		return
	broke_at = p.broke_at if p != null and p.broke_at >= 0.0 else GameWorld.time
	_culprit = weakref(culprit) if culprit != null else null
	set_physics_process(true)
	Sfx.play_at("wire_spark", global_position + Vector3.UP * 1.2)


## A late joiner: the host's break moment and culprit arrived after the panel was shown broken. Run from that moment, and
## count the shocks already past as fired (they hit nobody here: they happened before this machine was on the floor).
func _on_synced(p: PricedProp) -> void:
	broke_at = p.broke_at
	var by := p.last_culprit()
	_culprit = weakref(by) if by != null else null
	shocks = maxi(shocks, due_shocks())
	var live := is_live()
	set_physics_process(live)
	_pose_cable(clampf((GameWorld.time - broke_at) / DROP_T, 0.0, 1.0))


## How many shocks (the first and the pulses) are due by now since the break.
func due_shocks() -> int:
	if broke_at < 0.0:
		return 0
	var t := GameWorld.time - broke_at
	if t < DROP_T:
		return 0
	var due := 1 + int(floorf((t - DROP_T) / PULSE_EVERY + 0.0001))
	return mini(due, 1 + int(floorf(PULSE_FOR / PULSE_EVERY + 0.0001)))


func _physics_process(_delta: float) -> void:
	if broke_at < 0.0:
		return
	var t := GameWorld.time - broke_at
	_pose_cable(clampf(t / DROP_T, 0.0, 1.0))
	if t < DROP_T:
		return
	# the shock when it lands, then a pulse every PULSE_EVERY until PULSE_FOR is up
	var due := due_shocks()
	while shocks < due:
		_shock(shocks == 0)
	if t >= DROP_T + PULSE_FOR + 0.05:
		set_physics_process(false)
		Sfx.play_at("wire_fizzle", drop_point)
		if _end_glow != null:
			_end_glow.visible = false   # the breaker trips: the cable is dead


## Who a shock hits on THIS machine: every body standing in water within REACH_CELLS hex cells of the drop (not props,
## boxes or gates) that this machine resolves, the panel deciding (Combat.hits_in_radius: a hero by its owner, the rest by
## the host). Offline: all of them.
func victims() -> Array[Actor]:
	var out: Array[Actor] = []
	for a in Combat.hits_in_radius(drop_point, float(REACH_CELLS + 1) * Hex.SQRT3, panel):
		if _reaches(a):
			out.append(a)
	return out


## Everyone a shock reaches, whoever resolves them (the arcs on every screen).
func reached() -> Array[Actor]:
	var out: Array[Actor] = []
	for a in GameWorld.actors_in_radius(drop_point, float(REACH_CELLS + 1) * Hex.SQRT3):
		if _reaches(a):
			out.append(a)
	return out


func _reaches(a: Actor) -> bool:
	var map := GameWorld.map
	if map == null or a == null or a.dead:
		return false
	if a is PricedProp or a.is_in_group("breakables") or a is Hellgate or a is DecorBlocker or a.is_airborne():
		return false
	return Hex.distance(a.current_cell(), drop_cell) <= REACH_CELLS and map.water_at(a.global_position)


func _shock(first: bool) -> void:
	shocks += 1
	var src := _culprit.get_ref() as Node if _culprit != null else null
	last_hits = victims()
	var base := SHOCK_DAMAGE if first else PULSE_DAMAGE
	for a in last_hits:
		var soaked := Burning.is_soaked(a) or Wet.is_wet(a) or a.is_in_group("sharks")
		a.apply_damage(base * (SOAKED_MULT if soaked else 1.0), src)
		if first and not a.dead and Net.resolves(a):
			a.daze(DAZE_T, src)
	_shock_fx(first)


# --- the look ---------------------------------------------------------------------------------------------------------

func _build_cable() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.06, 0.06, 0.07)
	m.roughness = 0.6
	for i in LINKS:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.035
		cm.height = 1.0
		cm.radial_segments = 5
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = m
		mi.visible = false
		add_child(mi)
		_links.append(mi)
	_end_glow = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 8
	sm.rings = 4
	_end_glow.mesh = sm
	_end_glow.material_override = Fx.glow_material(Color(1.0, 0.95, 0.6))
	_end_glow.visible = false
	add_child(_end_glow)


## The cable from the box's cable root to its end, `k` of the way from hanging (0) to lying in the water (1). Before the
## break the panel's own model draws its cable, so this one stays hidden.
func _pose_cable(k: float) -> void:
	var shown := broke_at >= 0.0
	for l in _links:
		l.visible = shown
	_end_glow.visible = shown and is_live()
	if not shown:
		return
	var root := PropModelsScript.PANEL_CABLE_ROOT
	var hang := HANG_END
	var land := to_local(drop_point + Vector3.UP * 0.02)
	var e := k * k * (3.0 - 2.0 * k)
	var end := hang.lerp(land, e)
	end.y += sin(e * PI) * 0.4   # it swings out and down
	var sag := lerpf(0.35, 0.12, e)
	var prev := root
	for i in LINKS:
		var t := float(i + 1) / float(LINKS)
		var p := root.lerp(end, t)
		p.y -= sin(t * PI) * sag
		_place_link(_links[i], prev, p)
		prev = p
	_end_glow.position = end
	if shown and k >= 1.0 and is_live():
		var s := 1.0 + 0.35 * sin(GameWorld.time * 40.0)
		_end_glow.scale = Vector3.ONE * s


func _place_link(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.0001:
		mi.visible = false
		return
	var up := d / length
	var axis := Vector3.UP.cross(up)
	var basis := Basis.IDENTITY
	if axis.length() > 0.0001:
		basis = Basis(axis.normalized(), Vector3.UP.angle_to(up))
	elif up.y < 0.0:
		basis = Basis(Vector3.RIGHT, PI)
	mi.transform = Transform3D(basis.scaled(Vector3(1.0, length, 1.0)), (a + b) * 0.5)


## The arcs: from the cable's end to each victim and out across the water round it, a flash of the water, sparks.
func _shock_fx(first: bool) -> void:
	var root := GameWorld.root
	if root == null:
		return
	var y := drop_point.y + HexMap.WATER_DEPTH + 0.05
	var from := Vector3(drop_point.x, y, drop_point.z)
	var targets: Array[Vector3] = []
	for a in reached():
		if is_instance_valid(a):
			targets.append(Vector3(a.global_position.x, a.global_position.y + 0.6, a.global_position.z))
	var map := GameWorld.map
	var reach := float(REACH_CELLS) * Hex.SQRT3 * 0.9
	for i in (6 if first else 3):
		var ang := GameWorld.fx_rng.randf() * TAU
		var r := GameWorld.fx_rng.randf_range(1.5, reach)
		var q := from + Vector3(cos(ang), 0.0, sin(ang)) * r
		if map != null and map.water_at(q) and Hex.distance(Hex.from_world(q), drop_cell) <= REACH_CELLS:
			targets.append(Vector3(q.x, y, q.z))
	for tp in targets:
		var mid := from.lerp(tp, 0.5) + Vector3(0.0, 0.25, 0.0)
		var arc := SewerProps.build("shock", {"points": [Vector3.ZERO, mid - from, tp - from], "seed": GameWorld.fx_rng.randi() % 997})
		root.add_child(arc)
		arc.global_position = from
		get_tree().create_timer(ARC_LIFE).timeout.connect(arc.queue_free)
	var spark: Array[Color] = [Color(1.0, 0.97, 0.6), Color(1.0, 1.0, 1.0), Color(0.7, 0.9, 1.0)]
	Fx.burst(from, spark, 18 if first else 8, 4.5, 0.06, 0.35, 6.0, Vector3.UP, 110.0)
	Fx.ring(from, reach, Color(1.0, 0.95, 0.5, 0.55), 0.3, 0.0, false, 0.15)
	if view != null and is_instance_valid(view):
		view.flash(from, reach, 1.0 if first else 0.6)
	Sfx.play_at("wire_shock", from)
	if first:
		Fx.shake(0.25)
