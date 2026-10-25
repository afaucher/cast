extends TestCase
## Chicken (decided by the user 2026-10-18): "chickens run around and do zero damage attacks to everything, distracting
## them". One cast makes four chickens that scatter from the aim point and live 12 s. They peck everyone for ZERO: a pecked
## monster turns on its chicken (and kills it), anything else just gets a "0". One or two hits from anything kill a
## chicken. The spell has a component (Chicken feather), drops from imps, and "chicken" is a castable word.
## CLUCKS (the user's takes, 2026-10-25; Chicken.cluck): one per chicken as the flock lands (staggered), one on every peck (a
## puppet's too), now and then by itself, none while it poofs, and the "chicken_cluck" pool's voices cap a pecking flock.

var root: Node3D


func _init() -> void:
	timeout_sec = 120.0


func _flat_map(radius: int = 14) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		m.set_cell(c, 0)
	return m


func _fresh() -> void:
	if root != null:
		root.free()
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(_flat_map(), root, 11)
	Ledger.begin_contract(1000000)


func _hero(pos: Vector3) -> Hero:
	var h := Hero.new()
	GameWorld.spawn(h, pos)
	h.snap_to_ground()
	return h


## One chicken at `pos`, as the flock makes them but without the burst out of the cloud.
func _chicken(pos: Vector3) -> Chicken:
	var c := Chicken.new()
	c.home = pos
	c.born = GameWorld.time
	GameWorld.spawn(c, pos)
	c.snap_to_ground()
	return c


func _chickens() -> Array[Chicken]:
	var out: Array[Chicken] = []
	for n in get_tree().get_nodes_in_group(Chicken.GROUP):
		var c := n as Chicken
		if c != null and not c.dead and not c.is_queued_for_deletion():
			out.append(c)
	return out


func setup() -> void:
	_numbers()
	await _flock_scatters_and_times_out()
	await _pecks_do_nothing()
	await _pecked_monster_turns_and_kills()
	await _fragile()
	await _component_and_charges()
	await _clucks()
	_word()
	if root != null:
		root.free()
	finish()


# --- The spell's data ----------------------------------------------------------------------------

func _numbers() -> void:
	check(SpellBook.SPELLS.has("chicken") and SpellBook.is_available("chicken"), "chicken exists and is castable")
	check(SpellBook.ids().has("chicken"), "the license requisition offers it (SpellPicker lists SpellBook.ids())")
	eq(SpellBook.spell_name("chicken"), "Chicken")
	eq(SpellBook.incantation("chicken"), "CAST CHICKEN")
	eq(SpellBook.word_of("chicken"), "chicken")
	eq(SpellBook.component_name("chicken"), "Chicken feather")
	near(SpellBook.cooldown_of("chicken"), 14.0, 0.001, "cooldown 14 s")
	eq(Chicken.FLOCK, 4, "four chickens a cast")
	near(Chicken.LIFETIME, 12.0, 0.001, "each lasts 12 s")
	check(Chicken.HIT_FLOOR * 2.0 >= Chicken.MAX_HP, "two hits of anything kill one")
	var c := Chicken.new()
	var f: Dictionary = c.net_fields()
	eq(f["state"], Net.OWNER, "its state rides the stream")
	eq(f["pecks"], Net.OWNER, "its peck count rides the stream")
	eq(f["_target"], Net.PRIVATE, "its AI is the host's")
	eq(f["model"], Net.LOCAL, "its look is every screen's own")
	eq(f["clucks"], Net.LOCAL, "its clucks are every screen's own")
	eq(f["_cluck_t"], Net.LOCAL, "... and so is their clock")
	eq(c.team, GameWorld.TEAM_NEUTRAL, "neutral: not a side in the fight")
	c.free()


# --- 4 spawn and scatter; they time out at 12 s ------------------------------------------------------

