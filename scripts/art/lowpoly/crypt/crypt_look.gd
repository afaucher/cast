class_name CryptLook
extends RefCounted
## The crypt section's two sets (docs/design/crypt-section.md): first the look test's, now the game's (haunted-build-plan.md
## H2: a haunted floor's crypt, CryptCluster / CryptPlanner). The sets' materials are FloorMaterials rows (the game's table,
## HIGH slots 32-37: F_VAULT / F_VAULT_HALL / W_VAULT, F_CHAPEL / F_CHAPEL_HALL / W_CHAPEL), worn by the crypt rooms' themes
## (RoomThemeDefs.CRYPT) on a generated floor and painted by the section lab on its map; the room above in the lab is the
## game's mansion (walnut & damask) or church (limestone). `shaft` is the chapel's pale light from above, in the game too
## (the "light_shaft" decor).
##
## LAB ONLY: the lighting (`relight`, after DungeonLook.apply). Underground there is no daylight, so in the lab the key and
## fill are all but off (their wall shadows would leave the floors darker than the wall caps) and a dim, cool ambient is what
## is left; the bright parts of the crypt are candle light (CryptProps' lit pieces carry their own OmniLight3D), the dark
## parts are whatever the ambient leaves. A generated floor keeps the game's light (a crypt is one part of a floor): its crypt
## rooms get no downlight (DungeonLook.add_pools), a dim accent light, the candles and the dark stone.

const SETS: Array[String] = ["vault", "chapel"]

## The two sets differ on colour, floor, light and seams, not just a shade of stone (the user, 2026-10-29: "I want both a
## vault and chapel, but they are too similar to eachother"): the vault is warm black-brown wet stone, small rough stones
## underfoot, candle pools in the near dark; the chapel is whitewashed, large pale slabs, a cool brighter ambient and pale
## shafts of light falling from the church above (`shaft`). Both all but drop the hex seams, so a crypt does not read as
## the game's usual grid. The colours are FloorMaterials' rows ("floor", "hall", "wall": their ids); "seam" is the room floor
## row's own (the seams' strength is per cell now, so the lab's view keeps HexMapView's 1); the ambient, key, fill and
## background the lab's light.
const LOOK := {
	"vault": {
		"title": "vault: under the mansion",
		"above": "mansion",
		"floor": FloorMaterials.F_VAULT, "hall": FloorMaterials.F_VAULT_HALL, "wall": FloorMaterials.W_VAULT,
		"seam": 0.064,
		"ambient": Color(0.55, 0.45, 0.38), "ambient_k": 0.32, "key": 0.04, "key_col": Color(0.70, 0.76, 1.0), "fill": 0.03,
		"background": Color(0.02, 0.015, 0.01),
		"shafts": false,
	},
	"chapel": {
		"title": "chapel: under the church",
		"above": "church",
		"floor": FloorMaterials.F_CHAPEL, "hall": FloorMaterials.F_CHAPEL_HALL, "wall": FloorMaterials.W_CHAPEL,
		"seam": 0.08,
		"ambient": Color(0.62, 0.68, 0.86), "ambient_k": 0.4, "key": 0.08, "key_col": Color(0.74, 0.78, 1.0), "fill": 0.06,
		"background": Color(0.05, 0.05, 0.06),
		"shafts": true,
	},
}

const SHAFT_COLOR := Color(0.80, 0.88, 1.0)


static func look(set_name: String) -> Dictionary:
	return LOOK.get(set_name, LOOK["vault"])


## The material ids of a set: the crypt's rooms, its halls (the stair down, the ossuary gallery), the room above (the game's
## mansion and church rooms: walnut & damask, limestone).
static func crypt_room_mat(set_name: String) -> int:
	return FloorMaterials.pack(int(look(set_name)["floor"]), int(look(set_name)["wall"]))


static func crypt_hall_mat(set_name: String) -> int:
	return FloorMaterials.pack(int(look(set_name)["hall"]), int(look(set_name)["wall"]))


static func above_mat(set_name: String) -> int:
	if str(look(set_name)["above"]) == "church":
		return FloorMaterials.pack(FloorMaterials.F_LIMESTONE, FloorMaterials.W_LIMESTONE)
	return FloorMaterials.pack(FloorMaterials.F_PARQUET, FloorMaterials.W_DAMASK)


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

