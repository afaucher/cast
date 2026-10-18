extends TestCase
## M7, single process, Steam parts with a FAKE Steam object (SteamIdentity.use_for_tests): nothing here needs a Steam client.
##
## - INVITES: an overlay invite (`join_requested`) while a screen listens becomes `invite_received(lobby, inviter)` with the
##   friend's name; "Stay" (decline) joins nothing; "Leave and join" (accept) leaves this session and joins that lobby. An
##   invite to the lobby we are already in is ignored. `+connect_lobby <id>` on the command line joins that lobby at start.
## - INVITE CREW: the overlay's invite dialog opens for this crew's lobby only in a Steam crew with a seat free.
## - AVATARS: `getPlayerAvatar` answers with `avatar_loaded` (at once or later): the picture becomes a texture, the
##   roster badge shows it, and without one (no Steam, still loading, id 0) the badge shows the name's initial.
## - LINK ON STEAM: a preset sets Steam's FakePacket* config (lag and loss by GodotSteam's names, jitter by the raw ints
##   56-58), retrying a value as the other type when Steam refuses one; the ENet simulator stays off; the end of the
##   session sets them back to 0.
## - The forms: "Leave this job and join?" (Stay is the default, Esc declines, the host is told it ends the job for the
##   crew), the pause form's "Invite crew" row (only when it can invite), the job board's invite button, Settings >
##   Diagnostics "Simulate a long link" (saved; a bad saved value reads "off").
## - Passive logs: the voice log's net columns and its old-header file set aside; the telemetry's cast and hits sheets;
##   the speech gate's voice onset; the caster's utterance onset.

const PORT := 28781
const TMP := "user://test_net_m7"


class FakeSteam extends Object:
	signal lobby_created(result: int, lobby: int)
	signal lobby_joined(lobby: int, permissions: int, locked: bool, response: int)
	signal lobby_match_list(lobbies: Array)
	signal join_requested(lobby_id: int, steam_id: int)
	signal avatar_loaded(avatar_id: int, size: int, data: PackedByteArray)

	var calls: Array = []                ## [name, args...]
	var friends := {42: "Rosa", 77: "Ike"}
	var avatar_now := {77: Color(0.9, 0.2, 0.1)}   ## answered inside getPlayerAvatar
	var refuse_float_ids: Array[int] = []           ## setGlobalConfigValueFloat says no for these

	func getPersonaName() -> String: return "Fake Player"
	func getSteamID() -> int: return 1001
	func run_callbacks() -> void: pass
	func createLobby(t: int, n: int) -> void: calls.append(["createLobby", t, n])
	func joinLobby(id: int) -> void: calls.append(["joinLobby", id])
	func leaveLobby(id: int) -> void: calls.append(["leaveLobby", id])
	func getLobbyOwner(_id: int) -> int: return 0
	func getLobbyData(_id: int, _k: String) -> String: return ""
	func setLobbyData(id: int, k: String, v: String) -> void: calls.append(["setLobbyData", id, k, v])
	func activateGameOverlayInviteDialog(id: int) -> void: calls.append(["invite_dialog", id])
	func getFriendPersonaName(id: int) -> String: return str(friends.get(id, ""))
	func getPlayerAvatar(size: int, id: int) -> void:
		calls.append(["getPlayerAvatar", size, id])
		if avatar_now.has(id):
			avatar_loaded.emit(id, 64, image_bytes(64, avatar_now[id]))
	func setGlobalConfigValueInt32(id: int, v: int) -> bool:
		calls.append(["int", id, v])
		return true
	func setGlobalConfigValueFloat(id: int, v: float) -> bool:
		calls.append(["float", id, v])
		return not refuse_float_ids.has(id)

	static func image_bytes(size: int, c: Color) -> PackedByteArray:
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(c)
		return img.get_data()

	func named(n: String) -> Array:
		return calls.filter(func(c: Array) -> bool: return str(c[0]) == n)


var fake: FakeSteam


func setup() -> void:
	timeout_sec = 60.0
	DirAccess.make_dir_recursive_absolute(TMP)
	fake = FakeSteam.new()
	SteamIdentity.use_for_tests(fake)
	Session.link_from_settings = false
	await frames(2)   # (the Lobby child wires itself to the fake on its next frame)
	await _check_link_values()
	await _check_avatars()
	await _check_invites()
	await _check_connect_lobby()
	await _check_invite_crew_and_steam_link()
	await _check_forms()
	_check_settings()
	_check_voice_log()
	_check_sheets()
	_check_onset()
	SteamIdentity.reset_for_tests()
	fake.free()
	finish()


