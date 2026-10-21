extends TestCase
## The co-op authority contract (docs/design/networking.md, "Keeping authority straight").
## Keeps new content from quietly breaking the plan.
##
## 1. Declarations: every Actor subclass, every script listed in NET_SCRIPTS and every script that
##    defines net_fields() classifies EVERY script var it has as Net.SPAWN / OWNER / PRIVATE / LOCAL.
## 2. Lint: source patterns that break option A (see the RULES below). An allowlist entry needs a
##    reason, and adding one is a design decision, not a way to make the test pass. Most rules apply
##    outside scripts/net/; the transport rules (no unreliable_ordered, no high-level sync) apply
##    everywhere, and NET_RULES hold scripts/net/ itself to the wire contract (M0).
## 3. The lint is run against lines that must fail (LINT_SAMPLES), so a broken regex can't pass silently.
## 4. Carriers (M2, M3): every OWNER var of a replicated class (REPLICATED: the hero, and from M3 the host-owned world:
##    monsters of every kind, hellgates, employees, priced props, crates, mail boxes, pickups) rides a snapshot
##    (NetCodec.HERO_FIELDS, NetWorldCodec.*_FIELDS) or is named, with its carrier, in NetEvents.CARRIES / WORLD_CARRIES; a
##    codec never streams a SPAWN / PRIVATE / LOCAL var. Run against declarations that must fail too.
## 5. The packet budget (M3): the host's packet (heroes plus the world section NetWorld fills) fits NetWorldCodec.PACKET_BUDGET
##    (about 1.2 KB, one datagram); test_net_world_codec fills it with the worst floor it can find.
## 6. Area verbs (M4, layer 4): a loop over the actors in an area (GameWorld.actors_in_radius / hittable_in_radius /
##    team_actors / actors, the "actors" group) that calls a verb on them (apply_damage, shove, set_modifier, heal, daze, lose_ground) must ask
##    who resolves each one (Combat.resolves / Net.resolves / Net.resolves_hit / Net.owns) in that loop: effects run on
##    every machine, and a verb applied by every machine lands once per machine. Run against loops that must fail too.
## 7. Late-join coverage (M6): every replicated class (REPLICATED, and every class NetEvents.WORLD_CARRIES names) declares in
##    NetEvents.LATE_JOIN how a player who joins a running floor gets its state (keyframe, gone ids, an event replay, the
##    seat handover). A new replicated class without an entry would be wrong on a late joiner's screen.
## 8. Units (refactor-plan.md H5): every runtime actor (NetWorldCodec.RUNTIME_ACTORS) is in REPLICATED with its own field list
##    and implements what NetWorld calls (net_read, net_write, net_tick, static make_shown); every host-arbitrated object
##    (a script with net_link) implements the rest of the net-object contract NetObjects calls (net_event) and is held to its
##    carriers, and one that is not an Actor says where its net id goes (net_order, NetFloor).

## Gameplay scripts that aren't Actors but hold state that matters in co-op. A new one goes here.
const NET_SCRIPTS := [
	"res://scripts/core/game_world.gd",
	"res://scripts/contracts/contract_ledger.gd",
	"res://scripts/contracts/contract_session.gd",
	"res://scripts/contracts/contract_run.gd",
	"res://scripts/contracts/site_plan.gd",
	"res://scripts/contracts/office_door.gd",
	"res://scripts/combat/projectile.gd",
	"res://scripts/heroes/arrow_shot.gd",
	"res://scripts/heroes/bowl_boulder.gd",
	"res://scripts/heroes/ally_brain.gd",
	"res://scripts/monsters/shark_steer.gd",
	"res://scripts/heroes/player_controller.gd",
	"res://scripts/spells/armor_zone.gd",
	"res://scripts/spells/burning.gd",
	"res://scripts/spells/component_pickup.gd",
	"res://scripts/spells/coffee.gd",
	"res://scripts/spells/corn_strike.gd",
	"res://scripts/spells/damp.gd",
	"res://scripts/spells/tentacles.gd",
	"res://scripts/spells/vine_wrap.gd",
	"res://scripts/spells/vines.gd",
	"res://scripts/spells/vines_fx.gd",
	"res://scripts/spells/wet.gd",
	"res://scripts/world/lava/lava_field.gd",   # (a lava cave's rules: its crust is terrain on a schedule from the shared casts)
	"res://scripts/world/sewer/live_wire.gd",   # (the sewer's live wire: a scheduled effect from its panel's obj.break, sewer phase 2)
	"res://scripts/monsters/goo_ball.gd",       # (the goo imp's ball and patch: runtime objects the host announces, NetObjects)
	"res://scripts/monsters/goo_patch.gd",
]

