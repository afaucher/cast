class_name LavaField
extends Node3D
## A lava cave's RULES (docs/design/lava-playtest.md, "As built"): one per floor with a cave (HexMap.cave: a generated cave,
## LavaPlanner, or the `--lava-cave` prototype's LavaCave), on every machine, solo and crewed.
##
## LAVA IS VOID WITH A BITE. activate() takes the cave's lava cells (HexMap.lava) out of the map (HexMap.remove_cell), so the
## game's void rule applies (Actor._enter_void), and Actor knows the lava kind of void: a hero shoved in is pulled back to its
## last safe spot with Actor.LAVA_DAMAGE and Burning (unless soaked), anything else sinks and dies. All of that runs on the
## actor's owner, like any shove. Fog: RoomFog and FogView are built while the lava cells are still in the map (game.gd calls
## activate() after the fog), so the lava keeps the fog space of the rock nearest it.
##
## DAMP CRUST: TERRAIN THAT CHANGES ON A SCHEDULE. Every damp cast (Damp, a scheduled effect: its position, power and the
## shared start time are the same on every machine) is a crust SOURCE from the moment its drizzle lands (start + TELEGRAPH)
## for CRUST_LIFE seconds: the lava cells within CRUST_FRAC of its radius (CaveGen.crust_cells, never one a rim wall cuts).
## A lava cell is crust while any source covering it lasts; it is put back into the map at the cave's crust level (one under
## the cave's rock: walkable from rock at the cave's level, a climb to rock one higher), tagged HexMap.CRUST_TAG. Which cells
## are crust is a pure function of the sources and the shared clock (GameWorld.time), so every machine changes its map at the
## same shared moment with no message; the map's path, movement and wall queries read the cells as they are (no cache but
## the wall faces', which set_cell / remove_cell keep right), and the fog keeps each cell's space from the build.
##   - It looks like cooled rock (LavaLook.crust_material); over its last CRUST_WARN seconds the cracks glow and it shakes.
##   - When cells melt, whoever stands on one loses the ground under it (Actor.lose_ground, a verb): applied by the machine that
##     RESOLVES the actor (Net.resolves), so a client's hero is pulled back by its own machine, a monster sinks on the host.
##   - A late joiner gets the live sources (late_join_state / apply_late_join, the game's part of the join snapshot) and so
##     the same cells.
##
## NOBODY STANDS ON THE LAVA: Actor.move never puts a body over the void, AllyBrain never takes a formation slot across a gap,
## and _rescue_stranded gives the lava rule to anything this machine resolves that is found over a lava cell anyway.
## Cosmetic: a splash where a puppet (another machine's actor) goes into the lava; the owner's own splash is Fx's.
## Sounds (Sfx cues, silent until rendered): "crust_form", "crust_crack", "crust_melt"; Fx plays "lava_sizzle".

const CRUST_LIFE := 8.0
const CRUST_WARN := 2.0
const CRUST_FRAC := 0.9         ## of the damp's radius
const CRUST_TAG := HexMap.CRUST_TAG

var map: HexMap = null
var lava: Dictionary = {}                ## Vector2i -> true: the cave's lava cells (void once active)
var crustable: Dictionary = {}           ## the lava cells a crust may cover (not cut by a rim wall)
var crust_level := -1
var active := false
var crusts: Array[Dictionary] = []       ## the live sources: {x, z, r, born, end, cells: Dictionary}
var _cell_end: Dictionary = {}           ## crust cell -> when it melts
var _looks: Array[Dictionary] = []       ## {end, node, mat, warned}: one slab mesh per melt time
var _seen: Dictionary = {}               ## damp instance id -> true (its source is made)
var _splashed: Dictionary = {}           ## actor instance id -> true (a puppet's splash is drawn)


## Who writes each var (see Net). The lava set is from the seed; the crust follows on every machine from the damp casts and
## the shared clock (a late joiner from the host's sources), so all of it is computed locally.
func net_fields() -> Dictionary:
	return {
		"map": Net.LOCAL, "lava": Net.SPAWN, "crustable": Net.LOCAL, "crust_level": Net.SPAWN, "active": Net.LOCAL,
		"crusts": Net.LOCAL, "_cell_end": Net.LOCAL, "_looks": Net.LOCAL, "_seen": Net.LOCAL, "_splashed": Net.LOCAL,
	}


## Take the cave's map (its lava cells still in it).
func setup(m: HexMap) -> void:
	map = m
	lava = m.lava
	crust_level = int(m.cave.get("crust_level", -1))
	for c: Vector2i in lava:
		var cell: HexMap.Cell = m.get_cell(c)
		if cell == null or cell.wall_mask != 0:
			continue
		var whole := true
		for nn in Hex.neighbors(c):
			whole = whole and m.has_cell(nn)
		if whole:
			crustable[c] = true


