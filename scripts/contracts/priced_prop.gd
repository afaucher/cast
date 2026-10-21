class_name PricedProp
extends Actor
## A piece of the client's property with a price tag: wine racks and a gold toilet in a luxury
## bunker, a doomsday console and a torture rack in a villain lair. Neutral team, immovable, and
## fragile to anything area-based.
##
## MONEY RULE: partial damage costs nothing. Only BREAKING a prop (HP <= 0) costs money, and it
## costs the FULL price, recorded exactly once as `Ledger.damage(display_name, price, culprit)`.
## The culprit is the last damage source (the hero whose spell, shove or boulder finished it).
## A prop that is dented but survives is free, so chaos stings only when something actually goes.
##
## Damage sources (all go through Actor.apply_damage with the culprit as `source`):
##   - area effects that hit team -1: corn, teeth pops, tentacle shoves, Combat.explode
##   - fireball: its explosion also hits TEAM_NEUTRAL (spell_book.gd)
##   - Rebar's bowl: damage * BowlBoulder.PROP_DAMAGE_MULT to each prop it rolls through
##   - any actor SHOVED into it: damage scales with the shove (SHOVE_DAMAGE_PER_UNIT per world unit
##     of shove distance, less once it has slowed), credited to whoever caused the shove
##   - arrows and bolts that run into it (Wick's arrows, the hero bolt, an archer's arrow, in a fight or at target
##     practice: Projectile.hits_props, user 2026-10-18 "all arrows hit props"), credited to the shooter
##   - a hero's melee swing that reaches it (Combat.melee_arc: Wick's bow bash, Gasket's hammer and spin, Rebar's fist;
##     AI allies too, which avoid swinging at a target with a prop in the arc), credited to the hero (user, 2026-10-18:
##     "let player attacks break them"). Employees are still never hit by the crew's weapons
##
## Explosive props (oil drum, gas cylinders, propane tank, battery pack) are rows of the same TABLE with site "hazard":
## spawn() makes them an ExplosiveProp (a fuse, then a blast: docs/design/hazards.md), and no site's catalog has them.
##
## Usage:
##   var p := PricedProp.spawn(cell, "gold_toilet", {})
##   PricedProp.catalog("bunker")       # -> ["wine_rack", "wine_barrel", ...]
##   p.price, p.display_name, p.broken  # signal broken(prop, culprit)

## The prop broke: the Ledger line has been recorded.
signal broken(prop: PricedProp, culprit: Node)

const DEFAULT_YAW := 15.0              ## turns the +Z front toward the iso camera (yaw 45) with a three-quarter view
const TAG_RANGE := 3.0                 ## a hero this close (centre to centre) shows the price tag
const TAG_FADE_SPEED := 5.0            ## alpha per second
const SHOVE_DAMAGE_PER_UNIT := 10.0    ## a 2.5-unit shove at full speed does 25
const SHOVE_MIN_DAMAGE := 2.0
const TAG_COLOR := Color(1.0, 0.86, 0.45)
const TAG_OUTLINE := Color(0.12, 0.06, 0.03)
const MONEY_RED := Color(1.0, 0.36, 0.3)
const LIFE_AFTER_BREAK := 3.0           ## a prop without rubble lingers this long, then goes
const GROUP := "priced_props"           ## arrows and bolts find props here (GameWorld.props_in_radius)

