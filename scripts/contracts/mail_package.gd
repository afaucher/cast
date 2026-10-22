class_name MailPackage
extends Actor
## The client's unopened mail: a taped-up brown cardboard box the crew is free to "intercept". Interactive set
## dressing placed near room entrances (SiteBuilder: 4-6 spots a floor, sometimes stacked 2-3 high; each box
## is its own breakable). Neutral team, immovable, ONE hit of anything breaks it.
##
## NOT PROPERTY DAMAGE: breaking mail never touches Ledger.damage (it is unopened mail nobody wanted).
##
## What breaks it (all end in Actor.apply_damage; any damage at all is enough, see apply_damage):
##   - hero melee, Gasket's spin, monster swings: Combat.melee_arc looks at GameWorld.hittable_in_radius
##   - arrows, Wick's bolt, monster arrows: Projectile / ArrowShot use the same hook
##   - area spells: corn and teeth hit every team, the fireball blast hits TEAM_NEUTRAL, tentacles and Rebar's
##     bowl check the "breakables" group
##   - any actor SHOVED into it (a physics-frame contact scan, like PricedProp)
## Hero melee and arrows do not hit priced props or employees on purpose; only the group "breakables" is added.
##
## CONTENTS, rolled once when it breaks (roll_contents, pure so tests can check the table):
##   skulls 20% / yogurt 20% / pickles 20%  decorative bits spill out (PackageSpill), gone after 30 s
##   component 25%  a random spell's ComponentPickup (it does not count toward SpellComponents.FLOOR_DROP_CAP)
##   crypto 15%     $200-$2,000 earned on the invoice as "Unclaimed crypto"
## Every break also bursts into cardboard chips and leaves flattened flaps (and a torn-paper grime mark).
##
## Usage:
##   var m := MailPackage.spawn(Vector2(x, z), {"size": "medium", "yaw": 30.0, "level": 0, "lift": 0.0, "seed": 7})
##   m.apply_damage(1.0, hero)                    # breaks it; m.contents says what was inside
##   MailPackage.roll_contents(rng)               # "skulls" | "yogurt" | "pickles" | "component" | "crypto"

## The box broke: what was inside and who did it (null if unknown). Money / pickup already handed out.
signal broken(pkg: MailPackage, culprit: Node, contents: String)

const GROUP := "breakables"
const BOX_HP := 10.0
const LIFE_AFTER_BREAK := 1.0           ## the dead actor lingers this long (the spill is its own node), then goes
const SHOVE_REACH := 0.12               ## an actor being shoved breaks it from this far inside its edge
const FALL_GRAVITY := 14.0              ## a box left hanging by a broken one below drops with this
const CRYPTO_LABEL := "Unclaimed crypto"
const CRYPTO_MIN := 200
const CRYPTO_MAX := 2000
const CRYPTO_ROUND := 10
const CRYPTO_COLOR := Color(0.45, 1.0, 0.62)

## Contents in table order and their odds (sum 1.0).
const TABLE := [
	["skulls", 0.20], ["yogurt", 0.20], ["pickles", 0.20], ["component", 0.25], ["crypto", 0.15],
]
const DECORATIVE: Array[String] = ["skulls", "yogurt", "pickles"]

var size_kind := "medium"
var stack_index := 0                    ## 0 = on the floor, 1 = on the box below it ...
var contents := ""                      ## rolled when it breaks ("" before)
var forced_contents := ""               ## tests / the lab: break with exactly this inside
var crypto_amount := 0                  ## dollars earned (contents "crypto")
var component_id := ""                  ## spell id of the dropped component (contents "component")
var pickup: ComponentPickup = null      ## ... and the pickup it left
var spill: PackageSpill = null          ## the bits that fell out (decorative contents and flaps)
var broke := false

var _rng := RandomNumberGenerator.new()
var _model: Node3D = null
var _lift := 0.0                        ## height of the model above the actor's ground point (a stack)
var _below: WeakRef = null              ## the box this one sits on
var _fall_v := 0.0
var _last_source: WeakRef = null


