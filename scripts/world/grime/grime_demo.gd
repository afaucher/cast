class_name GrimeDemo
extends RefCounted
## Dev only (game.gd --grime-demo, for screenshots): one second in, the player casts a fireball, corn and
## tentacles at three spots a few cells from the crew (real casts, so the real hooks leave the marks) and
## teeth / stain / scuff marks are dropped directly. Pair with --shot-after 4 (just after) and
## --shot-after 36 (the marks are gone by then).
##
## With the environment variable GRIME_TRAIL=1 it instead frames the camera on the middle of the first
## ichor drag trail and casts nothing.

const SPOTS: Array[Vector3] = [Vector3(3.5, 0, -3.5), Vector3(-4.0, 0, 4.0), Vector3(-3.0, 0, -3.0)]


static func run(host: Node, player: Actor) -> void:
	if OS.get_environment("GRIME_TRAIL") != "":
		_focus_trail(host)
		return
	await host.get_tree().create_timer(1.0).timeout
	if not is_instance_valid(player) or GameWorld.root == null:
		return
	var base := player.global_position
	SpellBook.cast("fireball", player, 1.0, base + SPOTS[0])
	SpellBook.cast("corn", player, 1.0, base + SPOTS[1])
	SpellBook.cast("tentacles", player, 1.0, base + SPOTS[2])
	Grime.mark(Grime.TEETH, base + Vector3(2.5, 0, 2.5), 1.0)
	Grime.mark(Grime.STAIN, base + Vector3(4.5, 0, 1.0), 0.6)
	Grime.mark(Grime.SCUFF, base + Vector3(-1.0, 0, 3.0), 1.0)


static func _focus_trail(host: Node) -> void:
	var layer := Grime.layer()
	var rig := host.get("rig") as CameraRig
	if layer == null or rig == null or GameWorld.root == null:
		return
	var drags: Array[GrimePlan.Mark] = []
	for m in layer.ambient:
		if m.source == "trail" and m.kind == "drag":
			drags.append(m)
	if drags.is_empty():
		return
	var marker := Node3D.new()
	GameWorld.root.add_child(marker)
	marker.global_position = drags[drags.size() / 2].pos
	rig.target = marker
	rig.snap()