## One table for everything: display name, price (dollars), HP (fragility; corn does 60, fireball
## 40, a hard shove ~25), footprint radius and site. Order here = catalog order.
## Placement (RoomThemes): "place" = wall (back to the nearest wall) or corner (tucked into a concave corner);
## "orient" = away_from_wall (faces into the room along the wall's normal), face_center (toward the room's centre)
## or face_entrance (toward the room's main door); "foot" = the footprint (lateral x forward, world units).
## The front of every model is +Z, so a prop at yaw 0 faces +Z.
## The look (PropModels): "height" (the model's top: tag and fx placement), "model" (the PropModels builder, a static
## func(s: LowPoly.Soup) that adds the merged mesh), "palette" (the colours its shards are painted with) and optionally
## "extra" (a PropModels static func() -> Node3D added beside the body, e.g. the brazier's embers).
## Adding a prop is one row here plus its builder in PropModels (tests/test_priced_prop.gd checks every row).
const TABLE := {
	"wine_rack": {"name": "Wine rack", "price": 1200, "hp": 45.0, "radius": 0.7, "site": "bunker", "place": "wall", "orient": "away_from_wall", "foot": Vector2(1.4, 0.6),
		"height": 1.7, "model": "_wine_rack", "palette": [PropModels.WOOD, PropModels.WOOD_DK, PropModels.BOTTLE_GREEN, PropModels.BOTTLE_RED]},
	"wine_barrel": {"name": "Vintage 1787 wine barrel", "price": 4000, "hp": 85.0, "radius": 0.68, "site": "bunker", "place": "wall", "orient": "away_from_wall", "foot": Vector2(1.35, 1.25),
		"height": 1.25, "model": "_wine_barrel", "palette": [PropModels.WOOD, PropModels.WOOD_DK, PropModels.GOLD, PropModels.BOTTLE_RED]},
	"marble_statue": {"name": "Marble statue", "price": 8000, "hp": 110.0, "radius": 0.58, "site": "bunker", "place": "corner", "orient": "face_center", "foot": Vector2(1.1, 1.1),
		"height": 2.2, "model": "_marble_statue", "palette": [PropModels.MARBLE, PropModels.MARBLE_DK, PropModels.GOLD]},
	"gold_toilet": {"name": "Gold toilet", "price": 15000, "hp": 130.0, "radius": 0.55, "site": "bunker", "place": "wall", "orient": "away_from_wall", "foot": Vector2(1.05, 1.05),
		"height": 1.35, "model": "_gold_toilet", "palette": [PropModels.GOLD, PropModels.GOLD_DK, Color(1.0, 0.92, 0.55), PropModels.VELVET]},
	"projector": {"name": "Home-cinema projector", "price": 2500, "hp": 35.0, "radius": 0.5, "site": "bunker", "place": "wall", "orient": "away_from_wall", "foot": Vector2(0.9, 0.9),
		"height": 1.35, "model": "_projector", "palette": [PropModels.IRON, PropModels.IRON_LT, Color(0.5, 0.85, 1.0), PropModels.WOOD_DK]},
	"zen_fountain": {"name": "Zen fountain", "price": 900, "hp": 55.0, "radius": 0.72, "site": "bunker", "place": "corner", "orient": "face_center", "foot": Vector2(1.7, 1.7),
		"height": 1.15, "model": "_zen_fountain", "palette": [PropModels.STONE, Color(0.35, 0.36, 0.4), Color(0.4, 0.85, 0.85)]},
	"server_rack": {"name": "Server rack", "price": 3000, "hp": 70.0, "radius": 0.5, "site": "bunker", "place": "wall", "orient": "away_from_wall", "foot": Vector2(0.9, 0.8),
		"height": 1.95, "model": "_server_rack", "palette": [PropModels.IRON, PropModels.IRON_LT, Color(0.3, 1.0, 0.5), Color(1.0, 0.6, 0.2)]},
	"crystal_lamp": {"name": "Crystal lamp", "price": 600, "hp": 25.0, "radius": 0.5, "site": "bunker", "place": "corner", "orient": "face_center", "foot": Vector2(1.1, 1.1),
		"height": 1.45, "model": "_crystal_lamp", "palette": [Color(0.85, 0.55, 1.0), Color(1.0, 0.7, 0.95), PropModels.GOLD, Color(0.6, 0.35, 0.9)]},
	"treadmill": {"name": "Smart treadmill", "price": 2800, "hp": 75.0, "radius": 0.55, "site": "bunker", "place": "wall", "orient": "away_from_wall", "foot": Vector2(0.85, 1.9),
		"height": 1.5, "model": "_treadmill", "palette": [PropModels.IRON, PropModels.IRON_LT, PropModels.VELVET, Color(0.3, 0.9, 1.0)]},
	"doomsday_console": {"name": "Doomsday console", "price": 20000, "hp": 140.0, "radius": 0.78, "site": "lair", "place": "wall", "orient": "face_entrance", "foot": Vector2(1.5, 1.0),
		"height": 1.75, "model": "_doomsday_console", "palette": [PropModels.IRON, PropModels.IRON_LT, Color(1.0, 0.2, 0.15), Color(0.95, 0.8, 0.2)]},
	"torture_rack": {"name": "Torture rack", "price": 1500, "hp": 80.0, "radius": 0.75, "site": "lair", "place": "wall", "orient": "away_from_wall", "foot": Vector2(1.6, 0.9),
		"height": 0.95, "model": "_torture_rack", "palette": [PropModels.WOOD_DK, PropModels.WOOD, PropModels.IRON, Color(0.7, 0.62, 0.45)]},
	"specimen_vat": {"name": "Specimen vat", "price": 5000, "hp": 45.0, "radius": 0.68, "site": "lair", "place": "corner", "orient": "face_center", "foot": Vector2(1.5, 1.5),
		"height": 2.0, "model": "_specimen_vat", "palette": [PropModels.IRON, Color(0.3, 1.0, 0.55), Color(0.2, 0.55, 0.4), Color(0.45, 0.2, 0.6)]},
	"villain_throne": {"name": "Villain throne", "price": 9000, "hp": 100.0, "radius": 0.7, "site": "lair", "place": "wall", "orient": "face_entrance", "foot": Vector2(1.1, 1.2),
		"height": 2.35, "model": "_villain_throne", "palette": [PropModels.OBSIDIAN, PropModels.VELVET, PropModels.GOLD, Color(0.9, 0.88, 0.8)]},
	"shark_tank": {"name": "Shark tank", "price": 7000, "hp": 60.0, "radius": 0.78, "site": "lair", "place": "wall", "orient": "away_from_wall", "foot": Vector2(1.6, 1.0),
		"height": 1.6, "model": "_shark_tank", "palette": [PropModels.IRON, Color(0.3, 0.8, 0.95), Color(0.2, 0.55, 0.7), Color(0.6, 0.65, 0.72)]},
	"henchman_locker": {"name": "Henchman locker", "price": 300, "hp": 70.0, "radius": 0.62, "site": "lair", "place": "wall", "orient": "away_from_wall", "foot": Vector2(1.3, 0.6),
		"height": 1.75, "model": "_henchman_locker", "palette": [Color(0.38, 0.42, 0.5), PropModels.IRON, Color(0.85, 0.2, 0.15)]},
	"evil_portrait": {"name": "Evil portrait", "price": 2000, "hp": 30.0, "radius": 0.55, "site": "lair", "place": "wall", "orient": "away_from_wall", "foot": Vector2(1.1, 1.0),
		"height": 2.0, "model": "_evil_portrait", "palette": [PropModels.GOLD, PropModels.GOLD_DK, Color(0.45, 0.07, 0.1), PropModels.OBSIDIAN]},
	"brazier": {"name": "Brazier", "price": 400, "hp": 55.0, "radius": 0.5, "site": "lair", "place": "corner", "orient": "face_center", "foot": Vector2(1.1, 1.1),
		"height": 1.15, "model": "_brazier", "extra": "_embers", "palette": [PropModels.IRON, PropModels.IRON_LT, Color(1.0, 0.55, 0.12)]},
	# Explosive props (ExplosiveProp: a fuse, then a blast; docs/design/hazards.md). Site "hazard": never in a site's
	# catalog; the room themes place them (RoomThemeDefs "hazards", HazardPlanner.plan). Each one's row also carries
	# "blast" (ExplosiveProp: radius in world units, damage and shove at the centre, fuse in seconds; required, a hazard
	# without it is an error) and "fuse_point" (PropModels.fuse_point: where the lit fuse sparks, model space).
	"oil_drum": {"name": "Oil drum", "price": 800, "hp": 40.0, "radius": 0.45, "site": "hazard", "place": "wall", "orient": "away_from_wall", "foot": Vector2(0.85, 0.85),
		"height": 1.05, "model": "_oil_drum", "palette": [PropModels.DRUM_RED, PropModels.DRUM_RED_DK, PropModels.IRON, PropModels.HAZARD_YELLOW],
		"blast": {"radius": 3.0, "damage": 45.0, "shove": 2.6, "fuse": 1.3}, "fuse_point": Vector3(0.16, 1.06, 0.12)},
	"gas_cylinders": {"name": "Gas cylinders", "price": 1800, "hp": 35.0, "radius": 0.5, "site": "hazard", "place": "wall", "orient": "away_from_wall", "foot": Vector2(1.15, 0.5),
		"height": 1.45, "model": "_gas_cylinders", "palette": [PropModels.CYL_GREEN, PropModels.CYL_MAROON, PropModels.CYL_BLUE, PropModels.IRON_LT],
		"blast": {"radius": 3.2, "damage": 50.0, "shove": 2.8, "fuse": 1.0}, "fuse_point": Vector3(0.0, 1.42, 0.0)},
	"propane_tank": {"name": "Propane tank", "price": 1200, "hp": 45.0, "radius": 0.6, "site": "hazard", "place": "wall", "orient": "away_from_wall", "foot": Vector2(1.4, 0.8),
		"height": 1.2, "model": "_propane_tank", "palette": [PropModels.TANK_WHITE, PropModels.IRON, Color(0.85, 0.2, 0.15), PropModels.HAZARD_YELLOW],
		"blast": {"radius": 3.4, "damage": 55.0, "shove": 3.0, "fuse": 1.2}, "fuse_point": Vector3(0.0, 1.19, 0.0)},
	"battery_pack": {"name": "Server battery pack", "price": 6500, "hp": 60.0, "radius": 0.52, "site": "hazard", "place": "wall", "orient": "away_from_wall", "foot": Vector2(1.0, 0.7),
		"height": 1.52, "model": "_battery_pack", "palette": [PropModels.OBSIDIAN, PropModels.IRON, Color(1.0, 0.55, 0.12), Color(0.3, 1.0, 0.5)],
		"blast": {"radius": 2.8, "damage": 40.0, "shove": 2.4, "fuse": 1.5}, "fuse_point": Vector3(0.28, 1.51, 0.18)},
	# The sewer's props (docs/design/sewer-concept.md, phase 1: --sewer only). Site "sewer": no site's catalog has them. The
	# electrical panel breaks to any hit (HP 1) and drops the live wire into the water (LiveWire).
	"sump_pump": {"name": "Sump pump", "price": 3500, "hp": 70.0, "radius": 0.6, "site": "sewer", "place": "wall", "orient": "away_from_wall", "foot": Vector2(1.2, 0.85),
		"height": 1.7, "model": "_sump_pump", "palette": [Color(0.22, 0.4, 0.55), PropModels.IRON, Color(0.5, 0.27, 0.14), PropModels.HAZARD_YELLOW]},
	"electrical_panel": {"name": "Electrical panel", "price": 250, "hp": 1.0, "radius": 0.35, "site": "sewer", "place": "wall", "orient": "away_from_wall", "foot": Vector2(0.7, 0.35),
		"height": 1.8, "model": "_electrical_panel", "palette": [Color(0.55, 0.57, 0.55), PropModels.IRON, PropModels.HAZARD_YELLOW, Color(1.0, 0.95, 0.55)]},
}
const HAZARD_SITE := "hazard"