func _check_link_values() -> void:
	var coast := {}
	for v: Array in NetSteamLink.values_for("coast"):
		coast[str(v[3])] = [int(v[0]), str(v[1]), v[2]]
	eq(coast["FakePacketLag_Recv"], [5, "int", 30], "coast: 30 ms of base lag (45 - 15), int32, config id 5")
	eq(coast["FakePacketLoss_Recv"], [3, "float", 1.5], "coast: 1.5% loss, config id 3")
	eq(coast["FakePacketJitter_Recv_Avg"], [56, "float", 15.0], "coast: jitter mean 15 ms, raw id 56 (GodotSteam has no name for it)")
	eq(coast["FakePacketJitter_Recv_Max"], [57, "float", 30.0], "coast: jitter clamped at 30 ms (so 30-60 ms like NetLink's 45 +- 15), raw id 57")
	eq(coast["FakePacketJitter_Recv_Pct"], [58, "float", 100.0], "coast: every packet jittered, raw id 58")
	for v: Array in NetSteamLink.values_for("off"):
		check(float(v[2]) == 0.0, "off sets %s to 0" % str(v[3]))
	var rough := {}
	for v: Array in NetSteamLink.values_for("rough"):
		rough[str(v[3])] = v[2]
	eq([rough["FakePacketLag_Recv"], rough["FakePacketLoss_Recv"], rough["FakePacketJitter_Recv_Max"]], [50, 4.0, 60.0], "rough: 50 + up to 60 ms, 4%")
	# Steam refuses the float for the jitter max: it is sent again as an int32.
	fake.calls.clear()
	fake.refuse_float_ids = [57]
	var res := NetSteamLink.apply(fake, "coast")
	check(bool(res["FakePacketJitter_Recv_Max"]), "a value Steam refused as a float went through as an int32")
	check(fake.calls.has(["float", 57, 30.0]) and fake.calls.has(["int", 57, 30]), "... tried as float, then int")
	check(fake.calls.has(["int", 5, 30]) and fake.calls.has(["float", 3, 1.5]), "lag and loss set")
	fake.refuse_float_ids = []
	eq(NetSteamLink.apply(null, "coast"), {}, "no Steam: nothing to set")


func _check_avatars() -> void:
	var av := Session.avatars
	av.clear()
	var ready_ids: Array[int] = []
	av.avatar_ready.connect(func(id: int) -> void: ready_ids.append(id))
	var tex := av.texture(77)
	check(tex != null and tex.get_width() == 64, "an avatar Steam has cached arrives at once as a 64 x 64 texture")
	if tex != null:
		var c := tex.get_image().get_pixel(10, 10)
		check(c.is_equal_approx(Color(0.9, 0.2, 0.1)) or c.r > 0.85, "... with Steam's pixels")
	eq(av.texture(0), null, "steam id 0 (a test name, no Steam id): no picture")
	eq(av.texture(88), null, "one Steam is still downloading: null for now")
	eq(fake.named("getPlayerAvatar").size(), 2, "asked Steam once per id (none for id 0)")
	av.texture(88)
	eq(fake.named("getPlayerAvatar").size(), 2, "not asked again while the answer is on its way")
	fake.avatar_loaded.emit(88, 64, FakeSteam.image_bytes(64, Color(0.1, 0.3, 0.9)))
	check(ready_ids.has(88) and av.has_texture(88), "the late answer is cached and announced (the roster redraws)")
	fake.avatar_loaded.emit(99, 64, PackedByteArray([1, 2, 3]))
	check(not av.has_texture(99), "bytes that don't fit the size are ignored")
	eq(SteamAvatars.image_from_rgba(2, PackedByteArray([0, 0, 0, 0])), null, "image_from_rgba checks the length")

	# The roster badge: the picture, else the initial on the seat's colour.
	var with_pic := CrewBadge.new({"seat": 2, "name": "Ike", "character": "wick"}, av.texture(77), true)
	var without := CrewBadge.new({"seat": 3, "name": "rosa", "character": "wick"}, null, false)
	add_child(with_pic)
	add_child(without)
	await frames(1)
	check(with_pic.has_avatar() and with_pic.picture.visible and not with_pic.initial.visible, "a badge shows the Steam avatar")
	check(not without.has_avatar() and without.initial.visible and without.initial.text == "R", "no avatar: the name's initial")
	check(with_pic.name_label.text.contains("Ike") and with_pic.name_label.text.contains("Wick") and with_pic.name_label.text.contains("(you)"), "seat, name, character and (you)")
	without.set_avatar(av.texture(88))
	check(without.has_avatar() and not without.initial.visible, "a picture that arrives later replaces the initial")
	with_pic.queue_free()
	without.queue_free()


