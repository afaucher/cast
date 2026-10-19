class_name RoomThemeDefs
extends RefCounted
## Data for the room themes (docs/design/environment.md, "Room themes" + "Decisions (2026-10-17)"):
## which themes each site type draws from, what each theme dresses its room with, the accent light,
## the story-origin -> theme table, and the placement / orientation rule of every decor kind.
##
## Placement rules (where a prop goes):    Orientation rules (which way it faces):
##   wall    back to the nearest wall        away_from_wall  into the room, along the wall's normal
##   corner  in a concave corner             face_center     toward the room's centre
##   center  at the room's focal point       face_entrance   toward the room's main door
##   floor   free-standing                   face_start      toward the crew's start cell
##   group   a member of a vignette          face_target     toward the table / screen / rack / desk / pool it belongs to
##   ring    on a ring around a centrepiece  parallel        every piece of the set faces the same way
##                                           free            round / flat things: any yaw
## Priced props declare theirs in PricedProp.TABLE ("place", "orient", "foot").

const SERVICE := "service_entrance"     ## the start room's theme

const POOLS := {
	"bunker": ["wine_cellar", "home_cinema", "spa", "gym", "server_room", "panic_room", "pool"],
	"lair": ["torture_chamber", "throne_room", "lab", "barracks", "moat", "science"],
}

## Story origin ("where it started", ClientArchetype events) -> the theme of the floor-3 origin room.
## Every origin text a client can roll must be here (tests/test_room_themes.gd checks it).
const ORIGIN_THEMES := {
	# prepper billionaire
	"wine cellar": "wine_cellar",
	"home cinema": "home_cinema",
	"panic room": "panic_room",
	# wellness guru
	"yoga studio": "spa",
	"meditation dome": "spa",
	"cold plunge": "pool",
	# influencer
	"content studio": "home_cinema",      ## ring lights and a big screen
	"gifting suite": "wine_cellar",       ## shelves of free stuff
	"podcast room": "server_room",        ## desks, monitors, mics
	# supervillain
	"henchmen barracks": "barracks",
	"throne room": "throne_room",
	"vat room": "lab",
	# tech founder (a lair site)
	"keynote stage": "throne_room",       ## a stage, a podium and a red carpet
	"data center": "lab",
	"ping-pong lounge": "barracks",
}

## Keyword fallback for an origin text that is not in ORIGIN_THEMES.
const ORIGIN_KEYWORDS := {
	"wine": "wine_cellar", "cellar": "wine_cellar", "cinema": "home_cinema", "movie": "home_cinema",
	"yoga": "spa", "spa": "spa", "dome": "spa", "plunge": "pool", "pool": "pool", "gym": "gym",
	"server": "server_room", "data": "server_room", "panic": "panic_room", "vault": "panic_room",
	"torture": "torture_chamber", "dungeon": "torture_chamber", "throne": "throne_room", "stage": "throne_room",
	"vat": "lab", "lab": "lab", "barrack": "barracks", "moat": "moat", "shark": "moat",
	"science": "science", "specimen": "science",
}

