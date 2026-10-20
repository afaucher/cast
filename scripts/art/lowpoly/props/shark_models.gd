extends RefCounted
## The three pool sharks (docs/design/sharks.md): the regular shark, the laser shark (a laser emitter strapped to its head)
## and the laser shark ridden by an imp (the swarmer, seated behind the emitter, one claw on the rein strap and one on the
## trigger grip). The game's Shark draws them through SharkBody (the imp variant without its rider: the game's gunner is a
## Jockey, drawn in the saddle); the lab (scenes/shark_lab.tscn) builds them whole. Same kit as PoolProps and
## PropModels: LowPoly soup, MonsterMaterial (toon bands, amber rim, ink outline, vertex alpha 0.5 = the monster glow:
## the eyes, the lens, the antenna tip). No class_name (users preload it).
##
##   const SharkModels := preload("res://scripts/art/lowpoly/props/shark_models.gd")
##   var shark := SharkModels.build("laser")          # "regular" | "laser" | "imp"
##   SharkModels.pose(shark, head_xf, body_xf, tail_xf) # a bending swim (the lab's steering loop)
##
## THREE SEGMENTS so the body bends along its path instead of turning like a plank: a smooth swim is a follow-the-leader
## chain on the path the head has swum (the lab's SharkSwim keeps the trail):
##   Head  its origin is the head-body joint J0, the snout points +Z (tip 0.85 ahead); the laser rig rides on it
##   Body  its origin is J0 too, it runs back along -Z to the body-tail joint J1 (BODY_LEN behind); the dorsal fin, the
##         pectorals and (imp) the saddle and the rider ride on it, so the fin trails the head through a turn
##   Tail  its origin is J1, it runs back along -Z: the tail stock (TAIL_LEN) and the crescent tail
## At rest (build()) the three line up: snout tip to the end of the tail stock is 2.4 (LENGTH), the tail fin 0.45 more.
## The origin (J0) sits on the BELLY: y = 0 is the pool floor it rests on, its back is BACK_Y up, the dorsal fin's tip
## FIN_TOP. In the game's wading pools (0.36 deep) that is a land shark in a paddling pool: its back and fin out of the
## water, the belly in it (PoolGeo: the deck is 0.5 above the pool floor, the surface 0.36).
##
## Monster glow: the eyes (an ember slit under a brow ridge), the laser's lens and antenna bulb. The rig's EMITTER is a
## separate MeshInstance3D ("Emitter", under Head) so the lab can swing it on its swivel (the imp aims it) and flare the
## lens (Lens: its own mesh, so it can pulse while the laser charges).

const SwarmerScript := preload("res://scripts/art/lowpoly/monsters/swarmer_model.gd")

const VARIANTS: Array[String] = ["regular", "laser", "imp"]

const SKIN := Color(0.36, 0.44, 0.58)        ## slate blue back
const SKIN_DK := Color(0.22, 0.27, 0.37)     ## the dorsal fin, the tail and a stripe down the spine (counter-shading)
const BELLY := Color(0.9, 0.92, 0.95)
const MOUTH := Color(0.55, 0.12, 0.16)
const TOOTH := Color(0.98, 0.97, 0.9)
const EYE := Color(1.0, 0.32, 0.12)          ## ember, like the grunt's eyes (glows)
const SCAR := Color(0.78, 0.8, 0.84)
const LEATHER := Color(0.36, 0.22, 0.13)
const BUCKLE := Color(0.82, 0.78, 0.62)
const GUNMETAL := Color(0.24, 0.26, 0.3)
const STEEL := Color(0.55, 0.59, 0.65)
const HAZARD := Color(0.98, 0.78, 0.12)
const LASER := Color(1.0, 0.16, 0.12)         ## the lens and the beam (glows)

const LENGTH := 2.4
const HEAD_LEN := 0.85        ## J0 to the snout tip
const BODY_LEN := 0.95        ## J0 to J1
const TAIL_LEN := 0.6         ## J1 to the end of the tail stock
const BACK_Y := 0.6
const FIN_TOP := 1.21
const LENS_AT := Vector3(0.0, 0.83, 0.86)     ## the lens centre in the Head's frame (the beam starts here)
const EMITTER_AT := Vector3(0.0, 0.66, 0.3)   ## the swivel's centre on the head plate (the Emitter's origin)
const SADDLE_AT := Vector3(0.0, 0.6, -0.14)   ## the rider's seat on the Body (J0 frame)


