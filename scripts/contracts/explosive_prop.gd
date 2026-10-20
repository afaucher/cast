class_name ExplosiveProp
extends PricedProp
## An explosive prop, the first environmental hazard (docs/design/hazards.md, "Explosive props (as built)"): an oil drum,
## gas cylinders, a propane tank or a server battery pack, placed by the room themes. It is the client's property like any
## priced prop (PricedProp: neutral, immovable, partial damage free), and it can be SET OFF:
##
##   LIGHT   fire (a fireball's blast: fire_at; a burning actor touching it), a hard hit (one hit of HARD_HIT or more: a
##           hammer, a fist, a drawn arrow, a slam, corn, a blast), any arrow or bolt (it punctures: shot_damage), a hard
##           shove (an actor slammed into it, or a shove on it, of HARD_SHOVE or more), or enough small dents to break it.
##           A light tap (Wick's bow bash, a nudge) only dents it, for free.
##   FUSE    `fuse_time` (1.0-1.5 s by kind; a chained one CHAIN_DELAY_MIN + CHAIN_DELAY_PER_UNIT a unit away): a hiss,
##           sparks, a pulsing glow, a shake and the blast radius on the floor (FuseFx). Hits during the fuse do nothing.
##   BLAST   at the fuse's end, on EVERY machine: Combat.explode on everyone (team -1: heroes, monsters, employees, other
##           props, mail, chickens) within `blast_radius`, `blast_damage` falling off to EDGE_MULT at the rim, a shove out of
##           `blast_shove` (falling off the same way), and a fireball's chance to set them on fire (Burning.on_blast at
##           BURN_POWER). Each machine applies only what it resolves (the decider is the prop, so the host for everything
##           but a hero; each hero's own machine for its hero). Every other explosive in reach lights on a short chain fuse
##           first, so a row of drums goes off as a sequence. Then the prop breaks (die).
##   BILL    breaking it bills its full price ONCE (PricedProp._on_death, on the host) to whoever set it off: the igniter.
##           A chain keeps the first igniter, so one player's fireball pays for the whole row; whatever the blast breaks
##           (props, mail) is billed to them too (the blast's source is the igniter).
##   DAMP    a soaked explosive (Damp / Wet.douse / a pool: Burning.soak) will not light from anything while it is wet, and
##           a soak that lands on a lit fuse before its last DOUSE_LOCK seconds puts it out ("FIZZLE"). A soaked one can
##           still be smashed: it breaks as a dud (billed, no blast).
##
## Networking (docs/design/networking.md: a host-arbitrated object whose blast is a scheduled effect). The host owns it and
## decides everything: the ignition (a client's hit or shove arrives as a request, Net.route_hit / route_shove; fire and a
## burning walker are seen on the host's own run), the fuse's start and end (`lit` -> NetObjects `obj.fuse {id, s, e, by}`,
## host times), a douse (`doused` -> `obj.out`), the chain, and the break and its bill (`obj.break`, the Ledger). Every
## machine runs the blast itself at the fuse's end on its clock (`_detonate`), so a client's hero is hit by its own machine,
## once. A late joiner gets a burning fuse by an obj.fuse replay and a blown prop by the gone ids.

## A fuse was lit (on the owner): who set it off, and the fuse's start and end (GameWorld.time).
signal lit(prop: ExplosiveProp, culprit: Node, start: float, end: float)
## A fuse was put out by a soak (on the owner).
signal doused(prop: ExplosiveProp)
## The blast went off on this machine.
signal blew(prop: ExplosiveProp)

