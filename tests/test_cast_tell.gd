extends TestCase
## The cast tell (CastTell, docs/design/cast-armed-fx.md, option C on your own hero), driven headless by a stand-in caster
## that emits VoiceCaster's signals, in both A/B modes:
##   - the trigger arms it: the rune draws in under the hero and follows the feet, the hand glows;
##   - the spell word + the cast: the RELEASE, then nothing drawn; online it waits NetCasts.LEAD for the landing;
##     colour mode floods the rune with the spell's colour on recognition (linear in the shader), neutral keeps it white
##     and only the release flash is coloured;
##   - a refused cast (the spell word with no cast) cracks; a fizzle cracks; a dropped trigger fades without cracking; an
##     armed tell nobody ends fades after SAFETY;
##   - off: nothing is built or drawn;
##   - the real pipeline: a VoiceCaster's typed "cast fireball" arms and releases it through Hero.try_cast, and Incantation
##     says trigger_dropped for a "cast" buried in chatter (and not for a fizzle).

const DT := 1.0 / 60.0

class FakeCaster extends Node:
	signal trigger_heard(word: String)
	signal spell_spoken(spell_id: String, power: float, heard: String)
	signal spell_fizzled(heard: String, reason: String)
	signal trigger_dropped(word: String)
	signal ignored(spell_id: String, heard: String, reason: String)


var world: Node3D
var hero: Hero
var caster: FakeCaster
var tell: CastTell
var _mode_was := CastTell.COLOUR


func setup() -> void:
	timeout_sec = 60.0
	_mode_was = CastTell.mode
	var map := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 6):
		map.set_cell(c, 0)
	world = Node3D.new()
	add_child(world)
	GameWorld.begin(map, world, 7)
	hero = HeroFactory.spawn_hero(Vector2i.ZERO, "Tester", Color.BLUE, "sword", WickModel.new(), "wick")
	hero.spell_slots = ["fireball", "heal"]
	hero.set_charges("fireball", 3)
	hero.set_charges("heal", 3)
	caster = FakeCaster.new()
	add_child(caster)
	tell = CastTell.attach(world, hero, caster, func() -> Vector3: return hero.global_position + Vector3(0, 0, 4))
	tell.set_process(false)   # (the test steps it)
	for m in [CastTell.COLOUR, CastTell.NEUTRAL_MODE]:
		CastTell.mode = m
		await _check_release(m)
		await _check_online(m)
		await _check_refused(m)
		_check_fizzle_and_drop()
	_check_modes()
	await _check_off()
	await _check_pipeline()
	_check_incantation_drop()
	CastTell.mode = _mode_was
	finish()


func _run(seconds: float) -> void:
	for _i in int(roundf(seconds / DT)):
		tell.step(DT)


func _col() -> Vector3:
	return tell.rune.material_override.get_shader_parameter(&"col")


func _param(nm: StringName) -> float:
	return float(tell.rune.material_override.get_shader_parameter(nm))


func _close(a: Vector3, b: Vector3) -> bool:
	return a.distance_to(b) < 0.01


func _check_release(m: String) -> void:
	caster.trigger_heard.emit("CAST")
	eq(tell.phase, CastTell.Phase.ARMED, "%s: the trigger arms it" % m)
	_run(0.05)
	check(tell.rune.visible and tell.glow.visible, "%s: the rune and the hand glow are drawn" % m)
	check(_param(&"draw") < 1.0, "%s: the rune is still drawing in" % m)
	_run(0.3)
	near(_param(&"draw"), 1.0, 0.001, "%s: drawn in after DRAW_TIME" % m)
	check(_close(_col(), CastTell._lin(CastTell.NEUTRAL)), "%s: chalk white while armed" % m)
	check(_param(&"chalk") > 0.5, "%s: dashed chalk while armed" % m)
	# the hero walks: the rune trails, then catches up
	hero.global_position += Vector3(2, 0, 0)
	tell.step(DT)
	var lag := tell.rune.global_position - hero.global_position
	lag.y = 0.0
	check(lag.length() > 0.5, "%s: the rune trails a step behind a sudden move (%.2f)" % [m, lag.length()])
	_run(0.5)
	lag = tell.rune.global_position - hero.global_position
	lag.y = 0.0
	check(lag.length() < 0.05, "%s: and catches up (%.3f)" % [m, lag.length()])
	# the spell word, then the cast in the same frame (solo): released at once
	hero.set("_ready_at", {})   # (no cooldown between the two modes' casts)
	caster.spell_spoken.emit("fireball", 1.0, "cast fireball")
	check(hero.try_cast("fireball", 1.0, hero.global_position + Vector3(0, 0, 4)), "the fireball goes off")
	eq(tell.phase, CastTell.Phase.RELEASE, "%s: the cast releases it" % m)
	tell.step(DT)
	var want := CastTell._lin(SpellBook.color_of("fireball")) if m == CastTell.COLOUR else CastTell._lin(CastTell.NEUTRAL)
	check(_close(_col(), want), "%s: the releasing rune is %s %s" % [m, "the spell's colour" if m == CastTell.COLOUR else "still white", str(_col())])
	var glow_col: Vector3 = tell.glow.material_override.get_shader_parameter(&"col")
	check(_close(glow_col, CastTell._lin(SpellBook.color_of("fireball"))), "%s: the hand flashes in the spell's colour" % m)
	_run(CastTell.RELEASE_TIME + 0.05)
	eq(tell.phase, CastTell.Phase.IDLE, "%s: idle after the release" % m)
	check(not tell.is_drawn(), "%s: nothing drawn after the release" % m)
	await frames(1)   # (the deferred refusal check finds nothing to refuse)
	eq(tell.phase, CastTell.Phase.IDLE, "%s: a cast is not a refusal" % m)
	hero.set_charges("fireball", 3)


