class_name VanRug
extends Node3D
## The crew's summoning mat: a big worn round rug the work van parks on (the circle's chalk goes on top of it).
## One flat disc drawn by a shader, no textures: deep maroon wool with a woven diamond border and cream pinstripes,
## triangle-faceted tone and wear (so it reads low-poly, not photographic), sun-faded and threadbare patches that
## are worst where the crew walks, two tyre tracks that swing wide in front of the van and run in under it, a few oil stains, a ragged edge with
## tassels. `set_scorch()` burns three black patches into it (the morning after a bad job).
## Lit (banded like the toon look) so the garage lights, the grate spot and the night grade all land on it.
##
##   var rug := VanRug.new(4.4)
##   rug.set_van_yaw(-10.0)        # the tracks run the way the van points
##   rug.set_scorch(1.0)           # optional: burn marks

const LIFT := 0.014                  ## above the hex top (the chalk circle sits at 0.035)

const SHADER := """
shader_type spatial;
render_mode specular_disabled, shadows_disabled;

uniform float radius = 4.4;
uniform vec2 track_dir = vec2(0.985, 0.174);
uniform float scorch = 0.0;
uniform float brightness = 1.0;      // overall brightness (brightly lit rooms want it darker)
uniform float garage = 1.0;          // 1 = tyre tracks + oil stains (the van parks here); 0 = a plain ritual rug
varying vec2 wp;

const vec3 MAROON = vec3(0.36, 0.075, 0.10);
const vec3 MAROON_DK = vec3(0.21, 0.045, 0.075);
const vec3 RUST_DK = vec3(0.40, 0.15, 0.07);
const vec3 RUST = vec3(0.66, 0.26, 0.10);
const vec3 OCHRE = vec3(0.88, 0.62, 0.24);
const vec3 CREAM = vec3(0.84, 0.74, 0.54);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.5 + noise(p * 2.03 + 5.2) * 0.3 + noise(p * 4.1 + 1.7) * 0.2;
}

// the equilateral triangle of side t that holds p: x = a random 0..1 per triangle, yz = its centre
vec3 tri_cell(vec2 p, float t) {
	vec2 q = p / t;
	vec2 sk = vec2(q.x - q.y * 0.57735, q.y * 1.1547);
	vec2 i = floor(sk);
	vec2 f = sk - i;
	float up = step(1.0, f.x + f.y);
	vec2 c = i + mix(vec2(0.33333), vec2(0.66667), up);
	float cy = c.y / 1.1547;
	return vec3(hash(i * 2.0 + vec2(up, up * 3.0)), vec2(c.x + cy * 0.57735, cy) * t);
}

void vertex() {
	wp = VERTEX.xz;
}

void fragment() {
	vec2 p = wp;
	float u = length(p) / radius;
	float ang = atan(p.y, p.x);
	float an = ang / 6.2831853 + 0.5;
	vec2 circ = vec2(cos(ang), sin(ang));

	// ragged edge: bites worn out of it, and tassels (thin strands of varying length, some missing)
	float bite = smoothstep(0.6, 0.9, noise(circ * 3.0 + 1.7)) * 0.018 + smoothstep(0.7, 0.95, noise(circ * 9.0 + 4.1)) * 0.009;
	float edge_u = 0.955 - bite;
	float fcell = an * 300.0;
	float fid = floor(fcell);
	float ff = fract(fcell) - 0.5;
	float flen = 0.010 + 0.034 * hash(vec2(fid, 4.0));
	float strand = step(abs(ff), 0.21) * step(0.2, hash(vec2(fid, 8.0)));
	bool body = u < edge_u;
	bool fringe = u >= edge_u && u < edge_u + flen && strand > 0.5;
	if (!body && !fringe) {
		discard;
	}

	vec3 tc = tri_cell(p, 0.62);
	float tone = tc.x;

	vec3 col;
	if (!body) {
		float k = (u - edge_u) / flen;
		col = mix(vec3(0.66, 0.55, 0.40), vec3(0.34, 0.27, 0.20), k) * (0.75 + 0.25 * hash(vec2(fid, 2.0)));
	} else if (u < 0.82) {
		// the field: deep maroon, every facet a touch lighter or darker, a faint rust line out near the border
		col = MAROON * (0.86 + 0.28 * tone);
		col = mix(col, RUST_DK, (1.0 - smoothstep(0.0, 0.006, abs(u - 0.795))) * 0.6);
	} else if (u < 0.845) {
		col = MAROON_DK;
		col = mix(col, CREAM, 1.0 - smoothstep(0.0, 0.0045, abs(u - 0.8325)));
	} else if (u < 0.945) {
		// the border: a ring of diamonds (ochre, maroon eye, cream pip) with small rust diamonds between them
		float bx = fract(an * 56.0) - 0.5;
		float by = (u - 0.895) / 0.1;
		float dm = abs(bx) + abs(by);
		float dm2 = abs(abs(bx) - 0.5) + abs(by);
		col = RUST_DK * (0.88 + 0.24 * tone);
		col = mix(col, RUST, step(dm2, 0.24));
		col = mix(col, OCHRE, step(dm, 0.44));
		col = mix(col, MAROON_DK, step(dm, 0.30));
		col = mix(col, CREAM, step(dm, 0.12));
	} else {
		col = OCHRE * 0.85;
	}

	// weave and grime
	col *= 1.0 + 0.05 * sin(p.x * 42.0) * sin(p.y * 42.0);
	float dirt = fbm(p * 1.3 + 11.0);
	col *= mix(0.72, 1.0, smoothstep(0.30, 0.68, dirt));

	// wear: faceted patches of sun-fade and threadbare, worst where the crew walks (toward the camera) and at the rim
	float wn = mix(fbm(p * 0.5 + 3.0), fbm(tc.yz * 0.5 + 3.0), 0.7);
	float wear = wn + 0.16 * smoothstep(-0.5, 3.2, p.y) + 0.10 * smoothstep(0.55, 0.92, u) - 0.08;
	float fade = smoothstep(0.54, 0.76, wear);
	float bare = smoothstep(0.76, 0.82, wear + 0.05 * noise(p * 14.0));
	float lum = dot(col, vec3(0.34));
	col = mix(col, vec3(lum * 1.0 + 0.08, lum * 0.78 + 0.05, lum * 0.68 + 0.04), fade * 0.6);
	vec3 cord = vec3(0.36, 0.26, 0.17) * (0.72 + 0.28 * (0.5 + 0.5 * sin(p.x * 70.0)) * (0.6 + 0.4 * sin(p.y * 55.0)));
	col = mix(col, cord, bare * 0.9);

	// a darker rolled lip at the very edge
	col *= 1.0 - 0.45 * smoothstep(edge_u - 0.012, edge_u, u) * float(body);

	// tyre tracks: two V-tread bands that swing wide in front of the van (so the camera sees them) and run in under it, broken and dusty
	vec2 d = normalize(track_dir);
	vec2 nrm = vec2(-d.y, d.x);
	float s = dot(p, d);
	float t = dot(p, nrm);
	float track = 0.0;
	float dust = 0.0;
	float run = 1.0 - 0.6 * smoothstep(2.6, 4.2, -s);
	for (int k = 0; k < 2; k++) {
		float side = k == 0 ? -1.0 : 1.0;
		float tcen = side * 0.97 + 2.1 * exp(-pow((s + 0.2) / 2.0, 2.0)) + 0.12 * sin(s * 0.9);
		float dt = abs(t - tcen);
		float band = 1.0 - smoothstep(0.15, 0.21, dt);
		float treads = 0.7 + 0.3 * step(0.5, fract((s + dt * 1.1) * 6.5));
		float brk = 0.45 + 0.55 * smoothstep(0.22, 0.55, noise(vec2(s * 2.0 + float(k) * 9.0, t * 5.0)));
		track = max(track, band * treads * brk);
		dust = max(dust, (1.0 - smoothstep(0.1, 0.5, dt)) * 0.5);
	}
	track *= run * garage;
	dust *= run * garage * smoothstep(0.3, 0.6, noise(vec2(s * 1.2, t * 1.2 + 4.0)));
	col = mix(col, col * 0.6, dust * 0.6);
	col = mix(col, col * 0.15 + vec3(0.025, 0.018, 0.014), track * 0.92);

	// oil stains (in the van's frame: s along the van, t across), blue-purple at the wet edge
	vec3 stains[3] = vec3[3](vec3(-2.0, 1.25, 0.34), vec3(0.7, 1.55, 0.46), vec3(2.5, -0.5, 0.27));
	vec2 st = vec2(s, t);
	float oil = 0.0;
	float sheen = 0.0;
	for (int i = 0; i < 3; i++) {
		vec2 dv = st - stains[i].xy;
		float rr = stains[i].z * (1.0 + 0.45 * (noise(dv * 3.5 + float(i) * 5.0) - 0.5) + 0.12 * sin(atan(dv.y, dv.x) * 3.0 + float(i)));
		float dd = length(dv) / rr;
		oil = max(oil, 1.0 - smoothstep(0.82, 1.0, dd));
		sheen = max(sheen, smoothstep(0.55, 0.85, dd) * (1.0 - smoothstep(0.95, 1.2, dd)));
	}
	oil *= garage;
	col = mix(col, vec3(0.03, 0.024, 0.034), oil * 0.9);
	col += vec3(0.05, 0.035, 0.10) * sheen * garage * (1.0 - oil) * float(body);

	// burn marks (the morning after): charred centre, singed ring, ragged edge
	vec3 burns[3] = vec3[3](vec3(-0.5, 2.0, 1.0), vec3(2.6, 1.6, 0.55), vec3(-2.3, -0.4, 0.6));
	for (int i = 0; i < 3; i++) {
		vec2 dv = p - burns[i].xy;
		float ba = atan(dv.y, dv.x);
		float rr = burns[i].z * (1.0 + 0.5 * (noise(dv * 3.0 + float(i) * 7.0) - 0.5) + 0.2 * sin(ba * 5.0 + float(i) * 2.0));
		float dd = length(dv) / rr;
		float burn = (1.0 - smoothstep(0.68, 0.82, dd)) * scorch;
		float ring = (1.0 - smoothstep(0.9, 1.3, dd)) * scorch;
		col = mix(col, col * 0.5 + vec3(0.07, 0.03, 0.01), ring * 0.7);
		col = mix(col, vec3(0.035, 0.028, 0.028), burn * 0.95);
	}

	ALBEDO = col * brightness;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float q = floor(ATTENUATION * 5.0 + 0.5) / 5.0;
	float att = mix(ATTENUATION, q, 0.55);
	DIFFUSE_LIGHT += LIGHT_COLOR * ndl * att / PI;
}
"""

static var _shader: Shader

var radius := 4.4
var mat: ShaderMaterial
var disc: MeshInstance3D


func _init(r: float = 4.4) -> void:
	name = "VanRug"
	radius = r
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("radius", r)
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * r * 2.04
	disc = MeshInstance3D.new()
	disc.name = "Rug"
	disc.mesh = pm
	disc.material_override = mat
	disc.position = Vector3(0, LIFT, 0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)


## The tyre tracks run the way the van points: `yaw_deg` is the van holder's rotation about Y (its nose is +X before it).
func set_van_yaw(yaw_deg: float) -> void:
	var a := deg_to_rad(yaw_deg)
	mat.set_shader_parameter("track_dir", Vector2(cos(a), -sin(a)))


## false for a rug no van parks on (the ritual rooms' summoning circle): no tyre tracks, no oil.
func set_garage(on: bool) -> void:
	mat.set_shader_parameter("garage", 1.0 if on else 0.0)


## Overall brightness, 1 = as in the garage.
func set_tone(k: float) -> void:
	mat.set_shader_parameter("brightness", k)


## 0 = clean, 1 = three burn marks.
func set_scorch(k: float) -> void:
	mat.set_shader_parameter("scorch", clampf(k, 0.0, 1.0))
