class_name InputSetup
extends RefCounted
## Input actions, registered in code so project.godot stays readable.
## Keyboard + mouse for player 1. Keys 1-4 ready (hold) a spell slot, E casts the readied
## spell without voice (the keyboard fallback), F swaps a dropped component into the held slot.

const KEYS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"cast_slot_1": [KEY_1],
	"cast_slot_2": [KEY_2],
	"cast_slot_3": [KEY_3],
	"cast_slot_4": [KEY_4],
	"cast_readied": [KEY_E],
	"swap_pickup": [KEY_F],
	"toggle_voice_debug": [KEY_F1],
	"restart": [KEY_F5],
	"pause": [KEY_ESCAPE],
}
const MOUSE := {
	"attack_melee": MOUSE_BUTTON_LEFT,
	"attack_ranged": MOUSE_BUTTON_RIGHT,
}


static func ensure_actions() -> void:
	for action in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in KEYS[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
	for action in MOUSE:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE[action]
		InputMap.action_add_event(action, m)
