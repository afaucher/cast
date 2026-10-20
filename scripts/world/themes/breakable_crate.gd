class_name BreakableCrate
extends Actor
## A wooden crate stack of the room themes (DecorProp kinds in RoomThemeDefs.BREAKABLE_DECOR) that the crew can smash.
## It is the invisible walk-blocking circle of the piece (a neutral, immovable Actor like DecorBlocker, so heroes and
## monsters walk around it) AND a breakable: it joins the group "breakables" like a MailPackage, so hero melee,
## arrows, Wick's bolt, Gasket's spin, corn, the fireball blast, tentacles, Rebar's bowl and anything shoved into it
## break it. ONE hit of anything is enough.
##
## Breaking leaves wooden debris (PropDebris chips and a PackageSpill of planks that shrink away 30 s later, plus a
## scuffed Grime mark), removes the model and every blocker circle of the piece, so it no longer blocks movement.
## It has NO contents and NO loot, and it is NOT property damage: nothing here touches Ledger.
##
## Networking (networking.md, "host-arbitrated world object"): the crates come from the floor plan, so every
## machine builds the same ones; the break is the event. The host decides it, `broke` travels, and each machine
## plays the debris itself (cosmetic, seeded from the crate's spot, never GameWorld.rng).

## The crate broke: who did it (null if unknown).
signal broken(crate: BreakableCrate, culprit: Node)

const GROUP := "breakables"
const CRATE_HP := 10.0
const LIFE_AFTER_BREAK := 1.0           ## the dead actor lingers this long (the spill is its own node), then goes
const SHOVE_REACH := 0.12               ## an actor being shoved breaks it from this far inside its edge

## Debris colours per decor kind (the chips thrown when it breaks); anything else uses the plank colours.
const WOOD_CHIPS: Array[Color] = [Color(0.48, 0.29, 0.15), Color(0.28, 0.16, 0.09), Color(0.55, 0.36, 0.2), Color(0.75, 0.78, 0.82)]

var kind := ""
var broke := false
var spill: PackageSpill = null          ## the planks that fell out
var partners: Array[DecorBlocker] = []  ## the piece's other blocker circles (a wide crate row), freed with it
var model: Node3D = null                ## the piece's model (DecorProp's), removed when it breaks
var crate_height := 1.0                 ## how tall it stands (shoves over the top do not break it)
var debris_seed := 1                    ## cosmetic: the planks' dice, derived from where it stands

var _last_source: WeakRef = null


func _init() -> void:
	team = GameWorld.TEAM_NEUTRAL
	shove_mult = 0.0
	max_hp = CRATE_HP
	display_name = "Crate"
	add_to_group(GROUP)
	# one hit and it is gone: a floating number over a bursting crate is just noise
	set_meta("fx_hit_feedback", true)


## Who may write each var (see Net); Actor's come from super(). Crates are host-owned world objects: the same on every
## machine from the plan, and the break is an event the host sends.
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"kind": Net.SPAWN, "crate_height": Net.SPAWN, "debris_seed": Net.SPAWN,
		"partners": Net.SPAWN,             # built from the same plan on every machine
		"broke": Net.OWNER,                # the break event
		"_last_source": Net.PRIVATE,       # credit for the culprit, resolved where the hit was applied
		"model": Net.LOCAL, "spill": Net.LOCAL,
	})
	return f


## Configure before it enters the tree. `radius` is the blocker circle; `piece_model` is hidden when it breaks.
func setup(decor_kind: String, piece_model: Node3D, circle_radius: float, height: float, extra_circles: Array[DecorBlocker], at: Vector2) -> void:
	kind = decor_kind
	model = piece_model
	radius = circle_radius
	crate_height = height
	partners = extra_circles
	debris_seed = int(absf(at.x * 31.0 + at.y * 17.0) * 100.0) % 100000 + 1
	name = "Crate_" + kind


func _physics_process(_delta: float) -> void:
	if dead:
		return
	_check_shove_contacts()


func last_culprit() -> Node:
	if _last_source == null:
		return null
	return _last_source.get_ref() as Node


## Any hit breaks it, whatever the damage: a swing that does 0.5 or a blast that does 40.
func apply_damage(amount: float, source: Node = null) -> float:
	if dead or amount <= 0.0:
		return 0.0
	if source != null and is_instance_valid(source):
		_last_source = weakref(source)
	return super.apply_damage(maxf(amount, hp), source)


## Actors shoved into the crate break it. Cheap: one scan of the actor group per physics frame.
func _check_shove_contacts() -> void:
	for n in get_tree().get_nodes_in_group("actors"):
		var a := n as Actor
		if a == null or a == self or a.dead or not a.is_shoved() or not Net.owns(a):   # (M4: the slider's machine sees it)
			continue
		if GameWorld.flat_distance(a.global_position, global_position) > radius + a.radius - SHOVE_REACH:
			continue
		if a.global_position.y - global_position.y > crate_height:
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
# No late-join rows: one hit breaks a crate, and a broken one is a gone id (NetJoin).

## Host: the break goes to everyone as `obj.break {id}`.
func net_link(objects: NetObjects, id: int) -> void:
	objects.link(broken, _net_broken.bind(objects, id))


func _net_broken(_crate: BreakableCrate, _culprit: Node, objects: NetObjects, id: int) -> void:
	objects.tell("obj.break", {"id": id})
	objects.count("breaks")


## Client: the host broke it (obj.break).
func net_event(kind: String, _data: Dictionary, objects: NetObjects) -> void:
	if kind == "obj.break" and not dead:
		objects.copy_broke(self)


# --- Breaking ----------------------------------------------------------------------------

func _on_death() -> void:
	broke = true
	var culprit := last_culprit()
	var at := global_position
	_break_fx(at)
	spill = PackageSpill.burst(at, "planks", debris_seed, Vector2.ZERO, crate_height * 0.6)
	Grime.mark(Grime.SCUFF, at, 1.4)   # a scuffed, splintered patch that fades after 30 s (no-op without a layer)
	if model != null and is_instance_valid(model):
		model.queue_free()
	model = null
	for b in partners:
		if is_instance_valid(b):
			b.queue_free()
	partners.clear()
	broken.emit(self, culprit)
	if is_inside_tree():
		get_tree().create_timer(LIFE_AFTER_BREAK).timeout.connect(queue_free)
	else:
		queue_free()


## Splinters fly and a puff of dust.
func _break_fx(at: Vector3) -> void:
	PropDebris.burst(at + Vector3.UP * crate_height * 0.5, WOOD_CHIPS, 14, 0.85)
	var dust: Array[Color] = [Color(0.72, 0.6, 0.45), Color(0.5, 0.4, 0.3)]
	Fx.burst(at + Vector3.UP * crate_height * 0.4, dust, 12, 2.6, 0.1, 0.5, 1.5, Vector3.UP, 85.0, false)
	Fx.shake(0.05)