## The lava becomes void: from here a shove into it is the lava rule.
func activate() -> void:
	var keys: Array = lava.keys()
	keys.sort_custom(HexMap._cell_less)
	for c: Vector2i in keys:
		map.remove_cell(c)
	active = true


## The field of this floor, or null (the game makes one when the map has a cave).
static func of_world() -> LavaField:
	if GameWorld.root == null:
		return null
	return GameWorld.root.get_node_or_null("LavaField") as LavaField


func _physics_process(_delta: float) -> void:
	if not active or GameWorld.map != map:
		return
	var t := GameWorld.time
	for n in get_tree().get_nodes_in_group(Damp.GROUP):
		var d := n as Damp
		if d == null or _seen.has(d.get_instance_id()) or d.start_time < 0.0 or t < d.start_time + Damp.TELEGRAPH:
			continue
		_seen[d.get_instance_id()] = true
		add_source(d.global_position, DampSpell.damp_radius(d.power) * CRUST_FRAC, d.start_time + Damp.TELEGRAPH)
	_update(t)
	_rescue_stranded()
	_splash_puppets()
	_animate(t)


## A crust source: lava within `radius` of `centre` crusts from `born` for CRUST_LIFE (shared time). The same source twice
## (a cast and a late joiner's row for it) counts once.
func add_source(centre: Vector3, radius: float, born: float) -> void:
	for s in crusts:
		if absf(float(s["born"]) - born) < 0.001 and Vector2(float(s["x"]) - centre.x, float(s["z"]) - centre.z).length() < 0.05:
			return
	var cells := CaveGen.crust_cells(centre, radius, crustable, func(_c: Vector2i) -> bool: return true)
	if cells.is_empty():
		return
	crusts.append({"x": centre.x, "z": centre.z, "r": radius, "born": born, "end": born + CRUST_LIFE, "cells": cells})


## Bring the map in line with the sources at shared time t: crust where a source lasts, lava where none does.
func _update(t: float) -> void:
	var want := {}
	for s in crusts:
		if t < float(s["born"]) or t >= float(s["end"]):
			continue
		for c: Vector2i in (s["cells"] as Dictionary):
			want[c] = maxf(float(want.get(c, 0.0)), float(s["end"]))
	for i in range(crusts.size() - 1, -1, -1):
		if t >= float(crusts[i]["end"]):
			crusts.remove_at(i)
	var changed := false
	var made: Array[Vector2i] = []
	for c: Vector2i in want:
		if not _cell_end.has(c):
			var cell := map.set_cell(c, crust_level)
			cell.tag = CRUST_TAG
			made.append(c)
			changed = true
		elif float(_cell_end[c]) != float(want[c]):
			changed = true
		_cell_end[c] = want[c]
	var melted: Array[Vector2i] = []
	for c: Vector2i in _cell_end.keys():
		if not want.has(c):
			_cell_end.erase(c)
			melted.append(c)
	if melted.is_empty() and not changed:
		return
	if not melted.is_empty():
		var gone := {}
		for c in melted:
			gone[c] = true
		var victims: Array[Actor] = []
		for a in GameWorld.actors():
			if not a.dead and gone.has(Hex.from_world(a.global_position)):
				victims.append(a)
		melted.sort_custom(HexMap._cell_less)
		for c in melted:
			map.remove_cell(c)
		_melt_fx(melted)
		for a in victims:
			if Net.resolves(a):
				a.lose_ground(self)
	if not made.is_empty():
		_form_fx(made)
	_rebuild_looks()


## A safety net: nobody stands on the lava. An actor this machine resolves found over a lava cell (void), not already being
## shoved, pulled back or falling, loses the ground under it (a hero back on rock, anything else sinks).
func _rescue_stranded() -> void:
	for a in GameWorld.actors():
		if a.dead or a.is_shoved() or not Net.resolves(a):
			continue
		var c := Hex.from_world(a.global_position)
		if not lava.has(c) or map.has_cell(c):
			continue
		a.lose_ground(self)


## Cosmetic, on every machine: a splash where another machine's actor (a puppet) goes into the lava. The owner's own is Fx's.
func _splash_puppets() -> void:
	for a in GameWorld.actors():
		if Net.resolves(a) or not is_instance_valid(a):
			continue
		var id := a.get_instance_id()
		var c := Hex.from_world(a.global_position)
		var over := lava.has(c) and not map.has_cell(c)
		if over and not _splashed.has(id):
			_splashed[id] = true
			_splash(Vector3(a.global_position.x, float(map.cave.get("lava_y", -1.0)), a.global_position.z))
		elif not over:
			_splashed.erase(id)


