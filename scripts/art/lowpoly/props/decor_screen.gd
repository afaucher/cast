class_name DecorScreen
extends RefCounted
## The cinema screen's picture: a handful of static (TV snow) frames and one frame where a horned demon
## silhouette stands in the snow with glowing eyes. DecorAnim flips between them, so the screen flickers
## with a static image (docs/design/environment.md: "a demon silhouette flickering on the screen").
## Generated in code (48 x 27 pixels, nearest filtered), cached for the process.

const W := 48
const H := 27
const SNOW_FRAMES := 4

static var _frames: Array[ImageTexture] = []


## SNOW_FRAMES snow frames, then the demon frame (index SNOW_FRAMES).
static func frames() -> Array[ImageTexture]:
	if _frames.is_empty():
		for i in SNOW_FRAMES + 1:
			_frames.append(_make_frame(i))
	return _frames


static func _make_frame(i: int) -> ImageTexture:
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + i * 131
	for y in H:
		var band := 0.86 + 0.14 * sin(float(y) * 0.9 + float(i) * 1.7)
		for x in W:
			var v := (rng.randf() * 0.65 + 0.22) * band
			img.set_pixel(x, y, Color(v * 0.82, v * 0.93, v))
	if i == SNOW_FRAMES:
		_draw_demon(img)
	return ImageTexture.create_from_image(img)


static func _draw_demon(img: Image) -> void:
	var dark := Color(0.04, 0.02, 0.05)
	for y in H:
		for x in W:
			var fx := float(x) - 24.0
			var fy := float(y)
			var inside := false
			# head, neck and shoulders
			if pow(fx / 4.6, 2.0) + pow((fy - 12.5) / 5.6, 2.0) < 1.0:
				inside = true
			if absf(fx) < 3.0 and fy > 16.0 and fy < 21.0:
				inside = true
			if pow(fx / 14.0, 2.0) + pow((fy - 29.0) / 10.5, 2.0) < 1.0:
				inside = true
			# horns: two slanted spikes
			for side: float in [-1.0, 1.0]:
				var hx := fx * side
				var along := (fy - 8.5) / -7.0          # 0 at the head, 1 at the tip
				if along >= 0.0 and along <= 1.0 and absf(hx - (3.0 + along * 5.5)) < 1.3 * (1.0 - along) + 0.3:
					inside = true
			if inside:
				img.set_pixel(x, y, dark)
	for ex: int in [21, 27]:
		for ey: int in [11, 12]:
			img.set_pixel(ex, ey, Color(1.0, 0.18, 0.1))
	for x in range(22, 27):
		img.set_pixel(x, 16, Color(0.7, 0.08, 0.06))


## The picture: a quad that faces +Z, unshaded, starting on the first snow frame.
static func make_quad(size: Vector2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Screen"
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = frames()[0]
	m.albedo_color = Color(1.1, 1.18, 1.3)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
