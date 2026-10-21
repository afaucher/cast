class_name SewerCalls
extends Node
## Dispatch's sewer calls on the headset (docs/design/sewer-concept.md, "Polish as built"; NoteCopy.SEWER_CALLS), each at
## most ONCE A FLOOR:
##   SEWER_DOWN    a hero (any of the crew) first stands in a room of the floor's sewer cluster: down the service stair
##   GATOR_SEEN    a living gator is in view on this screen (this machine's fog shows it) within SIGHT of this machine's hero
##   GATOR_BILLED  a gator dies (its death bills its killer once, Gator._on_death); the sighting is not called after it
##   WIRE_LIVE     a panel's live wire fires its first shock (its cable is in the water) and no hero is in its reach ...
##   WIRE_SHOCK    ... or a hero is
## A call waits while the banner still holds or speaks another line (a new line cuts the clip), and is dropped if it waited
## longer than STALE.
##
## COSMETIC and LOCAL (AGENTS.md rule 6, like DispatchBanner and the other calls): every machine watches what it is shown,
## all of it already replicated (the heroes' positions, a gator's death by world.die, a panel's break by obj.break: the wire
## runs from its shared moment on every machine), and puts the line on its own banner. Nothing is sent or decided here; in a
## crew each player's dispatch says the same lines at about the same moments (the sighting is each screen's own).
##
##   var calls := SewerCalls.attach(game, map, site.wires, heroes_fn, func() -> Hero: return player, fog, banner)

const SIGHT := 11.0     ## a gator this close (flat) to this machine's hero, and shown, is seen
const STALE := 12.0     ## a call that waited this long for the banner is dropped
const HOLD := 4.5       ## how long a call holds the banner
const FRESH := 2.0      ## a wire's first shock is called only this soon after it (a late joiner's dead wire is not)
const GATORS := "gators"   ## Gator's group (it leaves "monsters": property, not a pest)

var map: HexMap = null
var wires: Array = []                   ## LiveWire nodes (SiteBuilder.Site.wires)
var heroes := Callable()                ## () -> Array of Actor: the crew on this floor (game: its heroes)
var local_hero := Callable()            ## () -> Actor: this machine's hero (the sighting is its screen's)
var fog: RoomFog = null                 ## null: no fog (--no-fog, tests), everything near is in view
var banner: DispatchBanner = null       ## null (tests): shown lines only go to `shown`
var said := {}                          ## call -> true: called (or queued) on this floor
var shown: Array[String] = []           ## the calls put on the banner, in order (tests, the log)
var _queue: Array = []                  ## [text, queued_at]
var _cluster := {}                      ## "room:N" tags of the cluster
var _wires_done := {}                   ## wire instance id -> true


## Who may write each var (see Net). All presentation, kept per machine.
func net_fields() -> Dictionary:
	return {
		"map": Net.LOCAL, "wires": Net.LOCAL, "heroes": Net.LOCAL, "local_hero": Net.LOCAL, "fog": Net.LOCAL, "banner": Net.LOCAL,
		"said": Net.LOCAL, "shown": Net.LOCAL, "_queue": Net.LOCAL, "_cluster": Net.LOCAL, "_wires_done": Net.LOCAL,
	}


## The calls for this floor, under `parent`. Null on a floor with nothing of the sewer (no cluster, no gator, no wire).
static func attach(parent: Node, m: HexMap, floor_wires: Array, heroes_fn: Callable, hero_fn: Callable, room_fog: RoomFog,
		dispatch: DispatchBanner) -> SewerCalls:
	if m == null or (m.sewer.is_empty() and floor_wires.is_empty() and not _any_gator(parent)):
		return null
	var c := SewerCalls.new()
	c.name = "SewerCalls"
	c.setup(m, floor_wires, heroes_fn, hero_fn, room_fog, dispatch)
	parent.add_child(c)
	return c


