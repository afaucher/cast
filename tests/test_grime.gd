extends MonsterTestBase
## The grime layer: deterministic ambient placement, the infestation heat (gates dirty, the start room almost
## clean, nothing on the start / exit cell), ichor trails, theme grime only for named themes, the player marks
## (right spot, fade, gone after 30 s, pooled and capped), and no errors without a layer.

const START := Vector2i(-14, 6)
const GATE := Vector2i(10, -3)
const EXIT := Vector2i(15, -8)
const THEME_KINDS: Array[String] = ["wine", "popcorn", "chalk", "oil", "rust", "spill"]

var _map: HexMap
var _plan: SitePlan


## Two rooms joined by a corridor, void everywhere else: the start room (room:0) and the gate room (room:1).
func _floor() -> void:
	_map = HexMap.new()
	var room0 := Hex.range_cells(START, 5)
	var room1 := Hex.range_cells(GATE, 6)
	for c in room0:
		_map.set_cell(c, 0).tag = "room:0"
	for c in room1:
		_map.set_cell(c, 0).tag = "room:1"
	for c in Hex.line(Vector2i(-9, 5), Vector2i(4, -1)):
		for n in [c] + Hex.neighbors(c):
			if not _map.has_cell(n):
				_map.set_cell(n, 0).tag = "corridor"
	_map.get_cell(START).tag = "start"
	_map.get_cell(EXIT).tag = "exit"
	_plan = SitePlan.new()
	_plan.start = START
	_plan.exit = EXIT
	_plan.start_room = "room:0"
	_plan.exit_room = "room:1"
	_plan.rooms = {"room:0": _typed(room0), "room:1": _typed(room1)}
	_plan.gates = [{"cell": GATE, "origin": false, "room": "room:1"}]


