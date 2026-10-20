class_name ElevatorUse
extends RefCounted
## E at the elevator: its menu (go down, exit, stay). A Usable (scripts/app/usable.gd) adapter over game.gd's exit state:
## the elevator is the exit cell, a plan record (SitePlan.elevator) and an arrival, so game.gd decides when the player is
## at it (_player_at_elevator: its landing or its car) and opens the menu (_open_elevator; online the exits are first to
## choose).

const PROMPT_ABOVE := 3.0   ## the use prompt floats this far above the exit cell's floor


func use_kind() -> String:
	return "elevator"


func use_score(_hero: Hero, game: Node) -> float:
	return Usable.ELEVATOR if bool(game.call("_player_at_elevator")) else -INF


func use_prompt(_hero: Hero, _game: Node) -> String:
	return "Elevator"


func use_point(_hero: Hero, game: Node) -> Vector3:
	var ex := Hex.to_world(game.get("_exit_cell"))
	return Vector3(ex.x, float(game.call("_floor_y", ex.x, ex.z)) + PROMPT_ABOVE, ex.z)


func use_press(_hero: Hero, game: Node) -> bool:
	game.call("_open_elevator")
	return true