const ACTOR := "res://scripts/core/actor.gd"

## Folders whose code is presentation only: GameWorld.rng (gameplay rolls) is wrong there.
const COSMETIC_DIRS := ["res://scripts/fx/", "res://scripts/art/", "res://scripts/ui/", "res://scripts/world/grime/"]

## Lint rules: [id, regex, message, {path: reason} allowlist, scope]. Scope "outside_net" (the default
## when omitted) skips scripts/net/; "everywhere" includes it.
var RULES := [
	["unreliable_ordered", "unreliable_ordered|TRANSFER_MODE_UNRELIABLE_ORDERED",
		"GodotSteam sends unreliable_ordered as RELIABLE. Use unreliable + our own sequence numbers.", {}, "everywhere"],
	["net_calls", "@rpc|\\brpc(_id)?\\(|send_bytes\\(|multiplayer_peer",
		"Network calls live in scripts/net/ only.", {}],
	["steam_api", "get_singleton\\(\\s*\"Steam\"|ClassDB\\.\\w+\\(\\s*\"Steam|\\bSteam\\.\\w+\\(|SteamMultiplayerPeer",
		"Steam is reached only from scripts/net/ (SteamIdentity, SteamLobby, NetSession). Ask Session instead.", {}],
	["high_level_sync", "MultiplayerSynchronizer|MultiplayerSpawner",
		"No MultiplayerSynchronizer/Spawner: we pack our own snapshots (networking.md).", {}, "everywhere"],
	["global_random", "(?<![\\w.])(randf|randi|randf_range|randi_range|randfn|randomize)\\(",
		"No global randomness: gameplay rolls use GameWorld.rng (or a seeded generator), looks use GameWorld.fx_rng.", {
			"res://scripts/app/game.gd": "fresh entropy for a new job-board seed; the host will roll it and send it",
		}],
	["foreign_hp_write", "\\w\\.(hp|dead)\\s*[-+*/]?=(?!=)",
		"Change another actor's hp/dead through apply_damage/heal/die, so the owner applies it.", {
			"res://scripts/contracts/contract_session.gd": "restores the crew's HP between floors (setup, run by each hero's owner)",
			"res://scripts/heroes/hero_kit.gd": "sets starting HP when a kit is applied (spawn)",
			"res://scripts/app/game.gd": "--hurt dev flag",
			"res://scripts/spells/burning_lab.gd": "screenshot lab",
			"res://scripts/art/lowpoly/props/decor_models.gd": "`anim.dead` is a decor animation, not an actor",
		}],
]


## scripts/net/ only: [id, trigger regex, required regex, message]. A line matching the trigger must also
## match the requirement.
var NET_RULES := [
	["send_bytes_mode", "send_bytes\\(", "TRANSFER_MODE_UNRELIABLE\\b(?!_ORDERED)",
		"send_bytes is for unreliable, sequence-numbered packets: name TRANSFER_MODE_UNRELIABLE (its default is reliable). Events use the reliable RPC."],
	["rpc_reliable", "@rpc\\(", "\"reliable\"",
		"An @rpc is a reliable event; motion goes through send_bytes (NetWire)."],
]

## Lines the lint must flag: [path, code, rule id]. Proves each rule still fires.
const LINT_SAMPLES := [
	["res://scripts/ui/x.gd", "var s: Object = Engine.get_singleton(\"Steam\")", "steam_api"],
	["res://scripts/ui/x.gd", "var p := ClassDB.instantiate(\"SteamMultiplayerPeer\")", "steam_api"],
	["res://scripts/ui/x.gd", "Steam.run_callbacks()", "steam_api"],
	["res://scripts/ui/x.gd", "foo.rpc_id(1, 2)", "net_calls"],
	["res://scripts/net/x.gd", "@rpc(\"any_peer\", \"unreliable_ordered\")", "unreliable_ordered"],
	["res://scripts/net/x.gd", "@rpc(\"any_peer\", \"unreliable\")", "rpc_reliable"],
	["res://scripts/net/x.gd", "var n := MultiplayerSynchronizer.new()", "high_level_sync"],
	["res://scripts/net/x.gd", "mp.send_bytes(b, 1)", "send_bytes_mode"],
	["res://scripts/net/x.gd", "mp.send_bytes(b, 1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)", "send_bytes_mode"],
]
## ... and lines it must leave alone.
const LINT_CLEAN := [
	["res://scripts/net/x.gd", "mp.send_bytes(b, 1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 2)"],
	["res://scripts/net/x.gd", "@rpc(\"any_peer\", \"call_remote\", \"reliable\", 1)"],
	["res://scripts/net/x.gd", "var s: Object = Engine.get_singleton(\"Steam\")"],
	["res://scripts/ui/x.gd", "label.text = \"Steam not running\""],
]


