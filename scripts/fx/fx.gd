class_name Fx
extends RefCounted
## Shared visual effects: floating numbers, rings, particle bursts, explosions,
## hit flashes. Everything spawns under GameWorld.root and cleans itself up.
## Uses CPUParticles3D only, so it behaves the same headless and on any GPU.
## All helpers are safe no-ops when there is no world root (e.g. unit tests of
## pure logic).

const FLASH_TIME := 0.12
const NUMBER_RISE := 1.3
const NUMBER_TIME := 0.9
const NUMBER_HERO_HIT := Color(1.0, 0.45, 0.4)
const NUMBER_MONSTER_HIT := Color(1.0, 0.95, 0.7)
const NUMBER_HEAL := Color(0.45, 1.0, 0.55)

static var _flash_mat: StandardMaterial3D = null
static var _shield_tex: ImageTexture = null


# --- Materials ------------------------------------------------------------------

## Unshaded translucent material (additive by default) for glows and rings.
static func glow_material(color: Color, additive: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	return m


static func solid_material(color: Color, rough: float = 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


static func _world_ready() -> bool:
	return GameWorld.root != null and GameWorld.root.is_inside_tree()


# --- Floating numbers -------------------------------------------------------------

## A billboard number/text that rises and fades.
static func number(pos: Vector3, text: String, color: Color = Color.WHITE, scale: float = 1.0) -> Label3D:
	if not _world_ready():
		return null
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.outline_size = 14
	l.font_size = int(64.0 * scale)
	l.pixel_size = 0.012
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 20
	GameWorld.spawn(l, pos)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position:y", pos.y + NUMBER_RISE, NUMBER_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(l, "modulate:a", 0.0, NUMBER_TIME * 0.5).set_delay(NUMBER_TIME * 0.5)
	tw.chain().tween_callback(l.queue_free)
	return l


# --- Rings, flashes, bursts ---------------------------------------------------------

## An expanding flat ring (hex outline when `hex` is true). `rise` lifts it while it fades.
static func ring(pos: Vector3, radius: float, color: Color, time: float = 0.6, rise: float = 0.0, hex: bool = false, start_scale: float = 0.25) -> MeshInstance3D:
	if not _world_ready():
		return null
	var t := TorusMesh.new()
	var tube := clampf(radius * 0.05, 0.04, 0.14)
	t.inner_radius = radius - tube
	t.outer_radius = radius + tube
	t.rings = 6 if hex else 40
	t.ring_segments = 6
	var mat := glow_material(color)
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * start_scale
	GameWorld.spawn(mi, pos + Vector3.UP * 0.08)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, time).set_delay(time * 0.35)
	if rise != 0.0:
		tw.tween_property(mi, "global_position:y", pos.y + 0.08 + rise, time)
	tw.chain().tween_callback(mi.queue_free)
	return mi


## A glowing sphere that swells and fades (explosion core, muzzle flash).
static func flash_sphere(pos: Vector3, radius: float, color: Color, time: float = 0.25) -> MeshInstance3D:
	if not _world_ready():
		return null
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 16
	s.rings = 8
	var mat := glow_material(color)
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * 0.3
	GameWorld.spawn(mi, pos)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE, time).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, time)
	tw.chain().tween_callback(mi.queue_free)
	return mi


## A one-shot particle burst. `colors` are sampled randomly per particle.
static func burst(pos: Vector3, colors: Array[Color], amount: int = 24, speed: float = 4.0, size: float = 0.12, lifetime: float = 0.7, gravity: float = 9.0, dir: Vector3 = Vector3.UP, spread_deg: float = 180.0, glow: bool = true) -> CPUParticles3D:
	if not _world_ready():
		return null
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.direction = dir
	p.spread = spread_deg
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var grad := Gradient.new()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / maxf(1.0, colors.size() - 1.0))
		cols.append(colors[i])
	if colors.size() == 1:
		offsets.append(1.0)
		cols.append(colors[0])
	grad.offsets = offsets
	grad.colors = cols
	p.color_initial_ramp = grad
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if glow else BaseMaterial3D.SHADING_MODE_PER_VERTEX
	sm.material = mat
	p.mesh = sm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	GameWorld.spawn(p, pos)
	p.emitting = true
	_free_later(p, lifetime + 0.4)
	return p


static func _free_later(n: Node, seconds: float) -> void:
	if n.is_inside_tree():
		n.get_tree().create_timer(seconds).timeout.connect(n.queue_free)


