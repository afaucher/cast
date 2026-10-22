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
## A cast was refused because the spell has no charges left ("out of Ember horn"). No cooldown is spent.
signal spell_empty(id: String)
## A component pickup was collected: kind "added" (more charges for a slotted spell) or "filled" (a new slot).
signal component_collected(id: String, amount: int, kind: String)
## A pickup was swapped into the held slot (old_id is "" if nothing was there).
signal component_swapped(old_id: String, new_id: String, slot: int)
## The held slot or its spell changed (the component in the hand follows it).
signal held_changed

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
# Wick's arrow (secondary_kind "arrow"): the defaults a HeroKit overrides (see HeroKit.ARROW).
const ARROW_TAP_DAMAGE := 12.0
const ARROW_TAP_COOLDOWN := 0.55
const ARROW_TAP_RANGE := 14.0
const ARROW_DRAW_TIME := 0.7
const ARROW_DRAW_DAMAGE := 28.0
const ARROW_DRAW_RANGE := 18.0
const ARROW_DRAW_PIERCE := 3
const ARROW_SPEED := 22.0
const DRAW_MOVE_MULT := 0.5
const CHARGE_RING_RADIUS := 1.05

@export var hero_color := Color(0.3, 0.55, 0.95)
@export var weapon_kind := "sword"   ## "sword" or "staff" (cosmetic)
## What shoot() (RMB / the AI's ranged use) does: "bolt" (the weak ranged bolt / arrows),
## "bowl" (Rebar's rolling boulder) or "spin" (Gasket's 360 degree whirl).
@export var secondary_kind := "bolt"
## The kit this hero was given (HeroKit.apply), or "" for the generic sword hero.
var kit_id := ""
## The primary (LMB / AI melee). The defaults are the generic sword; a HeroKit overrides them.
var primary_name := "Sword"
var melee_damage := MELEE_DAMAGE
var melee_cooldown := MELEE_COOLDOWN
var melee_reach := MELEE_REACH
var melee_arc := MELEE_ARC
var melee_shove := MELEE_SHOVE
## Rebar can't climb +2 ledges (he steps up +1 only), like the brute.
var can_climb := true
## Arrow stats (secondary_kind "arrow": tap, or hold RMB to draw); a HeroKit overrides them.
var arrow_tap_damage := ARROW_TAP_DAMAGE
var arrow_tap_cooldown := ARROW_TAP_COOLDOWN
var arrow_tap_range := ARROW_TAP_RANGE
var arrow_draw_time := ARROW_DRAW_TIME
var arrow_draw_damage := ARROW_DRAW_DAMAGE
var arrow_draw_range := ARROW_DRAW_RANGE
var arrow_draw_pierce := ARROW_DRAW_PIERCE
var arrow_speed := ARROW_SPEED
var draw_move_mult := DRAW_MOVE_MULT

var is_player := false:
	set(v):
		is_player = v
		if _name_label:
			_name_label.visible = not v and not dead
		_refresh_bar()
## Spell ids in slots 1..SLOT_COUNT, in order (index = slot - 1). "" is an open slot: a spell whose last charge was
## spent leaves its slot open in place (user, 2026-10-18), so the others keep their keys; trailing open slots are
## trimmed. Assigning a new list gives every newly listed spell SpellComponents.START_CHARGES; use slot_spell(i) for a
## safe lookup.
var spell_slots: Array[String] = []:
	set(v):
		spell_slots = v
		_sync_slots()
## Index (0-based) of the held slot: that spell gets the passive cooldown boost,
## and its component is shown in the hero's hand. Voice casts any slotted spell either way.
var held_slot := 0
## A dropped component the hero stands next to while every slot is full; E swaps it in. Set by ComponentPickup.
var swap_candidate: ComponentPickup = null

var _ready_at := {}                  ## cooldown key -> GameWorld.time when usable again
var _charges := {}                   ## spell id -> charges left (components), 0..MAX_CHARGES
var _held_prop: Node3D = null        ## the prototype body's held component (models keep theirs via hold_item)
var _visual: Node3D
var _weapon: Node3D
var _body_mat: StandardMaterial3D
var _bar: HpBar
var _name_label: Label3D
var _shield_icon: Sprite3D
var _shield_bubble: MeshInstance3D
var _swing_tween: Tween
var _visual_yaw := 0.0
var _draw_start := -1.0              ## GameWorld.time the bow draw began, or -1 when not drawing
## An AI seat's voice order as the party HUD shows it: "follow", "go", "hold" or "attack" ("" for a hero a person plays).
## Its AllyBrain writes it on the host (and solo); the host sends every change to the clients (NetOrders `ord.st`).
var order_state := ""
var _charge_ring: MeshInstance3D = null
var _charge_mat: StandardMaterial3D = null
var _ui_top := 1.95                  ## height of the figure's top (the bar, name, shield and daze stars float above it)
var _daze_stars: Node3D = null       ## the stars over the head while dazed (DazeFx)
var _daze_shown := false             ## this screen is showing the daze (stars, sway): follows is_dazed()

## Opt-in replacement for the capsule/hat/weapon body (e.g. a RebarModel). Set it before the
## hero enters the tree (HeroFactory.spawn_hero(..., model)). The model faces local -Z; if it has
## attack_swing() / cast_pose() / set_downed(bool) / ui_height they are used. Stats, radius and AI
## are untouched. Null = the prototype look.
var visual_override: Node3D = null