func setup() -> void:
	for p: String in NetWorldCodec.RUNTIME_ACTORS:   # (a runtime actor's carriers: its own codec field list, section 8)
		REPLICATED[p] = [NetWorldCodec.RUNTIME_ACTORS[p]["fields"], NetEvents.WORLD_CARRIES.get(p, {}), 5]
	var scripts := _all_scripts("res://scripts/")
	_check_declarations(scripts)
	_check_lint(scripts)
	_check_lint_samples()
	_check_carriers()
	_check_budget()
	_check_area_loops(scripts)
	_check_area_samples()
	_check_late_join()
	_check_units(scripts)
	finish()


# --- 1. Declarations -------------------------------------------------------------

func _check_declarations(paths: Array[String]) -> void:
	var targets: Array[String] = []
	for p in paths:
		var src := FileAccess.get_file_as_string(p)
		var actor := _extends_actor(load(p))
		if p in NET_SCRIPTS or src.contains("func net_fields(") or actor:
			targets.append(p)
		# Every Actor class is held to its carriers (section 4) and the late-join table (section 7), or says why not: a new
		# monster kind or world actor can't slip through unchecked (docs/design/refactor-plan.md, H1).
		if actor and p != ACTOR:
			check(REPLICATED.has(p) or NOT_REPLICATED.has(p), "%s is an Actor but not in REPLICATED (its carriers) or NOT_REPLICATED (why it never crosses the net)" % p)
	for p in NET_SCRIPTS:
		check(p in paths, "NET_SCRIPTS names a missing file: " + p)
	check(targets.size() >= NET_SCRIPTS.size() + 5, "found the actor classes (%d targets)" % targets.size())
	for p in targets:
		_check_script(p)


func _check_script(path: String) -> void:
	var script := load(path) as GDScript
	if not check(script != null and script.can_instantiate(), path + ": can't instantiate"):
		return
	var obj: Object = script.new()
	if not check(obj.has_method("net_fields"), path + ": no net_fields(). Declare who writes each var (see Net)."):
		_free(obj)
		return
	var fields: Dictionary = obj.net_fields()
	var vars := {}
	for prop in obj.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			vars[prop["name"]] = true
	for v in vars:
		check(fields.has(v), "%s: var `%s` has no authority class. Add it to net_fields() (SPAWN/OWNER/PRIVATE/LOCAL, see Net)." % [path, v])
	for f in fields:
		check(vars.has(f), "%s: net_fields() names `%s`, which isn't a var (stale?)" % [path, f])
		check(Net.is_kind(fields[f]), "%s: `%s` is not a Net kind" % [path, f])
	_free(obj)


func _extends_actor(s: Script) -> bool:
	while s != null:
		if s.resource_path == ACTOR:
			return true
		s = s.get_base_script()
	return false


func _free(obj: Object) -> void:
	if obj is Node:
		obj.free()


# --- 2. Lint -------------------------------------------------------------------

func _compiled() -> Array:
	var out := []
	for r: Array in RULES:
		out.append([r[0], RegEx.create_from_string(r[1]), r[2], r[3], r[4] if r.size() > 4 else "outside_net"])
	return out


func _compiled_net() -> Array:
	var out := []
	for r: Array in NET_RULES:
		out.append([r[0], RegEx.create_from_string(r[1]), RegEx.create_from_string(r[2]), r[3]])
	return out