const HAZARD_GROUP := "explosives"
const HARD_HIT := 15.0              ## one hit this big lights it (Wick's bow bash, 12, does not; a hammer, 28, does)
const HARD_SHOVE := 1.5             ## a shove on it this long lights it (a melee nudge, 0.7-1.0, does not)
const DOUSE_LOCK := 0.3             ## a soak in the fuse's last 0.3 s is too late (and the douse reaches every screen in time)
const CHAIN_DELAY_MIN := 0.3        ## a chained explosive's fuse: this ...
const CHAIN_DELAY_PER_UNIT := 0.08  ## ... plus this per world unit from the blast that lit it
const EDGE_MULT := 0.35             ## damage and shove at the rim, as a share of the centre's
const BURN_POWER := 0.7             ## the blast sets people on fire like a fireball of this power, over 0.75 of its radius
const TOUCH_SLACK := 0.15           ## a burning actor this close (edge to edge) lights it
const CLIENT_LATE := 1.0            ## a copy told of a fuse whose blast is further gone than this shows no blast of its own

## The blast of each kind: radius (world units), damage at the centre, shove at the centre, fuse (seconds).
const BLAST := {
	"oil_drum": {"radius": 3.0, "damage": 45.0, "shove": 2.6, "fuse": 1.3},
	"gas_cylinders": {"radius": 3.2, "damage": 50.0, "shove": 2.8, "fuse": 1.0},
	"propane_tank": {"radius": 3.4, "damage": 55.0, "shove": 3.0, "fuse": 1.2},
	"battery_pack": {"radius": 2.8, "damage": 40.0, "shove": 2.4, "fuse": 1.5},
}

var blast_radius := 3.0
var blast_damage := 45.0
var blast_shove := 2.6
var fuse_time := 1.25
var fuse_start := -1.0              ## GameWorld.time the fuse was lit; -1 while not lit
var fuse_end := -1.0                ## GameWorld.time it blows
var blown := false                  ## it went off (the owner)
## The actors this machine's blast applied its damage to (tests, the combat log).
var last_hits: Array[Actor] = []

var _igniter: WeakRef = null
var _blasted := false
var _fuse_fx: FuseFx = null
var _touch_tick := 0


# --- Static helpers ----------------------------------------------------------------------------------

## A fireball's blast at `pos` (SpellBook: every machine runs the cast; the host lights its own props here, a client's
## hit request that follows finds the fuse already burning). A soaked one fizzles.
static func fire_at(pos: Vector3, radius: float, source: Node) -> void:
	if GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return
	for n in GameWorld.root.get_tree().get_nodes_in_group(HAZARD_GROUP):
		var e := n as ExplosiveProp
		if e == null or e.dead or not Net.owns(e):
			continue
		if GameWorld.flat_distance(e.global_position, pos) <= radius + e.radius:
			e.catch_fire(source)


## What a shot (an arrow or a bolt) does to `target`: at least HARD_HIT to an explosive prop (it punctures and lights),
## its own damage to anything else. Run where the hit resolves, so the amount travels in a client's hit request.
static func shot_damage(target: Actor, damage: float) -> float:
	if damage > 0.0 and target is ExplosiveProp:
		return maxf(damage, HARD_HIT)
	return damage


## A chained explosive `dist` units from the blast lights on this short fuse.
static func chain_delay(dist: float) -> float:
	return CHAIN_DELAY_MIN + CHAIN_DELAY_PER_UNIT * maxf(dist, 0.0)


## Whoever a damage `source` stands for: a blast stands for whoever set it off (null if unknown).
static func blame_of(source: Node) -> Node:
	if source != null and is_instance_valid(source) and source is ExplosiveProp:
		return (source as ExplosiveProp).igniter()
	return source if source != null and is_instance_valid(source) else null


# --- Setup ----------------------------------------------------------------------------------------------

func setup(kind_id: String, opts: Dictionary = {}) -> void:
	super(kind_id, opts)
	var b: Dictionary = BLAST.get(kind_id, BLAST["oil_drum"])
	blast_radius = float(b["radius"])
	blast_damage = float(b["damage"])
	blast_shove = float(b["shove"])
	fuse_time = float(b["fuse"])


func _ready() -> void:
	super()
	add_to_group(HAZARD_GROUP)


