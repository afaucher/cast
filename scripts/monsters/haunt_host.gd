class_name HauntHost
extends Monster
## A body a ghost can possess on a haunted floor (docs/design/haunted-build-plan.md H5, "H5 networking" and "H5 as built";
## new-themes.md "Ghosts", decided: "The ghosts could haunt things like suits of armour or skeletons"). The base of the two
## kinds, ArmourHost (a suit of armour, the client's antique: billed when it breaks) and BonesHost (a skeleton: free to smash).
## A host monster from spawn (seed-built by HauntPlanner, after the processions):
##   DORMANT    no ghost in it: it stands (or lies) where it was put like a piece of the room. No AI, no senses: a hit, a
##              shout, a noise, a chicken leave it be; out of the "monsters" group (never a pest, the staff are not scared of
##              it); the AI allies never pick it (is_dormant). The crew can still break it (it is property: the armour bills).
##   POSSESSED  a wisp is in it (`ghost`): it wakes (its model stands up over its WAKE_T, helpless meanwhile) and is an
##              ordinary monster of the kind's stats: senses, chase, wind-up, strike, leash. A ghost never leaves a host of
##              its own accord (evicting one without breaking it is wanted but deferred).
##   BROKEN     its death: the kind's bill (ArmourHost) and, possessed, its wisp is thrown out and hurt (Wisp.eject: the hit
##              is the verb, the culprit its source) and flees to the next dormant host. The host is gone (a monster's death:
##              the kind's look, then freed).
## Online (an owned actor, the host's): who possesses what is `ghost` here and `Wisp.host` on the wisp, written only on the
## host's machine and carried by world.haunt (NetWorld, from the wisp's haunt_changed); a client applies it in net_take_ghost /
## net_drop_ghost. The possessed look is LOCAL, from `ghost`, on every machine.

const GROUP := "haunt_hosts"
const WAKE_T := 1.2                 ## seconds it is helpless while its model wakes (on every screen, from the possession)

var ghost: Monster = null           ## the wisp in it (null: dormant)
var price := 0                      ## what breaking it bills (0: free to smash, the bones)
var possessions := 0                ## times this machine showed it possessed (tests, the gym)
var phase := 0.0                    ## the ghost look's pulse phase (a look)
var _last_by: WeakRef = null        ## the last thing that hurt or shoved it: the bill's culprit
var _woke_at := -INF                ## GameWorld.time this machine showed it wake


func _init() -> void:
	super._init()
	employee_chance = 0.0


## Who may write each var (see Net); Monster's come from super().
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"ghost": Net.OWNER,          # world.haunt (NetWorld): the wisp's possess / eject
		"price": Net.SPAWN,          # MonsterDefs "billed"
		"possessions": Net.LOCAL,
		"phase": Net.LOCAL,
		"_last_by": Net.PRIVATE,     # the bill's culprit, written on the owner
		"_woke_at": Net.LOCAL,
	})
	return f


func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	phase = GameWorld.fx_rng.randf_range(0.0, TAU) if GameWorld.fx_rng != null else 0.0
	if ghost == null:
		_go_dormant()


# --- Dormant or possessed ------------------------------------------------------------------------------------------------

func is_dormant() -> bool:
	return ghost == null and not dead


func is_possessed() -> bool:
	return ghost != null and not dead


## The owner: wisp `w` possesses it (Wisp.possess; online the wisp's haunt_changed is world.haunt). `instant`: at spawn, no wake.
func take_ghost(w: Monster, instant: bool = false) -> void:
	if dead or ghost != null or not Net.owns(self):
		return
	_possessed_by(w, instant)
	home = global_position
	_home_set = true
	_prog_pos = global_position
	_clear_path()
	state = State.IDLE
	target = null
	if not instant:
		_next_attack_time = GameWorld.time + WAKE_T
		stagger(WAKE_T)


## A copy (world.haunt, or a late joiner's `haunts`): the host's wisp is in it now.
func net_take_ghost(w: Monster) -> void:
	if dead or ghost == w:
		return
	_possessed_by(w, false)


## Either side: the wisp left it (it broke; world.haunt h 0). Nothing wakes it back to dormant (a ghost never leaves an
## unbroken host); a copy only forgets the link.
func drop_ghost() -> void:
	ghost = null


func _possessed_by(w: Monster, instant: bool) -> void:
	ghost = w
	possessions += 1
	_woke_at = GameWorld.time - (WAKE_T if instant else 0.0)
	if not is_in_group("monsters"):
		add_to_group("monsters")
	_show_possessed(instant)
	_update_bar()


## Back to the dormant look and out of the monsters (spawn: before a ghost is put in it).
func _go_dormant() -> void:
	remove_from_group("monsters")
	_show_dormant()


## The kind's look: possessed (the model wakes, the ghost look on), at once when `instant`.
func _show_possessed(_instant: bool) -> void:
	pass


## The kind's look: dormant.
func _show_dormant() -> void:
	pass


## True while its model is still waking (helpless on its owner).
func is_waking() -> bool:
	return GameWorld.time - _woke_at < WAKE_T


# --- No AI, no senses while dormant ------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_dormant():
		if not dead:
			_update_visual(delta)   # (a piece of the room: no AI, only its look; a shove still slides it, Actor's own tick)
		return
	super._physics_process(delta)


func aggro(t: Actor) -> void:
	if is_dormant():
		return
	super.aggro(t)


func alert(pos: Vector3) -> bool:
	return false if is_dormant() else super.alert(pos)


func hear(pos: Vector3) -> bool:
	return false if is_dormant() else super.hear(pos)


func _on_pecked(source: Node) -> void:
	if not is_dormant():
		super._on_pecked(source)


func _on_damaged(amount: float, source: Node) -> void:
	if source != null and is_instance_valid(source):
		_last_by = weakref(source)
	if is_dormant():
		_flash_t = FLASH_TIME
		_dent(amount)
		return   # (no fight, no shout: an antique took a knock)
	super._on_damaged(amount, source)


## A dormant host takes a knock like a prop (ArmourHost: a wobble and chips). Default: nothing.
func _dent(_amount: float) -> void:
	pass


func shove(dir: Vector3, distance: float, source: Node = null) -> void:
	if source != null and is_instance_valid(source) and not Net.is_copy(self):
		_last_by = weakref(source)
	super.shove(dir, distance, source)


## Who breaking it is billed to (the last thing that hurt or shoved it).
func last_culprit() -> Node:
	return _last_by.get_ref() as Node if _last_by != null else null


## A dormant host shows no HP bar (a prop: it wobbles instead).
func _update_bar() -> void:
	if is_dormant():
		if _bar != null:
			_bar.visible = false
		return
	super._update_bar()


func is_hp_bar_visible() -> bool:
	return not is_dormant() and super.is_hp_bar_visible()


# --- Broken ----------------------------------------------------------------------------------------------------------------

## The owner bills it (a priced kind) and throws its wisp out, hurt; then the kind's death look (_break).
func _on_death() -> void:
	var culprit := last_culprit()
	var w := ghost
	if Net.owns(self):
		if price > 0:
			Ledger.damage(display_name, price, culprit)   # (online the host bills it; a client's Ledger mirrors it)
		if w != null and is_instance_valid(w) and not w.dead and w.has_method("eject"):
			w.call("eject", self, culprit)   # (world.haunt h 0, then the hurt: Wisp.eject)
	ghost = null
	remove_from_group(GROUP)
	_break()


## The kind's death look. Default: a monster's (topple, fade, freed).
func _break() -> void:
	super._on_death()