## MOVEMENT FEEL (MoveFeel, docs/design/movement-research.md "As built"). With the `today` profile none of this runs: move()
## is the old walk and the drawn hero is the old one. `grounded`: the owner's walk has an envelope, hops, mantles and falls
## (HeroMotion, on the machine that moves this hero), and every screen draws its stride, footsteps and dust from the shown
## motion (HeroGait). `pace` is an AI ally's catch-up (AllyBrain sets it; a profile without one leaves it at 1).
var pace := 1.0
var _motion: HeroMotion = null
var _gait: HeroGait = null
## grounded_anim (the animation track, animation-research.md "As built"): the lean, the squash and the strike-first swing,
## drawn on every screen from the shown motion and the replayed swing (HeroFeel).
var _feel: HeroFeel = null
## Physics interpolation of a hero this machine moves (MoveFeel.interp, F7): between physics ticks the node is drawn where
## it was a fraction of the way from the last tick to this one, and put back before the next tick (_interp_restore).
var _ip_prev := Vector3.INF
var _ip_cur := Vector3.ZERO
var _ip_shown := Vector3.INF      ## the position this frame drew it at (INF: not displaced)
var _ip_hooked := false


func _init() -> void:
	team = GameWorld.TEAM_HEROES
	max_hp = 100.0
	move_speed = 4.5
	radius = 0.4
	display_name = "Hero"
	_motion = HeroMotion.new(self)
	_gait = HeroGait.new(self)
	_feel = HeroFeel.new(self)
	process_physics_priority = 10   # (after its PlayerController / AllyBrain: a frame with no move() is a coast)


func _ready() -> void:
	super._ready()
	_build_visuals()
	Fx.auto_hit_feedback()
	Fx.attach_hit_feedback(self)
	damaged.connect(func(_a: float, _s: Node) -> void: _refresh_bar())
	healed.connect(func(_a: float) -> void: _refresh_bar())
	_refresh_bar()
	_refresh_hold()


## Who may write each var (see Net); Actor's come from super(). The hero's owner is its player's
## machine (AI allies: the host).
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		# Set once from the kit / factory.
		"hero_color": Net.SPAWN, "weapon_kind": Net.SPAWN, "secondary_kind": Net.SPAWN,
		"kit_id": Net.SPAWN, "primary_name": Net.SPAWN, "melee_damage": Net.SPAWN,
		"melee_cooldown": Net.SPAWN, "melee_reach": Net.SPAWN, "melee_arc": Net.SPAWN,
		"melee_shove": Net.SPAWN, "can_climb": Net.SPAWN,
		"arrow_tap_damage": Net.SPAWN, "arrow_tap_cooldown": Net.SPAWN, "arrow_tap_range": Net.SPAWN,
		"arrow_draw_time": Net.SPAWN, "arrow_draw_damage": Net.SPAWN, "arrow_draw_range": Net.SPAWN,
		"arrow_draw_pierce": Net.SPAWN, "arrow_speed": Net.SPAWN, "draw_move_mult": Net.SPAWN,
		# Slots, charges and the held spell show on other screens (the component in the hand).
		"spell_slots": Net.OWNER, "held_slot": Net.OWNER, "_charges": Net.OWNER,
		"_draw_start": Net.OWNER,         # other screens show the bow drawn
		"order_state": Net.OWNER,         # an AI seat's order chip (the host owns the AI seats): ord.st
		# The owner's own bookkeeping; the pickup it stands next to is only used by that machine.
		"_ready_at": Net.PRIVATE, "swap_candidate": Net.PRIVATE,
		# True only on the machine that drives this hero (remote copies stay false); it gates the
		# bar colour, the name label and pickup collection.
		"is_player": Net.LOCAL,
		"visual_override": Net.LOCAL, "_held_prop": Net.LOCAL, "_visual": Net.LOCAL, "_weapon": Net.LOCAL,
		"_body_mat": Net.LOCAL, "_bar": Net.LOCAL, "_name_label": Net.LOCAL, "_shield_icon": Net.LOCAL,
		"_shield_bubble": Net.LOCAL, "_swing_tween": Net.LOCAL, "_visual_yaw": Net.LOCAL,
		"_charge_ring": Net.LOCAL, "_charge_mat": Net.LOCAL,
		# The daze look: every screen shows it from the daze modifier (_modifiers, announced by the owner).
		"_ui_top": Net.LOCAL, "_daze_stars": Net.LOCAL, "_daze_shown": Net.LOCAL,
		# Movement feel: the owner's walk (its result streams as the position) and this screen's drawing of it.
		"pace": Net.PRIVATE, "_motion": Net.PRIVATE,
		"_gait": Net.LOCAL, "_feel": Net.LOCAL, "_ip_prev": Net.LOCAL, "_ip_cur": Net.LOCAL, "_ip_shown": Net.LOCAL, "_ip_hooked": Net.LOCAL,
	})
	return f


# --- Actions ------------------------------------------------------------------------------

func cooldown_left(id: String) -> float:
	return maxf(0.0, float(_ready_at.get(id, 0.0)) - GameWorld.time)


## The cooldown a cast of `id` costs right now: the held spell recharges 15% more often.
func cooldown_total(id: String) -> float:
	var base := SpellBook.cooldown_of(id)
	return base / SpellComponents.HELD_COOLDOWN_DIV if is_held(id) else base