static func g(c: Color) -> Color:
	return PropModels.glow(c)


## A shark of `variant` at rest (the segments lined up). Node tree: Shark > Head (+ Emitter > Lens), Body (+ Rider), Tail.
## `with_rider` false: the imp variant's saddle and free grips without the imp (the game's rider is its own monster,
## a Jockey, drawn in the saddle while mounted).
static func build(variant: String = "regular", with_rider: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Shark"
	root.set_meta("variant", variant)
	var laser := variant != "regular"
	var head := _part(root, "Head", _head_soup(laser))
	var body := _part(root, "Body", _body_soup(laser, variant == "imp"))
	var tail := _part(root, "Tail", _tail_soup())
	tail.position = Vector3(0, 0, -BODY_LEN)
	if laser:
		var em := _part(head, "Emitter", _emitter_soup(variant == "imp"))
		em.position = EMITTER_AT
		var lens := _part(em, "Lens", _lens_soup())
		lens.position = LENS_AT - EMITTER_AT
	if variant == "imp" and with_rider:
		body.add_child(rider())
	return root


static func _part(parent: Node3D, part_name: String, s: LowPoly.Soup) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = s.to_mesh()
	var mat := MonsterMaterial.make(2.0)
	mat.set_shader_parameter("glow_gain", 1.8)
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## The segments of a built shark: {head, body, tail, emitter (or null), lens (or null), rider (or null)}.
static func segments(shark: Node3D) -> Dictionary:
	var head := shark.get_node("Head") as Node3D
	var em := head.get_node_or_null("Emitter") as Node3D
	var body := shark.get_node("Body") as Node3D
	return {"head": head, "body": body, "tail": shark.get_node("Tail"), "emitter": em,
		"lens": em.get_node_or_null("Lens") if em != null else null, "rider": body.get_node_or_null("Rider")}


## Place the three segments (transforms in the shark's parent space; the shark node itself stays at the identity).
static func pose(shark: Node3D, head_xf: Transform3D, body_xf: Transform3D, tail_xf: Transform3D) -> void:
	shark.transform = Transform3D.IDENTITY
	var seg := segments(shark)
	(seg["head"] as Node3D).transform = head_xf
	(seg["body"] as Node3D).transform = body_xf
	(seg["tail"] as Node3D).transform = tail_xf


## The emitter's swivel (degrees, 0 = along the snout) and how hot the lens runs (0 idle .. 1 about to fire).
static func aim(shark: Node3D, yaw_deg: float, charge: float) -> void:
	var seg := segments(shark)
	var em := seg["emitter"] as Node3D
	if em == null:
		return
	em.rotation_degrees.y = yaw_deg
	var lens := seg["lens"] as MeshInstance3D
	(lens.material_override as ShaderMaterial).set_shader_parameter("glow_gain", 1.8 + 4.0 * charge)
	lens.scale = Vector3.ONE * (1.0 + 0.35 * charge)


## The lens's world position and the beam's direction (the emitter's +Z) of a shark in the tree.
static func muzzle(shark: Node3D) -> Array:
	var seg := segments(shark)
	var lens := seg["lens"] as Node3D
	if lens == null:
		var h := seg["head"] as Node3D
		return [h.global_transform * Vector3(0, 0.4, HEAD_LEN), h.global_transform.basis.z.normalized()]
	return [lens.global_position, (seg["emitter"] as Node3D).global_transform.basis.z.normalized()]


# --- the head ------------------------------------------------------------------------------------------------------

static func _head_soup(laser: bool) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(901, 0.05)
	PropModels.ball(s, Vector3(0.34, 0.28, 0.5), Vector3(0, 0.31, 0.22), SKIN, 1, 0.05)
	PropModels.ball(s, Vector3(0.27, 0.13, 0.42), Vector3(0, 0.13, 0.26), BELLY, 1, 0.04)
	# the snout, tapering forward, and the open jaw under it
	PropModels.frus(s, Vector2(0.46, 0.38), Vector2(0.16, 0.12), 0.4, Vector3(0, 0.33, 0.63), SKIN, Vector2(0, -0.04), Vector3(90, 0, 0))
	PropModels.box(s, Vector3(0.4, 0.06, 0.32), Vector3(0, 0.13, 0.55), MOUTH)
	for i in 6:
		var x := -0.17 + 0.068 * float(i)
		PropModels.frus(s, Vector2(0.05, 0.05), Vector2.ZERO, 0.07, Vector3(x, 0.17, 0.69 - absf(x) * 0.55), TOOTH, Vector2.ZERO, Vector3(180, 0, 0))
		PropModels.frus(s, Vector2(0.045, 0.045), Vector2.ZERO, 0.06, Vector3(x * 0.92, 0.1, 0.66 - absf(x) * 0.55), TOOTH)
	# mean eyes: an ember slit under a heavy brow ridge, on each side
	for sx: float in [-1.0, 1.0]:
		PropModels.box(s, Vector3(0.05, 0.035, 0.1), Vector3(0.235 * sx, 0.38, 0.5), g(EYE), Vector3(0, 18.0 * sx, -12.0 * sx))
		PropModels.box(s, Vector3(0.08, 0.05, 0.16), Vector3(0.22 * sx, 0.44, 0.47), SKIN_DK, Vector3(0, 14.0 * sx, -26.0 * sx))
		for i in 3:
			PropModels.box(s, Vector3(0.025, 0.17, 0.035), Vector3(0.33 * sx, 0.3, -0.02 - 0.08 * float(i)), SKIN_DK.darkened(0.4), Vector3(0, 0, 8.0 * sx))
	# an old scar across the snout
	PropModels.box(s, Vector3(0.025, 0.02, 0.22), Vector3(0.1, 0.5, 0.5), SCAR, Vector3(0, 38, 0))
	if laser:
		_harness_head(s)
	return s


## Two leather straps round the head behind the eyes, a chin strap, and the steel plate the emitter's swivel sits on.
static func _harness_head(s: LowPoly.Soup) -> void:
	for z: float in [0.08, 0.42]:
		PropModels.box(s, Vector3(0.5, 0.05, 0.09), Vector3(0, 0.59 - (0.03 if z > 0.2 else 0.0), z), LEATHER, Vector3(-4, 0, 0))
		for sx: float in [-1.0, 1.0]:
			PropModels.box(s, Vector3(0.05, 0.42, 0.075), Vector3(0.335 * sx - (0.02 * sx if z > 0.2 else 0.0), 0.34, z), LEATHER, Vector3(0, 0, 7.0 * sx))
		PropModels.box(s, Vector3(0.12, 0.05, 0.075), Vector3(0, 0.03, z), LEATHER)
		PropModels.box(s, Vector3(0.07, 0.09, 0.11), Vector3(0.355, 0.44, z), BUCKLE)
	PropModels.box(s, Vector3(0.42, 0.05, 0.5), Vector3(0, 0.615, 0.26), STEEL, Vector3(-5, 0, 0))
	for sx: float in [-0.16, 0.16]:
		for z: float in [0.08, 0.44]:
			PropModels.cyl(s, 0.025, 0.025, 0.03, 5, Vector3(sx, 0.645, z), STEEL.darkened(0.3))


## The emitter, in its own frame (origin on the swivel, +Z = the beam): a swivel ring, a chunky gunmetal housing with
## hazard rings and cooling fins, a flared muzzle, an antenna with a glowing bulb, a coiled cable back to the side
## canisters, and twin grips at the back (the imp's trigger; the riderless rig has them lashed down with a yellow strap).
static func _emitter_soup(ridden: bool) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(921, 0.04)
	PropModels.cyl(s, 0.2, 0.18, 0.05, 10, Vector3(0, 0.0, 0), STEEL.darkened(0.15))
	PropModels.box(s, Vector3(0.12, 0.12, 0.14), Vector3(0, 0.09, 0.0), GUNMETAL)
	var y := LENS_AT.y - EMITTER_AT.y
	PropModels.rod(s, Vector3(0, y, -0.22), Vector3(0, y, 0.42), 0.15, 0.14, 8, GUNMETAL)
	for z: float in [-0.08, 0.12]:
		PropModels.rod(s, Vector3(0, y, z), Vector3(0, y, z + 0.07), 0.165, 0.165, 8, HAZARD)
	for i in 4:
		PropModels.box(s, Vector3(0.025, 0.09, 0.3), Vector3(-0.09 + 0.06 * float(i), y + 0.17, 0.0), STEEL)
	# the muzzle flares out round the lens
	PropModels.rod(s, Vector3(0, y, 0.42), Vector3(0, y, 0.54), 0.15, 0.2, 8, GUNMETAL.lightened(0.1))
	# antenna and bulb
	PropModels.rod(s, Vector3(0.1, y + 0.12, -0.16), Vector3(0.15, y + 0.42, -0.24), 0.018, 0.012, 4, STEEL)
	PropModels.ball(s, Vector3(0.045, 0.045, 0.045), Vector3(0.15, y + 0.45, -0.24), g(LASER), 0, 0.0)
	# the back cap and the twin grips (the trigger)
	PropModels.cyl(s, 0.13, 0.1, 0.06, 8, Vector3(0, y, -0.25), STEEL.darkened(0.2), Vector3(-90, 0, 0))
	for sx: float in [-0.13, 0.13]:
		PropModels.rod(s, Vector3(sx * 0.6, y - 0.02, -0.26), Vector3(sx, y - 0.04, -0.42), 0.025, 0.025, 5, STEEL)
		PropModels.rod(s, Vector3(sx, y - 0.04, -0.42), Vector3(sx, y - 0.2, -0.46), 0.04, 0.035, 6, Color(0.12, 0.12, 0.14))
	PropModels.box(s, Vector3(0.04, 0.07, 0.03), Vector3(0.13, y - 0.07, -0.39), Color(0.85, 0.12, 0.1))   # the red trigger
	if not ridden:
		# lashed forward: a yellow ratchet strap from the grips down to the plate
		PropModels.box(s, Vector3(0.33, 0.035, 0.06), Vector3(0, y - 0.12, -0.42), HAZARD)
		PropModels.box(s, Vector3(0.05, 0.2, 0.05), Vector3(0.0, y - 0.24, -0.38), HAZARD, Vector3(18, 0, 0))
	return s


## The lens: a glowing red disc with a hot core, set in the muzzle (its own mesh so it can flare while charging).
static func _lens_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(941, 0.0)
	PropModels.cyl(s, 0.14, 0.14, 0.03, 10, Vector3(0, 0, 0.0), g(LASER), Vector3(90, 0, 0))
	PropModels.cyl(s, 0.06, 0.06, 0.03, 8, Vector3(0, 0, 0.012), g(Color(1.0, 0.75, 0.6)), Vector3(90, 0, 0))
	return s


# --- the body ------------------------------------------------------------------------------------------------------

static func _body_soup(laser: bool, saddle: bool) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(961, 0.05)
	PropModels.ball(s, Vector3(0.37, 0.3, 0.64), Vector3(0, 0.3, -0.42), SKIN, 1, 0.05)
	PropModels.ball(s, Vector3(0.29, 0.13, 0.56), Vector3(0, 0.13, -0.4), BELLY, 1, 0.04)
	# the dorsal fin, raked back, with a bite out of its trailing edge (a tell at any zoom)
	PropModels.frus(s, Vector2(0.1, 0.66), Vector2(0.02, 0.1), 0.66, Vector3(0, 0.88, -0.4), SKIN_DK, Vector2(0, -0.32))
	PropModels.box(s, Vector3(0.11, 0.035, 0.2), Vector3(0, 1.0, -0.6), SCAR, Vector3(-40, 0, 0))   # a pale old scar across it
	PropModels.ball(s, Vector3(0.16, 0.06, 0.5), Vector3(0, 0.57, -0.42), SKIN_DK, 0, 0.02)          # the dark spine
	# pectoral fins, swept back and down
	for sx: float in [-1.0, 1.0]:
		PropModels.rod(s, Vector3(0.28 * sx, 0.14, -0.06), Vector3(0.8 * sx, 0.02, -0.44), 0.1, 0.02, 4, SKIN_DK)
	if laser:
		# a leather girth with two hazard-yellow power canisters on the flanks, cabled forward to the head
		PropModels.box(s, Vector3(0.82, 0.06, 0.1), Vector3(0, 0.6, -0.22), LEATHER)
		for sx: float in [-1.0, 1.0]:
			PropModels.box(s, Vector3(0.06, 0.48, 0.085), Vector3(0.39 * sx, 0.36, -0.22), LEATHER, Vector3(0, 0, 6.0 * sx))
			PropModels.rod(s, Vector3(0.44 * sx, 0.4, -0.02), Vector3(0.44 * sx, 0.4, -0.5), 0.085, 0.085, 7, HAZARD)
			PropModels.cyl(s, 0.06, 0.06, 0.04, 6, Vector3(0.44 * sx, 0.4, 0.0), GUNMETAL, Vector3(90, 0, 0))
			PropModels.rod(s, Vector3(0.44 * sx, 0.4, 0.02), Vector3(0.3 * sx, 0.62, 0.2), 0.022, 0.022, 4, Color(0.1, 0.1, 0.12))
	if saddle:
		# a little leather saddle behind the swivel, with stirrup straps
		PropModels.box(s, Vector3(0.36, 0.08, 0.34), SADDLE_AT + Vector3(0, 0.0, 0.0), LEATHER.lightened(0.1))
		PropModels.box(s, Vector3(0.38, 0.12, 0.06), SADDLE_AT + Vector3(0, 0.05, -0.17), LEATHER)
		for sx: float in [-1.0, 1.0]:
			PropModels.box(s, Vector3(0.04, 0.3, 0.05), Vector3(0.3 * sx, 0.46, -0.08), LEATHER.darkened(0.2), Vector3(0, 0, 18.0 * sx))
	return s


static func _tail_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(981, 0.05)
	PropModels.frus(s, Vector2(0.4, 0.36), Vector2(0.1, 0.14), TAIL_LEN + 0.05, Vector3(0, 0.3, -0.3), SKIN, Vector2.ZERO, Vector3(-90, 0, 0))
	PropModels.ball(s, Vector3(0.18, 0.08, 0.3), Vector3(0, 0.15, -0.18), BELLY, 0, 0.03)
	# the crescent tail: a tall upper lobe and a short lower one
	PropModels.rod(s, Vector3(0, 0.3, -TAIL_LEN), Vector3(0, 0.95, -TAIL_LEN - 0.4), 0.13, 0.02, 4, SKIN_DK)
	PropModels.rod(s, Vector3(0, 0.3, -TAIL_LEN), Vector3(0, 0.03, -TAIL_LEN - 0.26), 0.1, 0.02, 4, SKIN_DK)
	# the little second dorsal
	PropModels.frus(s, Vector2(0.05, 0.18), Vector2(0.015, 0.04), 0.16, Vector3(0, 0.5, -0.26), SKIN_DK, Vector2(0, -0.08))
	return s


# --- the rider ------------------------------------------------------------------------------------------------------

## The imp (the swarmer model), seated in the saddle facing the snout: legs astride, knees forward, its left claw on the
## rein strap and its right on the trigger grip, leaning in. Name "Rider", in the Body's frame.
static func rider() -> Node3D:
	var holder := Node3D.new()
	holder.name = "Rider"
	var imp: MonsterModel = SwarmerScript.new()
	imp.name = "Imp"
	imp.idle_enabled = false
	holder.add_child(imp)
	holder.position = SADDLE_AT + Vector3(0, -0.16, -0.02)
	holder.rotation_degrees.y = 180.0          # (the model faces -Z; the shark +Z)
	seat(imp, 0.0)
	return holder


## The seated pose; `lean` 0..1 hunches it over the grips (aiming).
static func seat(imp: Node3D, lean: float) -> void:
	var p: Dictionary = (imp as LowPolyModel).parts
	(p["body"] as Node3D).rotation = Vector3(0.28 + 0.2 * lean, 0.0, 0.0)
	(p["head"] as Node3D).rotation = Vector3(-0.22 - 0.15 * lean, 0.0, 0.0)
	for side: String in ["l", "r"]:
		var sd := -1.0 if side == "l" else 1.0
		var leg := p["leg_" + side] as Node3D
		leg.rotation = Vector3(-1.25, 0.0, 0.62 * sd)
		leg.position.x = 0.2 * sd
	# both claws forward to the grips (the right one on the trigger, the left on the rein strap)
	(p["arm_l"] as Node3D).rotation = Vector3(-1.45 - 0.15 * lean, 0.0, -0.35)
	(p["arm_r"] as Node3D).rotation = Vector3(-1.5 - 0.15 * lean, 0.0, 0.3)
	(p["ear_l"] as Node3D).rotation = Vector3(0.0, 0.0, 0.35)
	(p["ear_r"] as Node3D).rotation = Vector3(0.0, 0.0, -0.35)
	(p["tail"] as Node3D).rotation = Vector3(0.9, 0.3, 0.0)