## id -> {name, site, min_cells (the smallest room it is dealt), priced (PricedProp kinds it prefers),
##        recipe (ops run in order while the room's decor budget lasts), light (the accent light),
##        needs_center (true: its centrepiece wants the middle of the room, so it is not dealt to the exit room or to a
##        room with a hellgate in the middle), avoid_exit (not dealt to the exit room: the elevator sits in its middle)}.
## Recipe ops are implemented in ThemeVignettes.
const THEMES := {
	"wine_cellar": {
		"name": "Wine cellar", "site": "bunker", "min_cells": 70,
		"priced": ["wine_rack", "wine_barrel"],
		"recipe": [
			{"op": "sign", "text": "WINE", "color": Color(1.0, 0.18, 0.32)},
			{"op": "tasting", "min_cells": 100},
			{"op": "barrels"},
			{"op": "barrels", "min_cells": 120},
		],
		"light": {"color": Color(1.0, 0.36, 0.28), "energy": 6.4, "range": 8.5, "flicker": 0.12},
	},
	"home_cinema": {
		"name": "Home cinema", "site": "bunker", "min_cells": 100,
		"priced": ["projector"],
		"recipe": [
			{"op": "sign", "text": "FILM", "color": Color(1.0, 0.3, 0.3)},
			{"op": "cinema"},
			{"op": "popcorn"},
		],
		"light": {"color": Color(0.4, 0.65, 1.0), "energy": 7.2, "range": 9.0, "flicker": 0.55},
	},
	"spa": {
		"name": "Wellness spa", "site": "bunker", "min_cells": 90,
		"priced": ["zen_fountain", "crystal_lamp"],
		"recipe": [
			{"op": "sign", "text": "OM", "color": Color(0.7, 0.45, 1.0)},
			{"op": "circle"},
			{"op": "mats"},
		],
		"light": {"color": Color(1.0, 0.68, 0.34), "energy": 6.8, "range": 8.5, "flicker": 0.35},
	},
	"gym": {
		"name": "Gym", "site": "bunker", "min_cells": 60,
		"priced": ["treadmill"],
		"recipe": [
			{"op": "sign", "text": "GYM", "color": Color(0.35, 0.9, 1.0)},
			{"op": "bench_rack"},
			{"op": "dumbbells"},
		],
		"light": {"color": Color(0.75, 0.92, 1.0), "energy": 6.0, "range": 8.5, "flicker": 0.0},
	},
	"server_room": {
		"name": "Server room", "site": "bunker", "min_cells": 60,
		"priced": ["server_rack"],
		"recipe": [
			{"op": "racks"},
			{"op": "desk"},
		],
		"light": {"color": Color(0.3, 1.0, 0.6), "energy": 6.0, "range": 8.0, "flicker": 0.25},
	},
	"panic_room": {
		"name": "Panic room", "site": "bunker", "min_cells": 60,
		"priced": ["gold_toilet"],
		"recipe": [
			{"op": "sign", "text": "PANIC", "color": Color(1.0, 0.12, 0.1)},
			{"op": "desk"},
			{"op": "crates"},
		],
		"light": {"color": Color(1.0, 0.14, 0.1), "energy": 6.8, "range": 8.5, "flicker": 0.0, "pulse": 0.5},
	},
	"pool": {
		## an in-ground pool (PoolGeo, carved by SiteBuilder before the decor) with loungers along its long sides
		"name": "Indoor pool", "site": "bunker", "min_cells": 100, "needs_center": true,
		"priced": ["marble_statue"],
		"recipe": [
			{"op": "sign", "text": "POOL", "color": Color(0.3, 0.95, 1.0)},
			{"op": "pool"},
		],
		"light": {"color": Color(0.25, 0.85, 0.95), "energy": 6.8, "range": 9.0, "flicker": 0.2},
	},
	"torture_chamber": {
		"name": "Torture chamber", "site": "lair", "min_cells": 60,
		"priced": ["torture_rack", "brazier"],
		"recipe": [
			{"op": "cage"},
			{"op": "cage", "min_cells": 110},
		],
		"light": {"color": Color(1.0, 0.24, 0.12), "energy": 7.2, "range": 8.5, "flicker": 0.4},
	},
	"throne_room": {
		"name": "Throne room", "site": "lair", "min_cells": 80,
		"priced": ["villain_throne", "doomsday_console", "evil_portrait"],
		"recipe": [
			{"op": "sign", "text": "EVIL", "color": Color(1.0, 0.2, 0.15), "dead": [3]},
			{"op": "carpet"},
		],
		"light": {"color": Color(1.0, 0.42, 0.18), "energy": 6.8, "range": 9.0, "flicker": 0.15},
	},
	"lab": {
		"name": "Lab / vat room", "site": "lair", "min_cells": 60,
		"priced": ["specimen_vat"],
		"recipe": [
			{"op": "sign", "text": "LAB", "color": Color(0.35, 1.0, 0.5)},
			{"op": "shelf"},
			{"op": "desk"},
			{"op": "shelf", "min_cells": 100},
		],
		"light": {"color": Color(0.3, 1.0, 0.5), "energy": 6.8, "range": 8.5, "flicker": 0.3},
	},
	"barracks": {
		"name": "Henchmen barracks", "site": "lair", "min_cells": 60,
		"priced": ["henchman_locker"],
		"recipe": [
			{"op": "bunks"},
			{"op": "bunks", "min_cells": 110},
		],
		"light": {"color": Color(0.95, 0.85, 0.4), "energy": 5.6, "range": 8.5, "flicker": 0.0},
	},
	"moat": {
		## a ring of wading water round an island (PoolGeo, LOOK_MOAT: real terrain, carved by SiteBuilder before the decor)
		## with two shark fins patrolling it, its bridge pulled back onto the deck and a fin hazard sign
		"name": "Shark moat", "site": "lair", "min_cells": 80, "avoid_exit": true, "needs_center": true,
		"priced": ["shark_tank"],
		"recipe": [
			{"op": "moat"},
		],
		"light": {"color": Color(0.2, 0.85, 0.8), "energy": 6.8, "range": 9.0, "flicker": 0.2},
	},
	"science": {
		## a green specimen pool (PoolGeo, the gantry with its dangling cage over it), the SCIENCE sign, specimen tanks, a lab
		## bench, a console, pipes and shelves
		"name": "Science", "site": "lair", "min_cells": 80, "needs_center": true,
		"priced": ["specimen_vat", "doomsday_console"],
		"recipe": [
			{"op": "sign", "text": "SCIENCE", "color": Color(0.72, 1.0, 0.22)},
			{"op": "specimen_pool"},
			{"op": "tanks"},
			{"op": "pipes"},
			{"op": "bench"},
			{"op": "console", "min_cells": 110},
			{"op": "shelf", "min_cells": 130},
		],
		"light": {"color": Color(0.45, 1.0, 0.4), "energy": 6.8, "range": 9.0, "flicker": 0.35},
	},
	"service_entrance": {
		"name": "Service entrance", "site": "any", "min_cells": 0,
		"priced": [],
		"recipe": [
			{"op": "hazard"},
			{"op": "hazard", "min_cells": 90},
			{"op": "wet_floor"},
		],
		"light": {"color": Color(1.0, 0.78, 0.25), "energy": 4.0, "range": 7.0, "flicker": 0.0},
	},
}