func _check_online(m: String) -> void:
	caster.trigger_heard.emit("CAST")
	_run(0.3)
	tell.recognise("heal")
	tell.cast_went_off("heal", true)
	await frames(1)
	eq(tell.phase, CastTell.Phase.ARMED, "%s, online: waits for the landing" % m)
	_run(CastTell.FLOOD_TIME + 0.02)
	var want := CastTell._lin(SpellBook.color_of("heal")) if m == CastTell.COLOUR else CastTell._lin(CastTell.NEUTRAL)
	check(_close(_col(), want), "%s, online: recognised, the rune is %s" % [m, "heal's colour" if m == CastTell.COLOUR else "still white"])
	if m == CastTell.COLOUR:
		near(_param(&"chalk"), 0.0, 0.001, "colour: the recognised rune is solid")
	else:
		check(_param(&"chalk") > 0.5, "neutral: still chalk after recognition")
	_run(NetCasts.LEAD)
	eq(tell.phase, CastTell.Phase.RELEASE, "%s, online: released when the cast lands (LEAD)" % m)
	_run(CastTell.RELEASE_TIME + 0.05)
	check(not tell.is_drawn(), "%s, online: gone after" % m)


func _check_refused(m: String) -> void:
	caster.trigger_heard.emit("CAST")
	_run(0.3)
	caster.spell_spoken.emit("teeth", 1.0, "cast teeth")   # (not slotted: the game refuses it, no Hero.spell_cast)
	await frames(1)
	eq(tell.phase, CastTell.Phase.CANCEL, "%s: a refused cast cracks" % m)
	check(tell.refused, "%s: marked refused" % m)
	tell.step(DT)
	var want := CastTell._lin(SpellBook.color_of("teeth")) if m == CastTell.COLOUR else CastTell._lin(CastTell.NEUTRAL)
	check(_close(_col(), want), "%s: the refused rune is %s" % [m, "teeth's colour" if m == CastTell.COLOUR else "white"])
	_run(0.2)
	check(_param(&"crack") > 0.3, "%s: cracking" % m)
	_run(CastTell.CANCEL_TIME)
	check(not tell.is_drawn(), "%s: gone after the crack" % m)
	# a repeat the recognizer ignored is a refusal too
	caster.trigger_heard.emit("CAST")
	_run(0.3)
	caster.ignored.emit("fireball", "cast fireball", "repeat")
	eq(tell.phase, CastTell.Phase.CANCEL, "%s: an ignored repeat cracks" % m)
	_run(CastTell.CANCEL_TIME + 0.05)