## Who may write each var (see Net). PricedProp's come from super(). The host owns the fuse; every machine runs the blast.
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"blast_radius": Net.SPAWN, "blast_damage": Net.SPAWN, "blast_shove": Net.SPAWN, "fuse_time": Net.SPAWN,
		"fuse_start": Net.OWNER, "fuse_end": Net.OWNER,   # obj.fuse (NetObjects): the host's start and end
		"_igniter": Net.OWNER,                            # obj.fuse "by": whoever set it off (the bill)
		"blown": Net.OWNER,                               # the blast is scheduled at fuse_end on every machine; obj.break
		"_blasted": Net.LOCAL,                            # this machine has run its blast
		"last_hits": Net.LOCAL,                           # what this machine's blast applied
		"_fuse_fx": Net.LOCAL,
		"_touch_tick": Net.PRIVATE,                       # the host's scan for burning walkers
	})
	return f


# --- State -------------------------------------------------------------------------------------------------

func is_lit() -> bool:
	return fuse_end >= 0.0 and not blown


## Seconds to the blast (0 when not lit).
func fuse_left() -> float:
	return maxf(0.0, fuse_end - GameWorld.time) if is_lit() else 0.0


## Whoever set it off (null: nobody yet, or unknown).
func igniter() -> Node:
	if _igniter == null:
		return null
	var n := _igniter.get_ref() as Node
	return n if n != null and is_instance_valid(n) else null


## Ledger.culprit_name asks this: a blast's damage is blamed on whoever set it off.
func blamed() -> Node:
	return igniter()


## The bill: whoever set it off, else (a dud break) the last thing that hit it.
func last_culprit() -> Node:
	var who := igniter()
	return who if who != null else super()


# --- Lighting it (the owner) -------------------------------------------------------------------------------

## Light the fuse, blamed on `culprit` (a blast stands for its igniter). `delay` < 0 is this kind's fuse. False when it
## cannot light: already lit or gone, a copy (the host decides), or soaked.
func ignite(culprit: Node = null, delay: float = -1.0) -> bool:
	if dead or blown or is_lit() or Net.is_copy(self) or not is_inside_tree():
		return false
	if Burning.is_soaked(self):
		return false
	var who := blame_of(culprit)
	_igniter = weakref(who) if who != null else null
	if who != null:
		_last_source = weakref(who)
	fuse_start = GameWorld.time
	fuse_end = fuse_start + (fuse_time if delay < 0.0 else delay)
	_show_fuse()
	lit.emit(self, who, fuse_start, fuse_end)
	return true


## Fire reached it (a fireball's blast, a burning actor): it lights, or a soaked one fizzles.
func catch_fire(culprit: Node) -> bool:
	if Burning.is_soaked(self):
		if not dead and not is_lit():
			var steam: Array[Color] = [Color(0.85, 0.92, 0.98), Color(0.6, 0.7, 0.78)]
			Fx.burst(global_position + Vector3.UP * model_height() * 0.6, steam, 8, 1.4, 0.16, 0.8, -1.2, Vector3.UP, 45.0, false)
		return false
	return ignite(culprit)


## Put a burning fuse out (a soak landed on it in time). The owner tells the other screens (`doused`).
func douse() -> void:
	if not is_lit():
		return
	fuse_start = -1.0
	fuse_end = -1.0
	_igniter = null
	_hide_fuse(true)
	doused.emit(self)


## Hits: a hard one lights it (and dents it, never past 1 HP: it goes up in the blast, not before); so does a dent that
## would break it. Below HARD_HIT it is any prop's free dent. A burning fuse ignores hits; a soaked prop is a plain prop.
func apply_damage(amount: float, source: Node = null) -> float:
	if dead or amount <= 0.0 or Net.is_copy(self):
		return super(amount, source)   # (a copy: a request to the host)
	if is_lit() or blown:
		return 0.0
	if Burning.is_soaked(self):
		return super(amount, source)   # a dud while wet: a break just breaks it
	var dealt_would := amount * damage_taken_mult()
	if dealt_would >= HARD_HIT or hp - dealt_would <= 0.0:
		var dealt := 0.0
		if hp > 1.0:
			dealt = super(minf(amount, (hp - 1.0) / maxf(damage_taken_mult(), 0.0001)), source)
		ignite(source)
		return dealt
	return super(amount, source)