# --- Spawning / helpers ------------------------------------------------------------------

## The contents of a box that breaks now, drawn with `rng` (pure: nothing else is touched).
static func roll_contents(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	for e: Array in TABLE:
		roll -= float(e[1])
		if roll < 0.0:
			return String(e[0])
	return String((TABLE[TABLE.size() - 1] as Array)[0])


## A crypto windfall: $200-$2,000 in whole $10s.
static func roll_crypto(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(CRYPTO_MIN / CRYPTO_ROUND, CRYPTO_MAX / CRYPTO_ROUND) * CRYPTO_ROUND


## A random castable spell for a component drop.
static func roll_component(rng: RandomNumberGenerator) -> String:
	var ids := SpellBook.ids()
	return ids[rng.randi_range(0, ids.size() - 1)]


## Spawn a box standing at world X/Z `pos2`. opts (all optional): `size` ("small" | "medium" | "long"), `yaw`
## degrees (front = +Z), `lift` (height above the floor: a box in a stack), `below` (the MailPackage it sits on),
## `stack` (index in the stack), `seed` (its private dice: model variation, contents, the spill), `contents`
## (force what is inside). Null without a world.
static func spawn(pos2: Vector2, opts: Dictionary = {}) -> MailPackage:
	if GameWorld.root == null:
		push_warning("MailPackage.spawn: no world")
		return null
	var m := MailPackage.new()
	m.setup(opts)
	var at := Vector3(pos2.x, 0.0, pos2.y)
	var map := GameWorld.map
	if map != null:
		var g := map.ground_height(at)
		if not is_nan(g):
			at.y = g
	GameWorld.spawn(m, at)
	m.snap_to_ground()
	return m


func setup(opts: Dictionary = {}) -> void:
	size_kind = String(opts.get("size", "medium"))
	if not PackageModels.SIZES.has(size_kind):
		size_kind = "medium"
	stack_index = int(opts.get("stack", 0))
	_lift = float(opts.get("lift", 0.0))
	var below: MailPackage = opts.get("below", null) as MailPackage
	if below != null:
		_below = weakref(below)
	forced_contents = String(opts.get("contents", ""))
	var seed_value: int = int(opts["seed"]) if opts.has("seed") else GameWorld.rng.randi()
	_rng.seed = seed_value
	name = "MailPackage"
	rotation_degrees.y = float(opts.get("yaw", 0.0))
	var dims := PackageModels.size_of(size_kind)
	radius = clampf(maxf(dims.x, dims.z) * 0.5 * 0.82, 0.3, 0.55)
	set_meta("model_seed", seed_value)


func _init() -> void:
	team = GameWorld.TEAM_NEUTRAL
	shove_mult = 0.0
	max_hp = BOX_HP
	display_name = "Mail package"
	add_to_group(GROUP)
	# one hit and it is gone: a floating "10" over a bursting box is just noise
	set_meta("fx_hit_feedback", true)


## Who may write each var (see Net); Actor's come from super(). Mail is host-owned: the host rolls the
## contents when a box breaks and everyone else is told the result.
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"size_kind": Net.SPAWN, "stack_index": Net.SPAWN, "forced_contents": Net.SPAWN,
		"_below": Net.SPAWN,               # travels as an entity id
		"contents": Net.OWNER, "crypto_amount": Net.OWNER, "component_id": Net.OWNER, "broke": Net.OWNER,
		"_lift": Net.OWNER,                # drops when the box below breaks
		"_rng": Net.PRIVATE,               # the host's dice for the contents; the result is replicated
		"_fall_v": Net.PRIVATE, "_last_source": Net.PRIVATE,
		"pickup": Net.PRIVATE,             # the pickup is its own host-owned entity
		"_model": Net.LOCAL, "spill": Net.LOCAL,
	})
	return f