## Dev (the test gym's "cooldowns off", GymDev): every spell is ready now (the attacks keep theirs). The owner's call.
func reset_spell_cooldowns() -> void:
	for id: String in SpellBook.SPELLS:
		_ready_at.erase(id)


## Cast a spell in one of this hero's slots. False if dead, not slotted, out of charges (emits
## spell_empty and spends nothing, no cooldown), on cooldown, or the spell refuses. A success spends 1 charge.
func try_cast(id: String, power: float, aim: Vector3) -> bool:
	if dead or not spell_slots.has(id):
		return false
	if charges_of(id) <= 0:
		spell_empty.emit(id)
		return false
	if cooldown_left(id) > 0.0:
		return false
	if not SpellBook.cast(id, self, power, aim):
		return false
	_ready_at[id] = GameWorld.time + cooldown_total(id)
	_charges[id] = maxi(0, charges_of(id) - 1)
	_cast_pose()
	spell_cast.emit(id, power)
	if charges_of(id) <= 0:
		empty_slot(id)   # the last component is used up: the slot opens again, nothing is dropped
	return true


## Open the slot holding `id` (its last component is spent): "" in its place, trailing open slots trimmed, no pickup
## dropped. Other copies of this hero do the same when the owner's cast says it has none left (NetCasts).
func empty_slot(id: String) -> void:
	var i := spell_slots.find(id)
	if i < 0:
		return
	var slots := spell_slots.duplicate()
	slots[i] = ""
	while not slots.is_empty() and slots[slots.size() - 1] == "":
		slots.remove_at(slots.size() - 1)
	spell_slots = slots
	held_changed.emit()


# --- Slots, charges, the held spell ---------------------------------------------------------

## The spell in slot `i` (0-based), or "" when that slot is empty.
func slot_spell(i: int) -> String:
	return spell_slots[i] if i >= 0 and i < spell_slots.size() else ""


func held_spell() -> String:
	return slot_spell(held_slot)


func is_held(id: String) -> bool:
	return id != "" and held_spell() == id


func charges_of(id: String) -> int:
	return int(_charges.get(id, 0))


## Set a slotted spell's charges directly (clamped 0..MAX_CHARGES). False if it is not slotted.
func set_charges(id: String, n: int) -> bool:
	if not spell_slots.has(id):
		return false
	_charges[id] = clampi(n, 0, SpellComponents.MAX_CHARGES)
	return true


## Put a spell into the first empty slot with `n` charges (or set its charges if already slotted).
## False if it is unavailable, or every slot is full.
func slot_in(id: String, n: int) -> bool:
	if not SpellBook.is_available(id):
		return false
	if spell_slots.has(id):
		return set_charges(id, n)
	var open := spell_slots.find("")
	if open >= 0:
		spell_slots[open] = id
	elif spell_slots.size() >= SpellComponents.SLOT_COUNT:
		return false
	else:
		spell_slots.append(id)
	_charges[id] = clampi(n, 0, SpellComponents.MAX_CHARGES)
	_refresh_hold()
	return true


## Ready slot `i` (0-based): it becomes the held spell. False (nothing changes) for an empty or invalid slot.
func select_slot(i: int) -> bool:
	if slot_spell(i) == "":
		return false
	if held_slot != i:
		held_slot = i
		_refresh_hold()
		held_changed.emit()
	return true


## What walking onto a pickup of `id` would do: "add" (slotted, room for charges), "capped" (slotted and
## full of charges), "fill" (an empty slot takes it), "swap" (every slot is full: E swaps it into the held
## slot) or "none" (the spell is not available).
func component_outcome(id: String) -> String:
	if not SpellBook.is_available(id):
		return "none"
	if spell_slots.has(id):
		return "add" if charges_of(id) < SpellComponents.MAX_CHARGES else "capped"
	return "fill" if spell_slots.size() < SpellComponents.SLOT_COUNT or spell_slots.has("") else "swap"


## Collect a component of `id` with `amount` charges. Returns {"result": "added" | "filled" | "none",
## "amount": charges actually taken, "slot": 0-based slot}. A slotted spell gains charges up to the cap; an
## unslotted one takes the first empty slot; with every slot full nothing is taken (the pickup waits for an
## E swap).
func collect_component(id: String, amount: int) -> Dictionary:
	var out := {"result": "none", "amount": 0, "slot": -1}
	if dead or amount <= 0:
		return out
	match component_outcome(id):
		"add":
			var taken := mini(amount, SpellComponents.MAX_CHARGES - charges_of(id))
			_charges[id] = charges_of(id) + taken
			out = {"result": "added", "amount": taken, "slot": spell_slots.find(id)}
		"fill":
			var taken := mini(amount, SpellComponents.MAX_CHARGES)
			slot_in(id, taken)
			out = {"result": "filled", "amount": taken, "slot": spell_slots.find(id)}
		_:
			return out
	component_collected.emit(id, int(out["amount"]), str(out["result"]))
	return out


## The pickup F would swap into the held slot right now, or null. The one place that decides it: swap_in_pickup()
## acts on it and the game's F prompt floats over it.
func swap_target() -> ComponentPickup:
	var cand := swap_candidate
	if dead or cand == null or not is_instance_valid(cand) or cand.is_queued_for_deletion():
		return null
	if component_outcome(cand.spell_id) != "swap":
		return null
	return cand


