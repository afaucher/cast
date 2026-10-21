class_name LavaField
extends Node3D
## The lava cave's rules (PROTOTYPE, docs/design/lava-playtest.md): solo play behind the dev flag `--lava-cave`, never
## built online (game.gd only makes one when the run is not shared). It declares its fields like any gameplay class and
## applies every verb only where this machine resolves the actor, so it would not break co-op; but it has no network
## shape of its own yet (the crust is terrain that changes on a schedule: see the doc).
##
## LAVA = VOID WITH A BURN. Once the floor runs, activate() removes the lava cells from the map, so lava is the void-pit
## rule the game already has (Actor._enter_void): walking can't step into it; a shoved HERO is pulled back to the last
## cell it stood on (5 damage) and a shoved MONSTER falls in and dies. LavaField adds the lava's bite to the hero's pull:
## EXTRA_DAMAGE more (15 in all; the user, 2026-10-20: "That mild damage sounds fine") and Burning for BURN_TIME (unless
## soaked: a damp first protects you from the burn, not the damage). Fog: RoomFog and FogView are built while the lava
## cells still exist, so the lava keeps the fog space of the rock nearest it.
##
## DAMP CRUST (the user: "Damping lava sounds hilarious. Yes."): a damp cast's burst crusts every lava cell within
## CRUST_FRAC of its radius. A crust cell is walkable rock at LavaCave.CRUST_LEVEL (one step down from shore rock at 0, a
## climb up to rock at 1, a wall below rock at 2+) for CRUST_LIFE seconds. It looks like dark cooled rock, no glow
## (LavaLook.crust_material; playtest 2026-10-20: "showing the crust as not glowing would read better"); over the last
## CRUST_WARN the glow comes back into its cracks, pulsing, and it shakes; then it melts back to lava. Whoever stands on it
## then gets the lava rule: a hero is pulled back to the nearest rock (and burned), a monster sinks. The damp's own cell
## field is a pure function of its cast (Damp), and so is the crust: the same on every machine from the cast's time.
##
## NOBODY STANDS ON THE LAVA: Actor.move never puts a body over the void, AllyBrain never takes a formation slot across a
## gap and waits at an edge it can't path past, and _rescue_stranded gives the lava rule to anything found over a lava
## cell anyway (a crust gone from under it, say).

const EXTRA_DAMAGE := 10.0      ## on top of the void pull's 5 (Actor.VOID_TICK_DAMAGE): 15
const BURN_TIME := 6.0          ## Burning: 3 HP/s
const CRUST_LIFE := 8.0
const CRUST_WARN := 2.0
const CRUST_FRAC := 0.9         ## of the damp's radius
const CRUST_TAG := "lava_crust"
## The bubbling bed (Sfx "lava_bubble", cosmetic): a 4 s play every BED_EVERY s (jittered), alternating between the lava
## cell nearest the ear and the nearest one at least BED_SPREAD from it, both within BED_REACH. Two emitters at most.
const BED_EVERY := 1.7
const BED_REACH := 14.0
const BED_SPREAD := 4.0

var map: HexMap = null
var lava: Dictionary = {}                ## Vector2i -> true: the cave's lava cells (void once active)
var active := false
var crusts: Array[Dictionary] = []       ## [{cells: Array[Vector2i], end: float, node: Node3D, mat: ShaderMaterial, at: Vector3}]
var _seen: Dictionary = {}               ## damp instance id -> true (its crust is made)
var _hooked: Dictionary = {}             ## actor instance id -> true (its shove_impact is connected)
var _bed_at := 0.0                       ## the bed's next play (GameWorld.time)
var _bed_n := 0                          ## plays so far (which of the two spots is next)


## Who writes each var (see Net). The lava set is from the seed; the crusts follow from the damp casts on every machine.
func net_fields() -> Dictionary:
	return {
		"map": Net.LOCAL, "lava": Net.SPAWN, "active": Net.LOCAL, "crusts": Net.LOCAL, "_seen": Net.LOCAL, "_hooked": Net.LOCAL,
		"_bed_at": Net.LOCAL, "_bed_n": Net.LOCAL,
	}


## Take the cave's map (its lava cells still in it) and listen to every actor's shoves.
func setup(m: HexMap) -> void:
	map = m
	for c in LavaCave.lava_cells(m):
		lava[c] = true
	for a in GameWorld.actors():
		_hook(a)
	if not GameWorld.actor_spawned.is_connected(_hook):
		GameWorld.actor_spawned.connect(_hook)


## The lava becomes void: from here a shove into it is the pit rule.
func activate() -> void:
	for c: Vector2i in lava:
		map.cells.erase(c)
	active = true


