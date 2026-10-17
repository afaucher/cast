extends MonsterTestBase
## The faceted models are wired into Monster: every kind spawns wearing its model by default, the
## windup / swing / tint / fade / downed hooks fire, Monster.use_proto_visuals brings back the old
## primitive bodies, a model-wearing monster shoved into a pit still dies and frees, and a pack
## fighting a dummy hero for 600 frames runs clean.

const SIZES := {"grunt": GruntModel.MODEL_SCALE, "archer": ArcherModel.MODEL_SCALE, "brute": BruteModel.MODEL_SCALE, "swarmer": SwarmerModel.MODEL_SCALE}


func _init() -> void:
	timeout_sec = 400.0      # the clock runs on fixed-fps frames in the runner: ~7000 frames below


func setup() -> void:
	Monster.use_proto_visuals = false
	check(not Monster.use_proto_visuals, "faceted models are the default")
	_defaults()
	await _hooks()
	await _proto()
	await _pit()
	await _brawl()
	await _perf()
	Monster.use_proto_visuals = false
	finish()


func _param(mod: MonsterModel, key: String) -> float:
	var v: Variant = mod._mat.get_shader_parameter(key)
	return float(v) if v != null else 0.0


func _tint_k(mod: MonsterModel) -> float:
	return _param(mod, "tint_k")


# ---------------------------------------------------------------- default look

func _defaults() -> void:
	new_world(flat_map(8))
	for kind in MonsterFactory.KINDS:
		var m := MonsterFactory.spawn(kind, Vector2i(0, 0))
		check(m.model != null, "%s spawns with a model" % kind)
		if m.model == null:
			continue
		check(m.model.get_parent() == m._visual, "%s model lives under the Visual" % kind)
		eq(m.model.monster_kind, kind, "%s gets its own model" % kind)
		eq(m._mats.size(), 0, "%s builds no primitive materials" % kind)
		var prims := 0
		for c in m._visual.get_children():
			if c != m.model:
				prims += 1
		eq(prims, 0, "%s Visual holds only the model" % kind)
		near(m.bar_height, m.model.ui_height + Monster.MODEL_BAR_GAP, 0.0001, "%s hp bar rides on ui_height" % kind)
		near(m.model.scale.x, float(SIZES[kind]), 0.0001, "%s model scale is its own" % kind)
		check(m.windup_scale <= 0.12 + 0.0001, "%s swell is small with a model (%.2f)" % [kind, m.windup_scale])
		m.apply_damage(1.0)
		near(m._bar.position.y, m.bar_height, 0.0001, "%s bar placed at bar_height" % kind)
		m.free()
	near(MonsterFactory.spawn("swarmer", Vector2i(1, 0)).windup_scale, 0.12, 0.0001, "swarmer swell is 0.12")
	near(MonsterFactory.spawn("brute", Vector2i(-1, 0)).windup_scale, 0.06, 0.0001, "brute swell is 0.06")
	check(GruntModel.MODEL_SCALE >= 1.19, "the grunt is scaled up for the game camera")


# ---------------------------------------------------------------- hooks