func _flock_scatters_and_times_out() -> void:
	_fresh()
	var caster := _hero(Vector3(-9, 0, 0))   # far from the flock (within the spell's reach): nothing near to peck
	var at := Vector3(2.0, 0.0, 1.0)
	check(SpellBook.cast("chicken", caster, 1.0, at), "chicken casts")
	var flock := _chickens()
	eq(flock.size(), Chicken.FLOCK, "four chickens")
	for c in flock:
		check(GameWorld.flat_distance(c.global_position, at) < 0.6, "each starts at the aim point (%.2f)" % GameWorld.flat_distance(c.global_position, at))
	await frames(int(Chicken.SCATTER_TIME * 60.0) + 2)
	flock = _chickens()
	eq(flock.size(), Chicken.FLOCK, "all four are running about")
	var dirs: Array[Vector3] = []
	for c in flock:
		var d := c.global_position - at
		d.y = 0.0
		check(d.length() > 1.2, "a chicken burst out of the cloud (%.2f from the aim point)" % d.length())
		dirs.append(d.normalized())
	var spread := true
	for i in dirs.size():
		for j in range(i + 1, dirs.size()):
			spread = spread and dirs[i].dot(dirs[j]) < 0.8
	check(spread, "they scatter, each its own way")
	# They run about erratically, but stay around where they were cast.
	var moved := 0
	var before: Array[Vector3] = []
	for c in flock:
		before.append(c.global_position)
	await frames(120)
	for i in flock.size():
		if is_instance_valid(flock[i]) and flock[i].global_position.distance_to(before[i]) > 0.3:
			moved += 1
	check(moved >= 3, "they keep running about (%d of 4 moved in 2 s)" % moved)
	for c in _chickens():
		check(GameWorld.flat_distance(c.global_position, at) < Chicken.LEASH + 2.5, "and stay near the cast (%.1f)" % GameWorld.flat_distance(c.global_position, at))
	# 12 s: alive at 11.5, puffing up just after 12, gone soon after.
	await frames(int((11.5 - Chicken.SCATTER_TIME) * 60.0) - 122)
	eq(_chickens().size(), Chicken.FLOCK, "all four still there at 11.5 s")
	await frames(int(0.6 * 60.0))
	var puffing := 0
	for c in _chickens():
		if c.state == Chicken.State.POOF:
			puffing += 1
	eq(puffing, Chicken.FLOCK, "at 12 s they puff up")
	await frames(int((Chicken.POOF_TIME + 0.2) * 60.0))
	eq(_chickens().size(), 0, "and poof into feathers")
	check(_particles() > 0, "feathers")
	near(caster.hp, caster.max_hp, 0.001, "nobody was hurt")


func _particles() -> int:
	var n := 0
	for ch in root.get_children():
		if ch is CPUParticles3D:
			n += 1
	return n


# --- Pecks do 0 to monsters, heroes, employees and props ------------------------------------------------

func _pecks_do_nothing() -> void:
	_fresh()
	var hero := _hero(Vector3(-9, 0, -7))
	var worker := Employee.spawn(Hex.from_world(Vector3(9, 0, -7)), {"style": "staff"})
	var prop := PricedProp.spawn(Hex.from_world(Vector3(-9, 0, 7)), "wine_rack", {"pos": Vector2(-9, 7)})
	var mail := MailPackage.spawn(Vector2(9, 7), {"size": "medium", "seed": 3})
	var mon := MonsterFactory.spawn("grunt", Hex.from_world(Vector3(0, 0, 0)))
	mon.aggro_range = 0.0   # frozen: it only reacts to what is done to it
	await frames(2)
	var targets: Array[Actor] = [hero, worker, prop, mail, mon]
	var hp_before: Array[float] = []
	for t in targets:
		hp_before.append(t.hp)
	var lines := Ledger.lines.size()
	# The verb straight: a hit for nothing.
	var pecker := _chicken(Vector3(0, 0, 13))
	for t in targets:
		check(Combat.peck(pecker, t), "the peck lands on %s (this machine resolves it)" % t.display_name)
	for i in targets.size():
		near(targets[i].hp, hp_before[i], 0.0001, "a peck does 0 to %s" % targets[i].display_name)
	check(mon.target == pecker and mon.is_taunted(), "the pecked monster turns on the chicken")
	pecker.die()
	await frames(2)
	# And the real thing: a chicken next to each, pecking away for three seconds.
	var birds: Array[Chicken] = []
	for t in [hero, worker, prop, mail]:
		var a: Actor = t
		birds.append(_chicken(a.global_position + Vector3(a.radius + 0.6, 0, 0.4)))
	await frames(180)
	for i in birds.size():
		var b := birds[i]
		check(is_instance_valid(b) and b.pecks >= 2, "chicken %d pecked its neighbour (%d pecks)" % [i, b.pecks if is_instance_valid(b) else -1])
	for i in 4:
		near(targets[i].hp, hp_before[i], 0.0001, "%s took nothing from the pecks" % targets[i].display_name)
	eq(Ledger.lines.size(), lines, "no Ledger line: no damage, no bill")
	check(not prop.broke and not prop.dead, "the client's property is not broken")
	check(not mail.broke and not mail.dead, "nor is the mail")
	check(worker.state != Employee.State.PANIC, "the employee does not panic over a chicken (%s)" % worker.state_name())
	check(not hero.is_helpless(), "no stagger, no shove on the hero")