func _exit_tree() -> void:
	if GameWorld.actor_spawned.is_connected(_hook):
		GameWorld.actor_spawned.disconnect(_hook)


func _hook(a: Actor) -> void:
	if a == null or _hooked.has(a.get_instance_id()):
		return
	_hooked[a.get_instance_id()] = true
	a.shove_impact.connect(_on_impact.bind(a))


## A shove ended in the lava (the void rule ran): the hero's owner adds the lava's bite; everyone sees the splash.
func _on_impact(kind: String, pos: Vector3, _amount: float, a: Actor) -> void:
	if kind != "void" or not active:
		return
	var at := Vector3(pos.x, LavaCave.LAVA_Y + 0.1, pos.z)
	var hot: Array[Color] = [LavaLook.HOT, LavaLook.CORE, Color(1.0, 0.25, 0.05)]
	Fx.burst(at, hot, 26, 4.5, 0.14, 0.8, 7.0, Vector3.UP, 55.0, true)
	Sfx.play_at("lava_sizzle", at)
	if a.team == GameWorld.TEAM_HEROES and Net.resolves(a) and not a.dead:
		a.apply_damage(EXTRA_DAMAGE, self)
		Burning.ignite(a, self, BURN_TIME)
		Fx.number(a.global_position + Vector3(0, 2.6 + a.radius, 0), "LAVA!", LavaLook.HOT.lightened(0.2), 0.9)


func _physics_process(_delta: float) -> void:
	if not active or GameWorld.map != map:
		return
	var t := GameWorld.time
	for n in get_tree().get_nodes_in_group(Damp.GROUP):
		var d := n as Damp
		if d == null or _seen.has(d.get_instance_id()) or d.start_time < 0.0 or t < d.start_time + Damp.TELEGRAPH:
			continue
		_seen[d.get_instance_id()] = true
		_make_crust(d.global_position, DampSpell.damp_radius(d.power) * CRUST_FRAC, d.start_time + Damp.TELEGRAPH)
	_rescue_stranded()
	_bed(t)
	for cr in crusts.duplicate():
		var left := float(cr["end"]) - t
		var warn := clampf(1.0 - left / CRUST_WARN, 0.0, 1.0)
		if warn > 0.0 and not cr.has("cracking"):
			cr["cracking"] = true
			Sfx.play_at("lava_crack", cr["at"])
		(cr["mat"] as ShaderMaterial).set_shader_parameter("flicker", warn)
		var node := cr["node"] as Node3D
		node.position = Vector3(sin(t * 47.0), 0.0, cos(t * 53.0)) * 0.025 * warn if warn > 0.0 else Vector3.ZERO
		if left <= 0.0:
			_melt(cr)


## A safety net: nobody stands on the lava. An actor over a lava cell (void) that isn't already being shoved, pulled
## back or falling (Actor.move keeps walkers off the void; this catches anything else) gets the lava rule: a hero is
## put back on the nearest rock (and burned), anything else sinks. Each machine moves only what it resolves.
func _rescue_stranded() -> void:
	for a in GameWorld.actors():
		if a.dead or a.is_shoved() or not Net.resolves(a) or a.shove_mult <= 0.0:
			continue
		var c := Hex.from_world(a.global_position)
		if not lava.has(c) or map.has_cell(c):
			continue
		_into_lava(a)


## The bubbling bed (cosmetic, every screen; Sfx "lava_bubble", ducked while the player speaks): every BED_EVERY s a play
## at one of the two lava spots nearest the ear (alternating), none when no lava is within BED_REACH. Looks use fx_rng.
func _bed(t: float) -> void:
	if t < _bed_at or not Sfx.enabled:
		return
	_bed_at = t + BED_EVERY * GameWorld.fx_rng.randf_range(0.85, 1.15)
	var ear := Sfx.ear()
	if ear == Vector3.INF:
		return
	var spots: Array[Vector3] = []
	for _k in 2:
		var best := Vector3.INF
		var best_d := BED_REACH
		for c: Vector2i in lava:
			if map.has_cell(c):
				continue   # (crust)
			var p := Hex.to_world(c)
			var d := GameWorld.flat_distance(p, ear)
			if d < best_d and (spots.is_empty() or GameWorld.flat_distance(p, spots[0]) >= BED_SPREAD):
				best_d = d
				best = p
		if best == Vector3.INF:
			break
		spots.append(Vector3(best.x, LavaCave.LAVA_Y + 0.2, best.z))
	if spots.is_empty():
		return
	_bed_n += 1
	Sfx.play_at("lava_bubble", spots[_bed_n % spots.size()])