func _check_invites() -> void:
	var got: Array = []
	var listener := func(lobby_id: int, inviter: String) -> void: got.append([lobby_id, inviter])
	Session.invite_received.connect(listener)
	fake.calls.clear()
	fake.join_requested.emit(555, 42)
	eq(got, [[555, "Rosa"]], "an overlay invite asks the screen that is up, with the friend's name")
	eq(Session.pending_invite, {"lobby": 555, "inviter": "Rosa"}, "the invite waits for the answer")
	eq(fake.named("joinLobby").size(), 0, "nothing is joined before the player answers")
	Session.decline_invite()
	eq(Session.pending_invite, {}, "Stay: the invite is dropped")
	eq(fake.named("joinLobby").size(), 0, "... and nothing joined")
	fake.join_requested.emit(556, 0)
	eq(got.back(), [556, ""], "an invite without a known friend still asks")
	check(Session.accept_invite(), "Leave and join")
	eq(fake.named("joinLobby"), [["joinLobby", 556]], "joins the invited lobby")
	check(Session.busy(), "the session is joining")
	check(not Session.accept_invite(), "no second accept without a new invite")
	Session.leave()
	check(not Session.busy() and not Session.online(), "left again")
	Session.invite_received.disconnect(listener)


func _check_connect_lobby() -> void:
	eq(SteamLobby.connect_lobby_arg(PackedStringArray(["--path", ".", "+connect_lobby", "109775241023"])), 109775241023, "+connect_lobby <id> is read")
	eq(SteamLobby.connect_lobby_arg(PackedStringArray(["+connect_lobby"])), 0, "no id: nothing")
	eq(SteamLobby.connect_lobby_arg(PackedStringArray(["+connect_lobby", "abc"])), 0, "not a number: nothing")
	fake.calls.clear()
	Session._apply_flags(PackedStringArray(), PackedStringArray(["+connect_lobby", "9001"]))
	Session.link_from_settings = false   # (_apply_flags sets it for a real run)
	eq(fake.named("joinLobby"), [["joinLobby", 9001]], "Steam launching the game for an invite (+connect_lobby) joins that lobby")
	check(Session.busy(), "... and the session is joining")
	Session.leave()
	await frames(1)


func _check_invite_crew_and_steam_link() -> void:
	check(not Session.can_invite() and not Session.invite_crew(), "offline: nobody to invite into")
	check(Session.host_enet(PORT), "a host (ENet stands in for the Steam peer)")
	check(not Session.can_invite(), "an ENet crew has no lobby to invite into")
	# Stand the session in for a Steam crew: the transport and the lobby id are what can_invite asks.
	Session.transport = NetSession.Transport.STEAM
	Session.lobby.lobby_id = 4242
	check(Session.can_invite(), "a Steam crew with seats free can invite")
	fake.calls.clear()
	check(Session.invite_crew(), "Invite crew")
	eq(fake.named("invite_dialog"), [["invite_dialog", 4242]], "the overlay's invite dialog opens for this lobby")
	# The link simulator on Steam: Steam's fake-lag config, never the ENet simulator.
	fake.calls.clear()
	var seen: Array[String] = []
	Session.link_changed.connect(func(p: String) -> void: seen.append(p))
	check(Session.set_link("coast"), "the host sets coast")
	eq(Session.link_preset, "coast", "the crew's link is coast")
	eq(Session.wire.link.preset, "off", "on Steam the ENet simulator stays off")
	check(fake.calls.has(["int", 5, 30]) and fake.calls.has(["float", 56, 15.0]) and fake.calls.has(["float", 3, 1.5]), "Steam's FakePacket* values were set")
	eq(seen, ["coast"] as Array[String], "link_changed fired once")
	check(not Session.set_link("tornado"), "an unknown preset is refused")
	# A full crew can't invite.
	Session.roster[50] = {"peer": 50, "seat": 2, "name": "x", "character": "wick", "steam_id": 0}
	Session.roster[51] = {"peer": 51, "seat": 3, "name": "y", "character": "wick", "steam_id": 0}
	check(not Session.can_invite(), "a full crew can't invite")
	Session.roster.erase(50)
	Session.roster.erase(51)
	fake.calls.clear()
	Session.leave()
	await frames(2)
	check(fake.calls.has(["int", 5, 0]) and fake.calls.has(["float", 3, 0.0]), "the session's end sets Steam's fake lag back to 0")
	Session.lobby.lobby_id = 0
	Session.link_preset = "off"