## F: swap the pickup we are standing next to into the held slot. The old spell is dropped as a pickup
## carrying its remaining charges (nothing is dropped if it had none). False if there is nothing to swap.
func swap_in_pickup() -> bool:
	var cand := swap_target()
	if cand == null:
		return false
	if not Net.owns(cand):
		return Net.request(cand, "swap")   # online the host owns pickups: it grants, then apply_swap() runs here (M3)
	var spot := cand.global_position
	var new_id := cand.spell_id
	var new_n := mini(cand.charges, SpellComponents.MAX_CHARGES)
	cand.consume()
	swap_candidate = null
	apply_swap(new_id, new_n, spot)
	return true


## Put `new_id` with `new_n` charges into the held slot; the spell it replaces goes on the floor beside `spot` with
## its charges (nothing if it had none). The second half of a swap (online, the host granted the pickup first).
func apply_swap(new_id: String, new_n: int, spot: Vector3) -> void:
	new_n = mini(new_n, SpellComponents.MAX_CHARGES)
	swap_candidate = null
	var slot := held_slot
	var old := slot_spell(slot)
	var old_n := charges_of(old)
	var slots := spell_slots.duplicate()
	slots[slot] = new_id
	spell_slots = slots           # the setter re-syncs the charge table (the new spell starts at START_CHARGES) ...
	_charges[new_id] = new_n      # ... then the pickup's own count replaces that
	if old != "" and old_n > 0:
		var away := spot - global_position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.05 else -facing
		ComponentPickup.drop(old, old_n, global_position + away * (SpellComponents.SWAP_RADIUS + 0.7), 0.0)   # the swapped-out spell never despawns
	_refresh_hold()
	held_changed.emit()
	component_swapped.emit(old, new_id, slot)


func _sync_slots() -> void:
	if spell_slots.size() > SpellComponents.SLOT_COUNT:
		spell_slots.resize(SpellComponents.SLOT_COUNT)
	for id in spell_slots:
		if id != "" and not _charges.has(id):
			_charges[id] = SpellComponents.START_CHARGES
	for id: String in _charges.keys():
		if not spell_slots.has(id):
			_charges.erase(id)
	held_slot = clampi(held_slot, 0, maxi(0, spell_slots.size() - 1))
	_refresh_hold()


## Show the held spell's component in the hand (on a model with hold_item, else on the prototype body).
func _refresh_hold() -> void:
	if _visual == null:
		return   # the body is not built yet; _ready calls this again
	var id := held_spell()
	var prop: Node3D = ComponentProps.make(id, true) if id != "" else null
	if visual_override != null:
		if visual_override.has_method("hold_item"):
			visual_override.call("hold_item", prop)
		elif prop != null:
			prop.free()
		return
	if _held_prop != null:
		_held_prop.queue_free()
		_held_prop = null
	if prop != null:
		prop.position = Vector3(-0.42, 0.78, -0.22)
		prop.scale = Vector3.ONE * 0.8
		_visual.add_child(prop)
		_held_prop = prop


## Sword/staff swing toward `dir` (X/Z). Returns false while on cooldown.
func melee(dir: Vector3) -> bool:
	if dead or is_helpless() or cooldown_left(KEY_MELEE) > 0.0:
		return false
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = facing
	dir = dir.normalized()
	facing = dir
	cancel_draw()
	_ready_at[KEY_MELEE] = GameWorld.time + scaled_cooldown(melee_cooldown)
	_melee_effect(dir)
	Net.hero_acted(self, "melee", dir)   # (online: the other screens replay the swing on this hero's puppet)
	melee_swung.emit()
	return true


## The swing itself (here, or replayed on another machine's puppet: Combat applies only what that machine resolves).
## The area is melee_area(): today's wedge, or (grounded_anim) the shape of this hero's weapon, the same on every machine
## because the crew plays the host's profile.
func _melee_effect(dir: Vector3) -> void:
	var area := melee_area()
	var lane := str(area["shape"]) == "lane"
	var far := float(area["far"]) if lane else 0.0
	var end := float(area.get("end_radius", 0.0))
	var reach := far + maxf(float(area["radius"]), end) if lane else float(area["reach"])
	for foe in GameWorld.actors_in_radius(global_position, reach, GameWorld.other_team(team)):
		Fx.attach_hit_feedback(foe)
	var touched := (Combat.lane_targets(self, dir, float(area["near"]), far, float(area["radius"]), end) if lane
			else Combat.arc_targets(self, dir, float(area["reach"]), float(area["arc"])))
	var hit := (Combat.melee_lane(self, dir, float(area["near"]), far, float(area["radius"]), melee_damage, melee_shove, end) if lane
			else Combat.melee_arc(self, dir, float(area["reach"]), float(area["arc"]), melee_damage, melee_shove))
	if not hit.is_empty():
		MonsterSenses.noise(global_position, MonsterSenses.NOISE_MELEE, "melee")   # a blow that lands is heard
	if lane:
		Fx.slam_lane(global_position, dir, float(area["near"]), far, float(area["radius"]), hero_color.lightened(0.5), end)
	else:
		Fx.slash_arc(global_position, dir, float(area["reach"]), float(area["arc"]), hero_color.lightened(0.5))
	_swing_pose(not touched.is_empty(), dir)


