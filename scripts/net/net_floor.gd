class_name NetFloor
extends RefCounted
## The floor every machine builds from the contract seed, and the tools that prove it is the same floor
## (docs/design/networking-build-plan.md M1):
##
## - ids: every seed-built actor gets a net id in BUILD order (the order the scene tree holds them, which is the
##   order SiteBuilder.spawn created them). Heroes get theirs from their seat (1-3). Ids start at ID_BASE for
##   everything else, so M3's runtime spawns can take 10000 and up. The ids are kept in NetRegistry (id -> node).
## - the CHECKSUM: a hash of the map (every cell, the midpoint-wall masks, the materials), the site plan (every
##   SitePlan field: rooms, themes, materials, notes, props, decor, the van), the contract, and the SPAWN TABLE
##   (id, kind, name, team, cell and position of every actor). Each machine computes it after building and the
##   host compares them; one different cell is a different hash. The parts are kept apart so a mismatch can
##   say WHAT differs.
## - copies: on a client every host-owned actor becomes a non-acting copy (Net.make_copy).
##
## Numbers are written with fixed decimals and dictionaries with their keys sorted, so the text (and the hash)
## does not depend on insertion order or on float formatting.

const ID_BASE := 100
const ID_META := "net_id"


## Give the seed-built actors under `root` their ids, in tree order; `heroes` maps a seat (1-3) to its hero.
## Returns how many seed-built actors got one.
static func assign_ids(root: Node, heroes: Dictionary) -> int:
	NetRegistry.clear()   # a new floor: the registry (id -> node) is rebuilt with the ids
	var seat_of: Dictionary = {}
	for seat: int in heroes:
		var h: Node = heroes[seat]
		if h != null:
			NetRegistry.register(seat, h)
			seat_of[h] = seat
	var next := ID_BASE
	for a in actors_under(root):
		if seat_of.has(a):
			continue
		NetRegistry.register(next, a)
		next += 1
	var actors := next - ID_BASE
	# M3: component pickups already on the floor (a dev --drop-near) are host-owned things too, built the same everywhere.
	for p in pickups_under(root):
		NetRegistry.register(next, p)
		next += 1
	NetRegistry.seed_top = next
	return actors


