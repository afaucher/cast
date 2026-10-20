class_name PartyInfo
extends RefCounted
## What the party HUD (PartyFrame) shows about each crew member and each employee following you, read through the game's
## own APIs only (nothing here is network code: it asks Net / Session, the heroes, their AllyBrain and the employees).
##
## A HERO's row, `hero_view(hero, you)`:
##   name       the Steam / roster name for a seat a person plays (yours: your Steam name, the hero's name without Steam),
##              else the hero's name (an AI seat)
##   character  the hero's name ("Gasket"), shown small when it differs from `name`
##   human      a person plays the seat; `you` it is this machine's own hero
##   avatar     the player's Steam picture (Session.avatars, by the roster's steam_id), or null: the HUD then shows the
##              hero's headshot (Headshots, "hero:<kit>")
##   order      the chip: "follow" / "go" / "hold" / "attack" for an AI hero (Hero.order_state: its AllyBrain writes it on
##              the host, the host sends it to the clients, NetOrders ord.st); for YOUR hero, "go" / "attack" while a
##              crewmate's order marker stands (OrderFx.Marker) with `order_left` (1 -> 0 over its 12 s); "" for another
##              person's hero (nobody orders a person)
##   down, dazed, hp, max_hp, color, kit
##
## EMPLOYEES, `followers(you)`: the living employees following you (Employee.leader() == your hero), and a henchman of
## yours that an "attack" sent into a FIGHT (it has no leader while it fights; the HUD remembers it was yours).
##
## STAGE (dev, screenshots: HudStage): `stage[hero instance id]` overrides {name, avatar, human} for a staged crew.

## Dev: per hero (instance id) -> {name?, avatar?: Texture2D, human?: bool}. Empty in play.
static var stage: Dictionary = {}


static func hero_view(hero: Hero, you: Hero) -> Dictionary:
	var mine := hero == you
	var v := {
		"hero": hero, "you": mine, "kit": hero.kit_id, "character": hero.display_name, "color": hero.hero_color,
		"hp": hero.hp, "max_hp": maxf(1.0, hero.max_hp), "down": hero.dead, "dazed": not hero.dead and hero.is_dazed(),
		"human": mine or hero.has_meta(Net.NAME_META), "name": "", "avatar": null, "order": "", "order_left": 0.0,
	}
	var steam_id := 0
	if mine:
		var entry := _session_entry_local()
		v["name"] = str(entry.get("name", "")) if str(entry.get("name", "")) != "" else SteamIdentity.player_name(hero.display_name)
		steam_id = int(entry.get("steam_id", 0)) if not entry.is_empty() else SteamIdentity.steam_id()
	elif bool(v["human"]):
		v["name"] = Net.label_of(hero)
		steam_id = _steam_id_of_seat(int(hero.get_meta(ContractSession.CREW_SEAT_META, 0)))
	else:
		v["name"] = hero.display_name
	var s := Net.session()
	if steam_id != 0 and s != null and s.avatars != null:
		v["avatar"] = s.avatars.texture(steam_id)
	var staged: Dictionary = stage.get(hero.get_instance_id(), {})
	for k: String in staged:
		v[k] = staged[k]
	var order := order_of(hero, you, bool(v["human"]))
	v["order"] = order[0]
	v["order_left"] = order[1]
	return v


## [chip, share left] for `hero` (see the header).
static func order_of(hero: Hero, you: Hero, human: bool) -> Array:
	if human:
		if hero != you:
			return ["", 0.0]
		var m := OrderFx.Marker.of(hero)
		return [m.kind, m.left()] if m != null else ["", 0.0]
	if hero.dead:
		return ["", 0.0]
	return [hero.order_state, 0.0]


## The employees to list under the crew: following `you`, plus `remembered` ones in a FIGHT (see the header). Sorted by
## name so the strip does not shuffle.
static func followers(you: Hero, remembered: Dictionary = {}) -> Array[Employee]:
	var out: Array[Employee] = []
	if you == null:
		return out
	for e in Employee.alive():
		if e.leader() == you or (e.state == Employee.State.FIGHT and remembered.has(e.get_instance_id())):
			out.append(e)
	out.sort_custom(func(a: Employee, b: Employee) -> bool: return a.display_name < b.display_name)
	return out


## An employee's short name: their name without the part in brackets ("Gary (Henchman 1)" -> "Gary", "Mr. Bloom
## (accounts)" -> "Mr. Bloom").
static func short_name(display_name: String) -> String:
	var i := display_name.find(" (")
	return (display_name.substr(0, i) if i > 0 else display_name).strip_edges()


## "Fight" while a henchman fights, else "follow".
static func employee_state(e: Employee) -> String:
	return "fight" if e.state == Employee.State.FIGHT else "follow"


static func _session_entry_local() -> Dictionary:
	var s := Net.session()
	if s == null or not s.online():
		return {}
	return s.local_entry()


## The Steam id of the person in `seat` (Session.seats -> the roster), or 0.
static func _steam_id_of_seat(seat: int) -> int:
	var s := Net.session()
	if s == null or not s.online() or s.seats == null:
		return 0
	var peer := s.seats.owner_of(seat)
	return int((s.roster.get(peer, {}) as Dictionary).get("steam_id", 0)) if peer != 0 else 0