var kind := ""
var price := 0
var site := ""
var broke := false
var rubble_enabled := true
var tag_label: Label3D = null

var _model: Node3D = null
var _rubble: Node3D = null
var _last_source: WeakRef = null
var _tag_target := false
var _tag_tick := 0
var _contacts := {}               ## shoved actors already counted against this prop
var _wobble: Tween = null


# --- Catalog / helpers -----------------------------------------------------------------

## Prop kinds for a site type ("bunker" or "lair"), in table order. Empty for anything else.
static func catalog(site_type: String) -> Array[String]:
	var out: Array[String] = []
	for k: String in TABLE.keys():
		if String((TABLE[k] as Dictionary)["site"]) == site_type:
			out.append(k)
	return out


static func is_kind(k: String) -> bool:
	return TABLE.has(k)


## An explosive prop (ExplosiveProp): placed by the room themes, never in a site's catalog.
static func is_hazard(k: String) -> bool:
	return TABLE.has(k) and String((TABLE[k] as Dictionary)["site"]) == HAZARD_SITE


## Every explosive kind, in table order.
static func hazard_kinds() -> Array[String]:
	return catalog(HAZARD_SITE)


## {place, orient, foot, radius} of a kind (see TABLE): where it goes and which way it faces.
static func placement(k: String) -> Dictionary:
	var d: Dictionary = TABLE.get(k, {})
	return {
		"place": String(d.get("place", "wall")), "orient": String(d.get("orient", "away_from_wall")),
		"foot": d.get("foot", Vector2(1.0, 1.0)), "radius": float(d.get("radius", 0.6)),
	}