## A shove ON it (tentacles, the spin, a blast): the prop does not move, but a hard one lights it like a hit.
func shove(dir: Vector3, distance: float, source: Node = null) -> void:
	if Net.is_copy(self) or dead:
		super(dir, distance, source)   # (a copy: a request to the host)
		return
	if distance >= HARD_SHOVE:
		apply_damage(distance * SHOVE_DAMAGE_PER_UNIT, source)


# --- Every frame -------------------------------------------------------------------------------------------

## The owner: the fuse (douse or blast) and the burning walkers. (A copy's physics is off: it shows the host's fuse.)
func _physics_process(delta: float) -> void:
	super(delta)
	if dead:
		return
	if is_lit():
		if Burning.is_soaked(self) and GameWorld.time < fuse_end - DOUSE_LOCK:
			douse()
		elif GameWorld.time >= fuse_end:
			_blast()
		return
	_touch_tick += 1
	if _touch_tick % 3 == 0:
		_check_fire_touch()


func _process(delta: float) -> void:
	super(delta)
	# A copy runs its own blast at the fuse's end on its clock (the host's obj.fuse set it): its hero is hit here, once.
	if Net.is_copy(self) and is_lit() and not _blasted and not dead and GameWorld.time >= fuse_end:
		_detonate(igniter())


## A burning actor touching it lights it, blamed on whoever set the walker on fire (else the walker).
func _check_fire_touch() -> void:
	if Burning.is_soaked(self):
		return
	for a in GameWorld.actors_in_radius(global_position, radius + TOUCH_SLACK):
		if a == self or a.dead or not Burning.is_burning(a):
			continue
		if a.global_position.y - global_position.y > model_height():
			continue
		var who := Burning.culprit(a)
		ignite(who if who != null else a)
		return


## The owner's blast: every other explosive in reach lights on its chain fuse first, then the blast runs, then it breaks
## (the bill).
func _blast() -> void:
	if blown or dead:
		return
	blown = true
	var who := igniter()
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group(HAZARD_GROUP):
			var e := n as ExplosiveProp
			if e == null or e == self or e.dead or not Net.owns(e):
				continue
			var d := GameWorld.flat_distance(e.global_position, global_position)
			if d <= blast_radius + e.radius:
				e.ignite(who if who != null else self, chain_delay(d))
	_detonate(who)
	die()


## The blast on THIS machine (the owner at the fuse's end, a copy on its own clock): the look, the hits this machine
## resolves (Combat.explode decided by the prop), the fires, the noise.
func _detonate(who: Node) -> void:
	if _blasted:
		return
	_blasted = true
	_hide_fuse(false)
	var pos := global_position
	BlastFx.play(pos, blast_radius, PropModels.palette(kind), model_height())
	last_hits = Combat.explode(pos, blast_radius, blast_damage, -1, who, EDGE_MULT, blast_shove, self)
	Burning.on_blast(pos, blast_radius * 0.75, BURN_POWER, who)   # (each actor's owner rolls its own)
	MonsterSenses.noise(pos, MonsterSenses.NOISE_CORN, "explosion")   # (only the monsters this machine runs hear it)
	if _model != null:
		_model.visible = false   # (a copy: the host's obj.break follows with the rubble)
	if tag_label != null:
		tag_label.visible = false
	blew.emit(self)


func _on_death() -> void:
	if is_lit() and not _blasted:
		_detonate(igniter())   # (a copy told of the break before its own clock reached the blast)
	_hide_fuse(false)
	if not _blasted and Burning.is_soaked(self):
		Fx.number(global_position + Vector3.UP * (model_height() + 0.9), "DUD", Color(0.6, 0.88, 1.0), 0.9)
	super()


# --- A copy (NetObjects) ---------------------------------------------------------------------------------

