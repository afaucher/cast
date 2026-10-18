extends TestCase
## PlayLog: every real play writes a contract row, one row per floor with its time, and an end row (passive, no UI).


func setup() -> void:
	var path := "user://test_play_log.csv"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	PlayLog.path = path
	PlayLog.enabled = true
	var run := ContractRun.make("prepper", 7, 0.5)
	var s := ContractSession.begin(run)
	GameWorld.time = 100.0
	s.enter_floor(1, 2, false, 3, 10)
	GameWorld.time = 160.0
	s.enter_floor(2, 2, false, 3, 10)
	GameWorld.time = 205.5
	s.finish(ContractSession.END_CASHED_OUT)
	s.finish(ContractSession.END_CASHED_OUT)   # idempotent: no second end row
	PlayLog.enabled = false
	PlayLog.path = PlayLog.PATH

	var lines := FileAccess.get_file_as_string(path).strip_edges().split("\n")
	eq(lines[0].strip_edges(), PlayLog.HEADER, "a header")
	eq(lines.size(), 5, "contract, floor 1, floor 2, end")
	var events: Array[String] = []
	for i in range(1, lines.size()):
		events.append(lines[i].split(",")[2])
	eq(events, ["contract", "floor", "floor", "end"] as Array[String], "the rows in order")
	var cols := PlayLog.HEADER.split(",")
	var f1 := lines[2].split(",")
	eq(f1[cols.find("floor")], "1", "floor 1 row")
	eq(f1[cols.find("floor_s")], "60.0", "floor 1 took 60 game seconds")
	eq(f1[cols.find("reason")], "elevator", "left by the elevator")
	var f2 := lines[3].split(",")
	eq(f2[cols.find("floor_s")], "45.5", "floor 2 took 45.5 s")
	eq(f2[cols.find("reason")], ContractSession.END_CASHED_OUT, "and ended the contract")
	var end := lines[4].split(",")
	eq(end[cols.find("role")], "solo", "a solo play")
	check(end[cols.find("payout")] != "", "the end row has the payout")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	finish()
