class_name HauntLook
extends RefCounted
## The haunted rooms' look test (docs/design/mansion-rooms.md, docs/design/church-rooms.md): the floor and wall materials
## (parquet, wallpaper over a dado, glazing, limestone) and the two lightings (cold moonlight, candle light).
##
## MATERIALS. The decided ones are the GAME's now (haunted-build-plan.md H1): walnut & damask, the conservatory's terracotta
## and glazing, and the church's limestone are rows of FloorMaterials (FloorMaterials.HIGH, the free slots 24-31) and their
## patterns are in the game's terrain shader (HexMapView.MATERIAL_SHADER), so the mansion and church room themes use them.
## The look test's other set, oak & stripe (not picked), stays lab-only: `tables()` is a COPY of the game's table with its
## two rows added (slots 25 and 28), and `dress_terrain(view)` puts that copy onto a built HexMapView, so a lab map whose
## cells carry these ids draws them all.
##
## LIGHT. `apply_light(root, mode)` relights a scene lit by DungeonLook (its LookEnvironment, KeyLight, FillLight and
## Downlights nodes, found under `root`): "game" puts DungeonLook's values back, "moonlight" is a cold, low key light with
## the warm pools off and every candle out, "candle" is near-dark with the pools off and every candle lit (each candle
## cluster of a haunt prop carries a small warm OmniLight). Live: the gym's "Haunt light" row calls it. (The game's haunted
## rooms keep the game's light; each room's accent light is candle-warm or moon-cold, RoomThemeDefs.)
##
##   HauntLook.dress_terrain(terrain)                     # after terrain.build(map) on a map with HauntLook ids
##   HauntLook.apply_light(self, "candle")

const MODES: Array[String] = ["game", "moonlight", "candle"]
const LIGHTS: Array[String] = ["moonlight", "candle"]
## The gym's current pick (GymDev's "Haunt light" row).
static var light := "game"

const CANDLES_GROUP := "haunt_candles"   ## every haunt prop's "Candles" node (flames and their lights)
const PROPS_GROUP := "haunt_props"       ## every haunt prop's root

# --- materials ---------------------------------------------------------------------------------------------------------
# Wall ids map to shader slot WALL_OFFSET (16) + id; floor ids are their own slot. The test's slots are 24-31.
const W_DAMASK := FloorMaterials.W_DAMASK          ## slot 24: oxblood damask over a walnut dado (set "walnut"; the game's)
const W_STRIPE := 9                                ## slot 25: faded sage stripe over an oak dado (set "oak"; lab only)
const W_LIMESTONE := FloorMaterials.W_LIMESTONE    ## slot 26: pale limestone blocks (the church; the game's)
const F_PARQUET_DARK := FloorMaterials.F_PARQUET   ## slot 27: dark walnut herringbone (set "walnut"; the game's)
const F_PARQUET_PALE := 28                         ## slot 28: pale oak herringbone (set "oak"; lab only)
const F_LIMESTONE := FloorMaterials.F_LIMESTONE    ## slot 29: worn limestone flags (the church; the game's)
const F_TERRACOTTA := FloorMaterials.F_TERRACOTTA  ## slot 30: terracotta tiles (the conservatory; the game's)
const W_GLAZING := FloorMaterials.W_GLAZING        ## slot 31: white iron glazing bars over dark glass (the conservatory; the game's)

## The patterns (the game's terrain shader carries them all, the oak set's stripe too).
const PAT_HERRINGBONE := FloorMaterials.PAT_HERRINGBONE
const PAT_DAMASK := FloorMaterials.PAT_DAMASK
const PAT_STRIPE := FloorMaterials.PAT_STRIPE
const PAT_GLAZING := FloorMaterials.PAT_GLAZING

## The lab-only rows (the oak set), written over a copy of the game's table: slot -> {name, pat, base, alt (sRGB), scale,
## rough, spec}.
const LAB_ROWS := {
	25: {"name": "sage stripe over oak", "pat": PAT_STRIPE, "base": Color(0.42, 0.48, 0.38), "alt": Color(0.70, 0.66, 0.52), "scale": 1.0, "rough": 0.75, "spec": 0.15},
	28: {"name": "oak herringbone", "pat": PAT_HERRINGBONE, "base": Color(0.66, 0.47, 0.28), "alt": Color(0.30, 0.19, 0.10), "scale": 0.13, "rough": 0.5, "spec": 0.3},
}
## Every slot the test draws (24-31): the game's rows (FloorMaterials.HIGH) and the lab's.
static var ROWS: Dictionary = _all_rows()

## The mansion's material sets: the house rooms' floor and wall (the conservatory keeps its own in both).
const SETS := {
	"walnut": {"name": "walnut & damask", "floor": F_PARQUET_DARK, "wall": W_DAMASK},
	"oak": {"name": "oak & stripe", "floor": F_PARQUET_PALE, "wall": W_STRIPE},
}
const SET_NAMES: Array[String] = ["walnut", "oak"]
const CONSERVATORY := {"floor": F_TERRACOTTA, "wall": W_GLAZING}
const CHURCH := {"floor": F_LIMESTONE, "wall": W_LIMESTONE}

static var _shader: Shader
static var _tables: Dictionary = {}


static func _all_rows() -> Dictionary:
	var out := {}
	for slot: int in FloorMaterials.HIGH:
		out[slot] = FloorMaterials.HIGH[slot]
	for slot: int in LAB_ROWS:
		out[slot] = LAB_ROWS[slot]
	return out


static func pack(floor_id: int, wall_id: int) -> int:
	return FloorMaterials.pack(floor_id, wall_id)