## This hero's primary hit area right now: {"shape": "arc", "reach", "arc"} (a wedge from the hero: the kit's own, and
## every kit under today / grounded) or {"shape": "lane", "near", "far", "radius"} (Combat.melee_lane; an optional
## "end_radius" adds a disc round the landing spot, and "smash" marks the landing on the floor: HeroFeel), from the active
## MoveFeel profile's `melee_areas` (grounded_anim: each weapon's own shape, animation-research.md "As built").
func melee_area() -> Dictionary:
	var areas := MoveFeel.value("melee_areas") as Dictionary
	if areas.has(kit_id):
		return areas[kit_id]
	return {"shape": "arc", "reach": melee_reach, "arc": melee_arc}


## Half the angle (degrees, seen from the hero) the primary covers: half the wedge, or a lane's sideways reach at its far end
## (the AI's "turn the swing to keep a priced prop out").
func melee_half_angle() -> float:
	var area := melee_area()
	if str(area["shape"]) == "lane":
		return rad_to_deg(atan2(maxf(float(area["radius"]), float(area.get("end_radius", 0.0))), maxf(float(area["far"]), 0.01)))
	return float(area["arc"]) * 0.5


## Another machine's hero attacked (NetCasts replays its `act` event on this puppet, at the moment the puppet shows): the
## swing, the shot, the bowl or the spin plays here from where this screen shows the hero, and Combat applies only what
## this machine resolves (its own hero against a teammate's spin or bowl; the attacker's machine already decided the
## monsters). Writes nothing the owner owns (no cooldowns, no facing).
func net_act(kind: String, dir: Vector3, drawn: bool) -> void:
	if dead:
		return
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.001 else facing
	match kind:
		"melee":
			_melee_effect(dir)
			melee_swung.emit()
		"arrow":
			_arrow_effect(dir, drawn)
			bolt_fired.emit()
		"bolt":
			_bolt_effect(dir)
			bolt_fired.emit()
		"bowl":
			BowlBoulder.launch(self, dir, BOWL_SPEED, BOWL_RANGE, BOWL_DAMAGE, BOWL_SHOVE)
			_bowl_pose()
			bolt_fired.emit()
		"spin":
			_spin_effect(dir)
			bolt_fired.emit()
		"cast":
			_cast_pose()


## The secondary attack toward `dir` (X/Z): the ranged bolt, Rebar's bowl or Gasket's spin,
## per secondary_kind. Returns false while on cooldown.
func shoot(dir: Vector3) -> bool:
	if dead or is_helpless() or cooldown_left(KEY_RANGED) > 0.0:
		return false
	match secondary_kind:
		"bowl":
			return _bowl(dir)
		"spin":
			return _spin()
		"arrow":
			return fire_arrow(dir, false)
	return _bolt(dir)


# --- Wick's arrow: tap, or hold to draw ------------------------------------------------------

## True while the bow is being drawn (RMB held with secondary_kind "arrow").
func is_drawing() -> bool:
	return _draw_start >= 0.0


## 0..1: how far the bow is drawn (1 = a full draw, the next release is the drawn shot). A hasted archer draws
## faster (the draw time scales with the attack rate, like every cooldown).
func draw_progress() -> float:
	if _draw_start < 0.0:
		return 0.0
	return clampf((GameWorld.time - _draw_start) / maxf(scaled_cooldown(arrow_draw_time), 0.001), 0.0, 1.0)


## Begin drawing the bow (RMB pressed). False if this hero has no arrow, is down or helpless, or the
## bow is still recovering from the last shot. Moving while drawn is allowed at draw_move_mult speed.
func start_draw() -> bool:
	if secondary_kind != "arrow" or dead or is_helpless() or cooldown_left(KEY_RANGED) > 0.0:
		return false
	if _draw_start < 0.0:
		_draw_start = GameWorld.time
		_update_draw_visuals()
	return true


## Let go of the string (RMB released). A full draw (held arrow_draw_time or more) fires the drawn
## shot (piercing, harder, longer); releasing early fires a tap shot. False if not drawing.
func release_draw(dir: Vector3) -> bool:
	if _draw_start < 0.0:
		return false
	var full := draw_progress() >= 1.0
	cancel_draw()
	return fire_arrow(dir, full)


## A daze took (Actor.daze, on this hero's own machine): the draw is lost and a swing or spin in progress is cut off
## (their hits already landed: both are instant). Casts are not touched: a spell spoken while dazed still goes off.
func _on_dazed(_seconds: float) -> void:
	cancel_draw()
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	if _weapon != null:
		_weapon.rotation = Vector3(0, deg_to_rad(SWING_REST_YAW), 0)


## Lower the bow without shooting.
func cancel_draw() -> void:
	if _draw_start < 0.0:
		return
	_draw_start = -1.0
	_update_draw_visuals()


## Fire an arrow toward `dir` (X/Z): the tap shot, or `drawn` for the charged one. Shares the
## secondary cooldown. False while on cooldown, down or helpless.
func fire_arrow(dir: Vector3, drawn: bool) -> bool:
	if dead or is_helpless() or cooldown_left(KEY_RANGED) > 0.0:
		return false
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = facing
	dir = dir.normalized()
	facing = dir
	cancel_draw()
	_ready_at[KEY_RANGED] = GameWorld.time + scaled_cooldown(arrow_tap_cooldown)
	_arrow_effect(dir, drawn)
	Net.hero_acted(self, "arrow", dir, drawn)
	bolt_fired.emit()
	return true


func _arrow_effect(dir: Vector3, drawn: bool) -> void:
	var dmg := arrow_draw_damage if drawn else arrow_tap_damage
	var rng := arrow_draw_range if drawn else arrow_tap_range
	var pierce := arrow_draw_pierce if drawn else 1
	ArrowShot.shoot(self, dir, dmg, arrow_speed, rng, pierce, drawn, hero_color.lightened(0.5))
	_shoot_pose()


