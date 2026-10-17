extends TestCase
## The co-op authority contract (docs/design/networking.md, "Keeping authority straight").
## There is no netcode yet; this keeps new content from quietly breaking the plan.
##
## 1. Declarations: every Actor subclass, every script listed in NET_SCRIPTS and every script that
##    defines net_fields() classifies EVERY script var it has as Net.SPAWN / OWNER / PRIVATE / LOCAL.
## 2. Lint: source patterns that break option A (see the RULES below). An allowlist entry needs a
##    reason, and adding one is a design decision, not a way to make the test pass.

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
	"res://scripts/spells/corn_strike.gd",
	"res://scripts/spells/tentacles.gd",
]

const ACTOR := "res://scripts/core/actor.gd"

## Folders whose code is presentation only: GameWorld.rng (gameplay rolls) is wrong there.
const COSMETIC_DIRS := ["res://scripts/fx/", "res://scripts/art/", "res://scripts/ui/", "res://scripts/world/grime/"]

## Lint rules: [id, regex, message, {path: reason} allowlist].
var RULES := [
	["unreliable_ordered", "unreliable_ordered|TRANSFER_MODE_UNRELIABLE_ORDERED",
		"GodotSteam sends unreliable_ordered as RELIABLE. Use unreliable + our own sequence numbers.", {}],
	["net_calls", "@rpc|\\brpc(_id)?\\(|send_bytes\\(|multiplayer_peer",
		"Network calls live in scripts/net/ only.", {}],
	["high_level_sync", "MultiplayerSynchronizer|MultiplayerSpawner",
		"No MultiplayerSynchronizer/Spawner: we pack our own snapshots (networking.md).", {}],
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


func setup() -> void:
	var scripts := _all_scripts("res://scripts/")
	_check_declarations(scripts)
	_check_lint(scripts)
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

func _check_lint(paths: Array[String]) -> void:
	var rng_re := RegEx.create_from_string("GameWorld\\.rng\\b")
	var compiled := []
	for r in RULES:
		compiled.append([r[0], RegEx.create_from_string(r[1]), r[2], r[3]])
	for rule in compiled:
		for p in rule[3]:
			check(p in paths, "rule %s allowlists a missing file: %s" % [rule[0], p])
	for p in paths:
		if p.begins_with("res://scripts/net/"):
			continue
		var lines := FileAccess.get_file_as_string(p).split("\n")
		var cosmetic := COSMETIC_DIRS.any(func(d: String) -> bool: return p.begins_with(d))
		for i in lines.size():
			var code := _strip_comment(lines[i])
			if code.strip_edges() == "":
				continue
			for rule in compiled:
				if rule[1].search(code) != null and not rule[3].has(p):
					_fail("%s:%d [%s] %s" % [p, i + 1, rule[0], rule[2]])
			if cosmetic and rng_re.search(code) != null:
				_fail("%s:%d [cosmetic_rng] Presentation code uses GameWorld.fx_rng, not GameWorld.rng." % [p, i + 1])


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