static func price_of(k: String) -> int:
	return int((TABLE[k] as Dictionary)["price"]) if TABLE.has(k) else 0


static func name_of(k: String) -> String:
	return String((TABLE[k] as Dictionary)["name"]) if TABLE.has(k) else k


## 4000 -> "$4,000".
static func money(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if amount < 0 else "") + "$" + digits + out


## Spawn a prop standing on `cell`. opts (all optional): `yaw` degrees (default 15: front toward the
## iso camera, a little turned so its side shows; SiteBuilder passes the themed pose's yaw: front = +Z, so
## the prop faces (sin yaw, cos yaw)), `pos` (Vector2 world X/Z: stand there instead of the cell centre, e.g.
## pushed up against a wall), `hp_mult`, `rubble` (false = vanish when broken). Null for an unknown kind.
static func spawn(cell: Vector2i, kind_id: String, opts: Dictionary = {}) -> PricedProp:
	if not TABLE.has(kind_id) or GameWorld.root == null:
		push_warning("PricedProp.spawn: unknown kind '%s' or no world" % kind_id)
		return null
	var p: PricedProp = ExplosiveProp.new() if is_hazard(kind_id) else PricedProp.new()
	p.setup(kind_id, opts)
	var at := Hex.to_world(cell)
	if opts.has("pos"):
		var pp: Vector2 = opts["pos"]
		at = Vector3(pp.x, 0.0, pp.y)
	var level := 0.0
	var map := GameWorld.map
	if map != null:
		var l := map.ground_level(at)
		if not is_nan(l):
			level = l
	GameWorld.spawn(p, Vector3(at.x, level * Hex.LEVEL_HEIGHT, at.z))
	p.snap_to_ground()
	return p


