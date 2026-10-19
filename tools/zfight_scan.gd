extends Node
## The full z-fighting scan (ZFightCheck over ZFightModels): every model and stack, the menu garage in its three moods
## and generated floors of every client archetype, built with LowPoly.trace on so each finding names the code that made
## its pieces. Writes a ranked report and quits.
##
##   godot --path . --headless -- --scene res://tools/zfight_scan.tscn --out <report.txt> [--only <name part>] [--seeds 2]

const SEVERE_CM2 := 5.0          ## the test's threshold (tests/test_zfight.gd): one pixel at the default game zoom


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out_path := _arg(a, "--out", "user://zfight_report.txt")
	var only := _arg(a, "--only", "")
	var seeds := int(_arg(a, "--seeds", "2"))
	LowPoly.trace = not a.has("--no-trace")
	ZFightModels.verbose = a.has("--verbose")
	var t0 := Time.get_ticks_msec()
	var found: Array[Dictionary] = []
	found.append_array(await ZFightModels.scan(self, only))
	var t_models := Time.get_ticks_msec() - t0
	if only == "" or "menu".contains(only):
		for mood: String in ["dawn", "night", "after"]:
			found.append_array(await ZFightModels.scan_menu(self, mood))
	var floors := 0
	if only == "" or "site".contains(only):
		for arch: String in ClientArchetype.IDS:
			for s in seeds:
				for f in range(1, ContractRun.FLOOR_COUNT + 1):
					found.append_array(await ZFightModels.scan_site(self, arch, 7 + s * 31, f))
					floors += 1
	found.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["shown_cm2"]) > float(y["shown_cm2"]))
	var lines := PackedStringArray()
	lines.append("Z-fighting scan (ZFightCheck): EPS %.1f mm, parallel within %.0f deg, min area %.2f cm2, same-look weight %.2f" % [
			ZFightCheck.EPS * 1000.0, ZFightCheck.PARALLEL_DEG, ZFightCheck.MIN_AREA_M2 * 10000.0, ZFightCheck.SAME_LOOK_WEIGHT])
	lines.append("%d models and stacks (%d ms), 3 menu moods, %d generated floors" % [ZFightModels.models().size() + ZFightModels.stacks().size(), t_models, floors])
	var bands := [[SEVERE_CM2, INF, "severe (>= %.0f cm2 shown: the test's bar)" % SEVERE_CM2], [1.0, SEVERE_CM2, "moderate (1 .. %.0f)" % SEVERE_CM2], [1e-9, 1.0, "minor (< 1)"], [-1.0, 1e-9, "hidden (no camera sees it)"]]
	for b: Array in bands:
		var n := 0
		for f in found:
			var sv := float(f["shown_cm2"])
			if sv >= float(b[0]) and sv < float(b[1]):
				n += 1
		lines.append("  %-40s %d" % [b[2], n])
	var per_scene := {}
	for f in found:
		var key := String(f["scene"]).get_slice("/", 0)
		per_scene[key] = int(per_scene.get(key, 0)) + 1
	lines.append("  by scene kind: %s" % str(per_scene))
	lines.append("")
	var rank := 0
	for f in found:
		rank += 1
		lines.append("#%d  %s" % [rank, f["scene"]])
		lines.append("   " + ZFightCheck.describe(f))
	var text := "\n".join(lines)
	var fa := FileAccess.open(out_path, FileAccess.WRITE)
	if fa != null:
		fa.store_string(text)
		fa.close()
	print(text.substr(0, 6000))
	print("report: ", out_path, " (", found.size(), " findings, ", Time.get_ticks_msec() - t0, " ms)")
	get_tree().quit(0)


static func _arg(a: PackedStringArray, flag: String, def: String = "") -> String:
	var i := a.find(flag)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else def