## Fireball-style explosion: core flash, light, embers, smoke, ground ring, and its sound (`cue`, 3D at the burst; the
## fireball is the only explosion so far). It runs on every machine the cast lands on, so everyone hears it.
static func explosion(pos: Vector3, radius: float, color: Color = Color(1.0, 0.55, 0.15), cue: String = "fireball") -> void:
	if not _world_ready():
		return
	Sfx.play_at(cue, pos)
	flash_sphere(pos, radius * 0.7, Color(color.r, color.g, color.b, 0.85), 0.28)
	flash_sphere(pos, radius * 0.4, Color(1.0, 0.95, 0.7, 0.95), 0.18)
	ring(Vector3(pos.x, pos.y, pos.z), radius, Color(color.r, color.g, color.b, 0.8), 0.45, 0.0, false, 0.2)
	var embers: Array[Color] = [Color(1.0, 0.9, 0.4), color, Color(0.9, 0.25, 0.1)]
	burst(pos, embers, 36, 6.0 + radius, 0.11, 0.8, 8.0)
	var smoke: Array[Color] = [Color(0.25, 0.22, 0.2), Color(0.4, 0.36, 0.33)]
	burst(pos + Vector3.UP * 0.3, smoke, 14, 2.5, 0.28, 1.0, -1.5, Vector3.UP, 60.0, false)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 6.0
	light.omni_range = radius * 3.5
	GameWorld.spawn(light, pos + Vector3.UP * 0.5)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.4)
	tw.tween_callback(light.queue_free)
	shake(0.25 + radius * 0.08)


## Soft grey puff for a failed cast.
static func fizzle_puff(pos: Vector3) -> void:
	if not _world_ready():
		return
	var cols: Array[Color] = [Color(0.55, 0.55, 0.58), Color(0.35, 0.35, 0.4)]
	burst(pos + Vector3.UP * 1.2, cols, 10, 1.2, 0.14, 0.9, -0.6, Vector3.UP, 40.0, false)
	number(pos + Vector3.UP * 2.0, "*pfft*", Color(0.75, 0.75, 0.8), 0.7)


## A translucent ground wedge flashed for a melee swing.
static func slash_arc(origin: Vector3, dir: Vector3, reach: float, arc_deg: float, color: Color) -> void:
	if not _world_ready():
		return
	dir.y = 0.0
	dir = dir.normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := deg_to_rad(arc_deg * 0.5)
	var segs := 12
	var base := atan2(dir.x, dir.z)  # yaw of dir measured from +Z
	var prev := Vector3(sin(base - half), 0, cos(base - half)) * reach
	for i in range(1, segs + 1):
		var a := base - half + (half * 2.0) * float(i) / segs
		var cur := Vector3(sin(a), 0, cos(a)) * reach
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.UP)
		st.add_vertex(cur)
		st.set_normal(Vector3.UP)
		st.add_vertex(prev)
		prev = cur
	var mat := glow_material(Color(color.r, color.g, color.b, 0.45))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	GameWorld.spawn(mi, origin + Vector3.UP * 0.25)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tw.tween_callback(mi.queue_free)


## The floor mark of Combat.melee_lane (a centred overhead strike): a stadium from `near` to `far` ahead of `origin` along
## `dir`, `radius` wide on each side, the same glow and fade as slash_arc, plus a quick ring where the blow lands (`far`).
## `end_radius` > 0 adds the disc round the landing (Combat.melee_lane's smash).
static func slam_lane(origin: Vector3, dir: Vector3, near: float, far: float, radius: float, color: Color, end_radius: float = 0.0) -> void:
	if not _world_ready():
		return
	dir.y = 0.0
	dir = dir.normalized()
	var side := Vector3(-dir.z, 0.0, dir.x)
	var pts: Array[Vector3] = []   # the outline: the near cap (+side round the back to -side), then the far cap
	var segs := 8
	for i in segs + 1:
		var a := PI * float(i) / segs
		pts.append(dir * near + (side * cos(a) - dir * sin(a)) * radius)
	for i in segs + 1:
		var a := PI * float(i) / segs
		pts.append(dir * far + (-side * cos(a) + dir * sin(a)) * radius)
	var c := dir * (near + far) * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size():
		for v: Vector3 in [c, pts[(i + 1) % pts.size()], pts[i]]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	if end_radius > radius:   # the landing's disc (drawn a hair above the lane, so the overlap is not doubled in the fade)
		var dc := dir * far
		for i in 20:
			var a0 := TAU * i / 20.0
			var a1 := TAU * (i + 1) / 20.0
			for v: Vector3 in [dc, dc + Vector3(cos(a1), 0.0, sin(a1)) * end_radius, dc + Vector3(cos(a0), 0.0, sin(a0)) * end_radius]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v + Vector3.UP * 0.005)
	var mat := glow_material(Color(color.r, color.g, color.b, 0.45))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	GameWorld.spawn(mi, origin + Vector3.UP * 0.25)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tw.tween_callback(mi.queue_free)
	ring(origin + dir * far + Vector3.UP * 0.1, maxf(radius, end_radius) + 0.35, Color(color.r, color.g, color.b, 0.7), 0.22, 0.0, false, 0.4)