func setup(kind_id: String, opts: Dictionary = {}) -> void:
	var d: Dictionary = TABLE[kind_id]
	kind = kind_id
	name = kind_id.capitalize().replace(" ", "")
	display_name = String(d["name"])
	price = int(d["price"])
	site = String(d["site"])
	max_hp = float(d["hp"]) * float(opts.get("hp_mult", 1.0))
	radius = float(d["radius"])
	rubble_enabled = bool(opts.get("rubble", true))
	rotation_degrees.y = float(opts.get("yaw", DEFAULT_YAW))


func _init() -> void:
	team = GameWorld.TEAM_NEUTRAL
	shove_mult = 0.0
	display_name = "Prop"


# --- Lifecycle --------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	if kind == "":
		return
	_model = PropModels.build(kind)
	add_child(_model)
	_build_tag()
	Fx.attach_hit_feedback(self)
	damaged.connect(_on_damaged)


## Who may write each var (see Net); Actor's come from super(). The host owns props and the
## money they cost, so who broke one is host working state.
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"kind": Net.SPAWN, "price": Net.SPAWN, "site": Net.SPAWN, "rubble_enabled": Net.SPAWN,
		"broke": Net.OWNER,
		"_last_source": Net.PRIVATE,    # the culprit goes into the Ledger line, written on the host
		"_contacts": Net.PRIVATE,       # shoved actors already counted against this prop
		# The price tag fades in near each screen's own heroes.
		"tag_label": Net.LOCAL, "_tag_target": Net.LOCAL, "_tag_tick": Net.LOCAL,
		"_model": Net.LOCAL, "_rubble": Net.LOCAL, "_wobble": Net.LOCAL,
	})
	return f


func _physics_process(_delta: float) -> void:
	if dead:
		return
	_tag_tick += 1
	if _tag_tick % 3 == 0:
		_tag_target = _hero_near()
	_check_shove_contacts()


## A copy's per-frame look on a client (M3; NetObjects calls it): the price tag fades in near this screen's heroes.
func net_tick(_delta: float) -> void:
	_tag_tick += 1
	if _tag_tick % 3 == 0:
		_tag_target = _hero_near()