## Walk (the controllers call it every frame they steer). Under a profile with an envelope it is HeroMotion's; otherwise the
## plain walk below, exactly as it always was.
func move(dir: Vector3, delta: float) -> bool:
	if MoveFeel.on("envelope"):
		return _motion.walk(dir, delta)
	return _walk(dir, delta)


## The plain walk: Actor.move at draw_move_mult speed while the bow is drawn (and an AI ally's catch-up `p`, grounded only).
func _walk(dir: Vector3, delta: float, p: float = 1.0) -> bool:
	if _draw_start < 0.0 and p == 1.0:
		return super.move(dir, delta)
	var base := move_speed
	move_speed = base * (draw_move_mult if _draw_start >= 0.0 else 1.0) * p   # (Actor.move then applies the modifiers on top: coffee, goo, roots)
	var moved := super.move(dir, delta)
	move_speed = base
	return moved


## Full walking speed right now, everything included (the bow, coffee, water, goo, roots, an ally's catch-up).
func walk_speed() -> float:
	return effective_speed() * (draw_move_mult if _draw_start >= 0.0 else 1.0) * pace


## A +2 ledge is a slow climb, or (a profile with a mantle) never walked onto: the mantle takes the hero up.
func _climb_allowed() -> bool:
	return can_climb and not MoveFeel.on("mantle")


## Under an envelope the walk's own vertical rules replace the eased settle (HeroMotion.vertical); placing a hero
## (no delta) is unchanged.
func snap_to_ground(delta: float = -1.0) -> void:
	if delta >= 0.0 and MoveFeel.on("envelope") and not Net.is_puppet(self):
		return
	super.snap_to_ground(delta)


## The movement feel's per-tick part, on the machine that moves this hero (after its controller or AI: priority 10).
func _physics_process(delta: float) -> void:
	if not MoveFeel.on("envelope"):
		if _motion.mantle != 0 or _motion.vel != Vector3.ZERO or _motion.air or _motion.hop_t >= 0.0:
			_motion.reset()   # (switched back to today mid-step: the plain walk takes over from here)
		return
	if Net.is_puppet(self):
		return
	if _motion.moved_frame != Engine.get_physics_frames():
		_motion.coast(delta)
	_motion.vertical(delta)


## Keep the model's bow and the charge ring in step with the draw.
func _update_draw_visuals() -> void:
	var p := draw_progress()
	if visual_override != null and visual_override.has_method("draw_hold"):
		visual_override.call("draw_hold", p)
	if _draw_start >= 0.0:
		if _charge_ring == null:
			_make_charge_ring()
		_charge_ring.visible = true
		var full := p >= 1.0
		var pulse := 1.0 + (0.07 * sin(GameWorld.time * 18.0) if full else 0.0)
		var k := lerpf(0.3, 1.0, p) * pulse
		_charge_ring.scale = Vector3(k, 0.15, k)
		var base := hero_color.lightened(0.45)
		var col := Color(1.0, 0.95, 0.55) if full else base
		_charge_mat.albedo_color = Color(col, lerpf(0.35, 0.95, p))
	elif _charge_ring != null:
		_charge_ring.visible = false


func _make_charge_ring() -> void:
	_charge_ring = MeshInstance3D.new()
	_charge_ring.name = "ChargeRing"
	var torus := TorusMesh.new()
	torus.inner_radius = CHARGE_RING_RADIUS - 0.09
	torus.outer_radius = CHARGE_RING_RADIUS
	torus.rings = 40
	torus.ring_segments = 6
	_charge_ring.mesh = torus
	_charge_mat = Fx.glow_material(Color(1, 1, 1, 0.5))
	_charge_ring.material_override = _charge_mat
	_charge_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_charge_ring.position = Vector3(0, 0.08, 0)
	_charge_ring.set_meta("no_flash", true)
	add_child(_charge_ring)


## Rebar's bowl: a boulder rolls along the ground toward `dir`, shoving everything it touches.
func _bowl(dir: Vector3) -> bool:
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = facing
	dir = dir.normalized()
	facing = dir
	_ready_at[KEY_RANGED] = GameWorld.time + scaled_cooldown(BOWL_COOLDOWN)
	BowlBoulder.launch(self, dir, BOWL_SPEED, BOWL_RANGE, BOWL_DAMAGE, BOWL_SHOVE)
	_bowl_pose()
	Net.hero_acted(self, "bowl", dir)   # (the boulder rolls on every screen; each machine shoves its own hero)
	bolt_fired.emit()
	return true


## Gasket's spin: everything within SPIN_REACH is shoved outward; monsters also take damage.
func _spin() -> bool:
	_ready_at[KEY_RANGED] = GameWorld.time + scaled_cooldown(SPIN_COOLDOWN)
	_spin_effect(facing)
	Net.hero_acted(self, "spin", facing)   # (a teammate's machine shoves its own hero: rule 5, the victim applies it)
	bolt_fired.emit()
	return true


