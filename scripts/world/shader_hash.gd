class_name ShaderHash
extends RefCounted
## The lattice hash for the shaders' procedural patterns (value noise, cellular cracks, a random tone per brick or per
## facet): splice GLSL into a shader's code, ahead of the functions that call it. It declares
##   vec2 h22(vec2 p)    two values in [0, 1)
##   float h21(vec2 p)   one value in [0, 1)
## for a LATTICE point, a vec2 with whole-number coordinates (floor(x), i + vec2(1, 0), vec2(id, 3.0), ...): it hashes the
## point's integers (pcg2d, Jarzynski and Olano 2020), so every pixel that asks about the same point gets the same answer
## however far it is from the origin.
##
## Never fract(sin(dot(p, k)) * 43758.5): tens of metres from the origin the sine's argument is in the thousands, where one
## rounding step of it is another value, and the GPU forms a point's argument its own way for each neighbour a noise or a
## cellular pattern visits (dot(i + g, k)), so one point came out as two values either side of a lattice line and the
## pattern was cut along it: the lava's creases (docs/design/lava-playtest.md, "The lava's creases"). test_shader_hash
## checks every in-game pattern shader for it.
##
##   const MY_SHADER := """shader_type spatial;
##   varying vec3 wp;
##   """ + ShaderHash.GLSL + """
##   float vn(vec2 p) { ... h21(i + vec2(1, 0)) ... }
##   """

const GLSL := """
vec2 h22(vec2 p) {
	uvec2 v = uvec2(ivec2(floor(p + 0.5)) + 32768);
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	return vec2(v >> 8u) * (1.0 / 16777216.0);
}
float h21(vec2 p) { return h22(p).x; }
"""
