extends MonsterTestBase
## The refactor safety net (docs/design/refactor-plan.md, wave 0): ten contract seeds (every client archetype twice) x
## floors 1-3, each built the way the game builds it (DungeonGen.for_run, SiteBuilder.plan + spawn, NetFloor.assign_ids),
## must reproduce the recorded floor exactly: the NetFloor checksum (map, plan, run, spawn), every site plan field's hash,
## the cell and actor counts and the number of net ids. Online play hangs on this (the load barrier compares the same
## checksum on every machine), and so does every seed a player has seen.
##
## A change that is MEANT to change floors (new content in the generator, a retuned planner) re-records the file and says
## so in its commit:
##   $env:CAST_GOLDEN_RECORD = "1"; .\test_runner.ps1 -TestName test_golden_floor; Remove-Item Env:CAST_GOLDEN_RECORD
## A refactor must never need that.

const SEEDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
const FLOORS := 3
const PATH := "res://tests/golden/floors.json"
const PARTS: Array[String] = ["all", "map", "plan", "run", "spawn"]


func setup() -> void:
	timeout_sec = 300.0
	Monster.use_proto_visuals = true   # (the checksum reads positions, ids and stats, never the meshes)
	var got := {}
	for s in SEEDS:
		for f in range(1, FLOORS + 1):
			got["%d/%d" % [s, f]] = _build(s, f)
	Monster.use_proto_visuals = false
	if OS.get_environment("CAST_GOLDEN_RECORD") == "1":
		_record(got)
	else:
		_compare(got)
	finish()


## Seed `s`'s floor `f` as the game builds it; a summary of its checksum.
func _build(s: int, f: int) -> Dictionary:
	var run := ContractBoard.run_for_seed(s)
	var map := DungeonGen.for_run(run, f)
	new_world(map)
	GameWorld.begin(map, world, run.floor_seed(f))
	var plan := SiteBuilder.plan(map, run, f, ContractParts.prop_catalog(run.site_type))
	SiteBuilder.spawn(map, run, plan)
	var ids := NetFloor.assign_ids(world, {})
	var sum := NetFloor.checksum(map, plan, run, world)
	var out := {"ids": ids, "cells": int(sum["cells"]), "actors": int(sum["actors"]), "plan_keys": sum["plan_keys"]}
	for k in PARTS:
		out[k] = str(sum[k])
	return out


func _record(got: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PATH.get_base_dir()))
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	check(file != null, "can write %s" % PATH)
	if file != null:
		file.store_string(JSON.stringify(got, "\t", true))
		file.close()
	print("[golden] recorded %d floors to %s" % [got.size(), PATH])


func _compare(got: Dictionary) -> void:
	if not check(FileAccess.file_exists(PATH), "the recorded floors exist (%s); record them with CAST_GOLDEN_RECORD=1" % PATH):
		return
	var want: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	eq(got.keys().size(), want.keys().size(), "the same floors as recorded")
	for key: String in want:
		var w: Dictionary = want[key]
		var g: Dictionary = got.get(key, {})
		if str(g.get("all", "")) == str(w["all"]) and int(g.get("ids", -1)) == int(w["ids"]):
			continue
		# Say which part moved, and for the site plan which fields.
		var parts: Array[String] = []
		for k in PARTS:
			if str(g.get(k, "")) != str(w[k]):
				parts.append(k)
		var fields: Array[String] = []
		var gk: Dictionary = g.get("plan_keys", {})
		for field: String in (w["plan_keys"] as Dictionary):
			if str(gk.get(field, "")) != str(w["plan_keys"][field]):
				fields.append(field)
		for field: String in gk:
			if not (w["plan_keys"] as Dictionary).has(field):
				fields.append(field + " (new)")
		check(false, "seed/floor %s matches the recorded floor: %s differ%s; ids %d vs %d, actors %d vs %d, cells %d vs %d" % [
			key, ", ".join(parts), " (plan fields: %s)" % ", ".join(fields) if not fields.is_empty() else "",
			int(g.get("ids", -1)), int(w["ids"]), int(g.get("actors", -1)), int(w["actors"]), int(g.get("cells", -1)), int(w["cells"])])
