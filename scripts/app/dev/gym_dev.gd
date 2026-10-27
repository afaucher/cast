class_name GymDev
extends Node
## THE TEST GYM (`--gym`, docs/design/test-gym.md): a solo dev mode for trying characters, spells, monsters and every
## environment on one fixed map (GymMap). GameDev (scripts/app/dev/game_dev.gd) swaps the map in (_dev_floor) and adds this
## node once the floor is ready; in a shared run the flag is refused (the gym is solo only) and nothing here is made.
##
## What it gives the player (all dev only, never outside --gym):
##   - the CHARACTER SWITCH: F2 (Shift+F2 back) or the panel's hero buttons re-kit the player's own hero node as any HeroKit
##     hero (Hero.become, as a seat handover does: same node, same spell slots, HP fraction kept); an AI ally who was that
##     hero takes the player's old one, so the allies always fill the other characters
##   - the SPAWN PANEL (GymPanel, F9 hides it): a button for every GymSpawns entry (monsters, dummies, props, explosives,
##     staff, components, gates, decor), x1 / x5 / x10. A button puts them at the RING, which follows the mouse over the
##     world (it stays put while the mouse is on the panel); G or a middle-click puts the last picked kind at the cursor
##   - the TOOLS: infinite components (on by default: the slots never run out, a picker per slot puts any spell in it),
##     spell cooldowns off, monster AI off (F4: monsters stand as dummies, still hit and shoved), god mode (F8: the crew
##     takes no damage), hit areas (F3: GymOverlay), heal the crew (the downed get up), refill the spells once, clear the
##     monsters, clear what the panel put down, a mixed pack, teleports, and the HIT LOG (GymStats: hits, and damage dealt
##     and taken per minute)
##   - three training dummies (GymSpawns.DUMMY_HP) on the arena's north side
##   - the EXPERIMENTS (GymPanel's pickers; the user, 2026-10-23: "lets put experiments in the gym menu instead of adding
##     keybindings"): the movement profile (MoveFeel: today / grounded / grounded_anim, the default) and the judder
##     smoothing (MoveFeel.interp, off by default), live; and the monsters' walk (MonsterModel.active_walk: old / new, the
##     default). A new A/B goes here, not on a key; its switch goes once it is settled (the heroes' elbow IK went on
##     2026-10-25: "Looks great, we can remove the switch").
##   - the HALLWAY LANDINGS' A/B (docs/design/hallways.md): the "Landings" picker (off / on, the default) is the generator's
##     switch (DungeonGen.landings), and the "Map" picker leaves the gym's fixed map for the contract's GENERATED floor
##     (`generated`: the scene reloads on that floor, solo, with this panel kept; "gym" comes back). On a generated floor a
##     Landings pick rebuilds it at once, and the Go to buttons are its landings. The elevator goes down to the next
##     generated floor as ever
##   - the WAR CRY button: the nearest monster of each kind yells once (Monster.yell), to audition the cries without a fight
##     (the user's takes, settled 2026-10-25: their "War cries" picker came out)
##   - the HALLWAY PACKS (to watch a pack come down a hall; Monster's crowd variety): "Hallway x12" puts 12 skeletons at the lobby end of the arena-lobby hall
##     (the gym's longest straight run) and the crew at its arena end, and sends them at the player; "Hallway mix" is the same
##     with a brute and imps among them

const GAME := preload("res://scripts/app/game.gd")
const FLAG := "--gym"              ## the command line's flag; the main menu's gym door (the garage's dead H) hands it in too
const DEFAULT_SPELLS := "fireball,heal,damp,tentacles"
const STAGE_DUMMIES := 3
const PACK_BUDGET := 14
const GOD_ID := "gym_god"
const STATS_EVERY := 0.25
## The hallway packs: the hall from the arena to the lobby (GymMap.LINKS), the crew at its arena end, the pack at the far end.
const HALL_FROM := "arena"
const HALL_TO := "lobby"
const HALL_COUNT := 12
const HALL_MIX: Array[String] = ["brute", "grunt", "grunt", "swarmer", "swarmer", "grunt", "grunt", "swarmer", "swarmer",
		"grunt", "grunt", "grunt"]