## A hammer's landing on the floor (HeroFeel, a smash's impact; cosmetic, every screen): a fast pale shock ring out to
## about `radius` and a puff of dust, gone in about 0.5 s. (No dark cracks: the user, 2026-10-22, "Lets also remove the
## crack from Gasket's primary. Just the white effects you have.")
static func ground_smash(pos: Vector3, radius: float) -> void:
	if not _world_ready():
		return
	var map: HexMap = GameWorld.map
	var g := map.ground_height(pos) if map != null else NAN
	if not is_nan(g):
		pos.y = g
	ring(pos + Vector3.UP * 0.08, radius + 0.25, Color(1.0, 0.92, 0.75, 0.85), 0.28, 0.0, false, 0.2)
	var dust: Array[Color] = [Color(0.8, 0.72, 0.58), Color(0.6, 0.52, 0.42)]
	burst(pos + Vector3.UP * 0.1, dust, 14, 3.2, 0.1, 0.5, 4.0, Vector3.UP, 80.0, false)


## Gasket's spin kicking up the floor (HeroFeel, a whirl's start; cosmetic, every screen): a pale ring sweeping out to
## `radius` at her feet and dust thrown out low all round. White effects only, like the smash.
static func spin_dust(pos: Vector3, radius: float) -> void:
	if not _world_ready():
		return
	ring(pos + Vector3.UP * 0.08, radius, Color(1.0, 0.94, 0.8, 0.8), 0.3, 0.0, false, 0.35)
	var dust: Array[Color] = [Color(0.8, 0.72, 0.58), Color(0.6, 0.52, 0.42)]
	burst(pos + Vector3.UP * 0.12, dust, 16, 3.6, 0.09, 0.45, 3.0, Vector3.UP, 88.0, false)


## Nudge any CameraRig in the scene (group "camera_rig").
static func shake(amount: float) -> void:
	if _world_ready():
		GameWorld.root.get_tree().call_group("camera_rig", "shake", amount)


# --- Projectiles ----------------------------------------------------------------------

## Like Projectile.fire, but sets color/size/on_hit BEFORE the node enters the tree
## (Projectile builds its mesh in _ready, so setting them after fire() has no effect).
static func make_projectile(shooter: Actor, from: Vector3, dir: Vector3, dmg: float, spd: float, max_range: float, color: Color, size: float, on_hit: Callable = Callable()) -> Projectile:
	var p := Projectile.new()
	p.source = shooter
	p.target_team = GameWorld.other_team(shooter.team)
	dir.y = 0.0
	p.direction = dir.normalized()
	p.damage = dmg
	p.speed = spd
	p.max_range = max_range
	p.color = color
	p.size = size
	p.on_hit = on_hit
	GameWorld.spawn(p, from)
	return p


# --- Hit feedback -----------------------------------------------------------------------

## Make any actor (hero, dummy, monster) flash and show a damage number when hurt.
## Safe to call repeatedly: it only attaches once.
static func attach_hit_feedback(actor: Actor) -> void:
	if actor == null or actor.has_meta("fx_hit_feedback"):
		return
	actor.set_meta("fx_hit_feedback", true)
	actor.damaged.connect(_on_actor_damaged.bind(actor))
	actor.shoved.connect(_on_actor_shoved.bind(actor))
	actor.shove_impact.connect(_on_shove_impact.bind(actor))


## Attach hit feedback to every actor now and to every actor spawned via GameWorld.spawn later.
static func auto_hit_feedback() -> void:
	for a in GameWorld.actors():
		attach_hit_feedback(a)
	if not GameWorld.actor_spawned.is_connected(attach_hit_feedback):
		GameWorld.actor_spawned.connect(attach_hit_feedback)


static func _on_actor_damaged(amount: float, _source: Node, actor: Actor) -> void:
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	var head := actor.global_position + Vector3(GameWorld.fx_rng.randf_range(-0.25, 0.25), 2.0 + actor.radius, 0)
	var col := NUMBER_HERO_HIT if actor.team == GameWorld.TEAM_HEROES else NUMBER_MONSTER_HIT
	number(head, str(int(roundf(amount))), col, 1.0)
	flash(actor)