func _check_forms() -> void:
	# "Leave this job and join?"
	var inv := InviteConfirm.new()
	inv.inviter = "Rosa"
	inv.on_job = true
	inv.hosting_crew = true
	var answers: Array[String] = []
	inv.confirmed.connect(func() -> void: answers.append("join"))
	inv.declined.connect(func() -> void: answers.append("stay"))
	add_child(inv)
	await frames(3)
	check(inv.find_child("Inviter", true, false) != null and (inv.find_child("Inviter", true, false) as Label).text == "Rosa's crew", "it says whose crew")
	check(inv.note_label.text.contains("whole crew"), "the host is told it ends the job for the whole crew")
	check(inv.stay_button.has_focus(), "Stay is the default")
	inv._born_ms -= 1000   # (past the input guard: tests run faster than the wall clock)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	inv._input(esc)
	await after_void()
	inv.join_button.pressed.emit()
	eq(answers, ["stay", "join"] as Array[String], "Esc stays, the second row joins")
	inv.queue_free()
	var solo := InviteConfirm.new()
	solo.on_job = false
	add_child(solo)
	await frames(1)
	check(solo.note_label.text.contains("job board"), "on the board it only asks about the board")
	solo.queue_free()

	# The pause form's Invite crew row.
	var p := PauseMenu.new()
	p.online = true
	p.can_invite = true
	var invites := [0]
	p.invite.connect(func() -> void: invites[0] += 1)
	add_child(p)
	await frames(2)
	check(p.invite_button != null and p.invite_button.text == "Invite crew", "a Steam crew's pause form has Invite crew")
	if p.invite_button != null:
		p.invite_button.pressed.emit()
	eq(invites[0], 1, "it asks for the overlay")
	p.queue_free()
	var p2 := PauseMenu.new()
	add_child(p2)
	await frames(1)
	eq(p2.invite_button, null, "solo / offline: no invite row (the form as before)")
	p2.queue_free()

	# The job board's invite button.
	var board := JobBoard.new(ContractBoard.offers(5))
	add_child(board)
	await frames(2)
	check(not board.invite_button.visible and not board.crew_badges.visible, "offline: no badges, no invite button")
	board.force_invite = true
	board.refresh_crew()
	check(board.invite_button.visible, "the invite button shows when the crew can invite")
	board.queue_free()
	await frames(1)


func _check_settings() -> void:
	var path := TMP + "/settings.cfg"
	DirAccess.remove_absolute(path)
	eq(GameSettings.load_settings(path)["link_sim"], "off", "the link simulator is off by default")
	GameSettings.save_settings({"link_sim": "coast"}, path)
	eq(GameSettings.load_settings(path)["link_sim"], "coast", "saved")
	GameSettings.save_settings({"link_sim": "tornado"}, path)
	eq(GameSettings.load_settings(path)["link_sim"], "off", "a bad saved value reads off")
	var screen := SettingsScreen.new()
	screen.settings_path = path
	screen.apply_live = false
	add_child(screen)
	eq(screen.link_menu.selected, 0, "the Diagnostics row shows Off")
	screen.set_link_sim("rough")
	eq(GameSettings.load_settings(path)["link_sim"], "rough", "picking Rough saves it")
	eq(screen.link_menu.selected, 2, "and shows it")
	check(screen.link_state.text == "CREW-WIDE", "it says it is for the whole crew")
	screen.queue_free()