func _splash(at: Vector3) -> void:
	var hot: Array[Color] = [LavaLook.HOT, LavaLook.CORE, Color(1.0, 0.25, 0.05)]
	Fx.burst(at + Vector3.UP * 0.1, hot, 22, 4.0, 0.14, 0.8, 7.0, Vector3.UP, 55.0, true)
	Sfx.play_at("lava_sizzle", at)


# --- the look -------------------------------------------------------------------------------------------------------

func _form_fx(cells: Array[Vector2i]) -> void:
	var steam: Array[Color] = [Color(0.92, 0.94, 0.96), Color(0.6, 0.6, 0.62)]
	var y := float(map.cave.get("lava_y", -1.0))
	var sum := Vector3.ZERO
	for c in cells:
		sum += Hex.to_world(c)
		if posmod(hash(c), 3) == 0:
			Fx.burst(Hex.to_world(c) + Vector3(0, y + 0.6, 0), steam, 6, 1.2, 0.25, 1.2, -1.0, Vector3.UP, 40.0, false)
	Sfx.play_at("crust_form", sum / float(cells.size()) + Vector3(0, y, 0))


func _melt_fx(cells: Array[Vector2i]) -> void:
	var hot: Array[Color] = [LavaLook.HOT, LavaLook.CORE]
	var y := float(map.cave.get("lava_y", -1.0))
	var sum := Vector3.ZERO
	for c in cells:
		sum += Hex.to_world(c)
		if posmod(hash(c), 2) == 0:
			Fx.burst(Hex.to_world(c) + Vector3(0, y + 0.2, 0), hot, 5, 2.0, 0.12, 0.6, 6.0, Vector3.UP, 50.0, true)
	Sfx.play_at("crust_melt", sum / float(cells.size()) + Vector3(0, y, 0))


## One slab mesh per melt time over the crust cells (rebuilt when the crust changes: a cast, a melt).
func _rebuild_looks() -> void:
	for lk in _looks:
		(lk["node"] as Node3D).queue_free()
	_looks.clear()
	var by_end := {}
	for c: Vector2i in _cell_end:
		var e := float(_cell_end[c])
		if not by_end.has(e):
			by_end[e] = [] as Array[Vector2i]
		(by_end[e] as Array[Vector2i]).append(c)
	var ends: Array = by_end.keys()
	ends.sort()
	for e: float in ends:
		var cells: Array[Vector2i] = by_end[e]
		cells.sort_custom(HexMap._cell_less)
		var node := Node3D.new()
		node.name = "Crust"
		add_child(node)
		var mat := LavaLook.crust_material()   # (dark cooled rock; its cracks glow again as it is about to melt)
		node.add_child(_crust_mesh(cells, mat))
		var mid := Vector3.ZERO
		for c in cells:
			mid += Hex.to_world(c, float(crust_level))
		_looks.append({"end": e, "node": node, "mat": mat, "warned": false, "at": mid / float(cells.size())})


func _animate(t: float) -> void:
	for lk in _looks:
		var left := float(lk["end"]) - t
		var warn := clampf(1.0 - left / CRUST_WARN, 0.0, 1.0)
		(lk["mat"] as ShaderMaterial).set_shader_parameter("flicker", warn)
		var node := lk["node"] as Node3D
		node.position = Vector3(sin(t * 47.0), 0.0, cos(t * 53.0)) * 0.025 * warn if warn > 0.0 else Vector3.ZERO
		if warn > 0.0 and not bool(lk["warned"]):
			lk["warned"] = true
			Sfx.play_at("crust_crack", lk["at"])


## A slab of crust over each cell: a dark top at the crust's height and sides down into the lava.
func _crust_mesh(cells: Array[Vector2i], mat: ShaderMaterial) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := float(crust_level) * Hex.LEVEL_HEIGHT
	var bot := float(map.cave.get("lava_y", -1.0)) - 0.15
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


# --- late join --------------------------------------------------------------------------------------------------------

## Host: the live crust sources for a late joiner's snapshot (the game sends them with its part): [[x, z, r, born], ...].
func late_join_state() -> Array:
	var out: Array = []
	for s in crusts:
		if float(s["end"]) > GameWorld.time:
			out.append([float(s["x"]), float(s["z"]), float(s["r"]), float(s["born"])])
	return out


## The late joiner: the host's sources; the crust comes from them as on every other machine.
func apply_late_join(rows: Array) -> void:
	for row: Variant in rows:
		var r := row as Array
		if r != null and r.size() >= 4:
			add_source(Vector3(float(r[0]), 0.0, float(r[1])), float(r[2]), float(r[3]))
