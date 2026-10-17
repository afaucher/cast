extends TestCase
## TeethFx ("cast teeth" visual): afflict a plain Node3D headless, the pop fires once at about
## grow_time, cancel() prevents the pop, the chomp squash restores the victim's scale, the height is read
## from ui_height when there is one, and every node is freed afterwards.

var pops := 0


func _on_pop() -> void:
	pops += 1


func _count_fx(n: Node) -> int:
	var c := 1 if n is TeethFx else 0
	for ch in n.get_children():
		c += _count_fx(ch)
	return c


func setup() -> void:
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	# --- A plain target: default height, 8..14 teeth, pop once at about grow_time.
	var target := Node3D.new()
	target.scale = Vector3(1.0, 1.3, 1.0)
	add_child(target)
	var fx := TeethFx.afflict(target, 1.0, _on_pop)
	check(fx != null, "afflict returns the effect")
	if fx == null:
		finish()
		return
	check(fx.get_parent() == target, "attached to the target")
	near(fx.height, 2.0, 0.001, "default height without ui_height")
	check(fx.tooth_count() >= 8 and fx.tooth_count() <= 14, "8..14 teeth, got %d" % fx.tooth_count())
	check(fx.is_growing(), "growing")
	var f := 0
	while pops == 0 and f < 200:
		await get_tree().physics_frame
		f += 1
	var popped_at := float(f) / 60.0
	check(pops == 1, "on_pop fired")
	check(absf(popped_at - 1.0) < 0.15, "pop at about grow_time, got %.2f s" % popped_at)
	check(not fx.is_growing(), "not growing after the pop")
	check(fx.get_parent() != target, "moved off the victim at the pop so debris outlives it")
	await frames(3)
	check(not is_equal_approx(target.scale.y, 1.3), "chomp squash in progress, got %s" % str(target.scale))
	await frames(30)
	eq(pops, 1, "on_pop fires exactly once")
	await frames(60 * 2)
	eq(pops, 1, "still once")
	check(not is_instance_valid(fx), "effect freed after the debris time")
	check(target.scale.is_equal_approx(Vector3(1.0, 1.3, 1.0)), "victim scale restored exactly, got %s" % str(target.scale))
	eq(target.get_child_count(), 0, "nothing left on the victim")
	check(not target.has_meta("teeth_fx"), "no stale meta")

	# --- cancel() (the dentist) prevents the pop.
	pops = 0
	var fx2 := TeethFx.afflict(target, 1.0, _on_pop)
	await frames(20)
	check(fx2.cancel(), "cancel returns true while growing")
	check(not fx2.cancel(), "cancel twice returns false")
	await frames(60 * 2)
	eq(pops, 0, "no pop after cancel")
	check(not is_instance_valid(fx2), "cancelled effect freed")
	eq(target.get_child_count(), 0, "nothing left on the victim after cancel")

	# --- Height from ui_height (a hero model); a second afflict replaces the first.
	var model := RebarModel.new()
	add_child(model)
	var fx3 := TeethFx.afflict(model, 5.0, _on_pop)
	near(fx3.height, model.ui_height, 0.001, "height read from the model's ui_height")
	var fx4 := TeethFx.afflict(model, 5.0, _on_pop)
	await get_tree().process_frame
	check(not is_instance_valid(fx3), "second afflict replaces the first")
	check(is_instance_valid(fx4), "second effect alive")
	# manual time: advance() drives it deterministically, and a pop with on_pop on a freed target is safe
	fx4.manual = true
	var steps := 0
	while is_instance_valid(fx4) and fx4.is_growing() and steps < 1000:
		fx4.advance(1.0 / 60.0)
		steps += 1
	check(absf(float(steps) / 60.0 - 5.0) < 0.05, "manual advance pops at grow_time, got %d steps" % steps)
	eq(pops, 1, "manual pop fired on_pop")
	model.free()
	for i in 100:
		if is_instance_valid(fx4):
			fx4.advance(1.0 / 60.0)
	await frames(2)
	check(not is_instance_valid(fx4), "debris freed even though the victim was freed at the pop")

	# --- Everything cleaned up.
	target.free()
	await frames(5)
	eq(_count_fx(get_tree().root), 0, "no TeethFx left in the tree")
	var nodes_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	eq(nodes_after, nodes_before, "no nodes left behind")
	finish()