func _hooks() -> void:
	for kind in MonsterFactory.KINDS:
		new_world(flat_map(10))
		var hero := add_hero(Vector2i(0, 0))
		hero.max_hp = 1.0e9
		hero.hp = hero.max_hp
		var m := MonsterFactory.spawn(kind, Vector2i(4, 0))
		var mod: MonsterModel = m.model
		m.aggro(hero)
		var peak_wind := 0.0
		var peak_swing := 0.0
		var peak_tint := 0.0
		var swell := 1.0
		for i in 480:
			await get_tree().physics_frame
			peak_wind = maxf(peak_wind, mod._wind)
			peak_swing = maxf(peak_swing, mod._swing)
			peak_tint = maxf(peak_tint, _tint_k(mod))
			swell = maxf(swell, m._visual.scale.x)
			if peak_wind > 0.8 and peak_swing > 0.5 and peak_tint > 0.2 and swell > 1.0 and i > 30:
				break
		print("  %s: windup %.2f swing %.2f tint %.2f swell %.3f" % [kind, peak_wind, peak_swing, peak_tint, swell])
		check(peak_wind > 0.8, "%s windup telegraph reaches the model (%.2f)" % [kind, peak_wind])
		check(peak_swing > 0.5, "%s strike calls attack_swing (%.2f)" % [kind, peak_swing])
		check(peak_tint > 0.2, "%s windup pulse tints the model (%.2f)" % [kind, peak_tint])
		check(swell > 1.0 and swell <= 1.0 + m.windup_scale + 0.001, "%s Visual swells a little (%.3f)" % [kind, swell])
		near(mod.scale.x, float(SIZES[kind]), 0.0001, "%s nothing else wrote the model's scale" % kind)

		# Hit flash.
		m.state = Monster.State.IDLE
		m.aggro_range = 0.0
		m.target = null
		m._telegraph = 0.0
		m.apply_damage(1.0, null)
		await get_tree().physics_frame
		check(_tint_k(mod) > 0.5, "%s hit flash tints the model" % kind)
		var tc: Color = mod._mat.get_shader_parameter("tint_color") if mod._mat.get_shader_parameter("tint_color") != null else Color.BLACK
		check(tc.r > 0.9 and tc.g > 0.9 and tc.b > 0.9, "%s flash is white" % kind)
		await frames(30)
		near(_tint_k(mod), 0.0, 0.01, "%s flash fades out" % kind)

		# Death: downed at once, topples, shrinks away, frees.
		m.apply_damage(9999.0, hero)
		check(m.dead and mod.is_downed(), "%s model is downed on death" % kind)
		near(_param(mod, "glow_gain"), 0.0, 0.0001, "%s glow goes out on death" % kind)
		await frames(20)
		check(absf(m._visual.rotation.x) > 0.5, "%s Visual topples" % kind)
		var s_mid := mod.scale.x
		await frames(30)
		check(mod.scale.x < s_mid or not is_instance_valid(m), "%s model shrinks away" % kind)
		await frames(80)
		check(not is_instance_valid(m), "%s frees after the death animation" % kind)


# ---------------------------------------------------------------- fallback

func _proto() -> void:
	Monster.use_proto_visuals = true
	new_world(flat_map(10))
	var hero := add_hero(Vector2i(0, 0))
	hero.max_hp = 1.0e9
	hero.hp = hero.max_hp
	for kind in MonsterFactory.KINDS:
		var m := MonsterFactory.spawn(kind, Vector2i(3, 1))
		check(m.model == null, "%s has no model with use_proto_visuals" % kind)
		check(m._visual.get_child_count() > 3, "%s wears primitives (%d parts)" % [kind, m._visual.get_child_count()])
		check(m._mats.size() > 0, "%s has primitive materials" % kind)
		m.aggro(hero)
		var swelled := false
		for i in 300:
			await get_tree().physics_frame
			swelled = swelled or m._visual.scale.x > 1.05
		check(swelled, "%s primitive body still swells in its windup" % kind)
		m.apply_damage(9999.0, hero)
		await frames(90)
		check(not is_instance_valid(m), "%s primitive frees on death" % kind)
	Monster.use_proto_visuals = false
	var back := MonsterFactory.spawn("grunt", Vector2i(3, 1))
	check(back.model != null, "clearing the flag brings the models back")
	back.free()


# ---------------------------------------------------------------- pits

