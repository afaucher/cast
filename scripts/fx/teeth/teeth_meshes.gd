class_name TeethMeshes
extends RefCounted
## The faceted tooth meshes for TeethFx, built from the same LowPoly soups as the heroes and monsters
## (flat facets, per-face painted colour jitter, welded normal in CUSTOM0 for the ink outline).
##
## Every tooth is modelled standing on the origin pointing +Y (the way it erupts from the body): a
## yellowish neck, then the bright crown (the pink gum collar is the separate "gum" mesh). The lowest bit
## (roots) sits below y = 0 so it stays buried in the victim until the tooth flies off.
##   molar       chunky block crown with four rounded cusps, two roots
##   molar_fill  the same with a gold filling in the biting surface
##   fang        wide at the neck, curved, blunt (a canine, not a spike)
##   incisor     a flat chisel
##   gold        one proud gold incisor
##   gum         the pink collar (its own mesh, a child of the tooth: it stays behind when the tooth flies)
##   chip        a loose fragment for the burst
## Width of the molar is about 0.62, so scale a tooth by the victim-sized unit.

## Alpha 0 = matte (no retro-reflective lift), so the facets keep their light / shade bands.
const IVORY := Color(0.93, 0.89, 0.78, 0.0)
const IVORY_HI := Color(0.99, 0.97, 0.88, 0.0)
const NECK := Color(0.90, 0.80, 0.56, 0.0)       ## tooth neck and the pit of a molar, a tobacco yellow
const GUM := Color(0.95, 0.50, 0.60, 0.0)
const GUM_DARK := Color(0.80, 0.32, 0.46, 0.0)
const GOLD := Color(1.00, 0.74, 0.14, 0.0)
const GOLD_DARK := Color(0.82, 0.52, 0.06, 0.0)

const KINDS: Array[String] = ["molar", "molar_fill", "fang", "incisor", "gold"]

static var _cache := {}


## The cached mesh for a tooth kind (or "chip" / "chip_gold").
static func mesh_for(kind: String) -> ArrayMesh:
	if _cache.has(kind):
		return _cache[kind]
	var s: LowPoly.Soup
	match kind:
		"molar":
			s = _molar(false, 11)
		"molar_fill":
			s = _molar(true, 23)
		"fang":
			s = _fang(37)
		"incisor":
			s = _incisor(49, false)
		"gold":
			s = _molar(false, 61, true)
		"gum":
			s = _gum(0.37, 41)
		"chip_gold":
			s = LowPoly.boulder(Vector3(0.5, 0.4, 0.45), 0, 0.28, GOLD, 71, 0.1)
		_:
			s = LowPoly.boulder(Vector3(0.5, 0.4, 0.45), 0, 0.28, IVORY_HI, 73, 0.05)
	var m := s.to_mesh()
	_cache[kind] = m
	return m


## Natural height of a tooth kind (for the pop sparkle / debris size).
static func height_of(kind: String) -> float:
	match kind:
		"fang":
			return 1.0
		"incisor":
			return 0.95
		"chip", "chip_gold":
			return 0.5
	return 0.75


static func _gum(radius: float, seed_value: int) -> LowPoly.Soup:
	var g := LowPoly.boulder(Vector3(radius, radius * 0.36, radius), 1, 0.12, GUM, seed_value, 0.08)
	# a darker lower lip so the gum reads as a collar
	g.merge(LowPoly.boulder(Vector3(radius * 0.9, radius * 0.3, radius * 0.9), 0, 0.1, GUM_DARK, seed_value + 3, 0.06),
			LowPoly.at(Vector3(0, -radius * 0.22, 0)))
	return g