## The host lit it: the fuse runs from `start` to `end` (this machine's GameWorld.time), set off by `by`.
func net_fuse(start: float, end: float, by: Node) -> void:
	if dead or blown or _blasted:
		return
	_igniter = weakref(by) if by != null else null
	fuse_start = start
	fuse_end = end
	if GameWorld.time - end > CLIENT_LATE:
		_blasted = true   # (told far too late: the break is on its way; no blast of its own now)
		return
	_show_fuse()


## Host: a prop's links (obj.hurt, obj.break), and the fuse: `obj.fuse {id, s, e, by}` when it lights (its start and end on
## the shared clock, who set it off: every machine runs the blast itself at the end, a scheduled effect, and the break and
## its bill follow as obj.break), `obj.out {id}` when a soak puts it out in time (at least DOUSE_LOCK before its end).
func net_link(objects: NetObjects, id: int) -> void:
	super(objects, id)
	objects.link(lit, _net_lit.bind(objects, id))
	objects.link(doused, _net_doused.bind(objects, id))


func _net_lit(_prop: ExplosiveProp, culprit: Node, start: float, end: float, objects: NetObjects, id: int) -> void:
	objects.tell("obj.fuse", {"id": id, "s": objects.host_stamp(start), "e": objects.host_stamp(end), "by": NetObjects.net_id(culprit)})
	objects.count("fuses")


func _net_doused(_prop: ExplosiveProp, objects: NetObjects, id: int) -> void:
	objects.tell("obj.out", {"id": id})
	objects.count("outs")


## Client: the host lit the fuse (obj.fuse) or put it out (obj.out); a dent or the break as any prop's.
func net_event(kind: String, data: Dictionary, objects: NetObjects) -> void:
	match kind:
		"obj.fuse":
			_net_fuse_event(data, objects)
		"obj.out":
			if not dead:
				net_douse()
				objects.count("outs")
		_:
			super(kind, data, objects)


func _net_fuse_event(data: Dictionary, objects: NetObjects) -> void:
	if dead:
		return
	net_fuse(objects.local_stamp(float(data.get("s", objects.now()))), objects.local_stamp(float(data.get("e", objects.now()))),
		NetRegistry.node(int(data.get("by", 0))))
	objects.count("fuses")


## Host: a prop's dent, and a fuse burning now for a late joiner, `fuses` [id, start, end, igniter] (an obj.fuse replay, so the
## joiner runs the blast at the same moment).
func late_join_state(objects: NetObjects, id: int) -> Dictionary:
	var rows := super(objects, id)
	if not dead and is_lit():
		rows["fuses"] = [id, objects.host_stamp(fuse_start), objects.host_stamp(fuse_end), NetObjects.net_id(igniter())]
	return rows


func apply_late_join(section: String, row: Array, objects: NetObjects) -> void:
	if section != "fuses":
		super(section, row, objects)
	elif row.size() >= 4:
		_net_fuse_event({"id": row[0], "s": row[1], "e": row[2], "by": row[3]}, objects)


## The host put the fuse out.
func net_douse() -> void:
	if not is_lit() or _blasted:
		return
	fuse_start = -1.0
	fuse_end = -1.0
	_igniter = null
	_hide_fuse(true)


# --- The look -------------------------------------------------------------------------------------------------

func _show_fuse() -> void:
	_hide_fuse(false)
	if not is_inside_tree():
		return
	_fuse_fx = FuseFx.attach(self, _model, PropModels.fuse_point(kind), blast_radius, fuse_start, fuse_end)


func _hide_fuse(doused_now: bool) -> void:
	if _fuse_fx != null and is_instance_valid(_fuse_fx):
		_fuse_fx.stop(doused_now)
		if doused_now and is_inside_tree() and not _any_fuse_lit():
			Sfx.stop_cue("fuse", 0.08)
	_fuse_fx = null


func _any_fuse_lit() -> bool:
	for n in get_tree().get_nodes_in_group(HAZARD_GROUP):
		var e := n as ExplosiveProp
		if e != null and e != self and e.is_lit() and not e._blasted:
			return true
	return false