const HALL_LEASH := 40.0           ## (a hall pack chases down the hall and into the arena: no leash home on the way)
const GOTO: Array[String] = ["arena", "lobby", "course_pad", "course_top", "course_end", "cinema", "throne", "pool", "moat",
		"barracks", "sewer_a", "sewer_c", "cave_a", "isle_shore", "cave_b"]
const LANDING_SPOT := "landing_"   ## a generated floor's Go to buttons: landing_0, landing_1, ...

## The "Map" experiment: true while the gym's panel runs on the contract's generated floor instead of the gym's map (GameDev
## reads it in _dev_floor; it survives the scene reloads, and game.gd's reset_flow forgets it).
static var generated := false

var game: Node = null              ## the GameDev node (its crew, HUD, site, controller)
var panel: GymPanel
var stats: GymStats
var overlay: GymOverlay
var ring: MeshInstance3D
var entries: Array[Dictionary] = []
var count := 1
var selected := ""                 ## the entry G / a middle-click spawns
var ai_on := true
var god := false
var infinite := true
var no_cooldowns := false
var spawned: Array[Node] = []      ## what the panel put down (Clear spawned)
var staged: Array[Node] = []       ## the arena's dummies
var ring_at := Vector3.INF
var _god_t := 0.0
var _stats_t := 0.0


## --gym: the flag, the gym's spells (the license is skipped) and its seed, unless the command line names them. Not in a
## crew: the gym is solo only (GameDev refuses it in a shared run). `args` is game.gd's launch_args(): the command line plus
## what the main menu asked for (MainMenu.open_gym), so an exported build opens it with no command line at all.
static func parse(args: PackedStringArray, opts: Dictionary) -> void:
	if not args.has(FLAG):
		return
	opts["gym"] = true
	var crew := args.has("--net-host") or args.has("--net-join") or args.has("--net-wait")
	if not opts.has("spells") and not crew:
		opts["spells"] = DEFAULT_SPELLS
	if not opts.has("seed"):
		opts["seed"] = GymMap.SEED
	var t := args.find("--gym-tour")
	if t >= 0 and t + 1 < args.size():
		opts["gym_tour"] = args[t + 1]


func _init() -> void:
	name = "GymDev"


## Attach to the running game (after its floor is ready). Builds the panel, the overlay, the ring and the dummies.
func setup(g: Node) -> void:
	game = g
	g.add_child(self)
	entries = GymSpawns.entries()
	stats = GymStats.new()
	stats.name = "GymStats"
	add_child(stats)
	overlay = GymOverlay.new()
	overlay.name = "GymOverlay"
	overlay.visible = false
	GameWorld.root.add_child(overlay)
	ring = _make_ring()
	GameWorld.root.add_child(ring)
	panel = GymPanel.new()
	add_child(panel)
	var spells: Array[String] = SpellBook.ids()
	panel.build(entries, HeroKit.ids(), spells,
		[["infinite", "Infinite", infinite], ["no_cooldowns", "No cooldown", no_cooldowns], ["ai", "AI", ai_on],
			["god", "God", god], ["areas", "Areas", false]],
		[["heal", "Heal crew"], ["refill", "Refill spells"], ["clear", "Clear monsters"], ["clear_spawned", "Clear spawned"], ["pack", "Spawn pack"],
			["hall", "Hallway x12"], ["hall_mix", "Hallway mix"], ["cry", "War cry"], ["reset_log", "Reset log"]],
		spots(), experiments())
	panel.spawn_pressed.connect(func(id: String) -> void: spawn(id, ring_point()))
	panel.hero_pressed.connect(switch_to)
	panel.slot_picked.connect(set_slot)
	panel.toggled.connect(set_toggle)
	panel.action_pressed.connect(act)
	panel.count_picked.connect(func(n: int) -> void: count = n)
	panel.goto_pressed.connect(go_to)
	panel.experiment_picked.connect(set_experiment)
	GameWorld.actor_spawned.connect(_on_spawned)
	_bind()
	if generated:
		var lands := GameWorld.map.landings.size() if GameWorld.map != null else 0
		_status("generated floor: %d landing%s, landings %s" % [lands, "" if lands == 1 else "s", "on" if DungeonGen.landings else "off"])
	else:
		stage()
	_log("test gym: %d spawnable kinds (%d listed), F9 hides the panel" % [entries.filter(func(e: Dictionary) -> bool: return str(e["skip"]) == "").size(), entries.size()])


