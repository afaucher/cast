class_name Hero
extends Actor
## A playable or allied hero: prototype capsule visuals built in code, a melee
## swing, a weak ranged bolt, and up to two spell slots. Input comes from a
## PlayerController child (is_player) or an AllyBrain child; the hero itself
## only exposes actions (melee / shoot / try_cast) and enforces cooldowns on
## GameWorld.time.

signal spell_cast(id: String, power: float)
signal melee_swung
signal bolt_fired

const MELEE_REACH := 1.6
const MELEE_ARC := 100.0
const MELEE_DAMAGE := 20.0
const MELEE_COOLDOWN := 0.45
const RANGED_DAMAGE := 8.0
const RANGED_COOLDOWN := 0.6
const BOLT_SPEED := 16.0
const BOLT_RANGE := 12.0
const BOLT_SIZE := 0.13
const MELEE_SHOVE := 0.7        ## mild outward nudge on every melee hit
# Secondary attacks (RMB / the AI's ranged use), chosen by secondary_kind.
const BOWL_COOLDOWN := 2.0
const BOWL_DAMAGE := 6.0        ## monsters only; heroes are shoved for 0
const BOWL_SHOVE := 3.5
const BOWL_SPEED := 7.0
const BOWL_RANGE := 9.0
const SPIN_REACH := 1.9
const SPIN_DAMAGE := 16.0       ## monsters only
const SPIN_COOLDOWN := 1.4
const SPIN_SHOVE := 2.2         ## everything in reach, teammates included
const TURN_RATE := 18.0
const KEY_MELEE := "_melee"
const KEY_RANGED := "_ranged"
const SWING_REST_YAW := -20.0   # degrees; weapon rests slightly to the right of forward

@export var hero_color := Color(0.3, 0.55, 0.95)
@export var weapon_kind := "sword"   ## "sword" or "staff" (cosmetic)
## What shoot() (RMB / the AI's ranged use) does: "bolt" (the weak ranged bolt / arrows),
## "bowl" (Pebble's rolling boulder) or "spin" (Dagna's 360 degree whirl).
@export var secondary_kind := "bolt"

var is_player := false:
	set(v):
		is_player = v
		if _name_label:
			_name_label.visible = not v and not dead
		_refresh_bar()
var spell_slots: Array[String] = []

var _ready_at := {}                  ## cooldown key -> GameWorld.time when usable again
var _visual: Node3D
var _weapon: Node3D
var _body_mat: StandardMaterial3D
var _bar: HpBar
var _name_label: Label3D
var _shield_icon: Sprite3D
var _shield_bubble: MeshInstance3D
var _swing_tween: Tween
var _visual_yaw := 0.0

## Opt-in replacement for the capsule/hat/weapon body (e.g. a PebbleModel). Set it before the
## hero enters the tree (HeroFactory.spawn_hero(..., model)). The model faces local -Z; if it has
## attack_swing() / cast_pose() / set_downed(bool) / ui_height they are used. Stats, radius and AI
## are untouched. Null = the prototype look.
var visual_override: Node3D = null


func _init() -> void:
	team = GameWorld.TEAM_HEROES
	max_hp = 100.0
	move_speed = 4.5
	radius = 0.4
	display_name = "Hero"


func _ready() -> void:
	super._ready()
	_build_visuals()
	Fx.auto_hit_feedback()
	Fx.attach_hit_feedback(self)
	damaged.connect(func(_a: float, _s: Node) -> void: _refresh_bar())
	healed.connect(func(_a: float) -> void: _refresh_bar())
	_refresh_bar()


# --- Actions ------------------------------------------------------------------------------

func cooldown_left(id: String) -> float:
	return maxf(0.0, float(_ready_at.get(id, 0.0)) - GameWorld.time)


## Cast a spell in one of this hero's slots. False if dead, not slotted, on cooldown, or the spell refuses.
func try_cast(id: String, power: float, aim: Vector3) -> bool:
	if dead or not spell_slots.has(id) or cooldown_left(id) > 0.0:
		return false
	if not SpellBook.cast(id, self, power, aim):
		return false
	_ready_at[id] = GameWorld.time + SpellBook.cooldown_of(id)
	_cast_pose()
	spell_cast.emit(id, power)
	return true


