extends Node3D
## Dev wrapper around the real game for screenshots: loads scenes/game.tscn (every game flag works as
## usual) and, once the crew is standing, adds a MIXED pack of monsters around the player.
##
##   godot --path . -- --scene res://scenes/monster_fight.tscn --seed 11 --spells heal,tentacles --no-mic
##       --shot <abs png> --shot-after 4 [--fight grunt:2,archer:1,brute:1,swarmer:4]
##
## --catch <kind> <png>   follows the first monster of that kind with the camera and saves a screenshot the
##                       moment it is deep in its attack telegraph (brute slam / archer draw), then quits.
## --proto-monsters      the old primitive monster bodies (Monster.use_proto_visuals) instead of the faceted models.
## --fight lists kind:count; the default is the pack above. Monsters spawn on open floor 3-6 cells from
## the player, kinds spread around the ring (archers a bit farther so they stay in their firing band).

const DEFAULT_PACK := "grunt:2,archer:1,brute:1,swarmer:4"
const GAME_SCENE := "res://scenes/game.tscn"

var _game: Node = null
var _catch_kind := ""
var _catch_path := ""
var _spawned: Array[Monster] = []
var _saved := false


func _ready() -> void:
	var cargs := OS.get_cmdline_user_args()
	Monster.use_proto_visuals = cargs.has("--proto-monsters")
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	_game = game
	add_child(game)
	var ci := cargs.find("--catch")
	if ci >= 0 and ci + 2 < cargs.size():
		_catch_kind = cargs[ci + 1]
		_catch_path = cargs[ci + 2]
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Hero = game.get("player")
	if player == null or GameWorld.map == null:
		push_warning("monster_fight: no player yet")
		return
	var pack := DEFAULT_PACK
	var args := OS.get_cmdline_user_args()
	var i := args.find("--fight")
	if i >= 0 and i + 1 < args.size():
		pack = args[i + 1]
	var map: HexMap = GameWorld.map
	var here := player.current_cell()
	var base_level: int = map.get_cell(here).level
	var used: Dictionary = {}
	for part in pack.split(","):
		var bits := part.split(":")
		var kind := bits[0].strip_edges()
		var n := int(bits[1]) if bits.size() > 1 else 1
		var lo := 5 if kind == "archer" else 3
		var cands: Array[Vector2i] = []
		for c in Hex.range_cells(here, lo + 2):
			var d := Hex.distance(c, here)
			var cell: HexMap.Cell = map.get_cell(c)
			if d >= lo and cell != null and cell.type == HexMap.Tile.FLOOR and absi(cell.level - base_level) <= 1 and not used.has(c):
				cands.append(c)
		cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
		var stride := maxi(1, cands.size() / maxi(n, 1))
		var k := 0
		var placed := 0
		while placed < n and k < cands.size():
			var m := MonsterFactory.spawn(kind, cands[k])
			if m != null:
				if _catch_kind == kind:
					m.max_hp *= 8.0      # lives long enough to be photographed
					m.hp = m.max_hp
				_spawned.append(m)
				used[cands[k]] = true
				placed += 1
			k += stride
		print("[fight] ", kind, " x", placed)


func _process(_delta: float) -> void:
	if _catch_kind == "" or _saved or _game == null:
		return
	# Follow the first live monster of the kind that is attacking, else the first live one.
	var pick: Monster = null
	for m in _spawned:
		if not is_instance_valid(m) or m.dead or m.kind != _catch_kind:
			continue
		if pick == null:
			pick = m
		if m.state == Monster.State.ATTACK:
			pick = m
			break
	if pick == null:
		return
	var rig: CameraRig = _game.get("rig")
	if rig != null:
		rig.target = pick
		rig.snap()
	if pick.state == Monster.State.ATTACK and pick._telegraph > 0.5:
		_saved = true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_catch_path)
		print("[fight] caught ", _catch_kind, " telegraph ", pick._telegraph, " -> ", _catch_path)
		get_tree().quit()