func _check_voice_log() -> void:
	var path := TMP + "/voice_log.csv"
	DirAccess.remove_absolute(path)
	for f in DirAccess.get_files_at(TMP):
		if f.begins_with("voice_log_"):
			DirAccess.remove_absolute(TMP + "/" + f)
	var old := FileAccess.open(path, FileAccess.WRITE)
	old.store_csv_line(PackedStringArray(["time", "clock", "heard"]))
	old.store_csv_line(PackedStringArray(["t", "1.0", "an old row"]))
	old.close()
	var log := VoiceLog.new(path)
	log.context = func() -> Dictionary: return {"net": "client", "seat": 2, "host_time": "12.345"}
	log.add({"heard": "cast heal", "label": "deliberate", "spell": "heal"})
	var rows := VoiceLog.read_all(path)
	eq(rows.size(), 1, "the new file holds only the new row")
	if rows.size() == 1:
		eq([rows[0]["net"], rows[0]["seat"], rows[0]["host_time"], rows[0]["spell"]], ["client", "2", "12.345", "heal"], "each row says which seat and when on the shared clock")
	var set_aside := Array(DirAccess.get_files_at(TMP)).filter(func(f: String) -> bool: return f.begins_with("voice_log_"))
	eq(set_aside.size(), 1, "the old file was set aside, not overwritten")
	var offline := VoiceLog.new(path)
	offline.add({"heard": "x"})
	eq(str(VoiceLog.read_all(path)[1]["net"]), "", "offline rows leave the net columns blank")


func _check_sheets() -> void:
	var dir := TMP + "/net"
	DirAccess.make_dir_recursive_absolute(dir)
	var tel := NetTelemetry.new()
	tel.dir = dir
	check(tel.open("host"), "telemetry opens")
	check(tel.casts.is_open() and tel.hits.is_open(), "with its casts and hits sheets")
	check(tel.casts.path.get_file().begins_with("net_casts_host_") and tel.hits.path.get_file().begins_with("net_hits_host_"), "named by kind and role")
	var row: Array = []
	for c in NetTelemetry.CAST_COLUMNS:
		row.append("x")
	check(tel.casts.write_peer(77, row), "a client's cast row is filed")
	check(not tel.casts.write_peer(77, ["too", "short"]), "a row of the wrong width is dropped")
	tel.close()
	var f := FileAccess.open(tel.casts.path, FileAccess.READ)
	var header := f.get_csv_line()
	var line := f.get_csv_line()
	eq(Array(header), Array(NetTelemetry.CAST_COLUMNS), "the casts sheet's header")
	eq(line[header.find("from")], "77", "a client's row is filed under the transport's peer id")
	eq(NetSession.source_kind(null), "other", "an unknown source")


func _check_onset() -> void:
	# The speech gate marks where a voice span begins (the onset) as well as where it ends.
	var gate := SpeechGate.new()
	var rate := 16000
	var quiet := PackedFloat32Array()
	quiet.resize(rate)   # 1 s of near silence teaches the floor
	for i in quiet.size():
		quiet[i] = 0.0005 * sin(float(i) * 0.37)
	gate.process(quiet, rate)
	var tone := PackedFloat32Array()
	tone.resize(rate / 2)
	for i in tone.size():
		tone[i] = 0.3 * sin(TAU * 220.0 * float(i) / float(rate))
	gate.process(tone, rate)
	gate.process(quiet, rate)
	check(gate.voice_start_sample >= 0, "the gate saw a voice start")
	near(float(gate.voice_start_sample), float(rate), rate * 0.03, "the onset is where the tone began (within 30 ms)")
	near(float(gate.voice_end_sample), float(rate + rate / 2), rate * 0.05, "the end is where it stopped")
	# The caster's utterance onset: the first voice span after the previous utterance's voice ended.
	var caster := VoiceCaster.new()
	caster._span_starts = [1.0, 2.5, 2.9] as Array[float]
	caster._prev_voice_end = 2.0
	near(caster._utterance_onset(), 2.5, 0.0001, "an utterance starts at its first span after the last one ended")
	caster._prev_voice_end = 3.5
	eq(caster._utterance_onset(), -1.0, "no span since: unknown")
	caster.free()