# --- A pecked monster retargets its chicken and kills it ------------------------------------------------------

func _pecked_monster_turns_and_kills() -> void:
	_fresh()
	var hero := _hero(Vector3(0, 0, 0))
	hero.max_hp = 100000.0
	hero.hp = hero.max_hp
	var grunt := MonsterFactory.spawn("grunt", Hex.from_world(Vector3(3, 0, 0)))
	await frames(2)
	grunt.aggro(hero)
	await frames(30)
	check(grunt.target == hero and grunt.is_aggro(), "the grunt is after the hero")
	var c := _chicken(Vector3(4.5, 0, 2.5))
	var turned := -1.0
	var t0 := GameWorld.time
	for i in 180:
		await frames(1)
		if grunt.target == c:
			turned = GameWorld.time - t0
			break
	check(turned >= 0.0, "the pecked grunt drops the hero for the chicken (after %.2f s)" % turned)
	check(grunt.is_taunted(), "it is taunted")
	# It keeps after the chicken, not the hero, and kills it within a few seconds.
	var killed := -1.0
	var stayed := true
	for i in 6 * 60:
		await frames(1)
		if not is_instance_valid(c) or c.dead:
			killed = GameWorld.time - t0
			break
		stayed = stayed and grunt.target == c
	print("[chicken] the grunt turned on its chicken %.2f s after it came, and killed it at %.2f s" % [turned, killed])
	check(killed > 0.0 and killed < 7.0, "the grunt kills its chicken within a few seconds (%.2f s)" % killed)
	check(stayed, "and chased it, not the hero, until then")
	check(killed < Chicken.LIFETIME, "killed, not timed out")
	await frames(90)
	check(grunt.target == hero and not grunt.is_taunted(), "with the chicken dead it goes back for the hero")
	# A brute's slam is for heroes only: its blow lands on its chicken all the same.
	_fresh()
	var brute := MonsterFactory.spawn("brute", Hex.from_world(Vector3(0, 0, 0)))
	brute.aggro_range = 0.0
	await frames(2)
	var sitting := _chicken(brute.global_position + Vector3(1.4, 0, 0))
	sitting.set_physics_process(false)   # a chicken that stays put
	Combat.peck(sitting, brute)
	await frames(int((brute.attack_windup + 0.6) * 60.0))
	check(not is_instance_valid(sitting) or sitting.dead, "the brute's blow kills the chicken it chased")


# --- One or two hits from anything ------------------------------------------------------------------------