## A little scuff of dust at the feet when something gets shoved.
static func _on_actor_shoved(_dir: Vector3, distance: float, actor: Actor) -> void:
	if not is_instance_valid(actor) or not actor.is_inside_tree() or distance < 1.0:
		return
	var dust: Array[Color] = [Color(0.8, 0.72, 0.58), Color(0.6, 0.52, 0.42)]
	burst(actor.global_position + Vector3.UP * 0.1, dust, 6, 1.6, 0.08, 0.4, 2.0, Vector3.UP, 70.0, false)


## Wall slams, hard landings and pits: dust, a ring, a shake and a word.
static func _on_shove_impact(kind: String, pos: Vector3, amount: float, actor: Actor) -> void:
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	var dust: Array[Color] = [Color(0.8, 0.72, 0.58), Color(0.6, 0.52, 0.42)]
	match kind:
		"slam":
			burst(pos + Vector3.UP * 0.7, dust, 14, 3.0, 0.1, 0.5, 4.0, Vector3.UP, 120.0, false)
			number(pos + Vector3(0, 2.6 + actor.radius, 0), "SLAM!", Color(1.0, 0.8, 0.3), 0.8)
			shake(0.12)
		"land":
			burst(pos + Vector3.UP * 0.1, dust, 12, 3.5, 0.11, 0.55, 3.0, Vector3.UP, 85.0, false)
			ring(pos, 0.9, Color(0.9, 0.8, 0.6, 0.6), 0.35, 0.0, false, 0.3)
			if amount > 0.0:
				number(pos + Vector3(0, 2.6 + actor.radius, 0), "THUD!", Color(1.0, 0.7, 0.3), 0.8)
				shake(0.18)
		"void":
			number(pos + Vector3(0, 2.4, 0), "AAAH!", Color(0.8, 0.6, 1.0), 0.8)
		"lava":
			# a lava cave's lava (Actor._enter_void): a hot splash where it went in and a shake for a hero (the pull's 15
			# shows as its damage number; no "LAVA!" word: user, 2026-10-22). On this machine: the actor's owner runs the
			# shove (LavaField splashes for the monsters other screens see sink).
			var hot: Array[Color] = [Color(1.0, 0.36, 0.05), Color(1.0, 0.82, 0.3), Color(1.0, 0.25, 0.05)]
			var at := pos
			var map := GameWorld.map
			if map != null and not map.cave.is_empty():
				at.y = float(map.cave.get("lava_y", at.y))
			burst(at + Vector3.UP * 0.1, hot, 26, 4.5, 0.14, 0.8, 7.0, Vector3.UP, 55.0, true)   # (the sizzle: LavaField)
			if actor.team == GameWorld.TEAM_HEROES:
				shake(0.15)


## White overlay on every mesh of the actor for a moment.
static func flash(actor: Node3D) -> void:
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.albedo_color = Color(1, 1, 1, 0.6)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(actor, meshes)
	for mi in meshes:
		mi.material_overlay = _flash_mat
	var stamp: int = int(actor.get_meta("fx_flash_stamp", 0)) + 1
	actor.set_meta("fx_flash_stamp", stamp)
	var tw := actor.create_tween()
	tw.tween_interval(FLASH_TIME)
	tw.tween_callback(func() -> void:
		if int(actor.get_meta("fx_flash_stamp", 0)) != stamp:
			return
		for mi in meshes:
			if is_instance_valid(mi):
				mi.material_overlay = null)


static func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and not c.has_meta("no_flash"):
			out.append(c)
		_collect_meshes(c, out)


# --- Icons -------------------------------------------------------------------------------

## A small procedurally drawn shield icon (blue with a light rim) for buffed heroes.
static func shield_texture() -> ImageTexture:
	if _shield_tex != null:
		return _shield_tex
	var n := 48
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / n * 2.0 - 1.0     # -1..1
			var v := (float(y) + 0.5) / n                   # 0..1 top to bottom
			var half_w := 0.85 if v < 0.45 else 0.85 * sqrt(maxf(0.0, 1.0 - pow((v - 0.45) / 0.55, 2.0)))
			var inside := v > 0.04 and v < 1.0 and absf(u) <= half_w
			if not inside:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var edge := half_w - absf(u)
			var rim := edge < 0.12 or v < 0.1
			if rim:
				img.set_pixel(x, y, Color(0.85, 0.95, 1.0, 1.0))
			elif absf(u) < 0.09 or (v > 0.3 and v < 0.4):
				img.set_pixel(x, y, Color(0.6, 0.8, 1.0, 1.0))  # cross emblem
			else:
				img.set_pixel(x, y, Color(0.2, 0.45, 0.95, 1.0))
	_shield_tex = ImageTexture.create_from_image(img)
	return _shield_tex