## Every ComponentPickup under `root`, depth first in tree order.
static func pickups_under(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	if root != null:
		_collect_pickups(root, out)
	return out


static func _collect_pickups(n: Node, out: Array[Node]) -> void:
	for c in n.get_children():
		if c is ComponentPickup:
			out.append(c)
		_collect_pickups(c, out)


static func id_of(node: Node) -> int:
	return int(node.get_meta(ID_META, 0)) if node != null else 0


## Every Actor under `root`, depth first in tree (= build) order.
static func actors_under(root: Node) -> Array[Actor]:
	var out: Array[Actor] = []
	if root != null:
		_collect(root, out)
	return out


static func _collect(n: Node, out: Array[Actor]) -> void:
	for c in n.get_children():
		if c is Actor:
			out.append(c as Actor)
		_collect(c, out)


## Make every host-owned thing under `root` a copy (client side): actors except `keep` (the local hero), and the
## component pickups on the floor. Returns how many.
static func freeze_copies(root: Node, keep: Array) -> int:
	var n := 0
	for a in actors_under(root):
		if keep.has(a):
			continue
		Net.make_copy(a)
		n += 1
	if root != null and root.is_inside_tree():
		for p in root.get_tree().get_nodes_in_group("component_pickups"):
			if root.is_ancestor_of(p):
				Net.make_copy(p)
				n += 1
	return n


# --- The checksum -----------------------------------------------------------------------------------------

## {"all", "map", "plan", "run", "spawn"} (16-hex-digit hashes), {"plan_keys": {field: hash}} for diagnostics,
## and the counts {"cells", "actors"}. `root` is the node the actors were spawned under (GameWorld.root).
static func checksum(map: HexMap, plan: SitePlan, run: ContractRun, root: Node) -> Dictionary:
	var map_text := map_text_of(map)
	var plan_keys := {}
	var plan_lines := PackedStringArray()
	var fields: Array = plan.net_fields().keys()
	fields.sort()
	for f: String in fields:
		var t := canon(plan.get(f))
		plan_keys[f] = _hash(t)
		plan_lines.append("%s=%s" % [f, t])
	var run_lines := PackedStringArray()
	var run_fields: Array = run.net_fields().keys()
	run_fields.sort()
	for f: String in run_fields:
		run_lines.append("%s=%s" % [f, canon(run.get(f))])
	var spawn_text := spawn_text_of(root)
	var parts := {
		"map": _hash(map_text),
		"plan": _hash("\n".join(plan_lines)),
		"run": _hash("\n".join(run_lines)),
		"spawn": _hash(spawn_text),
	}
	var out := parts.duplicate()
	out["all"] = _hash("%s|%s|%s|%s" % [parts["map"], parts["plan"], parts["run"], parts["spawn"]])
	out["plan_keys"] = plan_keys
	out["cells"] = map.cells.size()
	out["actors"] = actors_under(root).size()
	return out


## The names of the parts that differ between two checksums ("map", "plan", "run", "spawn").
static func differing_parts(a: Dictionary, b: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k in ["map", "plan", "run", "spawn"]:
		if str(a.get(k, "")) != str(b.get(k, "")):
			out.append(k)
	return out


static func map_text_of(map: HexMap) -> String:
	var keys: Array = map.cells.keys()
	keys.sort()
	var lines := PackedStringArray()
	lines.append("midpoint=%s" % str(map.midpoint_walls))
	for c: Vector2i in keys:
		var cell: HexMap.Cell = map.cells[c]
		lines.append("%d,%d:%d,%d,%d,%d,%s,%d,%d,%d" % [c.x, c.y, cell.level, cell.type, cell.stair_dir, cell.stair_rise,
			cell.tag, cell.wall_mask, cell.wall_top, cell.mat_id])
	return "\n".join(lines)


## One line per actor: id, kind (its script), name, team, cell, position, max hp.
static func spawn_text_of(root: Node) -> String:
	var lines := PackedStringArray()
	for a in actors_under(root):
		var script: Script = a.get_script()
		var kind := script.resource_path.get_file() if script != null else a.get_class()
		var p := a.global_position
		var cell := Hex.from_world(p)
		lines.append("%d|%s|%s|%d|%d,%d|%.2f,%.2f,%.2f|%.1f" % [id_of(a), kind, a.display_name, a.team, cell.x, cell.y, p.x, p.y, p.z, a.max_hp])
	return "\n".join(lines)


## A stable text for a Variant: sorted dictionary keys, fixed decimals.
static func canon(v: Variant) -> String:
	match typeof(v):
		TYPE_NIL:
			return "nil"
		TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return str(v)
		TYPE_FLOAT:
			return "%.4f" % (float(v) + 0.0)
		TYPE_VECTOR2:
			var v2: Vector2 = v
			return "(%.4f,%.4f)" % [v2.x + 0.0, v2.y + 0.0]
		TYPE_VECTOR3:
			var v3: Vector3 = v
			return "(%.4f,%.4f,%.4f)" % [v3.x + 0.0, v3.y + 0.0, v3.z + 0.0]
		TYPE_COLOR:
			var c: Color = v
			return "#%.3f,%.3f,%.3f,%.3f" % [c.r, c.g, c.b, c.a]
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var keys: Array = d.keys()
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
			var parts := PackedStringArray()
			for k: Variant in keys:
				parts.append("%s:%s" % [canon(k), canon(d[k])])
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var arr: Array = v
			var parts := PackedStringArray()
			for e: Variant in arr:
				parts.append(canon(e))
			return "[" + ",".join(parts) + "]"
		TYPE_OBJECT:
			return "obj"
		_:
			return str(v)


static func _hash(text: String) -> String:
	return text.sha256_text().substr(0, 16)