# --- Lifecycle ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	_model = PackageModels.box(size_kind, int(get_meta("model_seed", 1)) & 0xFFFF)
	_model.position.y = _lift
	add_child(_model)
	damaged.connect(_on_damaged)


func _physics_process(delta: float) -> void:
	if dead:
		return
	_settle(delta)
	_check_shove_contacts()


## A copy's per-frame work on a client (M3; NetObjects calls it): a box whose support broke still drops onto what is
## under it (the breaks are the host's, the settling is the same everywhere).
func net_tick(delta: float) -> void:
	_settle(delta)


## Total height (the model's top) above the floor.
func top_height() -> float:
	return _lift + PackageModels.height_of(size_kind)


func model_lift() -> float:
	return _lift


func last_culprit() -> Node:
	if _last_source == null:
		return null
	return _last_source.get_ref() as Node


## Stacked boxes: when the box below breaks (or is gone) this one drops to what is under it.
func _settle(delta: float) -> void:
	if _below == null and _lift <= 0.0:
		return
	var support := _support()
	if _lift <= support + 0.001:
		_lift = support
		_fall_v = 0.0
	else:
		_fall_v += FALL_GRAVITY * delta
		_lift = maxf(support, _lift - _fall_v * delta)
		if _lift <= support:
			_fall_v = 0.0
			var dust: Array[Color] = [Color(0.8, 0.72, 0.58), Color(0.6, 0.52, 0.42)]
			Fx.burst(global_position + Vector3.UP * (support + 0.05), dust, 5, 1.4, 0.06, 0.35, 2.0, Vector3.UP, 70.0, false)
	if _model != null:
		_model.position.y = _lift
	if _lift <= 0.0:
		_below = null   # on the floor now: nothing to wait for


## Top of what this box rests on: the nearest box below that still stands (a broken one is skipped), else the floor.
func _support() -> float:
	var b: MailPackage = null
	if _below != null:
		b = _below.get_ref() as MailPackage
	var relinked := false
	while b != null and b.dead:
		b = b._below.get_ref() as MailPackage if b._below != null else null
		relinked = true
	if relinked:
		_below = weakref(b) if b != null else null
	return b.top_height() if b != null else 0.0


## Any hit breaks it, whatever the damage: a swing that does 0.5 or a blast that does 40.
func apply_damage(amount: float, source: Node = null) -> float:
	if dead or amount <= 0.0:
		return 0.0
	return super.apply_damage(maxf(amount, hp), source)


func _on_damaged(_amount: float, source: Node) -> void:
	if source != null and is_instance_valid(source):
		_last_source = weakref(source)


## Actors shoved into the box break it. Cheap: one scan of the actor group per physics frame.
func _check_shove_contacts() -> void:
	for n in get_tree().get_nodes_in_group("actors"):
		var a := n as Actor
		if a == null or a == self or a.dead or not a.is_shoved() or not Net.owns(a):   # (M4: the slider's machine sees it)
			continue
		if GameWorld.flat_distance(a.global_position, global_position) > radius + a.radius - SHOVE_REACH:
			continue
		if a.global_position.y - global_position.y > top_height():
			continue
		var src: Node = a.shove_source()
		if src == null:
			src = a    # an unknown shover: the thing that was thrown is to blame
		Net.hit_object(self, 1.0, src)
		return


## A client (M4): run the contact check for this machine's own sliders on the host's copy (NetObjects).
func net_contacts() -> void:
	if not dead:
		_check_shove_contacts()


# --- The net-object contract (NetObjects) -------------------------------------------------------------------------
# No late-join rows: an opened box is a gone id (NetJoin), and its prize a pickup (replayed as one).

## Host: the break goes to everyone as `obj.break {id, c, cr, cid}`, with what only the host rolled: the contents, the
## crypto and the component.
func net_link(objects: NetObjects, id: int) -> void:
	objects.link(broken, _net_broken.bind(objects, id))


