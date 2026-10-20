class_name FireworksFx
extends Node3D
## The goblin scout's fireworks volley (docs/design/goblin-scout.md): COSMETIC ONLY. A string of rockets
## leaves the launch point (this node's position) one after another, climbs on a fizzing trail, ricochets off
## the bunker's ceiling with a spark, and bursts into a ball of faceted star streaks in red / gold / lime with a
## flash of coloured light over the room; each rocket has its own whistle and bang (Sfx "firework"). No comic words
## (user, 2026-10-20: "it hurts the reading more than helps"). The alert it stands for is gameplay and lives on
## the host (the scout raises it); this node only shows it.
##
## A scheduled effect: every machine builds it from (launch point, start time, fx_seed) and everything after is a
## pure function of the time since the start: sample(t). Its own generator (seeded by fx_seed) shapes the arcs;
## never GameWorld.rng. In play it runs from GameWorld.time; a lab sets `frozen` and calls sample(t) for a still.
##
##   var fw := FireworksFx.new(); fw.fx_seed = 7; fw.start_time = GameWorld.time
##   GameWorld.spawn(fw, scout.model.launch_point())

const RED := Color(1.0, 0.24, 0.14)
const GOLD := Color(1.0, 0.78, 0.26)
const LIME := Color(0.66, 1.0, 0.26)
const CORE := Color(1.0, 0.96, 0.82)
const SMOKE := Color(0.46, 0.42, 0.40, 0.55)
const PALETTE: Array[Color] = [RED, GOLD, LIME]

const RISE_TIME := 0.55          ## launch to the ceiling
const RICOCHET_TIME := 0.22      ## ceiling to the burst point
const BURST_LIFE := 1.35         ## the star ball, from burst to gone
const SMOKE_LIFE := 2.6
const TRAIL := 9                 ## trail sparks per rocket
const SPARKS := 40               ## star streaks per burst
const PUFFS := 6                 ## smoke puffs per rocket
const HDR := 2.6                 ## glow colours above 1.0 bloom

## How many rockets, and the gap between them (seconds).
var count := 3
var interval := 0.30
## Height above the launch point where the rockets hit the ceiling.
var ceiling := 4.4
## Horizontal lean of the volley (the way the scout was running): the rockets veer that way, over the room.
var drift := Vector3.ZERO
var fx_seed := 1
## GameWorld.time of the launch; -1 = now (at _ready).
var start_time := -1.0
## A lab still: do not advance by itself; call sample(t).
var frozen := false

var _rockets: Array[Dictionary] = []
var _t := 0.0
var _sounded := 0        ## rockets whose sound has started (one cue each, as it launches)


func _ready() -> void:
	if start_time < 0.0:
		start_time = GameWorld.time
	_build()
	sample(0.0)


## Who may write each var (see Net). A scheduled cosmetic: the volley event carries the SPAWN params; the rest is
## this machine's own presentation.
func net_fields() -> Dictionary:
	return {
		"count": Net.SPAWN, "interval": Net.SPAWN, "ceiling": Net.SPAWN, "drift": Net.SPAWN, "fx_seed": Net.SPAWN,
		"start_time": Net.SPAWN,
		"frozen": Net.LOCAL, "_rockets": Net.LOCAL, "_t": Net.LOCAL, "_sounded": Net.LOCAL,
	}


## Spawn a volley at `pos` that started (or starts) at `start` (GameWorld.time). The goblin scout's launch on the host,
## and the world.fireworks event on every other screen (NetWorld), call this with the same seed and drift.
static func launch(pos: Vector3, start: float, seed_value: int, lean: Vector3) -> FireworksFx:
	if GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return null
	var fw := FireworksFx.new()
	fw.fx_seed = seed_value
	fw.start_time = start
	fw.drift = lean
	GameWorld.spawn(fw, pos)
	return fw


## Seconds from the launch until the last burst has faded (and the smoke is gone).
func total_time() -> float:
	return float(count - 1) * interval + RISE_TIME + RICOCHET_TIME + maxf(BURST_LIFE, SMOKE_LIFE)


## When rocket i bursts (seconds after the launch).
func burst_time(i: int) -> float:
	return float(i) * interval + RISE_TIME + RICOCHET_TIME


func _process(_delta: float) -> void:
	if frozen:
		return
	var t := GameWorld.time - start_time
	sample(t)
	_sound(t)
	if t > total_time():
		queue_free()


## Each rocket's whistle and bang as it launches (its bang lands on the burst). A rocket that launched well before this
## machine heard of the volley stays quiet rather than bang late.
func _sound(t: float) -> void:
	while _sounded < _rockets.size() and t >= float(_rockets[_sounded]["t0"]):
		if t - float(_rockets[_sounded]["t0"]) < 0.3:
			Sfx.play_at("firework", global_position)
		_sounded += 1