func _spin_effect(dir: Vector3) -> void:
	var reach := float(spin_area()["reach"])
	for foe in GameWorld.actors_in_radius(global_position, reach, GameWorld.other_team(team)):
		Fx.attach_hit_feedback(foe)
	var touched := Combat.arc_targets(self, dir, reach, 360.0)
	if not Combat.melee_arc(self, dir, reach, 360.0, SPIN_DAMAGE, SPIN_SHOVE).is_empty():
		MonsterSenses.noise(global_position, MonsterSenses.NOISE_MELEE, "melee")
	Combat.shove_radius(global_position, reach, SPIN_SHOVE, self, team, self, 2.1 * Hex.LEVEL_HEIGHT)   # teammates too
	Fx.slash_arc(global_position, dir, reach, 360.0, hero_color.lightened(0.5))
	_spin_pose(not touched.is_empty())


## The spin's area right now: {"shape": "arc", "reach", "arc": 360}: SPIN_REACH, or the active MoveFeel profile's
## `spin_reach` (grounded_anim: the radius the wrench head really sweeps, animation-research.md "As built").
func spin_area() -> Dictionary:
	var r := MoveFeel.num("spin_reach")
	return {"shape": "arc", "reach": r if r > 0.0 else SPIN_REACH, "arc": 360.0}


## Fire the weak ranged bolt toward `dir` (X/Z).
func _bolt(dir: Vector3) -> bool:
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = facing
	dir = dir.normalized()
	facing = dir
	_ready_at[KEY_RANGED] = GameWorld.time + scaled_cooldown(RANGED_COOLDOWN)
	_bolt_effect(dir)
	Net.hero_acted(self, "bolt", dir)
	bolt_fired.emit()
	return true


func _bolt_effect(dir: Vector3) -> void:
	var on_hit := func(_p: Projectile, hit: Actor, pos: Vector3) -> void:
		if hit:
			Fx.attach_hit_feedback(hit)
		var sparks: Array[Color] = [hero_color.lightened(0.6), Color.WHITE]
		Fx.burst(pos, sparks, 6, 2.0, 0.06, 0.25, 4.0)
	var bolt := Fx.make_projectile(self, Combat.chest(self) + dir * 0.5, dir, RANGED_DAMAGE, BOLT_SPEED, BOLT_RANGE, hero_color.lightened(0.5), BOLT_SIZE, on_hit)
	bolt.hits_props = true   # a bolt chips (and can break) the priced prop it runs into, like an arrow
	_shoot_pose()


func _on_death() -> void:
	cancel_draw()
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


# --- Seat handover (docs/design/networking-build-plan.md M2b / M6) -----------------------------

## This hero node becomes another character IN PLACE: the kit (stats, primary, secondary), the name, the colour and
## the model change; the node, its position, its net id and everything that refers to it stay. HP keeps its
## FRACTION (a downed hero stays downed). Used when a player drops and the AI takes the seat back as its original
## character, and (M6) when a joiner takes over an AI. The one place a SPAWN field is written after the hero exists.
## `full` (M6, decided: a joiner always arrives at 100%): the hero comes back at full health, standing, even from downed.
func become(kit: String, new_name: String, color: Color, model: Node3D, full: bool = false) -> void:
	var fraction := 1.0 if full else (clampf(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 1.0)
	var was_dead := dead and not full
	cancel_draw()
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	for n: Node in [_visual, _bar, _name_label, _shield_icon, _shield_bubble, _charge_ring, _daze_stars]:
		if n != null and is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	_daze_stars = null
	_daze_shown = false
	_visual = null
	_bar = null
	_name_label = null
	_shield_icon = null
	_shield_bubble = null
	_charge_ring = null
	_charge_mat = null
	_held_prop = null
	_weapon = null
	_body_mat = null
	HeroKit.apply_to(self, kit)
	display_name = new_name
	hero_color = color
	visual_override = model
	if has_meta(Net.NAME_META):
		remove_meta(Net.NAME_META)   # a seat the AI plays shows its character's name
	_build_visuals()
	dead = false
	hp = max_hp * fraction
	if was_dead:
		hp = 0.0
		dead = true
		_on_death()
	_refresh_bar()
	_refresh_hold()


## Show a player's name over this hero instead of the character's (an online crew: two players may both be Wick).
func set_player_name(player_name: String) -> void:
	set_meta(Net.NAME_META, player_name)
	if _name_label != null:
		_name_label.text = player_name


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
	_ui_top = top
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
	_interp_show()
	var target_yaw := atan2(-facing.x, -facing.z)
	_visual_yaw = lerp_angle(_visual_yaw, target_yaw, clampf(TURN_RATE * delta, 0.0, 1.0))
	_visual.rotation.y = _visual_yaw
	_feel.tick(delta)   # (before the gait: the strike's kicks are set, or a hit-stop holds the pose, when the model is posed)
	_gait.tick(delta)
	if _draw_start >= 0.0:
		if dead or is_helpless():
			cancel_draw()
		else:
			_update_draw_visuals()
	if not dead:
		_set_armor_visuals(has_modifier("armor"))
		if _shield_bubble.visible:
			var pulse := 1.0 + 0.04 * sin(GameWorld.time * 6.0)
			_shield_bubble.scale = Vector3.ONE * pulse
	_update_daze_visuals(delta)


# --- Physics interpolation (MoveFeel.interp, F7; docs/design/movement-research.md "As built", the judder check) -------------

## Draw this hero between its last two physics positions (Engine.get_physics_interpolation_fraction), when this machine
## moves it. Its true position is put back at the start of the next physics tick (_interp_restore), before anything
## simulates; a position something else set in between (a teleport, an arrival) is kept.
func _interp_show() -> void:
	if not MoveFeel.interp or Net.is_puppet(self) or not is_inside_tree():
		if _ip_hooked:
			_interp_unhook()
		return
	if not _ip_hooked:
		_ip_hooked = true
		get_tree().physics_frame.connect(_interp_restore)
		_ip_prev = global_position
		_ip_cur = global_position
		_ip_shown = Vector3.INF
	if _ip_shown == Vector3.INF or global_position != _ip_shown:
		_ip_cur = global_position   # (the last tick's true position; or something placed the hero since)
	if _ip_prev == Vector3.INF or _ip_prev.distance_to(_ip_cur) > 2.0:
		_ip_prev = _ip_cur
	var shown := _ip_prev.lerp(_ip_cur, clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0))
	global_position = shown
	_ip_shown = shown