func _typed(cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.append_array(cells)
	return out


func _sig(marks: Array[GrimePlan.Mark]) -> String:
	var parts := PackedStringArray()
	for m in marks:
		parts.append("%s%d@%.3f,%.3f,%.3f r%.3f s%.3f" % [m.kind, m.variant, m.pos.x, m.pos.y, m.pos.z, m.rot, m.size.x])
	return "|".join(parts)


func _cell_of(m: GrimePlan.Mark) -> Vector2i:
	return Hex.from_world(m.pos)


func setup() -> void:
	_floor()
	_check_no_layer_is_harmless()
	_check_atlas()
	_check_ambient()
	_check_trails()
	_check_themes()
	await _check_marks_and_fade()
	await _check_cap()
	await _check_hooks()
	finish()


# --- no layer: nothing happens, nothing errors -------------------------------------------------------

func _check_no_layer_is_harmless() -> void:
	check(Grime.layer() == null, "no layer yet")
	check(not Grime.mark("scorch", Vector3.ZERO, 2.0), "Grime.mark with no layer is a no-op (false)")
	check(not Grime.mark("nonsense", Vector3(3, 0, 3), 1.0), "unknown kind with no layer")


# --- the atlas -----------------------------------------------------------------------------------

func _check_atlas() -> void:
	eq(GrimeAtlas.tile_count() <= GrimeAtlas.COLS * GrimeAtlas.ROWS, true, "every tile fits the atlas grid")
	var seen := {}
	for k in GrimeAtlas.kinds():
		for v in GrimeAtlas.variant_count(k):
			var t := GrimeAtlas.tile_of(k, v)
			check(t >= 0 and not seen.has(t), "%s/%d has its own tile" % [k, v])
			seen[t] = true
	for k in Grime.STYLE:
		check(GrimeAtlas.has_kind(k), "style kind %s is in the atlas" % k)
	var imgs := GrimeAtlas.images()
	eq(imgs[0].get_width(), GrimeAtlas.COLS * GrimeAtlas.TILE, "atlas width")
	# Every tile paints something (alpha) and keeps its edge pixels clear (so no mark is cut off by its quad).
	for k in GrimeAtlas.kinds():
		var tc := GrimeAtlas.tile_cell(GrimeAtlas.tile_of(k, 0))
		var ox := int(tc.x) * GrimeAtlas.TILE
		var oy := int(tc.y) * GrimeAtlas.TILE
		var painted := 0
		var edge := 0.0
		for y in GrimeAtlas.TILE:
			for x in GrimeAtlas.TILE:
				var a: float = imgs[0].get_pixel(ox + x, oy + y).a
				if a > 0.3:
					painted += 1
				if (x == 0 or y == 0) and a > 0.2:
					edge = maxf(edge, a)
		check(painted > 40, "tile %s is painted (%d px)" % [k, painted])
		if k != "drag":   # the drag streak runs to the tile's left edge by design
			check(edge < 0.2, "tile %s keeps its top/left edge clear" % k)


# --- ambient placement -------------------------------------------------------------------------------

func _check_ambient() -> void:
	var a := GrimePlan.build(_map, _plan, 7)
	var b := GrimePlan.build(_map, _plan, 7)
	var c := GrimePlan.build(_map, _plan, 8)
	check(a.size() > 40, "a floor with a gate has plenty of grime (%d)" % a.size())
	eq(_sig(a), _sig(b), "same seed -> identical placement")
	check(_sig(a) != _sig(c), "different seed -> different placement")
	check(a.size() <= GrimePlan.AMBIENT_CAP, "global cap (%d <= %d)" % [a.size(), GrimePlan.AMBIENT_CAP])

	var ctx := GrimePlan.context(_map, _plan)
	var per_cell := {}
	var near_gate := 0
	var in_start := 0
	var gate_cells := 0
	var start_cells := 0
	for cc in _map.cells:
		if Hex.distance(cc, GATE) <= 4 and cc != GATE:
			gate_cells += 1
		if _map.get_cell(cc).tag == "room:0":
			start_cells += 1
	for m in a:
		var cell := _cell_of(m)
		per_cell[cell] = int(per_cell.get(cell, 0)) + 1
		check(m.cell == cell, "a mark lies inside the cell it was planned for")
		check(_map.get_cell(cell).type == HexMap.Tile.FLOOR, "only on floor")
		check(cell != START and cell != EXIT, "nothing on the start or exit cell")
		check(Hex.distance(cell, START) > GrimePlan.START_CLEAR and Hex.distance(cell, EXIT) > GrimePlan.START_CLEAR, "clear zone around the start and exit")
		check(cell != GATE, "nothing under the gate")
		check(GrimeAtlas.has_kind(m.kind), "known kind " + m.kind)
		near_gate += 1 if Hex.distance(cell, GATE) <= 4 else 0
		in_start += 1 if _map.get_cell(cell).tag == "room:0" or cell == START else 0
	for cell: Vector2i in per_cell:
		check(int(per_cell[cell]) <= GrimePlan.CELL_CAP, "per-cell cap at %s" % str(cell))
	var gate_density := float(near_gate) / gate_cells
	var start_density := float(in_start) / start_cells
	print("grime: %d marks; near the gate %.2f per cell, start room %.3f per cell" % [a.size(), gate_density, start_density])
	check(gate_density > 0.8, "dense near the gate (%.2f per cell)" % gate_density)
	check(gate_density > 12.0 * maxf(start_density, 0.001), "far denser near the gate (%.2f) than in the start room (%.3f)" % [gate_density, start_density])
	check(in_start <= 3, "the start room is almost clean (%d marks)" % in_start)
	# Heat falls off with distance from the gate and the start room is scaled right down.
	var h1 := GrimePlan.heat_at(_map, ctx, GATE + Vector2i(1, 0))
	var h5 := GrimePlan.heat_at(_map, ctx, GATE + Vector2i(-5, 0))
	check(h1 > h5 and h5 > 0.0, "heat falls with distance (%.2f > %.2f)" % [h1, h5])
	check(GrimePlan.heat_at(_map, ctx, START + Vector2i(3, 0)) < 0.01, "start room heat ~ 0")
	# Floor 3: the origin room is hot even away from the gate.
	var p3 := SitePlan.new()
	p3.start = START
	p3.exit = EXIT
	p3.start_room = "room:0"
	p3.origin_room = "room:1"
	p3.gates = [{"cell": GATE, "origin": true, "room": "room:1"}]
	var ctx3 := GrimePlan.context(_map, p3)
	check(GrimePlan.heat_at(_map, ctx3, GATE + Vector2i(5, 0)) >= GrimePlan.ORIGIN_ROOM_HEAT - 0.001, "origin room heat floor")
	# Without any plan (a bare map) it still works and stays off the start / exit.
	var bare := GrimePlan.build(_map, null, 3)
	for m in bare:
		check(Hex.distance(_cell_of(m), START) > GrimePlan.START_CLEAR, "bare map: clear start")


func _check_trails() -> void:
	var marks := GrimePlan.build(_map, _plan, 7)
	var drags := 0
	var in_corridor := 0
	var min_d := 99
	var max_d := 0
	for m in marks:
		if m.source == "trail":
			var cell := _cell_of(m)
			var d := Hex.distance(cell, GATE)
			if m.kind == "drag":
				drags += 1
				min_d = mini(min_d, d)
				max_d = maxi(max_d, d)
				if _map.get_cell(cell).tag == "corridor":
					in_corridor += 1
	check(drags >= 6, "ichor drag trail leaves the gate (%d drag marks)" % drags)
	check(in_corridor >= 2, "the trail runs along the corridor (%d marks)" % in_corridor)
	check(max_d >= 7, "the trail leads away from the gate (reaches %d cells)" % max_d)
	# A trail on a map with no gate leaves nothing.
	var no_gate := SitePlan.new()
	no_gate.start = START
	no_gate.exit = EXIT
	no_gate.start_room = "room:0"
	for m in GrimePlan.build(_map, no_gate, 7):
		check(m.source != "trail", "no gate, no trail")


# --- theme grime: only when room_themes names the theme -----------------------------------------------------

func _check_themes() -> void:
	# No themes (and a SitePlan without room_themes): none of the theme kinds exist anywhere.
	for m in GrimePlan.build(_map, _plan, 7):
		check(m.source != "theme" and not THEME_KINDS.has(m.kind), "no theme marks without room_themes (%s)" % m.kind)
	var cases := {"wine_cellar": "wine", "home_cinema": "popcorn", "wellness_spa": "chalk", "gym": "oil", "torture_chamber": "rust", "lab": "spill"}
	for theme: String in cases:
		var want: String = cases[theme]
		var marks := GrimePlan.build(_map, _plan, 7, {"room:1": theme})
		var n := 0
		for m in marks:
			if THEME_KINDS.has(m.kind):
				check(m.kind == want, "%s grime is %s, not %s" % [theme, want, m.kind])
				check(_map.get_cell(_cell_of(m)).tag == "room:1", "%s marks stay in the themed room" % theme)
				n += 1
		check(n >= 8, "%s room gets %s marks (%d)" % [theme, want, n])
	# A theme with no grime of its own, or naming a room that is not there, adds nothing.
	for m in GrimePlan.build(_map, _plan, 7, {"room:1": "server_room", "room:9": "wine_cellar"}):
		check(not THEME_KINDS.has(m.kind), "server room / unknown room: no theme kinds")
	# The start room's themed marks are thinned out (it stays almost clean).
	var start_n := 0
	for m in GrimePlan.build(_map, _plan, 7, {"room:0": "wine_cellar"}):
		if THEME_KINDS.has(m.kind):
			start_n += 1
	check(start_n < 12, "themed start room stays mostly clean (%d)" % start_n)
	# The same seed gives the same themed floor.
	eq(_sig(GrimePlan.build(_map, _plan, 7, {"room:1": "gym"})), _sig(GrimePlan.build(_map, _plan, 7, {"room:1": "gym"})), "themed placement is deterministic")


# --- player marks: placed, fade, gone after 30 s -----------------------------------------------------------------

func _world() -> GrimeLayer:
	new_world(_map)
	return GrimeLayer.attach(world, _map, _plan, 7)


func _check_marks_and_fade() -> void:
	var layer := _world()
	check(Grime.layer() == layer, "the layer registers itself")
	check(layer.ambient.size() > 40, "the layer placed its ambient grime")
	eq(layer.live_count(), 0, "no player marks yet")
	var spots := {
		Grime.SCORCH: Vector3(-2.0, 0, 3.0), Grime.CORN: Vector3(3.0, 0, 0.0), Grime.TEETH: Vector3(0.0, 0, -4.0),
		Grime.CRACKS: Vector3(-5.0, 0, -2.0), Grime.STAIN: Vector3(6.0, 0, 6.0), Grime.SCUFF: Vector3(-1.0, 0, -1.0),
	}
	# These spots are over plain floor of the gate room or corridor; move them onto cells that exist.
	var i := 0
	var wanted: Array[Vector3] = []
	for kind: String in spots:
		var at: Vector3 = Hex.to_world(GATE + Vector2i(-2 + i, 2 - i), 0.0)
		wanted.append(at)
		check(Grime.mark(kind, at, 2.0 if kind != Grime.SCUFF else 1.0), "%s mark laid" % kind)
		i += 1
	eq(layer.live_count(), 6, "six player marks")
	var marks := layer.live_marks()
	var kinds_seen := {}
	for j in marks.size():
		var m: Dictionary = marks[j]
		kinds_seen[m["recipe"]] = true
		var pieces: Array = m["pieces"]
		check(pieces.size() >= 1, "%s lays at least one decal" % m["recipe"])
		var first: Vector3 = pieces[0]
		check(GameWorld.flat_distance(first, wanted[j]) < (1.0 if m["recipe"] == Grime.TEETH else 0.05), "%s: its main decal is at the requested spot (%s vs %s)" % [m["recipe"], str(first), str(wanted[j])])
		check(absf(first.y - (0.0 + Grime.LIFT)) < 0.02, "%s: lies just above the hex top (y %.3f)" % [m["recipe"], first.y])
		for p: Vector3 in pieces:
			check(GameWorld.flat_distance(p, wanted[j]) < 3.5, "%s: every decal stays near its mark" % m["recipe"])
		check(float(m["fade"]) == 1.0, "starts opaque")
	eq(kinds_seen.size(), 6, "all six recipes")
	var free_before := layer.free_slot_count()
	check(free_before < GrimeLayer.LIVE_SLOTS, "decals took pool slots")

	# Step real physics frames (the test runner fixes 60 fps): alive, then fading, then gone at 30 s.
	await frames(60 * 10)
	eq(layer.live_count(), 6, "alive after 10 s")
	check(float(layer.live_marks()[0]["fade"]) == 1.0, "still opaque after 10 s")
	await frames(60 * 13)   # t ~ 23 s: inside the fade window (starts at LIFE - FADE = 21 s)
	eq(layer.live_count(), 6, "alive after 23 s")
	var f23 := float(layer.live_marks()[0]["fade"])
	check(f23 < 1.0 and f23 > 0.0, "fading at 23 s (%.2f)" % f23)
	await frames(60 * 4)    # t ~ 27 s: dimmer still
	var f27 := float(layer.live_marks()[0]["fade"])
	check(f27 < f23, "dimmer at 27 s (%.2f < %.2f)" % [f27, f23])
	await frames(60 * 4)    # t ~ 31 s: gone
	print("grime: gone after %.1f s of layer clock, fade at 23 s %.2f, 27 s %.2f" % [layer.clock(), f23, f27])
	eq(layer.live_count(), 0, "gone after 30 s (clock %.1f)" % layer.clock())
	eq(layer.free_slot_count(), GrimeLayer.LIVE_SLOTS, "every pool slot is back")
	check(layer.ambient.size() > 40, "ambient grime persists")

	# A mark over the void or a wall leaves nothing (no floating decals).
	check(not Grime.mark(Grime.SCORCH, Hex.to_world(Vector2i(60, 60), 0.0), 1.0), "void: no mark")
	eq(layer.live_count(), 0, "nothing was laid over the void")
	# Marks free with the layer: no dangling registration.
	world.free()
	world = null
	await frames(2)
	check(Grime.layer() == null, "freed layer unregisters")
	check(not Grime.mark(Grime.SCORCH, Vector3.ZERO, 1.0), "no layer again: no-op")


# --- the cap and recycling ---------------------------------------------------------------------------------------------

func _check_cap() -> void:
	var layer := _world()
	var first_at := Hex.to_world(GATE, 0.0)
	check(Grime.mark(Grime.SCUFF, first_at, 1.0), "first mark")
	for i in 200:
		var c := GATE + Vector2i(-3 + (i % 7), -3 + (i / 7) % 7)
		Grime.mark(Grime.SCUFF if i % 2 == 0 else Grime.STAIN, Hex.to_world(c, 0.0) + Vector3(0.1, 0, 0.1), 1.0)
		await get_tree().physics_frame
	eq(layer.live_count(), Grime.MAX_LIVE, "live marks are capped at %d" % Grime.MAX_LIVE)
	for m in layer.live_marks():
		check(not (m["recipe"] == Grime.SCUFF and GameWorld.flat_distance(m["pos"], first_at) < 0.01), "the oldest mark was recycled")
	var used := 0
	for m in layer.live_marks():
		used += (m["pieces"] as Array).size()
	eq(layer.free_slot_count(), GrimeLayer.LIVE_SLOTS - used, "slots in use + free = pool size")
	world.free()
	world = null
	await frames(2)


# --- the real hooks: spells, deaths, slams ---------------------------------------------------------------------------------

func _check_hooks() -> void:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 9):
		m.set_cell(c, 0)
	new_world(m)
	var layer := GrimeLayer.attach(world, m, null, 3)
	var caster := add_hero(Vector2i(-4, 0))
	var recipes := func() -> Array:
		var out: Array = []
		for mk in layer.live_marks():
			out.append(mk["recipe"])
		return out

	# Fireball: scorch where it lands.
	SpellBook.cast("fireball", caster, 1.0, Hex.to_world(Vector2i(1, 0), 0.0))
	check(await wait_until(func() -> bool: return recipes.call().has(Grime.SCORCH), 120), "fireball leaves a scorch")
	var sc: Dictionary = layer.live_marks()[0]
	check(GameWorld.flat_distance(sc["pos"], Hex.to_world(Vector2i(1, 0), 0.0)) < 1.2, "the scorch is where the fireball landed")

	# Corn, tentacles: after their delay.
	var far := Hex.to_world(Vector2i(2, 1), 0.0)
	SpellBook.cast("corn", caster, 1.0, far)
	SpellBook.cast("tentacles", caster, 1.0, Hex.to_world(Vector2i(0, -4), 0.0))
	check(await wait_until(func() -> bool: return recipes.call().has(Grime.CORN) and recipes.call().has(Grime.CRACKS), 200), "corn and tentacles leave marks")
	for mk in layer.live_marks():
		if mk["recipe"] == Grime.CORN:
			check(GameWorld.flat_distance(mk["pos"], far) < 0.5, "corn's mark is at the strike")
			var kernels := (mk["pieces"] as Array).size()
			check(kernels >= 8, "corn: ring, scorch and kernels (%d decals)" % kernels)

	# Coffee: a dark spill at the aim point on EVERY cast, even one that hits nobody.
	SpellBook.cast("coffee", caster, 1.0, Hex.to_world(Vector2i(-1, 5), 0.0))
	check(await wait_until(func() -> bool: return recipes.call().has(Grime.COFFEE), 60), "a coffee cast that hits nobody still leaves a spill")
	for mk in layer.live_marks():
		if mk["recipe"] == Grime.COFFEE:
			check((mk["pieces"] as Array).size() >= 2, "the coffee spill is a splat with droplets (%d decals)" % (mk["pieces"] as Array).size())
	check(Grime.LIFE <= 30.0, "and it fades inside the 30 s player-mark rule")

	# Teeth pop.
	var dummy := TrainingDummy.new()
	dummy.max_hp = 1000.0
	GameWorld.spawn(dummy, Hex.to_world(Vector2i(-2, 3), 0.0))
	dummy.snap_to_ground()
	SpellBook.cast("teeth", caster, 1.0, dummy.global_position)
	check(await wait_until(func() -> bool: return recipes.call().has(Grime.TEETH), 200), "a teeth pop leaves tooth bits")

	# A monster's death: an ichor stain where it fell.
	var grunt := MonsterFactory.spawn("grunt", Vector2i(4, -3))
	var died_at := grunt.global_position
	grunt.apply_damage(9999.0, caster)
	check(recipes.call().has(Grime.STAIN), "a monster's death leaves a stain")
	for mk in layer.live_marks():
		if mk["recipe"] == Grime.STAIN:
			check(GameWorld.flat_distance(mk["pos"], died_at) < 0.3, "the stain is where it died")

	# A slam scuffs the floor.
	var before := layer.live_count()
	dummy.shove_impact.emit("slam", Hex.to_world(Vector2i(3, 3), 0.0), 5.0)
	eq(layer.live_count(), before + 1, "a shove slam leaves a scuff")
	check(recipes.call().has(Grime.SCUFF), "scuff recipe")

	# Layer gone: the same casts still run clean (test_spell_* run without a layer too).
	world.free()
	world = null
	await frames(2)
	new_world(m)
	var c2 := add_hero(Vector2i(-4, 0))
	SpellBook.cast("fireball", c2, 1.0, Hex.to_world(Vector2i(1, 0), 0.0))
	SpellBook.cast("tentacles", c2, 1.0, Hex.to_world(Vector2i(0, -4), 0.0))
	await frames(100)
	check(true, "casts with no layer are fine")
