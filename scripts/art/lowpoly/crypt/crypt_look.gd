class_name CryptLook
extends RefCounted
## LOOK-DEV ONLY (docs/design/crypt-section.md): the crypt section's two material sets and its lighting, for the crypt
## section lab. Nothing in the game uses them: no site, theme, floor generator or FloorMaterials row knows a crypt.
##
## A set restyles a few of FloorMaterials' rows on ONE terrain's materials (a duplicate per surface, as the sewer lab
## does; the shared table is untouched), so the lab's map can paint its crypt with ordinary material ids:
##   F_FLAGSTONE   the crypt's rooms
##   F_CORR_STONE  its halls (the stair down, the ossuary gallery)
##   W_STONE       its walls (rough stone blocks in courses)
##   W_CONCRETE    the church's walls above (pale ashlar; the chapel set only)
##   F_MARBLE      the church's floor above (pale marble; the chapel set only)
## The mansion above keeps the game's rows: its wood boards and panelling.
##
## The lighting (`relight`, after DungeonLook.apply): underground there is no daylight, so the key and fill are all but
## off (their wall shadows would leave the floors darker than the wall caps) and a dim, cool ambient is what is left; the bright parts of the crypt are candle light (CryptProps' lit pieces carry their own
## OmniLight3D), the dark parts are whatever the ambient leaves.

const SETS: Array[String] = ["vault", "chapel"]

## The two sets differ on colour, floor, light and seams, not just a shade of stone (the user, 2026-10-29: "I want both a
## vault and chapel, but they are too similar to eachother"): the vault is warm black-brown wet stone, small rough stones
## underfoot, candle pools in the near dark; the chapel is whitewashed, large pale slabs, a cool brighter ambient and pale
## shafts of light falling from the church above (`shaft`). Both all but drop the hex seams, so a crypt does not read as
## the game's usual grid.
const LOOK := {
	"vault": {
		"title": "vault: under the mansion",
		"above": "mansion",
		"floor": Color(0.30, 0.23, 0.17), "floor_alt": Color(0.06, 0.045, 0.035), "floor_scale": 0.55,
		"hall": Color(0.26, 0.20, 0.15),
		"wall": Color(0.30, 0.23, 0.17), "wall_alt": Color(0.04, 0.03, 0.025),
		"rough": 0.35, "spec": 0.55,
		"seam": 0.08,
		"ambient": Color(0.55, 0.45, 0.38), "ambient_k": 0.32, "key": 0.04, "key_col": Color(0.70, 0.76, 1.0), "fill": 0.03,
		"background": Color(0.02, 0.015, 0.01),
		"shafts": false,
	},
	"chapel": {
		"title": "chapel: under the church",
		"above": "church",
		"floor": Color(0.80, 0.78, 0.72), "floor_alt": Color(0.50, 0.48, 0.44), "floor_scale": 2.8,
		"hall": Color(0.74, 0.72, 0.67),
		"wall": Color(0.88, 0.86, 0.80), "wall_alt": Color(0.58, 0.56, 0.52),
		"rough": 0.9, "spec": 0.1,
		"seam": 0.1,
		"ambient": Color(0.62, 0.68, 0.86), "ambient_k": 0.4, "key": 0.08, "key_col": Color(0.74, 0.78, 1.0), "fill": 0.06,
		"background": Color(0.05, 0.05, 0.06),
		"shafts": true,
		"church_wall": Color(0.70, 0.66, 0.58), "church_wall_alt": Color(0.24, 0.21, 0.18),
		"church_floor": Color(0.80, 0.77, 0.70), "church_floor_alt": Color(0.42, 0.40, 0.40),
	},
}

const SHAFT_COLOR := Color(0.80, 0.88, 1.0)


static func look(set_name: String) -> Dictionary:
	return LOOK.get(set_name, LOOK["vault"])


## The material ids the lab paints with: the crypt's rooms, its halls, the room above.
static func crypt_room_mat() -> int:
	return FloorMaterials.pack(FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)


static func crypt_hall_mat() -> int:
	return FloorMaterials.pack(FloorMaterials.F_CORR_STONE, FloorMaterials.W_STONE)


static func above_mat(set_name: String) -> int:
	if str(look(set_name)["above"]) == "church":
		return FloorMaterials.pack(FloorMaterials.F_MARBLE, FloorMaterials.W_CONCRETE)
	return FloorMaterials.pack(FloorMaterials.F_WOOD, FloorMaterials.W_PANELLING)