static func _any_gator(n: Node) -> bool:
	if n == null or not n.is_inside_tree():
		return false
	for g in n.get_tree().get_nodes_in_group(GATORS):
		if g is Gator:
			return true
	return false


func setup(m: HexMap, floor_wires: Array, heroes_fn: Callable, hero_fn: Callable, room_fog: RoomFog, dispatch: DispatchBanner) -> void:
	map = m
	wires = floor_wires
	heroes = heroes_fn
	local_hero = hero_fn
	fog = room_fog
	banner = dispatch
	_cluster.clear()
	for t: String in (m.sewer.get("rooms", []) as Array):
		_cluster[t] = true


func _ready() -> void:
	GameWorld.actor_died.connect(_on_actor_died)


func _exit_tree() -> void:
	if GameWorld.actor_died.is_connected(_on_actor_died):
		GameWorld.actor_died.disconnect(_on_actor_died)


func _process(_delta: float) -> void:
	tick()


## One look at the floor, then the banner if it is free. (Tests call it directly.)
func tick() -> void:
	if not said.has(NoteCopy.SEWER_DOWN) and _crew_below():
		call_line(NoteCopy.SEWER_DOWN)
	if not said.has(NoteCopy.GATOR_SEEN) and _gator_in_view():
		call_line(NoteCopy.GATOR_SEEN)
	for w in wires:
		_check_wire(w as LiveWire)
	_flush()


## Queue `text` once a floor (a second call of the same line is ignored).
func call_line(text: String) -> void:
	if said.has(text):
		return
	said[text] = true
	_queue.append([text, GameWorld.time])


func _flush() -> void:
	while not _queue.is_empty() and GameWorld.time - float(_queue[0][1]) > STALE:
		_queue.pop_front()
	if _queue.is_empty() or _busy():
		return
	var text: String = _queue.pop_front()[0]
	shown.append(text)
	if banner != null:
		banner.show_line(text, HOLD)


func _busy() -> bool:
	return banner != null and (banner.hold > 0.0 or banner.is_speaking())


func _crew() -> Array:
	return heroes.call() if heroes.is_valid() else []


## A living hero stands in a room of the cluster.
func _crew_below() -> bool:
	if _cluster.is_empty():
		return false
	for h in _crew():
		if not is_instance_valid(h):
			continue
		var a := h as Actor
		if a == null or a.dead:
			continue
		var cell := map.get_cell(a.current_cell())
		if cell != null and _cluster.has(cell.tag):
			return true
	return false


func _gator_in_view() -> bool:
	var me := local_hero.call() as Actor if local_hero.is_valid() else null
	if me == null or me.dead or not is_inside_tree():
		return false
	for n in get_tree().get_nodes_in_group(GATORS):
		var g := n as Gator
		if g == null or g.dead:
			continue
		var d := Vector2(g.global_position.x - me.global_position.x, g.global_position.z - me.global_position.z).length()
		if d <= SIGHT and (fog == null or fog.shows_contents(g.global_position)):
			return true
	return false


func _check_wire(w: LiveWire) -> void:
	if w == null or not is_instance_valid(w) or _wires_done.has(w.get_instance_id()):
		return
	if w.broke_at < 0.0 or w.shocks < 1:
		return
	_wires_done[w.get_instance_id()] = true
	if GameWorld.time - w.broke_at > LiveWire.DROP_T + FRESH:
		return   # (a late joiner's wire: the shock was before this machine was on the floor)
	var hero_hit := false
	for a in w.reached():
		hero_hit = hero_hit or a.team == GameWorld.TEAM_HEROES
	call_line(NoteCopy.WIRE_SHOCK if hero_hit else NoteCopy.WIRE_LIVE)


func _on_actor_died(a: Actor) -> void:
	if a is Gator:
		said[NoteCopy.GATOR_SEEN] = true   # (no "that's the gator" after it is dead, not even one still waiting)
		_queue = _queue.filter(func(q: Array) -> bool: return q[0] != NoteCopy.GATOR_SEEN)
		call_line(NoteCopy.GATOR_BILLED)