func _process(delta: float) -> void:
	if tag_label == null:
		return
	var target := 1.0 if _tag_target and not dead else 0.0
	var a := move_toward(tag_label.modulate.a, target, TAG_FADE_SPEED * delta)
	tag_label.modulate.a = a
	tag_label.visible = a > 0.01


## The price tag text: "Vintage 1787 wine barrel – $4,000".
func tag_text() -> String:
	return "%s – %s" % [display_name, money(price)]


## True while the price tag is (fading) in because a hero is close.
func tag_shown() -> bool:
	return _tag_target and not dead


func tag_alpha() -> float:
	return tag_label.modulate.a if tag_label != null else 0.0


func model_height() -> float:
	return PropModels.height(kind)


## The unit X/Z vector the prop's front faces (its yaw: front = +Z).
func facing_vector() -> Vector2:
	var r := deg_to_rad(rotation_degrees.y)
	return Vector2(sin(r), cos(r))


func last_culprit() -> Node:
	if _last_source == null:
		return null
	return _last_source.get_ref() as Node


func _hero_near() -> bool:
	for n in get_tree().get_nodes_in_group("actors"):
		var a := n as Actor
		if a == null or a.dead or a.team != GameWorld.TEAM_HEROES:
			continue
		if GameWorld.flat_distance(a.global_position, global_position) <= TAG_RANGE:
			return true
	return false


func _build_tag() -> void:
	tag_label = Label3D.new()
	tag_label.name = "PriceTag"
	tag_label.text = tag_text()
	tag_label.font_size = 56
	tag_label.pixel_size = 0.0075
	tag_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag_label.no_depth_test = true
	tag_label.shaded = false
	tag_label.render_priority = 15
	tag_label.modulate = Color(TAG_COLOR.r, TAG_COLOR.g, TAG_COLOR.b, 0.0)
	tag_label.outline_modulate = TAG_OUTLINE
	tag_label.outline_size = 14
	tag_label.visible = false
	tag_label.position = Vector3(0, model_height() + 0.55, 0)
	add_child(tag_label)


# --- Damage -------------------------------------------------------------------------------

func _on_damaged(amount: float, source: Node) -> void:
	if source != null and is_instance_valid(source):
		_last_source = weakref(source)
	if dead or hp <= 0.0 or _model == null:
		return
	# A little wobble and a few chips; a prop that is only dented is free, but it should look hurt.
	if _wobble != null and _wobble.is_valid():
		_wobble.kill()
	_model.rotation = Vector3.ZERO
	_wobble = create_tween()
	var tilt := deg_to_rad(clampf(amount * 0.25, 1.5, 6.0))
	_wobble.tween_property(_model, "rotation:z", tilt, 0.05)
	_wobble.tween_property(_model, "rotation:z", -tilt * 0.6, 0.09)
	_wobble.tween_property(_model, "rotation:z", 0.0, 0.1)
	if amount >= 8.0:
		PropDebris.burst(global_position + Vector3.UP * model_height() * 0.5, PropModels.palette(kind), 3, 0.5)


## Actors shoved into the prop damage it. Cheap: scans the actor group once per physics frame. Online (M4) each machine
## checks only the sliders it OWNS (a slide is its owner's), so a player's hero thrown into the prop is seen on that
## player's machine, stops there, and the hit goes to the host (Net.hit_object), which bills the prop once.
func _check_shove_contacts() -> void:
	var seen := {}
	for n in get_tree().get_nodes_in_group("actors"):
		var a := n as Actor
		if a == null or a == self or a.dead or not a.is_shoved() or not Net.owns(a):
			continue
		var id := a.get_instance_id()
		seen[id] = true
		if _contacts.has(id):
			continue
		if GameWorld.flat_distance(a.global_position, global_position) > radius + a.radius + 0.1:
			continue
		if a.global_position.y - global_position.y > model_height():
			continue
		_contacts[id] = true
		_shove_hit(a)
	for id in _contacts.keys():
		if not seen.has(id):
			_contacts.erase(id)