func _exit_tree() -> void:
	if GameWorld.actor_spawned.is_connected(_on_spawned):
		GameWorld.actor_spawned.disconnect(_on_spawned)


## The crew as it is now into the readouts.
func _bind() -> void:
	var p := player()
	stats.player = p
	stats.crew = heroes()
	overlay.player = p
	if p != null:
		panel.set_hero(p.kit_id)
		panel.set_slots(p.spell_slots)


func player() -> Hero:
	return game.get("player") as Hero if game != null else null


func heroes() -> Array[Hero]:
	var out: Array[Hero] = []
	if game == null:
		return out
	var by_seat: Dictionary = game.get("heroes_by_seat")
	var seats: Array = by_seat.keys()
	seats.sort()
	for s: int in seats:
		var h: Hero = by_seat[s]
		if is_instance_valid(h):
			out.append(h)
	return out


func _log(text: String) -> void:
	if game != null and game.has_method("_log"):
		game.call("_log", text, Color(1.0, 0.85, 0.4))


# --- staging -----------------------------------------------------------------------------------------------------------

## Three static training dummies in a row on the arena's north side.
func stage() -> void:
	var at := Hex.to_world(GymMap.center_of("arena") + Hex.DIRS[2] * 5 + Hex.DIRS[1] * 1)
	staged = GymSpawns.spawn(GymSpawns.find("dummy:static"), at, STAGE_DUMMIES, null, null)


# --- spawning ----------------------------------------------------------------------------------------------------------

## Spawn `count` of entry `id` round `at` (the ring when the panel asked). It becomes the kind G / a middle-click spawns.
func spawn(id: String, at: Vector3) -> Array[Node]:
	var e := GymSpawns.find(id)
	var made: Array[Node] = []
	if e.is_empty():
		return made
	selected = id
	panel.set_selected(id)
	if str(e["skip"]) != "":
		_status("%s: %s" % [e["label"], e["skip"]])
		return made
	made = GymSpawns.spawn(e, at, count, game.get("_site"), game.get("_run"))
	spawned.append_array(made)
	_status("%s x%d: %d placed" % [e["label"], count, made.size()] if not made.is_empty() else "%s: no room there" % e["label"])
	return made


## Where a panel button spawns: the ring (the last floor point under the mouse), or in front of the player.
func ring_point() -> Vector3:
	if ring_at != Vector3.INF:
		return ring_at
	var p := player()
	return p.global_position + p.facing * 5.0 if p != null else Vector3.ZERO


func cursor_point() -> Vector3:
	var c: PlayerController = game.get("controller")
	return c.aim_point() if c != null else ring_point()


func _on_spawned(a: Actor) -> void:
	if not ai_on and a is Monster:
		a.set_physics_process(false)


# --- the character switch ----------------------------------------------------------------------------------------------

## The player becomes hero `kit` (a HeroKit id); the ally who was it takes the player's old hero.
func switch_to(kit: String) -> void:
	var p := player()
	if p == null or not HeroKit.has_kit(kit) or p.kit_id == kit:
		return
	var old := p.kit_id
	for a: Hero in (game.get("allies") as Array):
		if is_instance_valid(a) and a.kit_id == kit:
			_rekit(a, old, false)
			_rebrain(a)
	_rekit(p, kit, false)
	var hud: Hud = game.get("hud")
	if hud != null:
		hud.bind(p, game.get("allies"))
	_bind()
	_status("You are %s" % p.display_name)


## Cycle through HeroKit's heroes (F2; back with Shift).
func cycle(step: int) -> void:
	var p := player()
	if p == null:
		return
	var ids := HeroKit.ids()
	var i := ids.find(p.kit_id)
	switch_to(ids[posmod(i + step, ids.size())])


func _rekit(h: Hero, kit: String, full: bool) -> void:
	var looks: Dictionary = GAME.CREW_LOOKS
	var look: Dictionary = looks.get(kit, {"name": kit.capitalize(), "color": Color(0.7, 0.7, 0.75)})
	var proto := bool((game.get("opts") as Dictionary).get("proto_heroes", false))
	h.become(kit, str(look["name"]), look["color"], null if proto else game.call("_model_for", kit), full)
	for s: Dictionary in (game.get("_seat_info") as Array):
		if int(s["seat"]) == int(game.call("_seat_of", h)):
			s["character"] = kit


