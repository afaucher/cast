extends SceneTree
## Writes the prototype terrain textures to res://assets/textures/proto/*.png.
##   Godot --path . --headless --script res://tools/make_proto_textures.gd
const Proto = preload("res://scripts/world/proto_textures.gd")


func _init() -> void:
	var dir := ProjectSettings.globalize_path(Proto.DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	for n in Proto.NAMES:
		var img: Image = Proto.make(n)
		var err := img.save_png(dir + n + ".png")
		print("wrote ", n, ".png  err=", err)
	quit()