## Sword/staff swing toward `dir` (X/Z). Returns false while on cooldown.
func melee(dir: Vector3) -> bool:
	if dead or is_helpless() or cooldown_left(KEY_MELEE) > 0.0:
		return false
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = facing
	dir = dir.normalized()
	facing = dir
	_ready_at[KEY_MELEE] = GameWorld.time + MELEE_COOLDOWN
	for foe in GameWorld.actors_in_radius(global_position, MELEE_REACH, GameWorld.other_team(team)):
		Fx.attach_hit_feedback(foe)
	Combat.melee_arc(self, dir, MELEE_REACH, MELEE_ARC, MELEE_DAMAGE, MELEE_SHOVE)
	Fx.slash_arc(global_position, dir, MELEE_REACH, MELEE_ARC, hero_color.lightened(0.5))
	_swing_pose()
	melee_swung.emit()
	return true


## The secondary attack toward `dir` (X/Z): the ranged bolt, Pebble's bowl or Dagna's spin,
## per secondary_kind. Returns false while on cooldown.
func shoot(dir: Vector3) -> bool:
	if dead or is_helpless() or cooldown_left(KEY_RANGED) > 0.0:
		return false
	match secondary_kind:
		"bowl":
			return _bowl(dir)
		"spin":
			return _spin()
	return _bolt(dir)


## Pebble's bowl: a boulder rolls along the ground toward `dir`, shoving everything it touches.
func _bowl(dir: Vector3) -> bool:
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = facing
	dir = dir.normalized()
	facing = dir
	_ready_at[KEY_RANGED] = GameWorld.time + BOWL_COOLDOWN
	BowlBoulder.launch(self, dir, BOWL_SPEED, BOWL_RANGE, BOWL_DAMAGE, BOWL_SHOVE)
	_bowl_pose()
	bolt_fired.emit()
	return true


## Dagna's spin: everything within SPIN_REACH is shoved outward; monsters also take damage.
func _spin() -> bool:
	_ready_at[KEY_RANGED] = GameWorld.time + SPIN_COOLDOWN
	for foe in GameWorld.actors_in_radius(global_position, SPIN_REACH, GameWorld.other_team(team)):
		Fx.attach_hit_feedback(foe)
	Combat.melee_arc(self, facing, SPIN_REACH, 360.0, SPIN_DAMAGE, SPIN_SHOVE)
	for mate in GameWorld.actors_in_radius(global_position, SPIN_REACH, team):
		if mate != self and absf(mate.global_position.y - global_position.y) <= 2.1 * Hex.LEVEL_HEIGHT:
			mate.shove(mate.global_position - global_position, SPIN_SHOVE, self)
	Fx.slash_arc(global_position, facing, SPIN_REACH, 360.0, hero_color.lightened(0.5))
	_spin_pose()
	bolt_fired.emit()
	return true


## Fire the weak ranged bolt toward `dir` (X/Z).
func _bolt(dir: Vector3) -> bool:
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = facing
	dir = dir.normalized()
	facing = dir
	_ready_at[KEY_RANGED] = GameWorld.time + RANGED_COOLDOWN
	var on_hit := func(_p: Projectile, hit: Actor, pos: Vector3) -> void:
		if hit:
			Fx.attach_hit_feedback(hit)
		var sparks: Array[Color] = [hero_color.lightened(0.6), Color.WHITE]
		Fx.burst(pos, sparks, 6, 2.0, 0.06, 0.25, 4.0)
	Fx.make_projectile(self, Combat.chest(self) + dir * 0.5, dir, RANGED_DAMAGE, BOLT_SPEED, BOLT_RANGE, hero_color.lightened(0.5), BOLT_SIZE, on_hit)
	_shoot_pose()
	bolt_fired.emit()
	return true