## An AI ally's brain again for its (new) hero: an archer keeps its distance.
func _rebrain(h: Hero) -> void:
	var brain := h.get_node_or_null("AllyBrain")
	if brain == null:
		return
	h.remove_child(brain)
	brain.queue_free()
	var by_seat: Dictionary = game.get("heroes_by_seat")
	game.call("_make_ai", h, int(game.call("_seat_of", h)), by_seat.get(1, player()))


# --- spells ------------------------------------------------------------------------------------------------------------

## Put `spell` ("" empties it) in the player's slot `slot` (0-based); a spell already in another slot swaps over.
func set_slot(slot: int, spell: String) -> void:
	var p := player()
	if p == null:
		return
	var slots: Array[String] = p.spell_slots.duplicate()
	while slots.size() <= slot:
		slots.append("")
	var j := slots.find(spell)
	if spell != "" and j >= 0 and j != slot:
		slots[j] = slots[slot]
	slots[slot] = spell
	while not slots.is_empty() and slots[slots.size() - 1] == "":
		slots.remove_at(slots.size() - 1)
	p.spell_slots = slots
	if spell != "":
		p.set_charges(spell, SpellComponents.MAX_CHARGES)
		p.select_slot(slots.find(spell))
	panel.set_slots(p.spell_slots)


func set_toggle(nm: String, on: bool) -> void:
	match nm:
		"infinite":
			infinite = on
		"no_cooldowns":
			no_cooldowns = on
		"ai":
			set_ai(on)
		"god":
			set_god(on)
		"areas":
			overlay.visible = on
	panel.set_toggle(nm, on)
	_status("%s %s" % [nm.replace("_", " "), "on" if on else "off"])


## Monster AI off: every monster stands (its physics off; GymDev runs its look); a hit still lands and shoves it.
func set_ai(on: bool) -> void:
	ai_on = on
	for a in GameWorld.actors():
		if a is Monster and not a.dead:
			a.set_physics_process(on)


func set_god(on: bool) -> void:
	god = on
	for h in heroes():
		if not Net.owns(h):
			continue
		if on:
			h.set_modifier(GOD_ID, 0.0, 2.0)
		else:
			h.clear_modifier(GOD_ID)


func act(nm: String) -> void:
	match nm:
		"heal":
			heal_crew()
		"refill":
			var p := player()
			if p != null:
				for id in p.spell_slots:
					if id != "":
						p.set_charges(id, SpellComponents.MAX_CHARGES)
				p.reset_spell_cooldowns()
				_status("spells refilled")
		"clear":
			_status("cleared %d monsters" % clear_monsters())
		"clear_spawned":
			var n := 0
			for s in spawned:
				if is_instance_valid(s) and not s.is_queued_for_deletion():
					s.queue_free()
					n += 1
			spawned.clear()
			_status("cleared %d spawned things" % n)
		"pack":
			var made := GymSpawns.spawn_pack(ring_point(), PACK_BUDGET)
			spawned.append_array(made)
			_status("a pack of %d" % made.size())
		"hall", "hall_mix":
			if generated:
				_status("the hallway packs need the gym's map (Map: gym)")
				return
			_status("a hallway pack of %d" % hall_pack(nm == "hall_mix").size())
		"cry":
			var kinds := cry_each()
			_status("war cry: %s" % ", ".join(kinds) if not kinds.is_empty() else "war cry: no monster to yell")
		"reset_log":
			stats.reset()


## The WAR CRY button: the living monster of each kind nearest the player yells once (Monster.yell). Returns the kinds
## that yelled, sorted.
func cry_each() -> Array[String]:
	var p := player()
	var at := p.global_position if p != null else ring_point()
	var best := {}
	for a in GameWorld.actors():
		var m := a as Monster
		if m == null or m.dead or Monster.CRY_SKIP.has(m.kind):
			continue
		var d := GameWorld.flat_distance(at, m.global_position)
		if not best.has(m.kind) or d < float(best[m.kind][1]):
			best[m.kind] = [m, d]
	var kinds: Array[String] = []
	for k: String in best:
		(best[k][0] as Monster).yell()
		kinds.append(k)
	kinds.sort()
	return kinds