## The restyled material tables of a set (base, alt, par; linear colour), FloorMaterials' with the crypt rows changed.
static func tables(set_name: String) -> Dictionary:
	var lk := look(set_name)
	var t := FloorMaterials.table_arrays()
	var base: PackedVector4Array = (t["base"] as PackedVector4Array).duplicate()
	var alt: PackedVector4Array = (t["alt"] as PackedVector4Array).duplicate()
	var par: PackedVector4Array = (t["par"] as PackedVector4Array).duplicate()
	var flag := float(FloorMaterials.Pat.FLAGSTONE)
	var ashlar := float(FloorMaterials.Pat.ASHLAR)
	_row(base, alt, par, FloorMaterials.F_FLAGSTONE, lk["floor"], flag, lk["floor_alt"], float(lk["floor_scale"]), lk)
	_row(base, alt, par, FloorMaterials.F_CORR_STONE, lk["hall"], flag, lk["floor_alt"], float(lk["floor_scale"]), lk)
	_row(base, alt, par, FloorMaterials.WALL_OFFSET + FloorMaterials.W_STONE, lk["wall"], ashlar, lk["wall_alt"], 1.0, lk)
	if lk.has("church_wall"):
		_row(base, alt, par, FloorMaterials.WALL_OFFSET + FloorMaterials.W_CONCRETE, lk["church_wall"], ashlar, lk["church_wall_alt"], 1.0,
				{"rough": 0.8, "spec": 0.12})
	if lk.has("church_floor"):
		_row(base, alt, par, FloorMaterials.F_MARBLE, lk["church_floor"], float(FloorMaterials.Pat.MARBLE), lk["church_floor_alt"], 2.0,
				{"rough": 0.3, "spec": 0.45})
	return {"base": base, "alt": alt, "par": par}


static func _row(base: PackedVector4Array, alt: PackedVector4Array, par: PackedVector4Array, i: int, b: Color, pat: float, a: Color,
		scale: float, lk: Dictionary) -> void:
	var bl := b.srgb_to_linear()
	var al := a.srgb_to_linear()
	base[i] = Vector4(bl.r, bl.g, bl.b, pat)
	alt[i] = Vector4(al.r, al.g, al.b, scale)
	par[i] = Vector4(float(lk["rough"]), float(lk["spec"]), 0.0, 0.0)


## Give `terrain`'s floor and wall materials the set's tables (each surface's material duplicated, nothing shared touched).
static func restyle(terrain: HexMapView, set_name: String) -> void:
	var mesh := terrain.mesh_instance.mesh as ArrayMesh
	if mesh == null:
		return
	var tb := tables(set_name)
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as ShaderMaterial
		if m == null or m.get_shader_parameter("m_base") == null:
			continue
		var nm := m.duplicate() as ShaderMaterial
		nm.set_shader_parameter("m_base", tb["base"])
		nm.set_shader_parameter("m_alt", tb["alt"])
		nm.set_shader_parameter("m_par", tb["par"])
		mesh.surface_set_material(i, nm)


## Underground light on top of DungeonLook.apply(parent): a dim cool ambient, the key and fill cut low, a darker background.
static func relight(parent: Node, set_name: String) -> void:
	var lk := look(set_name)
	for ch in parent.get_children():
		if ch is WorldEnvironment:
			var env := (ch as WorldEnvironment).environment
			env.ambient_light_color = lk["ambient"]
			env.ambient_light_energy = float(lk["ambient_k"])
			env.background_color = lk["background"]
		elif ch.name == "KeyLight":
			(ch as DirectionalLight3D).light_energy = float(lk["key"])
			(ch as DirectionalLight3D).light_color = lk["key_col"]
		elif ch.name == "FillLight":
			(ch as DirectionalLight3D).light_energy = float(lk["fill"])


## A warm downlight pool over a room above (DungeonLook's own: the same height, energy and falloff).
static func downlight(at_floor: Vector3, energy: float = 11.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = "Downlight"
	l.position = at_floor + Vector3(0, DungeonLook.POOL_HEIGHT, 0)
	l.light_color = DungeonLook.WARM
	l.light_energy = energy
	l.omni_range = 9.5
	l.omni_attenuation = 1.8
	l.light_specular = 0.2
	l.shadow_enabled = false
	return l


## A pale shaft of light falling onto `at_floor` from a grating in the church floor above (the chapel set): a cool spot
## straight down and a faint beam to see it by. Not an OmniLight3D, so it is not a candle pool.
static func shaft(at_floor: Vector3, energy: float = 16.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Shaft"
	root.position = at_floor
	var l := SpotLight3D.new()
	l.name = "ShaftLight"
	l.position = Vector3(0, 7.0, 0)
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.light_color = SHAFT_COLOR
	l.light_energy = energy
	l.spot_range = 9.0
	l.spot_angle = 11.0
	l.spot_attenuation = 0.6
	l.spot_angle_attenuation = 1.6
	l.light_specular = 0.1
	l.shadow_enabled = false
	root.add_child(l)
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45
	cm.bottom_radius = 1.1
	cm.height = 6.0
	cm.radial_segments = 12
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	beam.position = Vector3(0, 3.0, 0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(SHAFT_COLOR.r, SHAFT_COLOR.g, SHAFT_COLOR.b, 0.08)
	beam.material_override = m
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)
	return root