func _on_death() -> void:
	# Downed, not removed: lie flat, grey out. Dead actors drop out of GameWorld queries.
	if _body_mat:
		_body_mat.albedo_color = Color(0.45, 0.45, 0.48)
	if _bar:
		_bar.visible = false
	if _name_label:
		_name_label.visible = false
	_set_armor_visuals(false)
	if visual_override != null and visual_override.has_method("set_downed"):
		visual_override.call("set_downed", true)
	if _visual:
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(_visual, "rotation:x", PI * 0.5, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_visual, "position:y", 0.3, 0.35)


# --- Visuals -------------------------------------------------------------------------------

func _build_visuals() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_body_mat = Fx.solid_material(hero_color, 0.6)
	var skin := Fx.solid_material(Color(0.96, 0.78, 0.62), 0.7)
	var dark := Fx.solid_material(hero_color.darkened(0.45), 0.7)

	var top := 1.95   # top of the figure; the bar, name and shield icon float above it
	if visual_override != null:
		_visual.add_child(visual_override)
		# A model that carries its own weapon (has_own_weapon) animates it itself in attack_swing() /
		# cast_pose(); every other override gets an inert stand-in so the tweens have a target.
		if not ("has_own_weapon" in visual_override and bool(visual_override.get("has_own_weapon"))):
			_weapon = Node3D.new()
			_visual.add_child(_weapon)
		if "ui_height" in visual_override:
			top = float(visual_override.get("ui_height"))
	else:
		_build_default_body(skin, dark)
	var ui_scale := top / 1.95

	_bar = HpBar.new()
	_bar.position = Vector3(0, top + 0.4, 0)
	add_child(_bar)
	if not is_player and display_name != "":
		_name_label = Label3D.new()
		_name_label.text = display_name
		_name_label.font_size = 40
		_name_label.pixel_size = 0.008
		_name_label.outline_size = 8
		_name_label.modulate = hero_color.lightened(0.45)
		_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_name_label.no_depth_test = true
		_name_label.position = Vector3(0, top + 0.65, 0)
		add_child(_name_label)

	# Armor buff visuals (hidden until the "armor" modifier is active).
	_shield_icon = Sprite3D.new()
	_shield_icon.texture = Fx.shield_texture()
	_shield_icon.pixel_size = 0.012
	_shield_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_shield_icon.no_depth_test = true
	_shield_icon.shaded = false
	_shield_icon.position = Vector3(-0.68 * ui_scale, top + 0.4, 0)
	_shield_icon.visible = false
	add_child(_shield_icon)
	_shield_bubble = _add_mesh(self, _sphere(0.8 * ui_scale), Fx.glow_material(Color(0.3, 0.55, 1.0, 0.16)), Vector3(0, 0.9 * ui_scale, 0))
	_shield_bubble.set_meta("no_flash", true)
	_shield_bubble.visible = false


## The prototype look: capsule body, skin head, facing nose, pointy hat and a sword / staff.
func _build_default_body(skin: Material, dark: Material) -> void:
	_add_mesh(_visual, _capsule(0.32, 1.2), _body_mat, Vector3(0, 0.6, 0))
	_add_mesh(_visual, _sphere(0.25), skin, Vector3(0, 1.42, 0))
	# Facing nose (points to local -Z, which Hero yaws toward `facing`).
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.1, 0.1, 0.2)
	_add_mesh(_visual, nose_mesh, Fx.solid_material(Color(0.85, 0.55, 0.4)), Vector3(0, 1.4, -0.3))
	# Pointy hat in a darker shade of the hero color.
	var hat := CylinderMesh.new()
	hat.top_radius = 0.0
	hat.bottom_radius = 0.28
	hat.height = 0.36
	_add_mesh(_visual, hat, dark, Vector3(0, 1.78, 0))

	_weapon = Node3D.new()
	_weapon.position = Vector3(0.38, 0.85, -0.1)
	_weapon.rotation.y = deg_to_rad(SWING_REST_YAW)
	_visual.add_child(_weapon)
	if weapon_kind == "staff":
		var rod := CylinderMesh.new()
		rod.top_radius = 0.035
		rod.bottom_radius = 0.045
		rod.height = 1.3
		var rod_mi := _add_mesh(_weapon, rod, Fx.solid_material(Color(0.5, 0.33, 0.18)), Vector3(0, 0, -0.55))
		rod_mi.rotation.x = deg_to_rad(90)
		var orb_mat := Fx.glow_material(Color(hero_color.lightened(0.4), 0.95))
		_add_mesh(_weapon, _sphere(0.13), orb_mat, Vector3(0, 0, -1.25))
	else:
		var blade := BoxMesh.new()
		blade.size = Vector3(0.08, 0.05, 0.95)
		_add_mesh(_weapon, blade, Fx.solid_material(Color(0.85, 0.88, 0.95), 0.25), Vector3(0, 0, -0.62))
		var guard := BoxMesh.new()
		guard.size = Vector3(0.3, 0.06, 0.07)
		_add_mesh(_weapon, guard, Fx.solid_material(Color(0.7, 0.55, 0.2)), Vector3(0, 0, -0.14))


