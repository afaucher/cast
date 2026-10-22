class_name GymStats
extends Node
## The test gym's hit log (`--gym`; dev only, solo): every hit the world reports (each actor's `damaged` signal, the one
## Actor.apply_damage emits with what was dealt and its source) sorted into what the player dealt, what the crew dealt and
## what the player took, as counts, totals and a rate per minute over the last WINDOW seconds. Reads only: it changes
## nothing in the fight. reset() starts the count again.

const WINDOW := 60.0
const LOG_SIZE := 6

var player: Hero = null
var crew: Array[Hero] = []
var since := 0.0
var events: Array[Dictionary] = []    ## {t, who: "you" | "crew" | "taken", amount, victim, source}
var last: Array[String] = []          ## the newest hits, newest first (the readout's log)
var _hooked := {}


func _ready() -> void:
	GameWorld.actor_spawned.connect(_hook)
	for a in GameWorld.actors():
		_hook(a)
	reset()


func _exit_tree() -> void:
	if GameWorld.actor_spawned.is_connected(_hook):
		GameWorld.actor_spawned.disconnect(_hook)


func reset() -> void:
	events.clear()
	last.clear()
	since = GameWorld.time


func _hook(a: Actor) -> void:
	if a == null or _hooked.has(a.get_instance_id()):
		return
	_hooked[a.get_instance_id()] = true
	a.damaged.connect(func(amount: float, source: Node) -> void: _on_hit(a, amount, source))


## Who a hit is from: the hero behind a source (the hero itself, or the shooter / caster a projectile or an effect names).
static func hero_of(source: Node) -> Hero:
	if source is Hero:
		return source
	if source == null:
		return null
	for key in ["shooter", "caster", "owner_actor", "source"]:
		var v: Variant = source.get(key)
		if v is Hero:
			return v
	return null


func _on_hit(victim: Actor, amount: float, source: Node) -> void:
	if not is_instance_valid(victim) or amount <= 0.0:
		return
	var h := hero_of(source)
	var who := ""
	if victim == player:
		who = "taken"
	elif h != null and h == player:
		who = "you"
	elif h != null and crew.has(h):
		who = "crew"
	else:
		return
	var t := GameWorld.time
	events.append({"t": t, "who": who, "amount": amount})
	var by: String = h.display_name if h != null else (str(source.name) if source != null else "?")
	if who == "taken":
		by = (source as Actor).display_name if source is Actor else by
	last.push_front("%5.1f  %s -> %s  (%s)" % [amount, by, victim.display_name, _what(source)])
	if last.size() > LOG_SIZE:
		last.resize(LOG_SIZE)


static func _what(source: Node) -> String:
	if source == null:
		return "?"
	if source is Hero:
		return (source as Hero).primary_name
	return str(source.name).rstrip("0123456789@")


## {hits, damage, per_min} for "you", "crew" or "taken" (per_min over the last WINDOW s, or since the reset when sooner).
func totals(who: String) -> Dictionary:
	var hits := 0
	var dmg := 0.0
	var recent := 0.0
	var now := GameWorld.time
	for e in events:
		if str(e["who"]) != who:
			continue
		hits += 1
		dmg += float(e["amount"])
		if now - float(e["t"]) <= WINDOW:
			recent += float(e["amount"])
	var span := clampf(now - since, 1.0, WINDOW)
	return {"hits": hits, "damage": dmg, "per_min": recent / span * 60.0}


## The readout's lines.
func text() -> String:
	var lines: Array[String] = []
	for who: String in ["you", "crew", "taken"]:
		var t := totals(who)
		var label: String = {"you": "You dealt", "crew": "Crew dealt", "taken": "You took"}[who]
		lines.append("%-10s %3d hits  %6.0f  (%5.0f /min)" % [label, int(t["hits"]), float(t["damage"]), float(t["per_min"])])
	lines.append("over %.0f s" % (GameWorld.time - since))
	lines.append_array(last)
	return "\n".join(lines)
