class_name SewerDev
extends RefCounted
## The sewer slice's dev driver (docs/design/sewer-concept.md, "Phase 1 as built"): `--sewer N` builds sewer layout N
## (SewerLayouts: 1, 2, 4, 5; 3 = L1 in the toxic look) as every floor of the contract, solo only (ignored in a shared run,
## like --lava-cave). GameDev (scripts/app/dev/game_dev.gd) calls it from the game's dev hooks:
##   _dev_floor     the layout's map and plan in place of the generated floor (game.gd's one hook for it)
##   (deferred)     SewerView dresses the terrain: the water, foam, kerbs, the look and its light
##   _spawn_near    stage(): the layout's monsters, its goblin scout, the gator, the live wires on the panels
##   _dev_on_floor_ready  demo(): --sewer-demo overview|nip|wire (screenshots)
## The flag starts the contract on floor 2 unless --floor says otherwise, so the crew arrives in the elevator, which stands
## on the layout's dry landing deck.
##
## Flags: --sewer N, --sewer-demo overview|nip|wire (with --demo-after S, default 1.0).


## The sewer flags into the game's opts (GameDev._parse_args).
static func parse(args: PackedStringArray, opts: Dictionary) -> void:
	var i := args.find("--sewer")
	if i >= 0:
		var n := int(args[i + 1]) if i + 1 < args.size() and not args[i + 1].begins_with("--") else 1
		opts["sewer"] = clampi(n, 1, SewerLayouts.COUNT)
		if not opts.has("floor"):
			opts["floor"] = 2   # (arrive in the elevator, onto the layout's dry landing deck)
	var j := args.find("--sewer-demo")
	if j >= 0 and j + 1 < args.size():
		opts["sewer_demo"] = args[j + 1]


## Everything a layout stages that is not in its plan: the monsters (the normal kinds, archers on the dry decks across the
## channels), the goblin scout on a ledge, the gator, and a live wire on every electrical panel. Returns {gators, wires,
## monsters, scout, pests (how many of the contract's pest kind it placed)}.
static func stage(L: Dictionary, site: SiteBuilder.Site, map: HexMap, floor_seed: int, view: SewerView) -> Dictionary:
	var out := {"gators": [] as Array[Gator], "wires": [] as Array[LiveWire], "monsters": [] as Array[Monster], "scout": null, "pests": 0}
	for e: Dictionary in L["monsters"]:
		var at: Vector2 = e["at"]
		var m := MonsterFactory.spawn(str(e["kind"]), ThemeGeo.cell_of(at))
		if m == null:
			continue
		_place(m, at, e["face"])
		site.monsters.append(m)
		(out["monsters"] as Array).append(m)
		if site.pest == "everything" or str(e["kind"]) == site.pest:
			out["pests"] = int(out["pests"]) + 1
	var sc: Dictionary = L["scout"]
	if sc.has("route"):
		var pts: Array[Vector3] = []
		for p: Vector2 in (sc["route"] as Array):
			var gh := map.ground_height(Vector3(p.x, 0.0, p.y))
			pts.append(Vector3(p.x, 0.0 if is_nan(gh) else gh, p.y))
		var looks: Array[Vector3] = []
		for v: Vector2 in (sc["looks"] as Array):
			looks.append(Vector3(v.x, 0.0, v.y))
		var g := MonsterFactory.spawn("goblin", Hex.from_world(pts[0]))
		if g != null:
			_place(g, Vector2(pts[0].x, pts[0].z), Vector2(pts[1].x - pts[0].x, pts[1].z - pts[0].z) if pts.size() > 1 else Vector2.RIGHT)
			g.call("set_route", pts, looks, 0)
			site.scouts.append(g)
			out["scout"] = g
	elif sc.has("at"):
		var g2 := MonsterFactory.spawn("goblin", ThemeGeo.cell_of(sc["at"]))
		if g2 != null:
			_place(g2, sc["at"], sc.get("face", Vector2.RIGHT))
			site.scouts.append(g2)
			out["scout"] = g2
	var gt: Dictionary = L["gator"]
	if not gt.is_empty():
		var spots: Array[Vector2] = []
		for s: Vector2 in (gt["spots"] as Array):
			spots.append(s)
		var gator := Gator.spawn(gt["at"], gt["face"], Gator.region_of(map), spots, floor_seed * 7 + int(L["id"]))
		if gator != null:
			(out["gators"] as Array).append(gator)
	for p in site.props:
		var pp := p as PricedProp
		if pp == null or pp.kind != "electrical_panel":
			continue
		var drop := LiveWire.drop_point_for(map, Vector2(pp.global_position.x, pp.global_position.z), pp.facing_vector())
		if drop != Vector3.INF:
			(out["wires"] as Array).append(LiveWire.attach(pp, drop, view))
	return out


## Stand a spawned actor at X/Z `at` (on the ground there), facing `face`.
static func _place(a: Monster, at: Vector2, face: Vector2) -> void:
	a.global_position = Vector3(at.x, a.global_position.y, at.y)
	a.snap_to_ground()
	if face.length() > 0.01:
		a.set_spawn_facing(Vector3(face.x, 0.0, face.y))