func _fragile() -> void:
	_fresh()
	var c := _chicken(Vector3(5, 0, 5))
	c.set_physics_process(false)
	c.apply_damage(1.0, null)
	check(not c.dead, "a scratch: still alive")
	near(c.hp, Chicken.MAX_HP - Chicken.HIT_FLOOR, 0.001, "but even a scratch takes half")
	c.apply_damage(1.0, null)
	check(c.dead, "two hits of anything kill it")
	var c2 := _chicken(Vector3(-5, 0, 5))
	c2.apply_damage(30.0, null)
	check(c2.dead, "one big hit kills it")
	await frames(2)
	check(_particles() > 0, "in a feather explosion")
	# A hero's swing: the crew's melee hits chickens (Chicken.WEAPONS_HIT).
	var hero := _hero(Vector3(0, 0, -6))
	var c3 := _chicken(Vector3(1.0, 0, -6))
	c3.set_physics_process(false)
	for i in 2:
		if not c3.dead:
			Combat.melee_arc(hero, Vector3.RIGHT, 1.6, 120.0, hero.melee_damage, 0.0)
	check(c3.dead, "two hero swings at most kill a chicken")
	# A monster's swing at a hero catches a chicken in its arc.
	var grunt := MonsterFactory.spawn("grunt", Hex.from_world(Vector3(-6, 0, -6)))
	grunt.aggro_range = 0.0
	await frames(2)
	var c4 := _chicken(grunt.global_position + Vector3(1.0, 0, 0))
	c4.set_physics_process(false)
	for i in 2:
		if not c4.dead:
			Combat.melee_arc(grunt, Vector3.RIGHT, grunt.attack_reach, 120.0, grunt.attack_damage)
	check(c4.dead, "a monster's swing kills it in two")
	# Spells: a fireball blast and a corn cob.
	var c5 := _chicken(Vector3(6, 0, -3))
	c5.set_physics_process(false)
	SpellBook.cast("fireball", hero, 1.0, c5.global_position)
	await frames(90)
	check(not is_instance_valid(c5) or c5.dead, "a fireball kills it")
	var c6 := _chicken(Vector3(-6, 0, 4))
	c6.set_physics_process(false)
	SpellBook.cast("corn", hero, 1.0, c6.global_position)
	await frames(int((CornStrike.DELAY + 0.5) * 60.0))
	check(not is_instance_valid(c6) or c6.dead, "a corn cob kills it")
	# A bolt in the path.
	var c7 := _chicken(Vector3(0, 0, 3))
	c7.set_physics_process(false)
	for i in 2:
		if is_instance_valid(c7) and not c7.dead:
			Fx.make_projectile(hero, Combat.chest(hero), Vector3(0, 0, 1), 5.0, 14.0, 12.0, Color.WHITE, 0.1)
			await frames(70)
	check(not is_instance_valid(c7) or c7.dead, "two bolts kill it")


# --- The component and its charges ---------------------------------------------------------------------------

func _component_and_charges() -> void:
	_fresh()
	var prop := ComponentProps.make("chicken")
	check(prop.get_child_count() >= 1 and (prop.get_child(0) as MeshInstance3D).mesh != null, "the feather prop has a mesh")
	prop.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := 4000
	var got := 0
	for i in n:
		if SpellComponents.roll_drops("swarmer", rng).has("chicken"):
			got += 1
	near(float(got) / n, 0.04, 0.015, "imps drop a chicken feather 4% of the time each")
	eq(SpellComponents.drop_charges("swarmer", "chicken"), SpellComponents.PICKUP_CHARGES, "a feather is worth the usual charges")
	var h := _hero(Vector3(-8, 0, -8))
	h.is_player = true
	h.spell_slots = ["chicken", "heal"] as Array[String]
	var before := h.charges_of("chicken")
	eq(before, SpellComponents.START_CHARGES, "a licensed spell starts with its charges")
	check(h.try_cast("chicken", 1.0, Vector3(-6, 0, -8)), "cast through the slots")
	eq(h.charges_of("chicken"), before - 1, "one feather spent")
	eq(_chickens().size(), Chicken.FLOCK, "and the flock is out")
	var p := ComponentPickup.drop("chicken", 3, h.global_position + Vector3(0.3, 0, 0))
	check(p != null, "a feather on the floor")
	await frames(30)
	eq(h.charges_of("chicken"), before - 1 + 3, "walking over it picks up three charges")