## The material name of a slot (a test's floor id, or WALL_OFFSET + a test's wall id).
static func slot_name(slot: int) -> String:
	return str((ROWS.get(slot, {}) as Dictionary).get("name", ""))


static func wall_slot(wall_id: int) -> int:
	return FloorMaterials.WALL_OFFSET + wall_id


## The terrain material shader the lab dresses a view with: the game's own (its patterns are in it now).
static func terrain_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = shader_code()
	return _shader


static func shader_code() -> String:
	return HexMapView.MATERIAL_SHADER


## FloorMaterials' shader tables with the lab-only rows added (linear colour, like table_arrays()).
static func tables() -> Dictionary:
	if not _tables.is_empty():
		return _tables
	var src := FloorMaterials.table_arrays()
	var base: PackedVector4Array = (src["base"] as PackedVector4Array).duplicate()
	var alt: PackedVector4Array = (src["alt"] as PackedVector4Array).duplicate()
	var par: PackedVector4Array = (src["par"] as PackedVector4Array).duplicate()
	for slot: int in LAB_ROWS:
		var d: Dictionary = LAB_ROWS[slot]
		var b: Color = (d["base"] as Color).srgb_to_linear()
		var a: Color = (d["alt"] as Color).srgb_to_linear()
		base[slot] = Vector4(b.r, b.g, b.b, float(int(d["pat"])))
		alt[slot] = Vector4(a.r, a.g, a.b, float(d["scale"]))
		par[slot] = Vector4(float(d["rough"]), float(d["spec"]), 0.0, 0.0)
	_tables = {"base": base, "alt": alt, "par": par}
	return _tables


## Swap the lab's shader and tables onto every material-shader surface of a built HexMapView. Returns how many.
static func dress_terrain(view: HexMapView) -> int:
	if view.mesh_instance == null or view.mesh_instance.mesh == null:
		return 0
	var n := 0
	var mesh := view.mesh_instance.mesh
	var t := tables()
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as ShaderMaterial
		if m == null or m.shader == null or m.shader.code != HexMapView.MATERIAL_SHADER:
			continue
		m.shader = terrain_shader()
		m.set_shader_parameter("m_base", t["base"])
		m.set_shader_parameter("m_alt", t["alt"])
		m.set_shader_parameter("m_par", t["par"])
		n += 1
	return n


# --- light -------------------------------------------------------------------------------------------------------------

## mode -> the environment and the two directional lights. "game" is DungeonLook's own values.
const LOOKS := {
	"game": {"bg": DungeonLook.BACKGROUND, "ambient": Color(0.50, 0.50, 0.60), "ambient_e": 0.55, "exposure": 1.0, "sat": 1.08,
		"key": Color(1.0, 0.86, 0.68), "key_e": 0.9, "key_rot": Vector3(-50, -30, 0), "fill_e": 0.22, "pools": true, "candles": true},
	"moonlight": {"bg": Color(0.02, 0.03, 0.06), "ambient": Color(0.42, 0.54, 0.92), "ambient_e": 0.8, "exposure": 1.15, "sat": 0.8,
		"key": Color(0.66, 0.78, 1.0), "key_e": 1.35, "key_rot": Vector3(-42, -62, 0), "fill_e": 0.14, "pools": false, "candles": false},
	"candle": {"bg": Color(0.035, 0.022, 0.015), "ambient": Color(0.58, 0.52, 0.52), "ambient_e": 0.4, "exposure": 1.0, "sat": 0.95,
		"key": Color(1.0, 0.86, 0.72), "key_e": 0.25, "key_rot": Vector3(-50, -30, 0), "fill_e": 0.06, "pools": false, "candles": true},
}

## A candle cluster's light (one per cluster of flames).
const CANDLE_COLOR := Color(1.0, 0.74, 0.48)
const CANDLE_ENERGY := 2.6
const CANDLE_RANGE := 5.0


## Relight the DungeonLook scene under `root` for `mode` (MODES) and light or snuff every haunt candle in the tree.
## Returns false for an unknown mode.
static func apply_light(root: Node, mode: String) -> bool:
	if not LOOKS.has(mode):
		return false
	var look: Dictionary = LOOKS[mode]
	var we := root.find_child("LookEnvironment", true, false) as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		env.background_color = look["bg"]
		env.ambient_light_color = look["ambient"]
		env.ambient_light_energy = float(look["ambient_e"])
		env.tonemap_exposure = float(look["exposure"])
		env.adjustment_saturation = float(look["sat"])
	var key := root.find_child("KeyLight", true, false) as DirectionalLight3D
	if key != null:
		key.light_color = look["key"]
		key.light_energy = float(look["key_e"])
		key.rotation_degrees = look["key_rot"]
	var fill := root.find_child("FillLight", true, false) as DirectionalLight3D
	if fill != null:
		fill.light_energy = float(look["fill_e"])
	var pools := root.find_child("Downlights", true, false) as Node3D
	if pools != null:
		pools.visible = bool(look["pools"])
	if root.is_inside_tree():
		for c in root.get_tree().get_nodes_in_group(CANDLES_GROUP):
			(c as Node3D).visible = bool(look["candles"])
	else:
		_set_candles(root, bool(look["candles"]))
	return true


static func _set_candles(n: Node, on: bool) -> void:
	if n.is_in_group(CANDLES_GROUP):
		(n as Node3D).visible = on
	for c in n.get_children():
		_set_candles(c, on)


## The gym's "Haunt light" row: remember the pick and relight the running scene.
static func pick(mode: String, root: Node) -> bool:
	if not MODES.has(mode):
		return false
	light = mode
	return apply_light(root, mode)


static func reset() -> void:
	light = "game"