# ------------------------------------------------------------------ build

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = fx_seed
	var spark_mesh := LowPoly.cylinder(0.09, 0.0, 0.52, 4, Color.WHITE, 3, 0.0, 1, 0.0).to_mesh()
	var dot_mesh := LowPoly.boulder(Vector3(0.09, 0.09, 0.09), 0, 0.0, Color.WHITE, 5, 0.0).to_mesh()
	var puff_mesh := LowPoly.boulder(Vector3(0.3, 0.26, 0.3), 0, 0.12, Color.WHITE, 9, 0.0).to_mesh()
	var core_mesh := LowPoly.boulder(Vector3(0.5, 0.5, 0.5), 1, 0.05, Color.WHITE, 11, 0.0).to_mesh()
	var rocket_soup := LowPoly.cylinder(0.06, 0.06, 0.34, 6, Color(0.86, 0.16, 0.12), 13, 0.0, 1, 0.05)
	rocket_soup.merge(LowPoly.cylinder(0.065, 0.0, 0.14, 6, Color(0.98, 0.76, 0.18), 14, 0.0, 1, 0.04), LowPoly.at(Vector3(0, 0.24, 0)))
	var rocket_mesh := rocket_soup.to_mesh()
	var rocket_mat := LowPolyMaterial.make(1.6)
	var smoke_mat := Fx.glow_material(SMOKE, false)
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in count:
		var r := {}
		var col: Color = PALETTE[i % PALETTE.size()]
		var a := rng.randf_range(0.0, TAU)
		var lean := rng.randf_range(0.5, 1.4)
		var dr := Vector3(drift.x, 0.0, drift.z)
		var side := Vector3(-dr.z, 0.0, dr.x)
		var off := Vector3(cos(a) * lean, 0.0, sin(a) * lean) + dr * rng.randf_range(0.8, 1.6) + side * rng.randf_range(-1.4, 1.4)
		r["t0"] = float(i) * interval
		r["apex"] = off + Vector3(0.0, ceiling + rng.randf_range(-0.25, 0.25), 0.0)
		var a2 := a + rng.randf_range(-1.2, 1.2)
		var bounce := Vector3(cos(a2), 0.0, sin(a2)) * rng.randf_range(0.8, 1.5) + dr * rng.randf_range(0.6, 1.4)
		r["burst"] = (r["apex"] as Vector3) + bounce + Vector3(0.0, -rng.randf_range(0.8, 1.3), 0.0)
		r["wobble"] = rng.randf_range(0.0, TAU)
		r["radius"] = rng.randf_range(2.3, 2.9)
		r["col"] = col
		var mat := Fx.glow_material(Color(col.r * HDR, col.g * HDR, col.b * HDR, 1.0))
		var core_mat := Fx.glow_material(Color(CORE.r * HDR, CORE.g * HDR, CORE.b * HDR, 1.0))
		r["mat"] = mat
		r["core_mat"] = core_mat
		r["rocket"] = _mesh(rocket_mesh, rocket_mat)
		var trail: Array[MeshInstance3D] = []
		for k in TRAIL:
			trail.append(_mesh(dot_mesh, core_mat if k < 2 else mat))
		r["trail"] = trail
		var puffs: Array[MeshInstance3D] = []
		for k in PUFFS:
			puffs.append(_mesh(puff_mesh, smoke_mat))
		r["puffs"] = puffs
		var star: Array[MeshInstance3D] = []
		for k in 5:
			star.append(_mesh(spark_mesh, core_mat))
		r["star"] = star
		var dirs: Array[Vector3] = []
		var sparks: Array[MeshInstance3D] = []
		for k in SPARKS:
			var y := lerpf(1.0, -1.0, (float(k) + 0.5) / float(SPARKS))
			var ring := sqrt(maxf(0.0, 1.0 - y * y))
			var ang := float(k) * 2.399963 + rng.randf_range(-0.2, 0.2)
			dirs.append(Vector3(cos(ang) * ring, y, sin(ang) * ring).normalized() * rng.randf_range(0.8, 1.05))
			sparks.append(_mesh(spark_mesh, core_mat if k % 5 == 0 else mat))
		r["dirs"] = dirs
		r["sparks"] = sparks
		r["core"] = _mesh(core_mesh, core_mat)
		var light := OmniLight3D.new()
		light.light_color = col
		light.omni_range = 11.0
		light.omni_attenuation = 1.2
		light.shadow_enabled = false
		add_child(light)
		r["light"] = light
		_rockets.append(r)


func _mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


# ------------------------------------------------------------------ the volley at time t

