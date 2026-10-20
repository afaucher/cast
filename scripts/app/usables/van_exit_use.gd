class_name VanExitUse
extends RefCounted
## E at the van's side door (floor 1): the clock-out slip. A Usable (scripts/app/usable.gd) adapter over game.gd's exit
## state: the van is a plan record (SitePlan.van) and an arrival, so game.gd decides when the player is at it
## (_player_at_van) and opens the slip (_open_van_exit; online the exits are first to choose).

const PROMPT_ABOVE := 2.7   ## the use prompt floats this far above the floor in front of the van's side door


func use_kind() -> String:
	return "van"


func use_score(_hero: Hero, game: Node) -> float:
	return Usable.VAN if bool(game.call("_player_at_van")) else -INF


func use_prompt(_hero: Hero, _game: Node) -> String:
	return "Clock out"


func use_point(_hero: Hero, game: Node) -> Vector3:
	var door: Vector2 = game.call("_van_door_pos")
	return Vector3(door.x, float(game.call("_floor_y", door.x, door.y)) + PROMPT_ABOVE, door.y)


func use_press(_hero: Hero, game: Node) -> bool:
	game.call("_open_van_exit")
	return true
