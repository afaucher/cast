class_name HudStage
extends RefCounted
## Dev (screenshots of the party HUD, PartyFrame): `--hud-stage <stage>` and `--hud-followers N` on a solo floor. The
## stage is timed against --shot-after so the picture catches it settled:
##   solo     nothing staged: you (your Steam name and avatar when Steam runs) and the two AI allies on FOLLOW
##   crew     seat 2 is played by "Fox" (a stand-in Steam avatar), seat 3 stays the AI; you keep your Steam picture, or get
##            a stand-in when Steam has none
##   long     32-character and wide names: you "xX_TheLongestSteamNameEver_Xx", Fox's seat "WWWW..." (32 W), the third a
##            Japanese name, all three played by people
##   long2    other scripts: Cyrillic, Korean and an accented Latin name
##   down     an ally down, you dazed, the other ally at a quarter of its HP
##   orders   one AI ally told "go" (it arrives and HOLDs), the other "attack", and a crewmate's "go here" marker on you
## Followers: N employees (staff and henchmen) spawn around you and follow you; with N > 1 the first henchman is told to
## fight just before the shot. Stand-in pictures are identicons made from the name (no Steam needed).
##
## Everything here is a dev seam: it uses the game's own verbs and orders (AllyBrain.give_order, Employee.order, daze,
## apply_damage) and PartyInfo.stage for the names and pictures.

const EMPLOYEES := [
	["henchman", "Gary (Henchman 1)"], ["staff", "Beatrice (sommelier)"], ["staff", "Mr. Bloom (accounts)"],
	["henchman", "Steve (Henchman 2)"], ["staff", "Penny (concierge)"], ["staff", "Molly (IT support)"],
	["henchman", "Nigel (Henchman 4)"], ["staff", "Iris (intern)"],
]
const LONG_YOU := "xX_TheLongestSteamNameEver_Xx"
const LONG_WIDE := "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"
const LONG_CJK := "ミッドナイト・キャスター・ジャパン"
const PALETTE := [Color("e76f51"), Color("2a9d8f"), Color("e9c46a"), Color("8ab17d"), Color("6d597a"), Color("457b9d"),
	Color("f4a261"), Color("b56576")]


static func run(game: Node, stage: String, followers: int, shot_after: float) -> void:
	var you: Hero = game.get("player")
	var allies: Array[Hero] = game.get("allies")
	if you == null:
		return
	var tree := game.get_tree()
	PartyInfo.stage.clear()
	match stage:
		"crew":
			_person(allies, 0, "Fox")
			_you_picture(you, "duckbob")
		"long":
			_you_picture(you, LONG_YOU, true)
			_person(allies, 0, LONG_WIDE)
			_person(allies, 1, LONG_CJK)
		"long2":
			_you_picture(you, "Повелитель_Заклинаний", true)
			_person(allies, 0, "김철수마법사길드장인")
			_person(allies, 1, "Ångström Ñoño-Ægir Øvergård")
		"down":
			tree.create_timer(maxf(0.1, shot_after - 1.2)).timeout.connect(func() -> void:
				if allies.size() > 0:
					allies[0].apply_damage(allies[0].max_hp * 3.0)
				if allies.size() > 1:
					allies[1].apply_damage(allies[1].hp - allies[1].max_hp * 0.25)
				you.daze(4.0))
		"orders":
			tree.create_timer(maxf(0.1, shot_after - 2.6)).timeout.connect(func() -> void:
				if allies.size() > 0:
					_order(allies[0], "go", you, you.global_position + Vector3(-3.0, 0.0, 2.0))
				OrderFx.marker(you.global_position + Vector3(7.0, 0.0, -5.0), "Fox: go here", you, Color(0.85, 0.5, 0.25), "go"))
			tree.create_timer(maxf(0.1, shot_after - 0.35)).timeout.connect(func() -> void:
				if allies.size() > 1:
					_order(allies[1], "attack", you, Vector3.INF))
	if followers > 0:
		tree.create_timer(maxf(0.1, shot_after - 2.4)).timeout.connect(func() -> void: _spawn_followers(you, followers))
		if followers > 1:
			tree.create_timer(maxf(0.1, shot_after - 0.3)).timeout.connect(func() -> void:
				for e in Employee.alive():
					if e.leader() == you and e.style == "henchman":
						e.order("attack", you)
						return)


static func _order(h: Hero, kind: String, by: Hero, point: Vector3) -> void:
	var brain := h.get_node_or_null("AllyBrain") as AllyBrain
	if brain != null:
		brain.give_order(kind, by, point)


## Seat `i` of the allies is played by a person called `who` (a stand-in avatar).
static func _person(allies: Array[Hero], i: int, who: String) -> void:
	if i < allies.size():
		PartyInfo.stage[allies[i].get_instance_id()] = {"name": who, "human": true, "avatar": identicon(who)}


## Your row: `who` as the name when `rename`; a stand-in picture unless Steam runs (then yours arrives from Steam).
static func _you_picture(you: Hero, who: String, rename: bool = false) -> void:
	var v := PartyInfo.hero_view(you, you)
	var st := {}
	if rename:
		st["name"] = who
	if v["avatar"] == null and SteamIdentity.steam_id() == 0:
		st["avatar"] = identicon(str(v["name"]) if not rename else who)
	PartyInfo.stage[you.get_instance_id()] = st


static func _spawn_followers(you: Hero, n: int) -> void:
	var map := GameWorld.map
	if map == null:
		return
	var cells: Array[Vector2i] = []
	for c in Hex.range_cells(you.current_cell(), 3):
		if c != you.current_cell() and map.is_walkable_cell(c):
			cells.append(c)
	for i in mini(n, EMPLOYEES.size()):
		if cells.is_empty():
			return
		var row: Array = EMPLOYEES[i]
		var e := Employee.spawn(cells[(i * 5) % cells.size()], {"style": row[0], "name": row[1]})
		cells.erase(cells[(i * 5) % cells.size()])
		if e != null:
			e.order("follow", you)
	if n >= 6:
		for e in Employee.alive():
			if e.leader() == you and e.display_name.begins_with("Penny"):
				e.apply_damage(e.max_hp * 0.6)   # (one hurt follower, to see the tiny bar move)


## A stand-in "Steam avatar": a 5x5 mirrored identicon from the name's hash on a tinted square, 64 x 64.
static func identicon(who: String) -> Texture2D:
	var h := absi(hash(who))
	var fg: Color = PALETTE[h % PALETTE.size()]
	var bg := fg.darkened(0.62)
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(bg)
	var bits := h >> 3
	for gy in 5:
		for gx in 3:
			if (bits >> (gy * 3 + gx)) & 1 == 1:
				for side in [gx, 4 - gx]:
					img.fill_rect(Rect2i(7 + side * 10, 7 + gy * 10, 10, 10), fg)
	return ImageTexture.create_from_image(img)