## Start the void rule on `a`, standing over the lava: a hero toward the nearest rock (where the pull will land it).
func _into_lava(a: Actor) -> void:
	var dir := Vector3.FORWARD
	if a.team == GameWorld.TEAM_HEROES:
		# PROTOTYPE: the void pull takes a hero back to its last safe cell, which may be a crust that is gone; point it at
		# the nearest rock instead (Actor's own field, written on the hero's owner only).
		var rock := _nearest_rock(a.global_position)
		a._safe_cell = rock
		dir = Hex.to_world(rock) - a.global_position
	a.shove(dir, 0.3, self)   # (the shove steps over the void: Actor._enter_void runs the pit rule)


## Crust every lava cell within `radius` of `centre` (that is not crust already) until `born` + CRUST_LIFE.
func _make_crust(centre: Vector3, radius: float, born: float) -> void:
	var cells: Array[Vector2i] = []
	for c: Vector2i in lava:
		if map.has_cell(c):
			continue   # (crust already)
		if GameWorld.flat_distance(Hex.to_world(c), centre) <= radius:
			cells.append(c)
	if cells.is_empty():
		return
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	for c in cells:
		var cell := map.set_cell(c, LavaCave.CRUST_LEVEL)
		cell.tag = CRUST_TAG
	var node := Node3D.new()
	node.name = "Crust"
	add_child(node)
	var mat := LavaLook.crust_material()   # (dark cooled rock; its cracks glow again as it is about to melt)
	node.add_child(_crust_mesh(cells, mat))
	var at := Vector3(centre.x, LavaCave.LAVA_Y + 0.3, centre.z)
	crusts.append({"cells": cells, "end": born + CRUST_LIFE, "node": node, "mat": mat, "at": at})
	Sfx.play_at("lava_crust", at)
	var steam: Array[Color] = [Color(0.92, 0.94, 0.96), Color(0.6, 0.6, 0.62)]
	for c in cells:
		if posmod(hash(c), 3) == 0:
			Fx.burst(Hex.to_world(c) + Vector3(0, LavaCave.LAVA_Y + 0.6, 0), steam, 6, 1.2, 0.25, 1.2, -1.0, Vector3.UP, 40.0, false)


## The crust melts: its cells go back to lava; whoever stands on one gets the lava rule (a hero is pulled back to the
## nearest rock and burned, a monster sinks). Each machine moves only what it resolves.
func _melt(cr: Dictionary) -> void:
	crusts.erase(cr)
	var cells: Array[Vector2i] = cr["cells"]
	var on := {}
	for c in cells:
		on[c] = true
	var victims: Array[Actor] = []
	for a in GameWorld.actors():
		if not a.dead and on.has(Hex.from_world(a.global_position)):
			victims.append(a)
	for c in cells:
		map.cells.erase(c)
	(cr["node"] as Node3D).queue_free()
	var hot: Array[Color] = [LavaLook.HOT, LavaLook.CORE]
	for c in cells:
		if posmod(hash(c), 2) == 0:
			Fx.burst(Hex.to_world(c) + Vector3(0, LavaCave.LAVA_Y + 0.2, 0), hot, 5, 2.0, 0.12, 0.6, 6.0, Vector3.UP, 50.0, true)
	for a in victims:
		if Net.resolves(a):
			_into_lava(a)


func _nearest_rock(p: Vector3) -> Vector2i:
	var here := Hex.from_world(p)
	for r in range(1, 12):
		var best := HexMap.NO_CELL
		var best_d := INF
		for c in Hex.ring(here, r):
			if map.is_walkable_cell(c) and map.cells[c].tag != CRUST_TAG:
				var d := Hex.to_world(c).distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = c
		if best != HexMap.NO_CELL:
			return best
	return here


## A slab of crust over each cell: a dark top at the crust's height and sides down into the lava.
func _crust_mesh(cells: Array[Vector2i], mat: ShaderMaterial) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := float(LavaCave.CRUST_LEVEL) * Hex.LEVEL_HEIGHT
	var bot := LavaCave.LAVA_Y - 0.15
	for c in cells:
		var w := Hex.to_world(c)
		var top := Vector3(w.x, y, w.z)
		for i in 6:
			var a := top + Hex.corner(i) * 0.97
			var b := top + Hex.corner((i + 1) % 6) * 0.97
			st.set_normal(Vector3.UP)
			st.add_vertex(top)
			st.add_vertex(b)
			st.add_vertex(a)
			var ab := Vector3(a.x, bot, a.z)
			var bb := Vector3(b.x, bot, b.z)
			var n := ((a + b) * 0.5 - top).normalized()
			for v: Vector3 in [a, b, bb, a, bb, ab]:
				st.set_normal(n)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