## The rule ids a line of code breaks, in file `p`.
func _violations(p: String, code: String, compiled: Array, compiled_net: Array) -> Array[String]:
	var out: Array[String] = []
	var in_net := p.begins_with("res://scripts/net/")
	for rule: Array in compiled:
		if in_net and rule[4] != "everywhere":
			continue
		if (rule[1] as RegEx).search(code) != null and not (rule[3] as Dictionary).has(p):
			out.append(rule[0])
	if in_net:
		for rule: Array in compiled_net:
			if (rule[1] as RegEx).search(code) != null and (rule[2] as RegEx).search(code) == null:
				out.append(rule[0])
	return out


func _check_lint(paths: Array[String]) -> void:
	var rng_re := RegEx.create_from_string("GameWorld\\.rng\\b")
	var compiled := _compiled()
	var compiled_net := _compiled_net()
	var messages := {}
	for rule: Array in compiled:
		messages[rule[0]] = rule[2]
		for p: String in rule[3]:
			check(p in paths, "rule %s allowlists a missing file: %s" % [rule[0], p])
	for rule: Array in compiled_net:
		messages[rule[0]] = rule[3]
	for p in paths:
		var lines := FileAccess.get_file_as_string(p).split("\n")
		var cosmetic := COSMETIC_DIRS.any(func(d: String) -> bool: return p.begins_with(d))
		for i in lines.size():
			var code := _strip_comment(lines[i])
			if code.strip_edges() == "":
				continue
			for id: String in _violations(p, code, compiled, compiled_net):
				_fail("%s:%d [%s] %s" % [p, i + 1, id, messages[id]])
			if cosmetic and rng_re.search(code) != null:
				_fail("%s:%d [cosmetic_rng] Presentation code uses GameWorld.fx_rng, not GameWorld.rng." % [p, i + 1])


func _check_lint_samples() -> void:
	var compiled := _compiled()
	var compiled_net := _compiled_net()
	for smp: Array in LINT_SAMPLES:
		check(_violations(smp[0], smp[1], compiled, compiled_net).has(smp[2]), "the lint flags `%s` in %s as %s" % [smp[1], smp[0], smp[2]])
	for smp: Array in LINT_CLEAN:
		var v := _violations(smp[0], smp[1], compiled, compiled_net)
		check(v.is_empty(), "the lint leaves `%s` in %s alone (got %s)" % [smp[1], smp[0], str(v)])


## The line without its # comment (a # inside a string literal is kept).
static func _strip_comment(line: String) -> String:
	var quote := ""
	var i := 0
	while i < line.length():
		var ch := line[i]
		if quote != "":
			if ch == "\\":
				i += 1      # skip the escaped character
			elif ch == quote:
				quote = ""
		elif ch == "\"" or ch == "'":
			quote = ch
		elif ch == "#":
			return line.substr(0, i)
		i += 1
	return line


func _all_scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_all_scripts(dir + d + "/"))
	return out


# --- 6. Area verbs (M4) ----------------------------------------------------------------------

## Files whose area loops may call verbs without asking who resolves: {path: reason}. Adding one is a design decision.
const AREA_LOOP_ALLOW := {}   # (empty: every area loop in scripts/ asks)
const AREA_LOOP_RE := "^(\\s*)for (\\w+)(?:\\s*:\\s*\\w+)? in .*(GameWorld\\.(actors_in_radius|hittable_in_radius|team_actors|actors)\\(|get_nodes_in_group\\(\"actors\"\\)|\\bheroes\\(\\))"
const AREA_ASK_RE := "Combat\\.resolves\\(|Net\\.resolves(_hit)?\\(|Net\\.owns\\("


## The area loops in `lines` that call a verb on their actor without asking who resolves it: [line number, var].
static func _area_loop_gaps(lines: PackedStringArray) -> Array:
	var loop_re := RegEx.create_from_string(AREA_LOOP_RE)
	var ask_re := RegEx.create_from_string(AREA_ASK_RE)
	var out := []
	for i in lines.size():
		var m := loop_re.search(_strip_comment(lines[i]))
		if m == null:
			continue
		var indent := m.get_string(1).length()
		var v := m.get_string(2)
		var verb_re := RegEx.create_from_string("\\b%s\\.(apply_damage|shove|set_modifier|heal|daze|lose_ground)\\(" % v)
		var verb := false
		var asks := false
		var j := i + 1
		while j < lines.size():
			var code := _strip_comment(lines[j])
			if code.strip_edges() != "":
				var ind := code.length() - code.lstrip("\t ").length()
				if ind <= indent:
					break
				verb = verb or verb_re.search(code) != null
				asks = asks or ask_re.search(code) != null
			j += 1
		if verb and not asks:
			out.append([i + 1, v])
	return out


