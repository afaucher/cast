class_name Usable
extends RefCounted
## USABLE: the contract of everything the E key acts on (refactor-plan.md H6). GDScript has no interfaces, so a usable is
## any object with these five methods (duck typing; `hero` is the player's hero, `game` the game scene, game.gd):
##
##   use_kind() -> String                     a short name: "van", "elevator", "employee", "note", "door", "pickup"
##   use_score(hero, game) -> float           how preferred it is right now; -INF when E cannot act on it
##   use_prompt(hero, game) -> String         the use prompt's verb ("Clock out", "Bring Beatrice", "Read", "Shut door")
##   use_point(hero, game) -> Vector3         the world point the prompt floats at
##   use_press(hero, game) -> bool            E: act on it; true when the press is used
##
## game.gd `use_target()` is the query: it collects one candidate per kind (each kind's own finder picks its nearest in
## reach, with its own tie-break: Employee.interact_target, game.gd _note_target, OfficeDoor.interact_target,
## Hero.swap_target; the van and the elevator are always candidates) and Usable.pick takes the best score, the first one on
## a tie. The prompt (`_update_use_prompts`) and the press (`_use_key`, PlayerController.press_use) both read that one
## pick, so the prompt can never promise something else.
##
## The scores are the bands below, one per kind: it reproduces the old priority chain (the van exit, then the elevator,
## then the employee next to the hero, then a note, a door, a pickup), so a note never steals a rescue. A new interactable
## is a class with the five methods, a band here, and one line in game.gd `_use_candidates()`.
##
## Implemented by: Employee, ClueNote, OfficeDoor, ComponentPickup, and two thin adapters over game.gd's exit state,
## VanExitUse and ElevatorUse (the van and the elevator are plan records and arrival nodes, not classes E could own).
##
## NETWORKING: none here. Each use_press keeps its own path: a client's E on an employee, a door or a pickup is a request
## (Net.request, NetObjects) made by Employee.interact, OfficeDoor.use and Hero.swap_in_pickup; the exits go through
## game.gd's exit slips (first to choose); a note is LOCAL presentation.

const VAN := 60.0
const ELEVATOR := 50.0
const EMPLOYEE := 40.0
const NOTE := 30.0
const DOOR := 20.0
const PICKUP := 10.0


## What E would act on: the usable, its kind, and the prompt's verb and point (read once, when it was picked).
class Target extends RefCounted:
	var node: Object = null
	var kind := ""
	var verb := ""
	var pos := Vector3.ZERO


## The best of `candidates` (nulls skipped) for `hero`: the highest use_score, the first on a tie. Null when none scores
## above -INF.
static func pick(candidates: Array, hero: Hero, game: Node) -> Target:
	var best: Object = null
	var best_s := -INF
	for c: Object in candidates:
		if c == null:
			continue
		var s: float = c.call("use_score", hero, game)
		if s > best_s:
			best_s = s
			best = c
	if best == null:
		return null
	var t := Target.new()
	t.node = best
	t.kind = str(best.call("use_kind"))
	t.verb = str(best.call("use_prompt", hero, game))
	t.pos = best.call("use_point", hero, game)
	return t


## E on a pick: its use_press.
static func press(t: Target, hero: Hero, game: Node) -> bool:
	return t != null and bool(t.node.call("use_press", hero, game))