func _check_fizzle_and_drop() -> void:
	var m := CastTell.mode
	caster.trigger_heard.emit("CAST")
	_run(1.2)
	check(_param(&"remain") < 1.0, "%s: the countdown ring recedes after %.1f s armed" % [m, CastTell.COUNTDOWN_FROM])
	caster.spell_fizzled.emit("cast", "no_spell")
	eq(tell.phase, CastTell.Phase.CANCEL, "%s: a fizzle cancels" % m)
	_run(0.25)
	check(_param(&"crack") > 0.4, "%s: a fizzle cracks" % m)
	_run(CastTell.CANCEL_TIME)
	check(not tell.is_drawn(), "%s: gone after the fizzle" % m)
	caster.trigger_heard.emit("CAST")
	_run(0.4)
	caster.trigger_dropped.emit("CAST")
	_run(0.1)
	eq(tell.phase, CastTell.Phase.CANCEL, "%s: a dropped trigger fades" % m)
	near(_param(&"crack"), 0.0, 0.001, "%s: a quiet fade does not crack" % m)
	check(_param(&"alpha") < 0.9, "%s: fading" % m)
	_run(CastTell.QUIET_TIME)
	check(not tell.is_drawn(), "%s: gone after the fade" % m)
	caster.trigger_heard.emit("CAST")
	_run(CastTell.SAFETY + CastTell.QUIET_TIME + 0.1)
	check(not tell.is_drawn(), "%s: an armed tell nobody ends fades after SAFETY" % m)


func _check_modes() -> void:
	check(CastTell.set_mode("color") and CastTell.mode == CastTell.COLOUR, "\"color\" is accepted")
	check(not CastTell.set_mode("purple"), "an unknown mode is refused")
	eq(CastTell.cycle(), CastTell.NEUTRAL_MODE, "F11 cycles colour -> neutral")
	eq(CastTell.cycle(), CastTell.OFF, "-> off")
	eq(CastTell.cycle(), CastTell.COLOUR, "-> colour")
	check(CastTell.label().contains("colour"), "the dev tag names the mode")


func _check_off() -> void:
	CastTell.mode = CastTell.OFF
	var t2 := CastTell.attach(world, hero, caster)
	t2.set_process(false)
	caster.trigger_heard.emit("CAST")
	eq(t2.phase, CastTell.Phase.IDLE, "off: the trigger arms nothing")
	check(t2.rune == null and t2.glow == null and t2.get_child_count() == 0, "off: nothing is built")
	check(not t2.is_drawn(), "off: nothing drawn")
	# switching to off mid-arm hides the main tell
	CastTell.mode = CastTell.COLOUR
	caster.trigger_heard.emit("CAST")
	tell.step(DT)
	check(tell.is_drawn(), "colour: drawn")
	CastTell.mode = CastTell.OFF
	tell._process(DT)
	check(not tell.is_drawn(), "switching to off mid-arm hides it")
	t2.queue_free()
	CastTell.mode = CastTell.COLOUR
	await frames(1)


## The real pipeline: a VoiceCaster's typed line arms the tell and the game's way of casting releases it.
func _check_pipeline() -> void:
	var vc := VoiceCaster.new()
	vc.use_mic = false
	vc.use_saved_settings = false
	vc.persist_settings = false
	vc.voice_log.enabled = false
	add_child(vc)
	var t3 := CastTell.attach(world, hero, vc)
	t3.set_process(false)
	var armed := [false]
	vc.trigger_heard.connect(func(_w: String) -> void: armed[0] = t3.phase == CastTell.Phase.ARMED)
	vc.spell_spoken.connect(func(id: String, p: float, _h: String) -> void: hero.try_cast(id, p, hero.global_position + Vector3(0, 0, 4)))
	hero.set_charges("heal", 3)
	hero.set("_ready_at", {})
	vc.inject_text("cast heal")
	check(armed[0], "a typed \"cast heal\" arms the tell (VoiceCaster.trigger_heard)")
	eq(t3.phase, CastTell.Phase.RELEASE, "and the cast releases it")
	eq(t3.spell, "heal", "recognised as heal")
	t3.queue_free()
	vc.queue_free()
	await frames(1)


func _check_incantation_drop() -> void:
	var inc := Incantation.new(PackedStringArray(["fireball", "heal"]))
	var got := []
	inc.trigger_armed.connect(func(tok: String) -> void: got.append("armed " + tok))
	inc.trigger_dropped.connect(func(tok: String) -> void: got.append("dropped " + tok))
	inc.feed("I SAID CAST IT AWAY", true, 0.0)
	eq(got, ["armed cast", "dropped cast"], "a \"cast\" buried in chatter arms, then drops quietly")
	got.clear()
	var events := inc.feed("CAST", true, 5.0)
	events.append_array(inc.tick(5.0 + 2.5))
	var kinds := events.map(func(e: Dictionary) -> String: return str(e["kind"]))
	eq(got, ["armed cast"], "a lone \"cast\" arms and is not dropped (%s)" % str(got))
	check(kinds.has("fizzle"), "it fizzles when the window runs out (%s)" % str(kinds))
