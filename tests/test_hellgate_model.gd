extends TestCase
## The hellgate model: builds headless, the origin gate is clearly bigger and spikier, stays cheap, the
## shards are flat-faced, the cracks glow (enemy language) and the hooks (flare, pulse, phase, shove
## telegraph, collapse) run.

const BUDGET := 9000


func setup() -> void:
	var normal := HellgateModel.make(false)
	var big := HellgateModel.make(true)
	add_child(normal)
	add_child(big)
	await get_tree().process_frame
	check(normal.shard_count >= 9, "normal gate has a ring of shards (%d)" % normal.shard_count)
	check(big.shard_count > normal.shard_count + 4, "origin gate has many more spikes (%d vs %d)" % [big.shard_count, normal.shard_count])
	check(big.scale.x >= 1.9 * normal.scale.x, "origin gate is double size")
	check(big.ui_height > normal.ui_height * 1.8, "origin bar floats higher")
	check(big.triangle_count() > normal.triangle_count(), "origin gate has more geometry")
	check(big.triangle_count() < BUDGET, "origin stays cheap (%d tris)" % big.triangle_count())
	check(normal.triangle_count() < BUDGET / 2, "normal stays cheap (%d tris)" % normal.triangle_count())
	_check_flat_and_glow(normal)
	# hooks run without errors
	normal.set_active(true)
	normal.set_flare(1.0)
	normal.pulse(1.0)
	normal.set_hurt(0.6)
	big.set_phase(2)
	big.telegraph_shove(0.5, 5.5)
	await get_tree().create_timer(0.7).timeout
	check(not normal.is_closing(), "not closing yet")
	normal.play_close(0.4)
	big.play_close(0.4)
	check(normal.is_closing(), "closing")
	await get_tree().create_timer(0.7).timeout
	check(normal.is_closed_done() and big.is_closed_done(), "collapse finished")
	finish()


func _check_flat_and_glow(m: HellgateModel) -> void:
	var glow_faces := 0
	var dark_faces := 0
	var checked := 0
	for mi in m._meshes():
		var arrays := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for t in range(0, verts.size(), 3):
			if t % 30 == 0:
				var fn := (verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t])
				if fn.length() > 0.00001:
					checked += 1
					if absf(fn.normalized().dot(normals[t])) < 0.99:
						check(false, "face normal is flat")
						return
			if cols[t].a < 0.75:
				glow_faces += 1
			else:
				dark_faces += 1
		check(mi.material_override is ShaderMaterial, "uses the enemy shader material")
	check(checked > 5, "faces checked")
	check(glow_faces > 20, "cracks and veins glow (%d faces)" % glow_faces)
	check(dark_faces > glow_faces, "mostly dark obsidian (%d dark, %d glowing)" % [dark_faces, glow_faces])
