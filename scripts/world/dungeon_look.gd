class_name DungeonLook
extends RefCounted
## The dungeon's lighting mood: a warm luxury bunker. A dark warm background instead of a
## void, dim cool-ish ambient so the slate stays slate, a warm key light, a faint cool fill
## for the other cliff faces, bloom on the amber seams, and (when given the map) a handful of
## warm OmniLight "downlights" hanging over the rooms that make soft pools of light.
##
## Usage: DungeonLook.apply(self, map)   (map is optional; without it there are no pools)

const BACKGROUND := Color(0.075, 0.052, 0.042)
const WARM := Color(1.0, 0.72, 0.42)
const MAX_POOLS := 12
const POOL_HEIGHT := 3.4          ## world units above the room's base floor


static func apply(parent: Node3D, map: HexMap = null) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.50, 0.50, 0.60)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 5.0
	# Bloom on the amber seams: they are emissive HDR (> 1), everything else is below the threshold.
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.name = "LookEnvironment"
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 0.9
	sun.light_color = Color(1.0, 0.86, 0.68)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	parent.add_child(sun)

	# Faint cool fill from the other side so the second set of cliff faces is not a flat black.
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(-35, 150, 0)
	fill.light_energy = 0.22
	fill.light_color = Color(0.55, 0.65, 0.95)
	fill.shadow_enabled = false
	parent.add_child(fill)

	if map != null:
		add_pools(parent, map)


## Warm downlight pools over rooms (+ a coloured light on start / exit). Returns the holder node.
static func add_pools(parent: Node3D, map: HexMap) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Downlights"
	parent.add_child(holder)

	var rooms := {}   ## tag -> Array[Vector2i]
	for c in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type == HexMap.Tile.WALL or not cell.tag.begins_with("room:"):
			continue
		if not rooms.has(cell.tag):
			rooms[cell.tag] = [] as Array[Vector2i]
		var list: Array[Vector2i] = rooms[cell.tag]
		list.append(c)

	var spots: Array = []   ## [Vector3 position, float energy, float range]
	for tag in rooms:
		var cells: Array[Vector2i] = rooms[tag]
		if cells.size() < 4:
			continue
		var base := _mode_level(map, cells)
		var want := clampi(cells.size() / 40 + 1, 1, 3)
		for c: Vector2i in _spread(cells, want):
			spots.append([Hex.to_world(c, base) + Vector3(0, POOL_HEIGHT, 0), 11.0, 9.5])
	while spots.size() > MAX_POOLS:
		spots.pop_back()
	for s in spots:
		var l := OmniLight3D.new()
		l.position = s[0]
		l.light_color = WARM
		l.light_energy = float(s[1])
		l.omni_range = float(s[2])
		l.omni_attenuation = 1.8
		l.light_specular = 0.2
		l.shadow_enabled = false
		holder.add_child(l)

	if map.elevator.is_empty():   # (no start light: the start hex is unmarked, user 2026-10-21)
		_marker_light(map, holder, "exit", HexMapView.EXIT_COLOR)   # (an elevator lights its own car and sill instead)
	return holder


static func _marker_light(map: HexMap, holder: Node3D, tag: String, col: Color) -> void:
	var cs := map.cells_with_tag(tag)
	if cs.is_empty():
		return
	var cell: HexMap.Cell = map.get_cell(cs[0])
	var l := OmniLight3D.new()
	l.position = Hex.to_world(cs[0], cell.level) + Vector3(0, 1.6, 0)
	l.light_color = col
	l.light_energy = 1.2
	l.omni_range = 4.5
	l.light_specular = 0.0
	l.shadow_enabled = false
	holder.add_child(l)


static func _mode_level(map: HexMap, cells: Array[Vector2i]) -> int:
	var counts := {}
	for c in cells:
		var lv: int = map.cells[c].level
		counts[lv] = int(counts.get(lv, 0)) + 1
	var best_n := -1
	var best := 0
	for lv in counts:
		var n: int = counts[lv]
		if n > best_n or (n == best_n and int(lv) < best):
			best_n = n
			best = int(lv)
	return best


## `count` cells spread through the room: the one nearest the centroid, then farthest-point picks.
static func _spread(cells: Array[Vector2i], count: int) -> Array[Vector2i]:
	var sum := Vector2.ZERO
	for c in cells:
		sum += Vector2(c)
	var mean := sum / cells.size()
	var first := cells[0]
	for c in cells:
		if Vector2(c).distance_to(mean) < Vector2(first).distance_to(mean):
			first = c
	var out: Array[Vector2i] = [first]
	while out.size() < count:
		var best := cells[0]
		var best_d := -1
		for c in cells:
			var d := 1 << 20
			for o in out:
				d = mini(d, Hex.distance(c, o))
			if d > best_d:
				best_d = d
				best = c
		if best_d < 4:
			break
		out.append(best)
	return out