func _shove_hit(a: Actor) -> void:
	var dmg := a.slide_impact() * SHOVE_DAMAGE_PER_UNIT   # (0 while only coasting: no real impact)
	if dmg < SHOVE_MIN_DAMAGE:
		return
	var src: Node = a.shove_source()
	if src == null:
		src = a   # an unknown shover: the thing that hit it is to blame
	# The shoved actor stops dead against the prop, like a wall slam without the damage (its own machine stops it).
	a.stop_slide()
	Net.hit_object(self, dmg, src)


## A client (M4): this prop is the host's copy, so its physics process is off; NetObjects runs the contact check for the
## heroes this machine owns.
func net_contacts() -> void:
	if not dead:
		_check_shove_contacts()


# --- The net-object contract (NetObjects) ---------------------------------------------------------------------------

## Host: a dent goes to everyone as `obj.hurt {id, hp, a}`, the break as `obj.break {id}` (billed once, in the host's
## Ledger: the bill goes out as obj.ledger).
func net_link(objects: NetObjects, id: int) -> void:
	objects.link(damaged, _net_hurt.bind(objects, id))
	objects.link(broken, _net_broken.bind(objects, id))


func _net_hurt(amount: float, _source: Node, objects: NetObjects, id: int) -> void:
	if not dead and hp > 0.0:
		objects.tell("obj.hurt", {"id": id, "hp": hp, "a": amount})


func _net_broken(_prop: PricedProp, _culprit: Node, objects: NetObjects, id: int) -> void:
	objects.tell("obj.break", {"id": id})
	objects.count("breaks")


## Client: the host's dent (obj.hurt: its HP and the wobble) or break (obj.break).
func net_event(kind: String, data: Dictionary, objects: NetObjects) -> void:
	if dead:
		return
	match kind:
		"obj.hurt":
			hp = float(data.get("hp", hp))
			_on_damaged(float(data.get("a", 0.0)), null)
		"obj.break":
			objects.copy_broke(self)


## Host: a dented prop for a late joiner, `dents` [id, hp] (an obj.hurt replay). A broken one is a gone id (NetJoin).
func late_join_state(_objects: NetObjects, id: int) -> Dictionary:
	if dead or hp >= max_hp - 0.001:
		return {}
	return {"dents": [id, hp]}


func apply_late_join(section: String, row: Array, _objects: NetObjects) -> void:
	if section == "dents" and row.size() >= 2 and not dead:
		hp = float(row[1])


# --- Breaking ------------------------------------------------------------------------------

func _on_death() -> void:
	broke = true
	var culprit := last_culprit()
	Ledger.damage(display_name, price, culprit)   # (online the host bills it; a client's Ledger mirrors the host's)
	broken.emit(self, culprit)
	_break_fx()
	if _model != null:
		_model.queue_free()
		_model = null
	if tag_label != null:
		tag_label.queue_free()
		tag_label = null
	if rubble_enabled:
		_rubble = PropModels.rubble(kind)
		add_child(_rubble)
	else:
		get_tree().create_timer(LIFE_AFTER_BREAK).timeout.connect(queue_free)



func _break_fx() -> void:
	var c := global_position
	var h := model_height()
	var big := clampf(float(price) / 15000.0, 0.0, 1.0)
	PropDebris.burst(c + Vector3.UP * h * 0.45, PropModels.palette(kind), 12 + int(10.0 * big), 0.9 + 0.5 * big)
	var dust: Array[Color] = [Color(0.8, 0.72, 0.58), Color(0.55, 0.48, 0.4)]
	Fx.burst(c + Vector3.UP * 0.4, dust, 18, 3.2, 0.17, 0.75, 1.5, Vector3.UP, 85.0, false)
	var sparkle: Array[Color] = [Color(1.0, 0.95, 0.7), Color(1.0, 0.8, 0.3), Color(1.0, 0.6, 0.2)]
	Fx.burst(c + Vector3.UP * h * 0.5, sparkle, 14 + int(18.0 * big), 4.0, 0.05, 1.0, 5.0, Vector3.UP, 120.0)
	Fx.ring(c, 1.1 + 0.5 * big, Color(1.0, 0.8, 0.3, 0.6), 0.4, 0.0, false, 0.25)
	Fx.number(c + Vector3(0, h + 0.5, 0), "-" + money(price), MONEY_RED, 0.95 + 0.4 * big)
	Fx.shake(0.1 + 0.3 * big)