## A hallway pack (the crowd variety's A/B): HALL_COUNT skeletons (`mixed`: HALL_MIX, a brute and imps among them) on the
## free cells nearest the far end of the arena-lobby hall, the crew moved to its arena end, and every one sent at the
## player. Returns the monsters.
func hall_pack(mixed: bool) -> Array[Node]:
	var made: Array[Node] = []
	var map := GameWorld.map
	var link := hall_link()
	if map == null or link.is_empty():
		return made
	var dir: Vector2i = Hex.DIRS[int(link["dir"])]
	if game != null:
		game.call("_teleport_crew", link["door_a"] as Vector2i)
	var far: Vector2i = link["door_b"]
	var cells := GymSpawns.cells_near(map, Hex.to_world(far + dir), HALL_COUNT)
	for i in cells.size():
		var m := MonsterFactory.spawn(HALL_MIX[i % HALL_MIX.size()] if mixed else "grunt", cells[i])
		if m == null:
			continue
		m.leash_range = HALL_LEASH
		made.append(m)
	spawned.append_array(made)
	var p := player()
	if p != null:
		for m in made:
			(m as Monster).aggro(p)
	return made


## The arena-lobby hall's row of GymMap.layout()["links"]: {a, b, dir, n, lanes, door_a (the arena's end), door_b}.
static func hall_link() -> Dictionary:
	for lk: Dictionary in (GymMap.layout()["links"] as Array):
		if str(lk["a"]) == HALL_FROM and str(lk["b"]) == HALL_TO:
			return lk
	return {}


## The panel's experiments: [name, label, values, current].
static func experiments() -> Array:
	return [["feel", "Movement", MoveFeel.ORDER, MoveFeel.active()],
		["smoothing", "Smoothing", ["off", "on"], "on" if MoveFeel.interp else "off"],
		["walk", "Monster walk", ["old", "new"], "new" if MonsterModel.active_walk else "old"],
		["landings", "Landings", ["off", "on"], "on" if DungeonGen.landings else "off"],
		["map", "Map", ["gym", "generated"], "generated" if generated else "gym"]]


## The Go to buttons: the gym's places, or on a generated floor its landings.
func spots() -> Array:
	if not generated:
		return GOTO
	var out: Array[String] = []
	var map := GameWorld.map
	for i in (map.landings.size() if map != null else 0):
		out.append(LANDING_SPOT + str(i))
	return out


## An experiment picked in the panel: "feel" plays that movement profile (MoveFeel.pick), "smoothing" turns the judder
## smoothing on or off (MoveFeel.interp). The status line and the corner dev tag (MoveFeelTag's) say which; the passive move
## log starts a new stretch. "walk" plays the monsters' old or new walk (MonsterModel.active_walk), live; the status line
## says which.
func set_experiment(nm: String, value: String) -> void:
	var text := ""
	if nm == "landings" or nm == "map":
		_set_floor_experiment(nm, value)
		return
	if nm == "walk":
		if value != "old" and value != "new":
			return
		MonsterModel.active_walk = value == "new"
		text = "monster walk: %s" % value
		panel.set_experiment(nm, value)
		_status(text)
		return
	match nm:
		"feel":
			if not MoveFeel.pick(value):
				return
			text = "movement: %s" % MoveFeel.label()
		"smoothing":
			MoveFeel.interp = value == "on"
			text = "smoothing %s" % ("on" if MoveFeel.interp else "off")
		_:
			return
	panel.set_experiment(nm, value)
	_status(text)
	var tag := game.get_node_or_null("MoveFeelTag") as MoveFeelTag if game != null else null
	if tag != null:
		tag.show_tag(text)
		if tag.move_log != null:
			tag.move_log.switched()


## The hallway landings' A/B (docs/design/hallways.md): "landings" sets the generator's switch (DungeonGen.landings), and on
## a generated floor rebuilds it at once; "map" goes to the contract's generated floor (or back to the gym's map) by
## reloading the scene on the same floor of the same contract, this panel kept.
func _set_floor_experiment(nm: String, value: String) -> void:
	match nm:
		"landings":
			if value != "off" and value != "on":
				return
			DungeonGen.landings = value == "on"
			panel.set_experiment(nm, value)
			if generated:
				_status("landings %s: rebuilding the floor" % value)
				_reload()
			else:
				_status("landings %s (Map: generated walks a floor)" % value)
		"map":
			if value != "gym" and value != "generated":
				return
			panel.set_experiment(nm, value)
			if (value == "generated") == generated:
				return
			generated = value == "generated"
			_status("to the generated floor" if generated else "back to the gym")
			_reload()