# --- Clucks ---------------------------------------------------------------------------------------------------

## A short tone (a cluck stand-in: the test needs no rendered audio).
func _tone(seconds: float, hz: float) -> AudioStreamWAV:
	var n := int(seconds * 22050.0)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(2000.0 * sin(TAU * hz * float(i) / 22050.0)))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	w.data = bytes
	return w


func _cluck_voices() -> int:
	var n := 0
	for p: Node in Sfx._voice:
		if Sfx._voice[p][0] == Chicken.CLUCK_CUE and p.get("playing"):
			n += 1
	return n


func _clucks() -> void:
	_fresh()
	Sfx.enable_for_tests()
	var pool: Array = []
	for i in Sfx.files_of(Chicken.CLUCK_CUE).size():
		pool.append(_tone(0.35, 300.0 + 80.0 * i))
	Sfx.override_streams(Chicken.CLUCK_CUE, pool)
	var cue: Dictionary = Sfx.CUES[Chicken.CLUCK_CUE]
	eq(Sfx.files_of(Chicken.CLUCK_CUE).size(), 5, "the cluck is a pool of the user's five takes")
	check(int(cue["max_voices"]) <= 2 and float(cue["min_gap"]) >= 0.15, "the cue caps a flock: %d voices, %.2f s apart" % [int(cue["max_voices"]), float(cue["min_gap"])])
	# Landing: one cluck per chicken, staggered.
	var caster := _hero(Vector3(-9, 0, 0))
	check(SpellBook.cast("chicken", caster, 1.0, Vector3(3, 0, 2)), "chicken casts")
	var flock := _chickens()
	var landed := {}
	for f in int((Chicken.CLUCK_LAND.y + 0.1) * 60.0):
		await frames(1)
		for c in flock:
			if is_instance_valid(c) and c.clucks > 0 and not landed.has(c):
				landed[c] = f
	eq(landed.size(), Chicken.FLOCK, "every chicken clucks as the flock lands")
	var firsts := {}
	for c in landed:
		firsts[landed[c]] = true
	check(firsts.size() >= 2, "... staggered, not all at once (%s)" % str(landed.values()))
	for c in flock:
		eq(c.clucks, 1, "... once each")
	check(int(Sfx.played.get(Chicken.CLUCK_CUE, 0)) >= 1, "the landing clucks play (%d)" % int(Sfx.played.get(Chicken.CLUCK_CUE, 0)))
	for c in flock:
		c.die()
	await frames(2)
	# Idle: a lone chicken with nothing to peck clucks every CLUCK_IDLE_MIN..MAX s.
	var lone := _chicken(Vector3(6, 0, 6))
	await frames(int(8.0 * 60.0))
	var idle := lone.clucks - 1
	print("  idle clucks in 8 s: %d" % idle)
	check(idle >= 1 and idle <= int(8.0 / Chicken.CLUCK_IDLE_MIN), "now and then by itself (%d idle clucks in 8 s)" % idle)
	lone.die()
	# Pecks: four chickens round a frozen grunt, pecking for 4 s: a cluck on every peck, and never more voices than the cap.
	var grunt := MonsterFactory.spawn("grunt", Hex.from_world(Vector3(-4, 0, -4)))
	grunt.aggro_range = 0.0
	grunt.max_hp = 100000.0
	grunt.hp = grunt.max_hp
	grunt.set_physics_process(false)   # (it stands: the chickens keep pecking)
	await frames(2)
	var birds: Array[Chicken] = []
	for a in 4:
		birds.append(_chicken(grunt.global_position + Vector3(cos(a * PI * 0.5), 0, sin(a * PI * 0.5)) * (grunt.radius + 0.6)))
	await frames(30)   # (past their landing clucks)
	var before := []
	for b in birds:
		before.append([b.clucks, b.pecks])
	var played0 := int(Sfx.played.get(Chicken.CLUCK_CUE, 0))
	var t0 := Time.get_ticks_msec()
	var most := 0
	for f in 240:
		OS.delay_msec(16)   # (Sfx's gap is wall-clock and --fixed-fps runs faster than real time: pace it like the game)
		await frames(1)
		most = maxi(most, _cluck_voices())
	var real_s := (Time.get_ticks_msec() - t0) / 1000.0
	var pecks := 0
	var clucks := 0
	for i in birds.size():
		if not is_instance_valid(birds[i]):
			continue
		var dp: int = birds[i].pecks - int(before[i][1])
		var dc: int = birds[i].clucks - int(before[i][0])
		pecks += dp
		clucks += dc
		check(dc >= dp, "chicken %d clucks on each peck (%d pecks, %d clucks)" % [i, dp, dc])
	var played := int(Sfx.played.get(Chicken.CLUCK_CUE, 0)) - played0
	print("  a flock pecking for 4 s: %d pecks, %d clucks asked, %d played (%.1f s real), at most %d at once" % [pecks, clucks, played, real_s, most])
	check(pecks >= 8, "the flock pecks away (%d pecks)" % pecks)
	check(most <= int(cue["max_voices"]), "never more than %d clucks at once (%d)" % [int(cue["max_voices"]), most])
	check(played >= 1, "the pecking flock is heard (%d clucks played)" % played)
	check(played < clucks or clucks <= int(real_s / float(cue["min_gap"])), "the cue drops some of a pecking flock's clucks (%d of %d)" % [played, clucks])
	check(played <= int(real_s / float(cue["min_gap"])) + 1, "the gap caps the rate (%d played in %.1f s)" % [played, real_s])
	# A puppet clucks when its peck count moves (as it plays the peck), not on its first sample.
	var shown := Chicken.make_shown(Vector3(6, 0, -6))
	shown.set_physics_process(false)
	await frames(1)
	var c0 := shown.clucks
	shown.net_show(Vector3.FORWARD, false, shown.hp, Chicken.State.WANDER, 0.0, 5)
	eq(shown.clucks, c0, "a puppet's first sample is not a peck: no cluck")
	shown.net_show(Vector3.FORWARD, false, shown.hp, Chicken.State.PECK, 0.0, 6)
	eq(shown.clucks, c0 + 1, "a puppet's peck clucks")
	# Poofing: no clucks.
	shown.net_show(Vector3.FORWARD, false, shown.hp, Chicken.State.POOF, 0.0, 6)
	var c1 := shown.clucks
	shown.cluck()
	for f in int((Chicken.CLUCK_IDLE_MAX + 0.5) * 60.0):
		shown.net_tick(1.0 / 60.0)
	eq(shown.clucks, c1, "a poofing chicken never clucks")
	shown.die()
	for b in birds:
		if is_instance_valid(b):
			b.die()
	await frames(2)
	Sfx.disable_for_tests()


