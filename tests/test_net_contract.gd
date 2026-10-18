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

## Gameplay scripts that aren't Actors but hold state that matters in co-op. A new one goes here.
const NET_SCRIPTS := [
	"res://scripts/core/game_world.gd",
	"res://scripts/contracts/contract_ledger.gd",
	"res://scripts/contracts/contract_session.gd",
	"res://scripts/contracts/contract_run.gd",
	"res://scripts/contracts/site_plan.gd",
	"res://scripts/combat/projectile.gd",
	"res://scripts/heroes/arrow_shot.gd",
	"res://scripts/heroes/bowl_boulder.gd",
	"res://scripts/heroes/ally_brain.gd",
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
			"res://scripts/monsters/monster_fight.gd": "screenshot lab",
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
	var scripts := _all_scripts("res://scripts/")
	_check_declarations(scripts)
	_check_lint(scripts)
	_check_lint_samples()
	finish()


# --- 1. Declarations -------------------------------------------------------------

func _check_declarations(paths: Array[String]) -> void:
	var targets: Array[String] = []
	for p in paths:
		var src := FileAccess.get_file_as_string(p)
		if p in NET_SCRIPTS or src.contains("func net_fields(") or _extends_actor(load(p)):
			targets.append(p)
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