func _net_broken(_pkg: MailPackage, _culprit: Node, rolled: String, objects: NetObjects, id: int) -> void:
	objects.tell("obj.break", {"id": id, "c": rolled, "cr": crypto_amount, "cid": component_id})
	objects.count("breaks")


## Client: the host opened it (obj.break): it breaks here with the host's contents.
func net_event(kind: String, data: Dictionary, objects: NetObjects) -> void:
	if kind != "obj.break" or dead:
		return
	forced_contents = str(data.get("c", ""))
	crypto_amount = int(data.get("cr", 0))
	component_id = str(data.get("cid", ""))
	objects.copy_broke(self)


# --- Breaking ----------------------------------------------------------------------------

func _on_death() -> void:
	broke = true
	var culprit := last_culprit()
	contents = forced_contents if forced_contents != "" else roll_contents(_rng)
	var here := global_position + Vector3.UP * _lift
	var away := Vector2(sin(rotation.y), cos(rotation.y))   # the box faces away from its wall: the spill leans that way
	_break_fx(here)
	_hand_out(contents, here, culprit)
	var spill_contents := contents if DECORATIVE.has(contents) else ""
	spill = PackageSpill.burst(global_position, spill_contents, _rng.randi(), away, _lift + PackageModels.height_of(size_kind) * 0.6)
	Grime.mark(Grime.PAPER, global_position, 1.0)   # torn packing paper that fades after 30 s (no-op without a layer)
	if _model != null:
		_model.queue_free()
		_model = null
	broken.emit(self, culprit, contents)
	if is_inside_tree():
		get_tree().create_timer(LIFE_AFTER_BREAK).timeout.connect(queue_free)
	else:
		queue_free()


## The prize: a component pickup or crypto cash (decorative contents are the spill's job).
## Online (M3) only the owner (the host) rolls and hands out: a client's copy was told the contents, the component and
## the crypto by the host's break event, and only shows them (the pickup and the money come from the host).
func _hand_out(what: String, here: Vector3, culprit: Node) -> void:
	var owner := Net.owns(self)
	match what:
		"component":
			if owner:
				component_id = roll_component(_rng)
				# ComponentPickup.drop does not touch GameWorld.floor_drops: mail is not a monster drop
				pickup = ComponentPickup.drop(component_id, SpellComponents.PICKUP_CHARGES, global_position)
			if component_id == "":
				return
			var sparks: Array[Color] = [SpellBook.color_of(component_id).lightened(0.4), Color.WHITE]
			Fx.burst(here + Vector3.UP * 0.3, sparks, 10, 2.2, 0.06, 0.5, -0.5, Vector3.UP, 70.0)
		"crypto":
			if owner:
				crypto_amount = roll_crypto(_rng)
				Ledger.earn(CRYPTO_LABEL, crypto_amount, culprit)
			Fx.number(here + Vector3(0, top_height() - _lift + 0.7, 0), "+%s crypto" % PricedProp.money(crypto_amount), CRYPTO_COLOR, 1.1)
			var coins: Array[Color] = [Color(0.45, 1.0, 0.62), Color(1.0, 0.9, 0.4), Color.WHITE]
			Fx.burst(here + Vector3.UP * 0.3, coins, 14, 3.4, 0.06, 0.7, 7.0, Vector3.UP, 80.0)


## A short pop: cardboard chips fly, a puff of dust.
func _break_fx(here: Vector3) -> void:
	Sfx.play_at("mailbox_break", here)
	var h := PackageModels.height_of(size_kind)
	PropDebris.burst(here + Vector3.UP * h * 0.5, PackageModels.palette(), 8, 0.55)
	var dust: Array[Color] = [Color(0.82, 0.74, 0.6), Color(0.62, 0.54, 0.42)]
	Fx.burst(here + Vector3.UP * h * 0.4, dust, 10, 2.4, 0.09, 0.45, 1.5, Vector3.UP, 85.0, false)
	Fx.shake(0.04)