## Where rocket r is `u` seconds after its own launch (rising, wobbling, then deflected off the ceiling).
func _rocket_pos(r: Dictionary, u: float) -> Vector3:
	var apex: Vector3 = r["apex"]
	if u <= RISE_TIME:
		var k := u / RISE_TIME
		var e := k * (2.0 - k) * 0.35 + k * 0.65      # quick off the rack, steady climb
		var p := Vector3(apex.x * e * e, apex.y * e, apex.z * e * e)
		var wob: float = r["wobble"]
		p += Vector3(sin(k * 9.0 + wob), 0.0, cos(k * 7.0 + wob)) * 0.12 * k
		return p
	var k2 := clampf((u - RISE_TIME) / RICOCHET_TIME, 0.0, 1.0)
	return apex.lerp(r["burst"], k2 * (2.0 - k2))


## Pose every piece of the volley at `t` seconds after the launch.
func sample(t: float) -> void:
	_t = t
	for r in _rockets:
		var u: float = t - float(r["t0"])
		var col: Color = r["col"]
		var flying := u >= 0.0 and u < RISE_TIME + RICOCHET_TIME
		# the rocket itself
		var rocket: MeshInstance3D = r["rocket"]
		rocket.visible = flying
		if flying:
			var p := _rocket_pos(r, u)
			var ahead := _rocket_pos(r, u + 0.02) - p
			rocket.position = p
			if ahead.length() > 0.0001:
				rocket.basis = Basis(Quaternion(Vector3.UP, ahead.normalized()))
		# the fizzing trail behind it (it outlives the rocket by a beat)
		var trail: Array[MeshInstance3D] = r["trail"]
		for k in trail.size():
			var uk := u - 0.035 * float(k + 1)
			var on := uk >= 0.0 and uk < RISE_TIME + RICOCHET_TIME and u < RISE_TIME + RICOCHET_TIME + 0.2
			trail[k].visible = on
			if on:
				trail[k].position = _rocket_pos(r, uk) + Vector3(0, -0.02 * float(k), 0)
				trail[k].scale = Vector3.ONE * lerpf(1.3, 0.35, float(k) / float(trail.size()))
		# smoke along the climb: puffs appear as the rocket passes, swell and drift, then thin out
		var puffs: Array[MeshInstance3D] = r["puffs"]
		for k in puffs.size():
			var born := RISE_TIME * float(k) / float(puffs.size())
			var age := u - born
			var on2 := age >= 0.0 and age < SMOKE_LIFE
			puffs[k].visible = on2
			if on2:
				var a := age / SMOKE_LIFE
				puffs[k].position = _rocket_pos(r, born) + Vector3(0.15 * a, 0.35 * a, -0.1 * a)
				puffs[k].scale = Vector3.ONE * (0.5 + 1.6 * sqrt(a)) * (1.0 - a * a)
		# the ricochet spark at the ceiling
		var star: Array[MeshInstance3D] = r["star"]
		var su := u - RISE_TIME
		for k in star.size():
			var on3 := su >= 0.0 and su < 0.16
			star[k].visible = on3
			if on3:
				var ang := TAU * float(k) / float(star.size()) + float(r["wobble"])
				var d := Vector3(cos(ang), -0.35, sin(ang)).normalized()
				star[k].position = r["apex"]
				star[k].basis = Basis(Quaternion(Vector3.UP, d)).scaled(Vector3.ONE * (1.4 - 4.0 * su))
		# the burst
		var bu := u - RISE_TIME - RICOCHET_TIME
		var bursting := bu >= 0.0 and bu < BURST_LIFE
		var centre: Vector3 = r["burst"]
		var radius: float = r["radius"]
		var spread := radius * (1.0 - exp(-bu * 5.5))
		var fade := 1.0 - smoothstep(0.55, 1.0, bu / BURST_LIFE) if bursting else 0.0
		var sparks: Array[MeshInstance3D] = r["sparks"]
		var dirs: Array[Vector3] = r["dirs"]
		for k in sparks.size():
			sparks[k].visible = bursting and fade > 0.02
			if sparks[k].visible:
				var d2: Vector3 = dirs[k]
				var p2 := centre + d2 * spread + Vector3(0, -0.9 * bu * bu, 0)
				sparks[k].position = p2
				var stretch := 0.6 + 1.6 * exp(-bu * 3.0)
				var dn := (d2 + Vector3(0, -0.35 * bu, 0)).normalized()
				sparks[k].basis = Basis(Quaternion(Vector3.UP, dn)).scaled(Vector3(fade, stretch * fade, fade))
		var core: MeshInstance3D = r["core"]
		core.visible = bursting and bu < 0.22
		if core.visible:
			core.position = centre
			core.scale = Vector3.ONE * (0.6 + 4.0 * bu) * (1.0 - bu / 0.22)
		var light: OmniLight3D = r["light"]
		light.position = centre if bu >= 0.0 else _rocket_pos(r, maxf(u, 0.0))
		light.light_energy = 0.0
		if bursting:
			light.light_energy = 9.0 * exp(-bu * 2.6)
		elif flying:
			light.light_energy = 1.2
			light.light_color = Color(1.0, 0.8, 0.5)
		if bursting:
			light.light_color = col
