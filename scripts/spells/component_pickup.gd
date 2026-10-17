class_name ComponentPickup
extends Node3D
## A material component lying in the world: a faceted prop that bobs and turns, a soft glow, and a
## small floating label when a player is close. A player hero walking within COLLECT_RADIUS picks
## it up automatically (see Hero.collect_component for what that does). When the hero's slots are
## all full and this spell is not slotted, it stays on the floor and offers a swap: Hero.swap_candidate
## is set while the hero stands within SWAP_RADIUS and F swaps it into the held slot.
##
## Only heroes with is_player collect (the keyboard player today, later each human). AI allies
## do not cast spells yet, so their slots would only steal the player's loot.

const HOVER := 0.55
const BOB := 0.07
const TURN := 1.2

var spell_id := ""
var charges := SpellComponents.PICKUP_CHARGES
## Seconds until it vanishes if nobody takes it (blinks for the last SpellComponents.PICKUP_FADE). 0 = never.
var lifetime := SpellComponents.PICKUP_LIFETIME

var _prop: Node3D
var _glow: MeshInstance3D
var _label: Label3D
var _t := 0.0
var _used := false
var _age := 0.0
var _ring: MeshInstance3D


## Put a pickup of `id` on the floor at `pos` (nearest walkable spot within a couple of cells).
## Null when there is no world, the spell is unknown, or no floor is anywhere near.
static func drop(id: String, amount: int, pos: Vector3, life: float = SpellComponents.PICKUP_LIFETIME) -> ComponentPickup:
	if GameWorld.root == null or not SpellBook.has_spell(id) or amount <= 0:
		return null
	var spot := _floor_spot(pos)
	if spot == Vector3.INF:
		return null
	var p := ComponentPickup.new()
	p.spell_id = id
	p.charges = amount
	p.lifetime = life
	GameWorld.spawn(p, spot)
	return p


## `pos` pulled onto real ground: itself if it is over a floor cell, else the nearest of a few
## candidates around it. Vector3.INF if none.
static func _floor_spot(pos: Vector3) -> Vector3:
	var map: HexMap = GameWorld.map
	if map == null:
		return pos
	var candidates: Array[Vector3] = [pos]
	for r: float in [0.8, 1.6]:
		for k in 8:
			var a := TAU * k / 8.0
			candidates.append(pos + Vector3(cos(a), 0.0, sin(a)) * r)
	for c: Vector3 in candidates:
		var h := map.ground_height(c)
		if is_nan(h):
			continue
		var cell: HexMap.Cell = map.get_cell(Hex.from_world(c))
		if cell == null or cell.type == HexMap.Tile.WALL:
			continue
		return Vector3(c.x, h, c.z)
	return Vector3.INF


func _ready() -> void:
	add_to_group("component_pickups")
	name = "Pickup_" + spell_id
	_t = GameWorld.fx_rng.randf() * TAU
	var col := SpellBook.color_of(spell_id)
	_prop = ComponentProps.make(spell_id)
	_prop.scale = Vector3.ONE * 1.5
	_prop.position.y = HOVER
	add_child(_prop)
	_glow = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	sm.radial_segments = 12
	sm.rings = 6
	_glow.mesh = sm
	_glow.material_override = Fx.glow_material(Color(col.r, col.g, col.b, 0.16))
	_glow.position.y = HOVER
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.set_meta("no_flash", true)
	add_child(_glow)
	# A faint ring on the floor so it is findable among corpses.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.5
	tm.rings = 16
	tm.ring_segments = 4
	ring.mesh = tm
	ring.material_override = Fx.glow_material(Color(col.r, col.g, col.b, 0.5))
	ring.scale = Vector3(1.0, 0.15, 1.0)
	ring.position.y = 0.06
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_ring = ring
	_label = Label3D.new()
	_label.text = label_text()
	_label.font_size = 36
	_label.pixel_size = 0.0075
	_label.outline_size = 10
	_label.modulate = col.lightened(0.35)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position.y = HOVER + 0.75
	_label.visible = false
	add_child(_label)