## Rebuild this floor of the contract (the scene reloads; game.gd's scene changer, a test seam).
func _reload() -> void:
	if game != null and game.has_method("_change_scene"):
		game.call("_change_scene", "")


## Every hero at full health; a downed one gets up (Hero.become, full: as a joiner arrives).
func heal_crew() -> void:
	for h in heroes():
		if not Net.owns(h):
			continue
		if h.dead:
			_rekit(h, h.kit_id, true)
		else:
			h.heal(h.max_hp)
	var hud: Hud = game.get("hud")
	if hud != null:
		hud.bind(player(), game.get("allies"))
	_status("crew healed")


## Remove every monster but the gym's own fauna (its sharks, their gunners, the gator). Returns how many went.
func clear_monsters() -> int:
	var keep := {}
	var site: SiteBuilder.Site = game.get("_site")
	if site != null:
		for s in site.sharks:
			keep[s] = true
		for s in site.gators:
			keep[s] = true
		for s in site.jockeys:
			keep[s] = true
	var n := 0
	for a in GameWorld.actors():
		if a is Monster and not keep.has(a) and not a.is_queued_for_deletion():
			a.queue_free()
			n += 1
	return n


func go_to(spot: String) -> void:
	if spot.begins_with(LANDING_SPOT):
		var map := GameWorld.map
		var i := int(spot.trim_prefix(LANDING_SPOT))
		if map != null and i >= 0 and i < map.landings.size():
			game.call("_teleport_crew", map.landings[i]["center"] as Vector2i)
			_status("at landing %d" % i)
		return
	var gym_spots := GymMap.spots(GameWorld.map)
	if gym_spots.has(spot):
		game.call("_teleport_crew", gym_spots[spot])
		_status("at %s" % spot.replace("_", " "))


func _status(text: String) -> void:
	if panel != null and panel.status_label != null:
		panel.status_label.text = text


# --- every frame -------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var p := player()
	if p != null and not p.dead:
		if infinite:
			for id in p.spell_slots:
				if id != "" and p.charges_of(id) < SpellComponents.MAX_CHARGES:
					p.set_charges(id, SpellComponents.MAX_CHARGES)
		if no_cooldowns:
			p.reset_spell_cooldowns()
	if not ai_on:
		for a in GameWorld.actors():
			if a is Monster and not a.dead and not a.is_physics_processing():
				(a as Monster).net_tick(delta)
	_god_t -= delta
	if god and _god_t <= 0.0:
		_god_t = 0.5
		set_god(true)


func _process(delta: float) -> void:
	if ring != null and panel != null and not panel.is_hovered() and game.get("controller") != null:
		var at := cursor_point()
		if at != Vector3.INF:
			ring_at = at
			ring.global_position = at + Vector3.UP * 0.05
	_stats_t -= delta
	if _stats_t <= 0.0 and panel != null:
		_stats_t = STATS_EVERY
		panel.stats_label.text = stats.text()
		var p := player()
		if p != null:
			panel.set_slots(p.spell_slots)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.physical_keycode:
			KEY_F2:
				cycle(-1 if k.shift_pressed else 1)
			KEY_F3:
				set_toggle("areas", not overlay.visible)
			KEY_F4:
				set_toggle("ai", not ai_on)
			KEY_F8:
				set_toggle("god", not god)
			KEY_F9:
				panel.visible = not panel.visible
			KEY_G:
				if selected != "":
					spawn(selected, cursor_point())
			_:
				return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE:
		if selected != "" and not panel.is_hovered():
			spawn(selected, cursor_point())
			get_viewport().set_input_as_handled()


func _make_ring() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "GymRing"
	var tor := TorusMesh.new()
	tor.inner_radius = 0.55
	tor.outer_radius = 0.7
	tor.rings = 24
	tor.ring_segments = 4
	mi.mesh = tor
	mi.scale = Vector3(1.0, 0.15, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.4, 1.0, 0.55, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	return mi