static func _molar(filling: bool, seed_value: int, gold: bool = false) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(seed_value, 0.05)
	var neck := GOLD_DARK if gold else NECK
	var crown := GOLD if gold else IVORY_HI
	var pit := GOLD_DARK if gold else NECK
	# roots, buried
	for sx in [-1.0, 1.0]:
		s.merge(LowPoly.cylinder(0.16, 0.07, 0.4, 5, neck, seed_value + 5, 0.02), LowPoly.at(Vector3(0.15 * sx, -0.22, 0)))
	# neck, then crown
	s.merge(LowPoly.frustum(Vector2(0.50, 0.46), Vector2(0.62, 0.58), 0.22, neck, seed_value + 1, 0.025), LowPoly.at(Vector3(0, 0.11, 0)))
	s.merge(LowPoly.frustum(Vector2(0.62, 0.58), Vector2(0.58, 0.54), 0.30, crown, seed_value + 2, 0.025), LowPoly.at(Vector3(0, 0.37, 0)))
	# the pit between the cusps (darker), then four tall rounded cusps around it
	s.merge(LowPoly.box(Vector3(0.40, 0.06, 0.38), pit, seed_value + 4, 0.0), LowPoly.at(Vector3(0, 0.53, 0)))
	var i := 0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var h := 0.22 + 0.04 * float(i % 2)
			s.merge(LowPoly.cylinder(0.19, 0.10, h, 5, crown, seed_value + 10 + i, 0.015), LowPoly.at(Vector3(0.20 * sx, 0.52 + h * 0.5, 0.19 * sz), Vector3(0, 20.0 * float(i), 0)))
			i += 1
	if filling:
		s.merge(LowPoly.box(Vector3(0.26, 0.09, 0.24), GOLD, seed_value + 30, 0.012), LowPoly.at(Vector3(0, 0.55, 0)))
	return s


static func _fang(seed_value: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(seed_value, 0.05)
	var body := LowPoly.Soup.new(seed_value, 0.05)
	body.merge(LowPoly.cylinder(0.32, 0.29, 0.24, 6, NECK, seed_value + 1, 0.015), LowPoly.at(Vector3(0, 0.13, 0)))
	body.merge(LowPoly.cylinder(0.29, 0.19, 0.30, 6, IVORY_HI, seed_value + 2, 0.015, 2), LowPoly.at(Vector3(0, 0.39, 0)))
	body.merge(LowPoly.cylinder(0.19, 0.09, 0.40, 6, IVORY_HI, seed_value + 3, 0.012, 2), LowPoly.at(Vector3(0, 0.74, 0)))
	# curve the fang like a canine: sweep x forward with height
	for i in body.verts.size():
		var p := body.verts[i]
		body.verts[i] = Vector3(p.x + 0.12 * pow(maxf(p.y - 0.2, 0.0) / 0.7, 2.0), p.y, p.z)
	s.merge(body)
	s.merge(LowPoly.cylinder(0.18, 0.08, 0.44, 5, NECK, seed_value + 5, 0.02), LowPoly.at(Vector3(0, -0.22, 0)))
	return s


static func _incisor(seed_value: int, gold: bool) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(seed_value, 0.05)
	var neck := GOLD_DARK if gold else NECK
	var crown := GOLD if gold else IVORY_HI
	s.merge(LowPoly.frustum(Vector2(0.34, 0.26), Vector2(0.36, 0.28), 0.4, neck, seed_value + 5, 0.02), LowPoly.at(Vector3(0, -0.2, 0)))
	s.merge(LowPoly.frustum(Vector2(0.50, 0.32), Vector2(0.60, 0.30), 0.30, neck, seed_value + 1, 0.02), LowPoly.at(Vector3(0, 0.15, 0)))
	s.merge(LowPoly.frustum(Vector2(0.60, 0.30), Vector2(0.64, 0.20), 0.46, crown, seed_value + 2, 0.02), LowPoly.at(Vector3(0, 0.53, 0)))
	# a chiselled bevel on the cutting edge
	s.merge(LowPoly.frustum(Vector2(0.64, 0.20), Vector2(0.58, 0.07), 0.10, crown, seed_value + 3, 0.01), LowPoly.at(Vector3(0, 0.81, 0)))
	return s