## Who may write each var (see Net). The host owns pickups.
func net_fields() -> Dictionary:
	return {
		"spell_id": Net.SPAWN, "lifetime": Net.SPAWN,
		# What is left on the floor: every screen shows the count, and a collected or swapped pickup vanishes.
		"charges": Net.OWNER, "_used": Net.OWNER,
		# Each machine ages it from the spawn time, for the fade-out blink.
		"_age": Net.LOCAL,
		"_prop": Net.LOCAL, "_glow": Net.LOCAL, "_label": Net.LOCAL, "_t": Net.LOCAL, "_ring": Net.LOCAL,
	}


func _exit_tree() -> void:
	_release_swap_offers()


## "Ember horn x3".
func label_text() -> String:
	return "%s x%d" % [SpellBook.component_name(spell_id), charges]


func _process(delta: float) -> void:
	_t += delta
	if _prop:
		_prop.position.y = HOVER + sin(_t * 2.2) * BOB
		_prop.rotation.y += TURN * delta
	if _glow:
		var k := 1.0 + 0.08 * sin(_t * 3.0)
		_glow.scale = Vector3.ONE * k
		_glow.position.y = _prop.position.y if _prop else HOVER


func _physics_process(delta: float) -> void:
	if _used:
		return
	_age += delta
	if lifetime > 0.0 and _age >= lifetime:
		consume()
		return
	_blink()
	var near_player := false
	for h in GameWorld.team_actors(GameWorld.TEAM_HEROES):
		var hero := h as Hero
		if hero == null or not hero.is_player:
			continue
		var d := GameWorld.flat_distance(hero.global_position, global_position)
		if absf(hero.global_position.y - global_position.y) > 1.6:
			_withdraw_offer(hero)
			continue
		if d <= SpellComponents.LABEL_RADIUS:
			near_player = true
		match hero.component_outcome(spell_id):
			"add", "fill":
				_withdraw_offer(hero)
				if d <= SpellComponents.COLLECT_RADIUS:
					_collect(hero)
			"swap":
				if d <= SpellComponents.SWAP_RADIUS:
					_offer(hero, d)
				else:
					_withdraw_offer(hero)
			_:
				_withdraw_offer(hero)   # capped: it waits on the floor
		if _used:
			return
	if _label:
		_label.visible = near_player
		_label.text = label_text()


## Seconds left before it vanishes (INF when it never does).
func time_left() -> float:
	return INF if lifetime <= 0.0 else lifetime - _age


## In its last PICKUP_FADE seconds the pickup blinks, faster as the end nears.
func _blink() -> void:
	var left := time_left()
	var on := true
	if left <= SpellComponents.PICKUP_FADE:
		var rate := 2.0 if left > 2.0 else 5.0   # blinks per second
		on = fmod(_age * rate, 1.0) < 0.6
	for n: Node3D in [_prop, _glow, _ring]:
		if n != null:
			n.visible = on


func _collect(hero: Hero) -> void:
	var res := hero.collect_component(spell_id, charges)
	var taken := int(res.get("amount", 0))
	if taken <= 0:
		return
	charges -= taken
	if charges <= 0:
		consume()
		var sparks: Array[Color] = [SpellBook.color_of(spell_id).lightened(0.4), Color.WHITE]
		Fx.burst(global_position + Vector3.UP * HOVER, sparks, 10, 2.0, 0.06, 0.5, -1.0, Vector3.UP, 60.0)


## Remove this pickup for good (collected or swapped in).
func consume() -> void:
	_used = true
	_release_swap_offers()
	visible = false
	set_physics_process(false)
	set_process(false)
	queue_free()


func _offer(hero: Hero, d: float) -> void:
	var cur: ComponentPickup = hero.swap_candidate if is_instance_valid(hero.swap_candidate) else null
	if cur == null or cur == self or cur._used or d < GameWorld.flat_distance(hero.global_position, cur.global_position):
		hero.swap_candidate = self


func _withdraw_offer(hero: Hero) -> void:
	if hero.swap_candidate == self:
		hero.swap_candidate = null


func _release_swap_offers() -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("actors"):
		var hero := n as Hero
		if hero != null and hero.swap_candidate == self:
			hero.swap_candidate = null
