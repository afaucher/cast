extends TestCase
## M1 screens, single process: a client's read-only job board, the license checkout's leave row, and the host's
## "end the job for everyone" question.

func setup() -> void:
	timeout_sec = 60.0
	await _check_board()
	await _check_picker()
	await _check_confirm()
	finish()


func _check_board() -> void:
	var offers := ContractBoard.offers(77)
	var picks: Array[int] = []
	# The host's board: keys and clicks pick, and moving the highlight is announced (the crew follows it).
	var host_board := JobBoard.new(offers)
	var moves: Array[int] = []
	host_board.highlight_changed.connect(func(i: int) -> void: moves.append(i))
	host_board.picked.connect(func(r: ContractRun) -> void: picks.append(offers.find(r)))
	add_child(host_board)
	await frames(2)
	check(host_board.find_child("HostPicks", true, false) == null, "the host's board does not say the host picks")
	host_board.set_highlight(2)
	host_board.set_highlight(2)
	eq(moves, [2] as Array[int], "a highlight change is announced once")
	host_board.sign_hold = 0.0
	host_board.choose(1)
	eq(picks, [1] as Array[int], "the host's board picks")
	host_board.queue_free()
	await frames(2)

	# A client's board: the same offers, read-only, the host's note, the highlight set from outside.
	picks.clear()
	var board := JobBoard.new(offers)
	board.read_only = true
	board.picked.connect(func(r: ContractRun) -> void: picks.append(offers.find(r)))
	add_child(board)
	await frames(2)
	check(board.find_child("HostPicks", true, false) != null, "a client's board says the host picks")
	board.choose(0)
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	board._input(key)
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	board._input(accept)
	eq(picks, [] as Array[int], "keys and clicks pick nothing on a client's board")
	board.set_highlight(2)
	eq(board.highlighted(), 2, "but the host's highlighted card shows")
	board.queue_free()
	await frames(2)


func _check_picker() -> void:
	var host_picker := SpellPicker.new()
	add_child(host_picker)
	await frames(2)
	eq(host_picker._back.text, "Back to the board", "the host's checkout goes back to the board")
	host_picker.queue_free()
	var picker := SpellPicker.new()
	picker.back_text = "Leave the crew"
	picker.back_hint = "back to the menu"
	var left: Array[bool] = []
	picker.cancelled.connect(func() -> void: left.append(true))
	add_child(picker)
	await frames(2)
	eq(picker._back.text, "Leave the crew", "a client's checkout has a Leave the crew row")
	eq(picker._back.hint, "back to the menu", "and says where it goes")
	picker._back.pressed.emit()
	eq(left.size(), 1, "pressing it cancels the checkout")
	picker.queue_free()
	await frames(2)


func _check_confirm() -> void:
	var confirm := CrewConfirm.new()
	var answers: Array[String] = []
	confirm.confirmed.connect(func() -> void: answers.append("leave"))
	confirm.declined.connect(func() -> void: answers.append("stay"))
	add_child(confirm)
	await frames(3)
	check(confirm.stay_button.has_focus(), "Stay is the default")
	confirm.stay_button.pressed.emit()
	confirm.leave_button.pressed.emit()
	eq(answers, ["stay", "leave"] as Array[String], "Stay declines and End the job confirms")
	answers.clear()
	OS.delay_msec(200)   # the input guard is wall time (this batch runs --fixed-fps)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	confirm._input(esc)
	eq(answers, ["stay"] as Array[String], "Esc stays")
	confirm.queue_free()
	await frames(2)
