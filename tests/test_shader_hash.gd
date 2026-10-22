extends TestCase
## The shaders' lattice hash (ShaderHash; docs/design/lava-playtest.md, "The lava's creases"):
##   - no script under res://scripts hashes in a shader with fract(sin(...)): tens of metres from the origin one rounding
##     step of the sine's argument is another value, and a noise or cellular pattern reaches each lattice point from its
##     neighbours by different arithmetic, so its cells were cut along lattice lines (the lava's creases);
##   - the pattern shaders that had it splice ShaderHash.GLSL (an integer hash): the lava and its crust, the sewer's channel
##     and water, the pool floor's moat blocks, the van's rug and summoning circle, and the lava and sewer labs.
## The shaders can't run headless; this reads their code.

const SINE_HASH := "fract\\s*\\(\\s*sin\\s*\\("


func setup() -> void:
	var sine := RegEx.create_from_string(SINE_HASH)
	var files: Array[String] = []
	_scripts("res://scripts", files)
	check(files.size() > 50, "the scripts are found (%d)" % files.size())
	var bad: Array[String] = []
	for path in files:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var line := lines[i].strip_edges()
			if line.begins_with("#") or line.begins_with("//"):
				continue   # (a comment that tells why not)
			if sine.search(line) != null:
				bad.append("%s:%d" % [path, i + 1])
	check(bad.is_empty(), "no sine hash in a shader: %s" % (", ".join(bad) if not bad.is_empty() else "none"))

	var shaders := {
		"LavaLook.LAVA_SHADER": LavaLook.LAVA_SHADER,
		"LavaLook.CRUST_SHADER": LavaLook.CRUST_SHADER,
		"SewerView.CHANNEL_SHADER": SewerView.CHANNEL_SHADER,
		"SewerView.WATER_SHADER": SewerView.WATER_SHADER,
		"HexMapView.POOL_SHADER": HexMapView.POOL_SHADER,
		"VanRug.SHADER": VanRug.SHADER,
		"VanCircle.FIGURE_SHADER": VanCircle.FIGURE_SHADER,
		"LavaLab.LAVA_SHADER": _const("res://scripts/art/lowpoly/lava_lab.gd", "LAVA_SHADER"),
		"SewerLab.CHANNEL_SHADER": _const("res://scripts/art/lowpoly/sewer_lab.gd", "CHANNEL_SHADER"),
		"SewerLab.WATER_SHADER": _const("res://scripts/art/lowpoly/sewer_lab.gd", "WATER_SHADER"),
	}
	for name: String in shaders:
		var code := str(shaders[name])
		check(code.contains(ShaderHash.GLSL), "%s splices ShaderHash.GLSL" % name)
		check(code.count("vec2 h22(vec2 p)") == 1 and code.count("float h21(vec2 p)") == 1, "%s declares its hash once" % name)
		check(sine.search(code) == null, "%s has no sine hash" % name)
	finish()


func _scripts(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scripts(dir.path_join(d), out)


## A lab script's shader constant (the labs have no class_name).
func _const(path: String, name: String) -> String:
	return str((load(path) as GDScript).get_script_constant_map().get(name, ""))
