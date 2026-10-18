class_name NetGameTest
extends NetTest
## NetTest plus the real game scene on every process: the shared-run tests (M1) put a game.gd node under the test
## and drive it through its own screens (the job board, the license checkout), exactly as a player would.
##
## Every process runs the SAME script with its role; the host is the judge (see NetTest). Helpers here: make_game()
## (a game with the test seams: no mic, scene changes recorded instead of done), the screens, the shared clock as the
## wall clock sees it (`truth()`: all the processes of a test share this machine's clock), and signing a license.

const GAME_SCRIPT := preload("res://scripts/app/game.gd")

var game: Node3D = null
## Every scene the game asked for (the menu when the crew ends, "" for the job board), in order.
var scene_changes: Array[String] = []

## Each seat's license, by test index (0 = the host): different on purpose, so a mix-up shows.
const LICENSES := [["heal", "corn"], ["fireball", "armor"], ["tentacles", "teeth"]]


## A game scene with the test seams. `extra` adds to its opts (the dev flags).
func make_game(extra: Dictionary = {}) -> Node3D:
	GAME_SCRIPT.reset_flow()
	var g: Node3D = GAME_SCRIPT.new()
	var o := {"no_mic": true, "van_intro": true}
	o.merge(extra, true)
	g.set("opts", o)
	g.set("scene_changer", func(p: String) -> void: scene_changes.append(p))
	add_child(g)
	game = g
	return g


func board() -> JobBoard:
	return game.get("_board") as JobBoard


func picker() -> SpellPicker:
	return game.get("_picker") as SpellPicker


func flow() -> CrewFlow:
	return Session.flow


## The shared clock as this machine's wall clock says it is (all the processes share one machine's clock).
func truth() -> float:
	if Session.is_host():
		return Session.host_time()
	return Time.get_unix_time_from_system() - Session.host_unix_epoch


## The offers on a board as one comparable string.
static func offers_signature(offers: Array[ContractRun]) -> String:
	var parts: PackedStringArray = []
	for r in offers:
		parts.append("%s|%s|%s|%d|%d|%s" % [r.invoice_number, r.client_name, r.pest, r.contract_value, r.seed, r.story["event"]])
	return "\n".join(parts)


## A contract as one comparable string.
static func run_signature(r: ContractRun) -> String:
	return "%s|%s|%d|%.4f|%d|%s" % [r.invoice_number, r.archetype_id, r.seed, r.difficulty, r.contract_value, r.story["event"]]


## Tick two spells in the license checkout and sign. False if there is no checkout open.
func sign_license(ids: Array) -> bool:
	var p := picker()
	if p == null:
		return false
	for id: String in ids:
		p.toggle(id)
	return p.confirm()


func my_license() -> Array:
	return LICENSES[index]


## Wait until the game has a board / a checkout / a running floor.
func wait_board(seconds: float = 20.0) -> bool:
	return await until(func() -> bool: return board() != null, seconds)


func wait_picker(seconds: float = 20.0) -> bool:
	return await until(func() -> bool: return picker() != null, seconds)


func wait_floor(seconds: float = 30.0) -> bool:
	return await until(func() -> bool: return bool(game.get("_floor_begun")), seconds)


## The hero this machine controls, and the seat it sits in.
func my_hero() -> Hero:
	return game.get("player") as Hero


func hero_at(seat: int) -> Hero:
	return (game.get("heroes_by_seat") as Dictionary).get(seat) as Hero