func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 16
	c.rings = 6
	return c


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s


func _process(delta: float) -> void:
	if _visual == null:
		return
	var target_yaw := atan2(-facing.x, -facing.z)
	_visual_yaw = lerp_angle(_visual_yaw, target_yaw, clampf(TURN_RATE * delta, 0.0, 1.0))
	_visual.rotation.y = _visual_yaw
	if not dead:
		_set_armor_visuals(has_modifier("armor"))
		if _shield_bubble.visible:
			var pulse := 1.0 + 0.04 * sin(GameWorld.time * 6.0)
			_shield_bubble.scale = Vector3.ONE * pulse


func _set_armor_visuals(on: bool) -> void:
	if _shield_icon and _shield_icon.visible != on:
		_shield_icon.visible = on
		_shield_bubble.visible = on


func _refresh_bar() -> void:
	if _bar:
		_bar.set_fraction(hp / max_hp, Color(0.25, 0.85, 0.75) if is_player and hp / max_hp > 0.5 else Color(0, 0, 0, 0))


func _swing_pose() -> void:
	if visual_override != null and visual_override.has_method("attack_swing"):
		visual_override.call("attack_swing")
	if _weapon == null:
		return
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	var rest := deg_to_rad(SWING_REST_YAW)
	_weapon.rotation = Vector3(0, deg_to_rad(-85), 0)
	_swing_tween = create_tween()
	_swing_tween.tween_property(_weapon, "rotation:y", deg_to_rad(75), 0.11).set_trans(Tween.TRANS_SINE)
	_swing_tween.tween_property(_weapon, "rotation:y", rest, 0.22).set_trans(Tween.TRANS_SINE)


func _bowl_pose() -> void:
	if visual_override != null and visual_override.has_method("bowl_pose"):
		visual_override.call("bowl_pose")
		return
	_shoot_pose()


func _spin_pose() -> void:
	if visual_override != null and visual_override.has_method("spin"):
		visual_override.call("spin", 0.5)
		return
	if _weapon == null:
		return
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	_weapon.rotation = Vector3(0, 0, 0)
	_swing_tween = create_tween()
	_swing_tween.tween_property(_weapon, "rotation:y", TAU, 0.4).set_trans(Tween.TRANS_SINE)
	_swing_tween.tween_callback(func() -> void: _weapon.rotation = Vector3(0, deg_to_rad(SWING_REST_YAW), 0))


func _shoot_pose() -> void:
	if visual_override != null and visual_override.has_method("shoot_pose"):
		visual_override.call("shoot_pose")
	if _weapon == null:
		return
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	_weapon.rotation = Vector3(deg_to_rad(25), 0, 0)
	_swing_tween = create_tween()
	_swing_tween.tween_property(_weapon, "rotation", Vector3(0, deg_to_rad(SWING_REST_YAW), 0), 0.25).set_trans(Tween.TRANS_BACK)


func _cast_pose() -> void:
	if visual_override != null and visual_override.has_method("cast_pose"):
		visual_override.call("cast_pose")
	if _weapon == null:
		return
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	_weapon.rotation = Vector3(deg_to_rad(-60), 0, 0)
	_swing_tween = create_tween()
	_swing_tween.tween_property(_weapon, "rotation", Vector3(0, deg_to_rad(SWING_REST_YAW), 0), 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