# --- The word ------------------------------------------------------------------------------------------------

func _word() -> void:
	check(VoiceCaster.default_spells().has("chicken"), "the recognizer listens for it")
	var inc := Incantation.new(VoiceCaster.default_spells())
	check(inc.vocabulary().has("chicken"), "it is in the hotword vocabulary")
	for text in ["cast chicken", "CAST CHICKENS", "okay cast chicken"]:
		var ev := inc.feed(text, true, 10.0 + float(text.length()))
		var casts := ev.filter(func(e: Dictionary) -> bool: return e["kind"] == "cast")
		eq(casts.size(), 1, "\"%s\" casts" % text)
		if casts.size() == 1:
			eq(casts[0]["spell"], "chicken", text)
			check(float(casts[0]["power"]) >= 0.9, "%s at full power (%.2f)" % [text, float(casts[0]["power"])])
		inc.reset()
	var bare := inc.feed("chicken", true, 50.0)
	eq(bare.filter(func(e: Dictionary) -> bool: return e["kind"] == "cast").size(), 0, "a bare \"chicken\" does not cast (loose)")
	check(not VoiceSettings.validate_trigger("chicken")["ok"], "chicken cannot be the trigger word")
	eq(SpellBook.find_in_text("Cast chicken!"), "chicken", "text lookup")