func _check_area_loops(paths: Array[String]) -> void:
	for p: String in AREA_LOOP_ALLOW:
		check(p in paths, "the area-loop rule allowlists a missing file: " + p)
	for p in paths:
		if AREA_LOOP_ALLOW.has(p) or p.begins_with("res://scripts/net/") or p.begins_with("res://scripts/test_support/"):
			continue
		for g: Array in _area_loop_gaps(FileAccess.get_file_as_string(p).split("\n")):
			_fail("%s:%d [area_verb] the loop calls a verb on `%s` without asking who resolves it (Combat.resolves / Net.resolves): online every machine runs it, so the verb lands once per machine" % [p, int(g[0]), str(g[1])])


func _check_area_samples() -> void:
	var bad := PackedStringArray(["func f() -> void:", "\tfor a in GameWorld.actors_in_radius(p, 2.0):", "\t\ta.apply_damage(5.0, self)", "\tpass"])
	eq(_area_loop_gaps(bad).size(), 1, "the area-loop rule flags a verb loop that does not ask")
	var bad2 := PackedStringArray(["\tfor h: Actor in GameWorld.team_actors(0):", "\t\tif h.hp > 1.0:", "\t\t\th.shove(Vector3.RIGHT, 2.0)"])
	eq(_area_loop_gaps(bad2).size(), 1, "... a shove nested deeper in the loop")
	var bad3 := PackedStringArray(["\tfor h in GameWorld.actors_in_radius(p, 2.0):", "\t\th.daze(0.6, self)"])
	eq(_area_loop_gaps(bad3).size(), 1, "... a daze (the brute slam's verb)")
	var bad4 := PackedStringArray(["\tfor a in GameWorld.actors():", "\t\ta.lose_ground(self)"])
	eq(_area_loop_gaps(bad4).size(), 1, "... the ground taken from under it (a lava crust melting: lose_ground)")
	var good := PackedStringArray(["\tfor a in GameWorld.actors_in_radius(p, 2.0):", "\t\tif not Combat.resolves(a, self):", "\t\t\tcontinue", "\t\ta.apply_damage(5.0, self)"])
	eq(_area_loop_gaps(good).size(), 0, "a loop that asks Combat.resolves passes")
	var other := PackedStringArray(["\tfor a in GameWorld.actors_in_radius(p, 2.0):", "\t\tFx.attach_hit_feedback(a)", "\tb.apply_damage(1.0)"])
	eq(_area_loop_gaps(other).size(), 0, "a loop with no verb on its actor passes (a verb after the loop is not in it)")


# --- 5. The packet budget (M3) ---------------------------------------------------------------

func _check_budget() -> void:
	var heroes := NetWire.HEADER + 1 + 2 * NetCodec.ENTRY_SIZE_DRAWING
	check(heroes + NetWorld.WORLD_BUDGET <= NetWorldCodec.PACKET_BUDGET, "the host's packet (heroes %d + world %d bytes) fits the %d-byte budget" % [heroes, NetWorld.WORLD_BUDGET, NetWorldCodec.PACKET_BUDGET])
	check(NetWorldCodec.PACKET_BUDGET <= 1200, "the budget is one datagram on Steam's relays (1.2 KB)")
	check(NetWorld.WORLD_BUDGET >= 60 * NetWorldCodec.MONSTER_SIZE, "the world section holds at least 60 moving monsters a tick")


# --- 3. Carriers (M2): nothing owned by a player goes unreplicated ---------------------------

## Actor classes that never cross the net, and why (every other Actor class must be in REPLICATED).
const NOT_REPLICATED := {
	"res://scripts/heroes/training_dummy.gd": "the arena test scene's target; never on a contract floor",
	"res://scripts/world/themes/decor_blocker.gd": "built on every machine from the floor plan; immovable, undamageable, no state changes",
}

