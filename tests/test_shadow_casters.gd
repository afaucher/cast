extends TestCase
## The ground shadows stay wherever the player stands (user playtest 2026-10-22, the movement lab: "there was a line on
## the ground that if I crossed it the shadows went away"). Godot's tighter shadow caster culling (RenderingLightCuller,
## on by default) builds each directional cascade's caster hull from the camera's cascade frustum; with our ORTHOGONAL
## camera it rejected the whole terrain (one MeshInstance3D, one AABB: every wall, pillar and step) for some camera
## positions, so all the terrain's shadows went off when the camera crossed a line (in the lab at the player's x 45.25,
## z 0) and came back crossing back. Measured with GameDev's --shot-seq --shadow-mask: the key light's shadow fell from
## ~7300 to ~1300 pixels (only the actors' left) between two frames 0.1 m apart, and stayed continuous with the culling off.
## The project turns it off (project.godot); the plain light-frustum cull still runs, and we have one shadowed light.
## Rendering can't run headless, so this holds the setting and that the key light is the only shadow-casting light.


func setup() -> void:
	eq(ProjectSettings.get_setting("rendering/lights_and_shadows/tighter_shadow_caster_culling", true), false,
			"tighter shadow caster culling is off (it drops the terrain's shadows under the orthographic camera)")
	var holder := Node3D.new()
	DungeonLook.apply(holder)
	var shadowed: Array[String] = []
	for l in holder.find_children("*", "Light3D", true, false):
		if (l as Light3D).shadow_enabled:
			shadowed.append(String(l.name))
	eq(shadowed, ["KeyLight"] as Array[String], "the key light is the floor's one shadowed light")
	holder.free()
	finish()