## The start of a physics tick: the true position back, and it becomes the "previous" one for the next drawn frames.
func _interp_restore() -> void:
	if _ip_shown != Vector3.INF and global_position == _ip_shown:
		global_position = _ip_cur
	_ip_shown = Vector3.INF
	_ip_prev = global_position


func _interp_unhook() -> void:
	_ip_hooked = false
	if _ip_shown != Vector3.INF and global_position == _ip_shown:
		global_position = _ip_cur
	_ip_shown = Vector3.INF
	_ip_prev = Vector3.INF
	if is_inside_tree() and get_tree().physics_frame.is_connected(_interp_restore):
		get_tree().physics_frame.disconnect(_interp_restore)


func _exit_tree() -> void:
	if _ip_hooked:
		_interp_unhook()


## The daze on this screen (the owner's daze, or the one its owner announced): stars over the head, the model reeling
## from side to side, the "*bonk*" callout as it lands (and a camera bump for your own hero).
func _update_daze_visuals(delta: float) -> void:
	var on := not dead and is_dazed()
	if on != _daze_shown:
		_daze_shown = on
		if on:
			if _daze_stars == null or not is_instance_valid(_daze_stars):
				_daze_stars = DazeFx.stars(_ui_top)
				add_child(_daze_stars)
			DazeFx.callout(self, _ui_top)
			if is_player:
				Fx.shake(0.15)
		if _daze_stars != null and is_instance_valid(_daze_stars):
			_daze_stars.visible = on
	if on:
		var t := GameWorld.time
		DazeFx.spin(_daze_stars, t)
		_visual.rotation.z = 0.2 * sin(t * 11.0)
		_visual.rotation.x = 0.08 * sin(t * 7.0 + 1.3)
	else:
		# Settle back upright (a downed hero's own tween owns rotation.x: only the sideways sway is undone then).
		var k := clampf(12.0 * delta, 0.0, 1.0)
		if _visual.rotation.z != 0.0:
			_visual.rotation.z = 0.0 if absf(_visual.rotation.z) < 0.002 else lerpf(_visual.rotation.z, 0.0, k)
		if not dead and _visual.rotation.x != 0.0:
			_visual.rotation.x = 0.0 if absf(_visual.rotation.x) < 0.002 else lerpf(_visual.rotation.x, 0.0, k)


## True while this screen shows the daze (stars and sway; tests).
func is_showing_daze() -> bool:
	return _daze_shown and _daze_stars != null and is_instance_valid(_daze_stars) and _daze_stars.visible


func _set_armor_visuals(on: bool) -> void:
	if _shield_icon and _shield_icon.visible != on:
		_shield_icon.visible = on
		_shield_bubble.visible = on


func _refresh_bar() -> void:
	if _bar:
		_bar.set_fraction(hp / max_hp, Color(0.25, 0.85, 0.75) if is_player and hp / max_hp > 0.5 else Color(0, 0, 0, 0))


## The swing's pose. `connects`: the blow touched something. Under strike_first (grounded_anim) HeroFeel plays it (the
## impact on this frame, then the follow-through, a hit-stop when it connects); otherwise the model's own swing.
func _swing_pose(connects: bool = false, dir: Vector3 = Vector3.ZERO) -> void:
	if _feel.strike(connects, dir if dir != Vector3.ZERO else facing):
		return
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
	if _feel.secondary():
		return   # (grounded_anim: the glove is at the boulder on the click's frame, HeroFeel)
	if visual_override != null and visual_override.has_method("bowl_pose"):
		visual_override.call("bowl_pose")
		return
	_shoot_pose()


## The spin's pose. Under strike_first (grounded_anim) HeroFeel whirls her through it at once (the hits already landed),
## with a hit-stop when it touches something; otherwise the model's own spin.
func _spin_pose(connects: bool = false) -> void:
	if _feel.secondary(connects):
		return
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
	if secondary_kind == "arrow" and _feel.secondary():
		return   # (grounded_anim: Wick's bow is up and released on the click's frame, HeroFeel)
	if visual_override != null and visual_override.has_method("shoot_pose"):
		visual_override.call("shoot_pose")
	if _weapon == null:
		return
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	_weapon.rotation = Vector3(deg_to_rad(25), 0, 0)
	_swing_tween = create_tween()
	_swing_tween.tween_property(_weapon, "rotation", Vector3(0, deg_to_rad(SWING_REST_YAW), 0), 0.25).set_trans(Tween.TRANS_BACK)


## A cosmetic acknowledgement (an AI hero taking a voice order, OrderFx / VoiceOrders.feedback): the cast pose, no spell.
func gesture() -> void:
	_cast_pose()


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
