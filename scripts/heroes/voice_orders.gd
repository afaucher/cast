class_name VoiceOrders
extends RefCounted
## Voice orders (docs/design/combat-proposals.md 1.0, "As built"): "<name> go | attack | follow".
##
##   give(who, kind, speaker, point)   the speaker's machine (game.gd, from VoiceCaster.order_spoken): online it goes to the
##                                     host (Net.send_order -> NetOrders), solo it is applied here at once
##   apply(who, kind, speaker, point)  the host (or solo): every character the name reaches takes it once
##   feedback(view, local)             every machine: the barks and poses, the speaker's waypoint, a player's marker
##
## NAMES (the official one is the key Incantation emits; its aliases are Incantation's):
##   everyone    the heroes (but the speaker) and every employee in earshot
##   crew        the heroes (but the speaker)
##   rebar / wick / gasket   the hero(es) of that character (two players may both be Wick: both are named)
##   hench       every henchman in earshot; "hench four" only Hench #4 (or the floor's "Henchman 4")
##   pym, reginald, ...      the employee whose name starts with it ("Mrs. Pym", "Gary (Henchman 1)")
## A name nobody on the floor answers to does nothing, quietly.
##
## WHO DOES WHAT: an AI hero (an AllyBrain) takes the order (AllyBrain.give_order); a hero a person plays is shown a marker
## on their own screen ("Fox: go here"), which controls nothing ("follow" sends them nothing); an employee takes it
## (Employee.order: a henchman fights on "attack", staff refuse). Employees only hear a speaker within EARSHOT; the AI heroes
## are on the crew's radio and hear from anywhere. Nobody can be told to follow anyone but the speaker.

const ORDERS := ["go", "attack", "follow"]
## Employees hear an order from this far (world units); the crew hears it anywhere.
const EARSHOT := 16.0
## Titles skipped when an employee's name is matched ("Mrs. Pym" answers to "pym").
const TITLES := ["mr", "mrs", "ms", "miss", "missus", "dr", "sir"]


## The speaker's machine. `point` is where the speaker aims (the waypoint for "go").
static func give(who: String, kind: String, speaker: Hero, point: Vector3) -> void:
	if speaker == null or not ORDERS.has(kind):
		return
	if Net.send_order(who, kind, speaker, point):
		return   # (online: the host applies it and every screen shows it, NetOrders)
	if Net.online() and not Net.is_host():
		return   # (a client off a running floor: nothing to order)
	var r := apply(who, kind, speaker, point)
	feedback({"o": kind, "p": point, "by": speaker, "barks": r["barks"], "marks": r["marks"], "took": r["took"]}, speaker)


## Who a name reaches, as the speaker says it: [Hero or Employee].
static func targets(who: String, speaker: Hero) -> Array:
	var out: Array = []
	for a in GameWorld.team_actors(GameWorld.TEAM_HEROES):
		var h := a as Hero
		if h != null and h != speaker and hero_answers(h, who):
			out.append(h)
	if who == "crew":
		return out
	for e in Employee.alive():
		if employee_answers(e, who) and (speaker == null or GameWorld.flat_distance(e.global_position, speaker.global_position) <= EARSHOT):
			out.append(e)
	return out


static func hero_answers(h: Hero, who: String) -> bool:
	return who == "everyone" or who == "crew" or h.display_name.to_lower() == who


## Does employee `e` answer to the name key `who`?
static func employee_answers(e: Employee, who: String) -> bool:
	match who:
		"everyone":
			return true
		"crew":
			return false
		"hench":
			return e.style == "henchman"
		"hench four":
			return e.display_name.contains("#4") or e.display_name.contains("Henchman 4)")
	return call_name(e.display_name) == who


## The name an employee is called by: the first word of its name that is not a title, lower case ("Mrs. Pym" -> "pym",
## "Gary (Henchman 1)" -> "gary", "Hench #4" -> "hench").
static func call_name(display_name: String) -> String:
	var clean := ""
	for ch in display_name.to_lower():
		clean += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else " "
	for w in clean.split(" ", false):
		if not TITLES.has(w):
			return w
	return ""


## The host (or solo): every character `who` reaches takes the order. Returns {barks: [[Hero, text]] (AI heroes that took
## it), marks: [Hero] (heroes people play, for a marker), took: int, refused: int}.
static func apply(who: String, kind: String, speaker: Hero, point: Vector3) -> Dictionary:
	var out := {"barks": [], "marks": [], "took": 0, "refused": 0}
	if speaker == null or not ORDERS.has(kind):
		return out
	var label := speaker_label(speaker)
	for t: Node in targets(who, speaker):
		if t is Hero:
			var h := t as Hero
			var brain := h.get_node_or_null("AllyBrain") as AllyBrain
			if brain != null:
				var bark := brain.give_order(kind, speaker, point)
				if bark != "":
					out["barks"].append([h, _named(bark, label)])
					out["took"] = int(out["took"]) + 1
			elif kind != "follow" and not h.dead:
				out["marks"].append(h)   # (a person plays it: a marker on their screen, nothing more)
		elif t is Employee:
			match (t as Employee).order(kind, speaker, point):
				"took":
					out["took"] = int(out["took"]) + 1
				"refused":
					out["refused"] = int(out["refused"]) + 1
	return out


## What to call the speaker: their roster name online (two players may both be Wick), else the hero's name.
static func speaker_label(h: Hero) -> String:
	if Net.online():
		var seat := int(h.get_meta(ContractSession.CREW_SEAT_META, NetFloor.id_of(h)))
		for e: Dictionary in Session.crew():
			if int(e.get("seat", 0)) == seat and str(e.get("name", "")) != "":
				return str(e["name"])
	return Net.label_of(h)


## Online the bark names the speaker ("Moving, Fox."); solo there is only one speaker.
static func _named(bark: String, label: String) -> String:
	if not Net.crewed() or bark == "" or label == "":
		return bark
	var last := bark.substr(bark.length() - 1)
	if last == "." or last == "!":
		return "%s, %s%s" % [bark.substr(0, bark.length() - 1), label, last]
	return "%s, %s" % [bark, label]


## Every machine (cosmetic): `view` {o, p, by (the speaker's hero), barks [[Hero, text]], marks [Hero], took}; `local` is
## this machine's own hero. The AI heroes that took it say their line and gesture; the speaker sees a waypoint where a
## "go" sends them; a player the order names sees a marker.
static func feedback(view: Dictionary, local: Hero) -> void:
	var kind := str(view.get("o", ""))
	var p: Vector3 = view.get("p", Vector3.INF)
	var by := view.get("by") as Hero
	for e: Array in view.get("barks", []) as Array:
		var h := e[0] as Hero
		if h != null and is_instance_valid(h):
			OrderFx.bark(h, str(e[1]))
			h.gesture()
	if local == null or p == Vector3.INF:
		return
	if by == local and kind == "go" and int(view.get("took", 0)) > 0:
		OrderFx.waypoint(p, local.hero_color)
	if (view.get("marks", []) as Array).has(local) and by != null and by != local:
		OrderFx.marker(p, "%s: %s" % [speaker_label(by), "go here" if kind == "go" else "attack here"], local, by.hero_color)