## Decor kinds (not priced, purely decorative). w/d = footprint (lateral x forward, world units), h = height,
## blocks = walk-blocking (an invisible neutral blocker actor), weight = share of the room's decor budget.
const DECOR := {
	"recliner": {"place": "group", "orient": "face_target", "w": 1.0, "d": 1.1, "h": 1.3, "blocks": false, "weight": 0.7},
	"cinema_screen": {"place": "wall", "orient": "away_from_wall", "w": 3.5, "d": 0.5, "h": 2.6, "blocks": false, "weight": 1.2},
	"popcorn_machine": {"place": "corner", "orient": "face_center", "w": 0.95, "d": 0.8, "h": 1.8, "blocks": true, "weight": 1.0},
	"yoga_mat": {"place": "floor", "orient": "parallel", "w": 0.75, "d": 1.9, "h": 0.06, "blocks": false, "weight": 0.3},
	"summoning_circle": {"place": "center", "orient": "free", "w": 4.2, "d": 4.2, "h": 0.06, "blocks": false, "weight": 1.0},
	"candle": {"place": "ring", "orient": "free", "w": 0.22, "d": 0.22, "h": 0.5, "blocks": false, "weight": 0.1},
	"dumbbell_rack": {"place": "wall", "orient": "away_from_wall", "w": 1.7, "d": 0.65, "h": 1.0, "blocks": true, "weight": 1.0},
	"weight_bench": {"place": "group", "orient": "face_target", "w": 0.6, "d": 1.6, "h": 0.6, "blocks": false, "weight": 0.5},
	"bunk_bed": {"place": "wall", "orient": "away_from_wall", "w": 2.0, "d": 1.05, "h": 1.6, "blocks": true, "weight": 1.0},
	"chains_cage": {"place": "corner", "orient": "face_center", "w": 1.2, "d": 1.2, "h": 2.2, "blocks": true, "weight": 1.0},
	"specimen_shelf": {"place": "wall", "orient": "away_from_wall", "w": 1.8, "d": 0.55, "h": 1.95, "blocks": true, "weight": 1.0},
	"neon_sign": {"place": "wall", "orient": "away_from_wall", "w": 1.9, "d": 0.4, "h": 2.2, "blocks": false, "weight": 0.5},
	"hazard_tape": {"place": "wall", "orient": "away_from_wall", "w": 2.4, "d": 0.3, "h": 0.9, "blocks": false, "weight": 0.3},
	"wet_floor_sign": {"place": "floor", "orient": "face_start", "w": 0.6, "d": 0.5, "h": 1.0, "blocks": false, "weight": 0.3},
	"pool_lounger": {"place": "group", "orient": "face_target", "w": 0.85, "d": 1.9, "h": 0.6, "blocks": false, "weight": 0.5},
	"specimen_tank": {"place": "corner", "orient": "face_center", "w": 1.5, "d": 1.5, "h": 2.1, "blocks": true, "weight": 1.0},
	"lab_bench": {"place": "wall", "orient": "away_from_wall", "w": 1.85, "d": 0.8, "h": 1.45, "blocks": true, "weight": 1.0},
	"lab_console": {"place": "wall", "orient": "away_from_wall", "w": 1.55, "d": 1.0, "h": 1.9, "blocks": true, "weight": 1.0},
	"pipe_run": {"place": "wall", "orient": "away_from_wall", "w": 3.4, "d": 0.45, "h": 1.0, "blocks": false, "weight": 0.5},
	"hazard_sign": {"place": "group", "orient": "face_target", "w": 0.9, "d": 0.3, "h": 1.85, "blocks": false, "weight": 0.3},
	"moat_bridge": {"place": "group", "orient": "face_target", "w": 1.4, "d": 2.3, "h": 0.2, "blocks": false, "weight": 0.5},
	"shark_fin": {"place": "ring", "orient": "free", "w": 0.4, "d": 0.8, "h": 0.6, "blocks": false, "weight": 0.2},
	"red_carpet": {"place": "floor", "orient": "away_from_wall", "w": 1.5, "d": 5.0, "h": 0.05, "blocks": false, "weight": 0.5},
	"tasting_table": {"place": "center", "orient": "face_entrance", "w": 1.5, "d": 1.5, "h": 1.0, "blocks": true, "weight": 1.0},
	"chair": {"place": "group", "orient": "face_target", "w": 0.6, "d": 0.6, "h": 1.0, "blocks": false, "weight": 0.4},
	"barrel": {"place": "group", "orient": "free", "w": 0.9, "d": 0.9, "h": 1.0, "blocks": true, "weight": 0.5},
	"desk": {"place": "wall", "orient": "away_from_wall", "w": 1.7, "d": 0.85, "h": 0.85, "blocks": true, "weight": 1.0},
	"monitor": {"place": "group", "orient": "away_from_wall", "w": 0.7, "d": 0.3, "h": 0.5, "blocks": false, "weight": 0.2},
	"office_chair": {"place": "group", "orient": "face_target", "w": 0.65, "d": 0.65, "h": 1.0, "blocks": false, "weight": 0.4},
	"rack_cab": {"place": "wall", "orient": "away_from_wall", "w": 0.95, "d": 0.85, "h": 2.0, "blocks": true, "weight": 1.0},
	"crate_stack": {"place": "corner", "orient": "face_center", "w": 1.15, "d": 1.15, "h": 1.3, "blocks": true, "weight": 1.0},
}