func _pit() -> void:
	for kind in MonsterFactory.KINDS:
		var map := HexMap.new()
		for c in Hex.range_cells(Vector2i.ZERO, 9):
			if Hex.to_world(c).x < 2.0:
				map.set_cell(c, 0)
		new_world(map)
		var m := MonsterFactory.spawn(kind, Vector2i.ZERO)
		m.shove_mult = 1.0
		var died := [false]
		m.died.connect(func() -> void: died[0] = true)
		var mod: MonsterModel = m.model
		m.shove(Vector3.RIGHT, 6.0)
		var fell := 0
		var scale_ok := true
		for i in 160:
			await get_tree().physics_frame
			if not is_instance_valid(m):
				break
			if m.is_airborne():
				fell += 1
				# The pit fall spins / shrinks the ACTOR; the model keeps its own scale until the death fade.
				if not m.dead and absf(mod.scale.x - float(SIZES[kind])) > 0.0001:
					scale_ok = false
			if died[0] and not is_instance_valid(m):
				break
		check(died[0], "%s shoved into a pit dies" % kind)
		check(fell >= 20, "%s visibly falls first (%d frames)" % [kind, fell])
		check(scale_ok, "%s model scale untouched during the fall" % kind)
		await frames(90)
		check(not is_instance_valid(m), "%s with a model frees after the pit" % kind)


# ---------------------------------------------------------------- brawl

func _brawl() -> void:
	new_world(flat_map(10))
	var hero := add_hero(Vector2i(0, 0))
	hero.max_hp = 1.0e9
	hero.hp = hero.max_hp
	var cells := Hex.ring(Vector2i.ZERO, 3)
	cells.append_array(Hex.ring(Vector2i.ZERO, 4))
	var pack: Array[Monster] = []
	for i in 10:
		pack.append(MonsterFactory.spawn(MonsterFactory.KINDS[i % 4], cells[i]))
	var models := 0
	for m in pack:
		if m.model != null:
			models += 1
	eq(models, 10, "all ten monsters wear models")
	for f in 600:
		await get_tree().physics_frame
		if f == 200:
			pack[0].shove(Vector3.RIGHT, 2.0)        # a shove mid-fight
			pack[1].apply_damage(5.0, hero)          # a hit flash
		if f == 400:
			pack[2].apply_damage(9999.0, hero)       # a death
			pack[6].apply_damage(9999.0, hero)
	check(hero.hp < hero.max_hp, "the pack actually fought the hero")
	var alive := 0
	for m in pack:
		if is_instance_valid(m) and not m.dead:
			alive += 1
			check(m.model != null and not m.model.is_downed(), "a living %s is not downed" % m.kind)
	print("  brawl: hero lost %.0f hp, %d of 10 monsters alive" % [hero.max_hp - hero.hp, alive])
	check(alive >= 7, "the rest of the pack is alive (%d)" % alive)
	check(not is_instance_valid(pack[2]) or pack[2].dead, "the killed monster is dead")


# ---------------------------------------------------------------- performance

## 40 awake monsters (10 of each kind) with models: logic frame time and the triangle total.
func _perf() -> void:
	for proto in [false, true]:
		Monster.use_proto_visuals = proto
		new_world(flat_map(14))
		var hero := add_hero(Vector2i(0, 0))
		hero.max_hp = 1.0e9
		hero.hp = hero.max_hp
		var cells := Hex.ring(Vector2i.ZERO, 3)
		cells.append_array(Hex.ring(Vector2i.ZERO, 4))
		var crowd: Array[Monster] = []
		for i in 40:
			crowd.append(MonsterFactory.spawn(MonsterFactory.KINDS[i % 4], cells[i]))
		await frames(60)
		var tris := 0
		for m in crowd:
			if m.model != null:
				tris += m.model.triangle_count()
		var t0 := Time.get_ticks_usec()
		await frames(240)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 240.0
		if proto:
			print("  40 monsters, primitive bodies: %.2f ms per frame" % ms)
		else:
			print("  40 monsters, faceted models: %.2f ms per frame, %d model triangles (x2 with the outline pass)" % [ms, tris])
			check(tris > 0, "models counted")
			check(tris < 80000, "40 models stay under 80k triangles (%d)" % tris)
			check(ms < 16.0, "40 modelled monsters fit a 60fps frame (%.2f ms)" % ms)
	Monster.use_proto_visuals = false
