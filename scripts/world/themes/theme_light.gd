class_name ThemeLight
extends OmniLight3D
## The accent light of a themed room (cinema blue flicker, spa candle warm, lab green, torture red, panic-room
## red pulse, ...): ONE small OmniLight per room, no shadows. Flickers or pulses from a cheap sine mix.
## Built from a SitePlan.lights entry: {room, theme, pos, color, energy, range, flicker, pulse}.

var base_energy := 3.0
var flicker := 0.0
var pulse := 0.0
var _t := 0.0
var _seed := 0.0


static func make(l: Dictionary) -> ThemeLight:
	var light := ThemeLight.new()
	light.name = "Light_" + str(l["room"]).replace(":", "_")
	light.position = l["pos"]
	light.light_color = l["color"]
	light.base_energy = float(l["energy"])
	light.light_energy = light.base_energy
	light.omni_range = float(l["range"])
	light.omni_attenuation = 1.6
	light.light_specular = 0.1
	light.shadow_enabled = false
	light.flicker = float(l.get("flicker", 0.0))
	light.pulse = float(l.get("pulse", 0.0))
	light._seed = float(hash(str(l["room"]))) * 0.001
	return light


func _ready() -> void:
	set_process(flicker > 0.0 or pulse > 0.0)


func _process(delta: float) -> void:
	_t += delta
	var k := 1.0
	if flicker > 0.0:
		var n := 0.5 + 0.5 * sin(_t * 13.0 + _seed) * sin(_t * 7.3 + _seed * 2.0) * sin(_t * 3.1 + 1.0)
		k *= 1.0 - flicker * (1.0 - n) * 0.9
	if pulse > 0.0:
		k *= 1.0 + pulse * 0.5 * sin(_t * TAU * 0.6 + _seed)
	light_energy = base_energy * k