## Decor kinds that read as stacks of boxes or crates. They join the "breakables" group and smash like mail packages
## (no loot, no property damage); every other kind (shelves, racks, furniture, barrels) stays solid. Add a box-like
## kind here and it breaks too.
const BREAKABLE_DECOR: Array[String] = ["crate_stack"]


static func theme(id: String) -> Dictionary:
	return THEMES.get(id, {})


static func has_theme(id: String) -> bool:
	return THEMES.has(id)


static func pool(site_type: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in POOLS.get(site_type, POOLS["bunker"]):
		out.append(id)
	return out


static func theme_name(id: String) -> String:
	return String((THEMES.get(id, {}) as Dictionary).get("name", id))


## True for the decor kinds that read as boxes or crates: they break (BreakableCrate) instead of standing solid.
static func is_breakable(kind: String) -> bool:
	return BREAKABLE_DECOR.has(kind)


static func decor(kind: String) -> Dictionary:
	return DECOR.get(kind, {})


static func is_decor(kind: String) -> bool:
	return DECOR.has(kind)


## The theme the story's origin text names (e.g. "yoga studio" -> "spa") for this site type; always a
## theme of the site's pool.
static func origin_theme(site_type: String, origin: String) -> String:
	var p := pool(site_type)
	var key := origin.strip_edges().to_lower()
	var t: String = ORIGIN_THEMES.get(key, "")
	if t == "":
		for kw: String in ORIGIN_KEYWORDS:
			if key.contains(kw):
				t = ORIGIN_KEYWORDS[kw]
				break
	if t != "" and p.has(t):
		return t
	return p[0]