## Classes whose OWNER vars travel: script -> [the codec's field list, the event table, the fewest codec fields it should
## have]. Each monster kind is held to the monster tables (a kind that adds an OWNER var must add its carrier).
const MONSTER_PATH := "res://scripts/monsters/monster.gd"
var REPLICATED := {
	"res://scripts/heroes/hero.gd": [NetCodec.HERO_FIELDS, NetEvents.CARRIES, 6],
	MONSTER_PATH: [NetWorldCodec.MONSTER_FIELDS, NetEvents.WORLD_CARRIES[MONSTER_PATH], 5],
	"res://scripts/monsters/grunt.gd": [NetWorldCodec.MONSTER_FIELDS, NetEvents.WORLD_CARRIES[MONSTER_PATH], 5],
	"res://scripts/monsters/archer.gd": [NetWorldCodec.MONSTER_FIELDS, NetEvents.WORLD_CARRIES[MONSTER_PATH], 5],
	"res://scripts/monsters/brute.gd": [NetWorldCodec.MONSTER_FIELDS, NetEvents.WORLD_CARRIES[MONSTER_PATH], 5],
	"res://scripts/monsters/swarmer.gd": [NetWorldCodec.MONSTER_FIELDS, NetEvents.WORLD_CARRIES[MONSTER_PATH], 5],
	"res://scripts/monsters/goblin.gd": [NetWorldCodec.MONSTER_FIELDS, NetEvents.WORLD_CARRIES["res://scripts/monsters/goblin.gd"], 5],
	# the pool shark and its imp gunner (docs/design/sharks.md): monster-format entries plus their own events
	"res://scripts/monsters/shark.gd": [NetWorldCodec.MONSTER_FIELDS, NetEvents.WORLD_CARRIES["res://scripts/monsters/shark.gd"], 5],
	"res://scripts/monsters/jockey.gd": [NetWorldCodec.MONSTER_FIELDS, NetEvents.WORLD_CARRIES["res://scripts/monsters/jockey.gd"], 5],
	# the sewer gator (docs/design/sewer-concept.md, "Phase 2 as built"): a monster-format entry, the monster carriers
	"res://scripts/monsters/gator.gd": [NetWorldCodec.MONSTER_FIELDS, NetEvents.WORLD_CARRIES[MONSTER_PATH], 5],
	# the Pavise Crossbowman (its shield and bolt: their own events) and the Water Boy (a plain monster: its pour is a wind-up)
	"res://scripts/monsters/pavise.gd": [NetWorldCodec.MONSTER_FIELDS, NetEvents.WORLD_CARRIES["res://scripts/monsters/pavise.gd"], 5],
	"res://scripts/monsters/water_boy.gd": [NetWorldCodec.MONSTER_FIELDS, NetEvents.WORLD_CARRIES[MONSTER_PATH], 5],
	"res://scripts/contracts/employee.gd": [NetWorldCodec.EMPLOYEE_FIELDS, NetEvents.WORLD_CARRIES["res://scripts/contracts/employee.gd"], 5],
	"res://scripts/contracts/hellgate.gd": [NetWorldCodec.GATE_FIELDS, NetEvents.WORLD_CARRIES["res://scripts/contracts/hellgate.gd"], 5],
	"res://scripts/contracts/priced_prop.gd": [{}, NetEvents.WORLD_CARRIES["res://scripts/contracts/priced_prop.gd"], 0],
	"res://scripts/contracts/explosive_prop.gd": [{}, NetEvents.WORLD_CARRIES["res://scripts/contracts/explosive_prop.gd"], 0],
	"res://scripts/world/themes/breakable_crate.gd": [{}, NetEvents.WORLD_CARRIES["res://scripts/world/themes/breakable_crate.gd"], 0],
	"res://scripts/contracts/mail_package.gd": [{}, NetEvents.WORLD_CARRIES["res://scripts/contracts/mail_package.gd"], 0],
	"res://scripts/spells/component_pickup.gd": [{}, NetEvents.WORLD_CARRIES["res://scripts/spells/component_pickup.gd"], 0],
	# (the runtime actors, the Chicken spell's chickens among them, are added from NetWorldCodec.RUNTIME_ACTORS in setup)
	"res://scripts/contracts/office_door.gd": [{}, NetEvents.WORLD_CARRIES["res://scripts/contracts/office_door.gd"], 0],
	# the goo imp (a plain monster: its tell is a wind-up), its ball (a scheduled effect announced by the host: no OWNER var)
	# and its patch (a runtime host-arbitrated object: obj.new, obj.goo)
	"res://scripts/monsters/goo_imp.gd": [NetWorldCodec.MONSTER_FIELDS, NetEvents.WORLD_CARRIES[MONSTER_PATH], 5],
	"res://scripts/monsters/goo_ball.gd": [{}, {}, 0],
	"res://scripts/monsters/goo_patch.gd": [{}, NetEvents.WORLD_CARRIES["res://scripts/monsters/goo_patch.gd"], 0],
}


## The problems with a class's carrier tables, for its net_fields(): an OWNER var nobody carries, a codec that streams a
## var that is not OWNER (SPAWN / PRIVATE / LOCAL never travel in a snapshot), a stale name, and a var with two carriers.
func _carrier_gaps(fields: Dictionary, codec: Dictionary, events: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for f: String in fields:
		if int(fields[f]) == Net.OWNER and not codec.has(f) and not events.has(f):
			out.append("OWNER var `%s` has no carrier: add it to the codec's field list or to NetEvents.CARRIES" % f)
	for f: String in codec:
		if not fields.has(f):
			out.append("the codec names `%s`, which is not a var (stale?)" % f)
		elif int(fields[f]) != Net.OWNER:
			out.append("the codec streams `%s`, which is %s: only OWNER vars travel" % [f, Net.NAMES[int(fields[f])]])
		if events.has(f):
			out.append("`%s` is in the codec AND in NetEvents.CARRIES: one carrier" % f)
	for f: String in events:
		if not fields.has(f):
			out.append("NetEvents.CARRIES names `%s`, which is not a var (stale?)" % f)
		elif int(fields[f]) != Net.OWNER:
			out.append("NetEvents.CARRIES names `%s`, which is %s: only OWNER vars need a carrier" % [f, Net.NAMES[int(fields[f])]])
	return out


func _check_carriers() -> void:
	for p: String in REPLICATED:
		var tables: Array = REPLICATED[p]
		var obj: Object = (load(p) as GDScript).new()
		var gaps := _carrier_gaps(obj.net_fields(), tables[0] as Dictionary, tables[1] as Dictionary)
		for g in gaps:
			_fail("%s: %s" % [p, g])
		check((tables[0] as Dictionary).size() >= int(tables[2]), p + ": the codec carries its state")
		_free(obj)
	for p: String in NetEvents.WORLD_CARRIES:
		check(REPLICATED.has(p), "NetEvents.WORLD_CARRIES names %s, which this test does not hold to it" % p)
	# The rule is run against declarations that must fail, so a broken check can't pass silently.
	var fake := {"carried": Net.OWNER, "event_carried": Net.OWNER, "dropped": Net.OWNER, "secret": Net.PRIVATE, "look": Net.LOCAL, "fixed": Net.SPAWN}
	eq(_carrier_gaps(fake, {"carried": "x"}, {"event_carried": "later"}).size(), 1, "an OWNER var with no carrier is flagged (and only it)")
	check(_carrier_gaps(fake, {"carried": "x", "secret": "x"}, {"event_carried": "m"}).any(func(g: String) -> bool: return g.contains("secret") and g.contains("PRIVATE")), "a codec that streams a PRIVATE var is flagged")
	check(_carrier_gaps(fake, {"carried": "x", "look": "x"}, {"event_carried": "m"}).any(func(g: String) -> bool: return g.contains("look") and g.contains("LOCAL")), "... a LOCAL one")
	check(_carrier_gaps(fake, {"carried": "x", "fixed": "x"}, {"event_carried": "m"}).any(func(g: String) -> bool: return g.contains("fixed") and g.contains("SPAWN")), "... a SPAWN one")
	check(_carrier_gaps(fake, {"carried": "x", "gone": "x"}, {"event_carried": "m"}).any(func(g: String) -> bool: return g.contains("gone")), "... a stale name")
	check(_carrier_gaps(fake, {"carried": "x", "event_carried": "x"}, {"event_carried": "m"}).any(func(g: String) -> bool: return g.contains("one carrier")), "a var with two carriers is flagged")
	eq(_carrier_gaps({"a": Net.OWNER}, {"a": "x"}, {}).size(), 0, "a carried OWNER var is clean")


# --- 7. Late-join coverage (M6) ----------------------------------------------------------------------------

## The problems with a late-join table against the replicated classes: a class with no entry, an entry with no way named, an
## entry for a class nobody replicates.
static func _late_join_gaps(classes: Array, table: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for p: String in classes:
		if not table.has(p):
			out.append("%s has no NetEvents.LATE_JOIN entry: say how a late joiner gets its state" % p)
		elif not ["keyframe", "gone", "replay", "handover", "as "].any(func(w: String) -> bool: return str(table[p]).contains(w)):
			out.append("%s: its LATE_JOIN entry names no way (keyframe, gone ids, replay, handover)" % p)
	for p: String in table:
		if not classes.has(p):
			out.append("NetEvents.LATE_JOIN names %s, which is not replicated (stale?)" % p)
	return out


func _check_late_join() -> void:
	var classes: Array = REPLICATED.keys()
	for p: String in NetEvents.WORLD_CARRIES:
		if not classes.has(p):
			classes.append(p)
	for g in _late_join_gaps(classes, NetEvents.LATE_JOIN):
		_fail(g)
	# Run against tables that must fail.
	eq(_late_join_gaps(["a.gd", "b.gd"], {"a.gd": "keyframe"}).size(), 1, "a replicated class with no late-join entry is flagged")
	eq(_late_join_gaps(["a.gd"], {"a.gd": "somehow"}).size(), 1, "an entry that names no way is flagged")
	eq(_late_join_gaps(["a.gd"], {"a.gd": "gone ids", "z.gd": "replay"}).size(), 1, "a stale entry is flagged")
	eq(_late_join_gaps(["a.gd"], {"a.gd": "replay of obj.x"}).size(), 0, "a covered class is clean")


# --- 8. Units (H5): runtime actors and host-arbitrated objects --------------------------------------------------------

func _methods(script: Script) -> Dictionary:
	var out := {}
	var sc := script
	while sc != null:
		for m: Dictionary in sc.get_script_method_list():
			out[str(m["name"])] = true
		sc = sc.get_base_script()
	return out


func _check_units(paths: Array[String]) -> void:
	var kinds := {}
	for p: String in NetWorldCodec.RUNTIME_ACTORS:
		var e: Dictionary = NetWorldCodec.RUNTIME_ACTORS[p]
		var script := load(p) as GDScript
		if not check(script != null, "RUNTIME_ACTORS names a missing script: " + p):
			continue
		check(_extends_actor(script), p + ": a runtime actor is an Actor")
		var have := _methods(script)
		for m in ["net_read", "net_write", "net_tick", "make_shown"]:
			check(have.has(m), "%s: a runtime actor implements %s (NetWorld calls it)" % [p, m])
		var kind := str(e.get("kind", ""))
		check(kind != "" and not kinds.has(kind), "%s: its world.spawn kind `%s` is set and unique" % [p, kind])
		kinds[kind] = true
		check(NetWorldCodec.runtime_script(kind) == script, "%s: a world.spawn row of kind `%s` builds it" % [p, kind])
		check(str(e.get("group", "")) != "", p + ": its query group is named")
	var objects := 0
	for p in paths:
		if not FileAccess.get_file_as_string(p).contains("func net_link("):
			continue
		objects += 1
		var script := load(p) as GDScript
		var have := _methods(script)
		check(have.has("net_event"), "%s: a net object (net_link) implements net_event (a client applies the host's obj.* events)" % p)
		check(REPLICATED.has(p), "%s: a net object is in REPLICATED (its carriers)" % p)
		if not _extends_actor(script):
			check(have.has("net_order"), "%s: a net object that is not an Actor says where its net id goes (net_order)" % p)
	check(objects >= 5, "found the host-arbitrated objects (%d scripts with net_link)" % objects)
	# Runtime objects (NetObjects.RUNTIME_OBJECTS: what the host makes during play and announces, obj.new): each builds its
	# copy from a row (static net_copy), says what goes in the row (net_spawn_row), is declared (NET_SCRIPTS) and is held to
	# its carriers and its late-join entry (REPLICATED).
	for k: String in NetObjects.RUNTIME_OBJECTS:
		var p := str(NetObjects.RUNTIME_OBJECTS[k])
		var script := load(p) as GDScript
		if not check(script != null, "RUNTIME_OBJECTS names a missing script: " + p):
			continue
		var have := _methods(script)
		for m in ["net_spawn_row", "net_copy"]:
			check(have.has(m), "%s: a runtime object implements %s (NetObjects calls it)" % [p, m])
		check(p in NET_SCRIPTS or _extends_actor(script), p + ": a runtime object declares its vars (NET_SCRIPTS)")
		check(REPLICATED.has(p), p + ": a runtime object is in REPLICATED (its carriers)")
