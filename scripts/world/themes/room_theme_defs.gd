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
const SEWER := "sewer"                  ## a sewer cluster's rooms (SewerPlanner.theme; never dealt from a site's POOLS)
const LAVA := "lava"                    ## a lava cave's chambers (LavaPlanner.theme; never dealt from a site's POOLS)

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

## id -> {name, site, min_cells (the smallest room it is dealt), priced (PricedProp kinds it prefers), hazards (the
##        explosive props it may hold, ExplosiveProp: HazardPlanner.plan; none = a room without them),
##        recipe (ops run in order while the room's decor budget lasts), light (the accent light),
##        needs_center (true: its centrepiece wants the middle of the room, so it is not dealt to the exit room or to a
##        room with a hellgate in the middle), avoid_exit (not dealt to the exit room: the elevator sits in its middle),
##        note_word (the room as a note names it: "the {staff_room}" -> "the spa"; NoteFacts. Notes are in the floor plan,
##        so a changed word changes the floor), floor_mat (its floor material, FloorMaterials.F_*), wall_mat (its own
##        walls, FloorMaterials.W_*; none = the site's), pool_look (a pool carved into the room, PoolGeo.LOOK_*; none = no
##        pool)}.
## Recipe ops are implemented in ThemeVignettes. A new theme is one row here (and its id in POOLS), plus any new ops.
const THEMES := {
	"wine_cellar": {
		"name": "Wine cellar", "site": "bunker", "min_cells": 70,
		"note_word": "wine cellar", "floor_mat": FloorMaterials.F_WOOD, "wall_mat": FloorMaterials.W_PANELLING,
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
		"note_word": "home cinema", "floor_mat": FloorMaterials.F_CARPET, "wall_mat": FloorMaterials.W_PANELLING,
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
		"note_word": "spa", "floor_mat": FloorMaterials.F_TILE,
		"priced": ["zen_fountain", "crystal_lamp"],
		"hazards": ["propane_tank"],              ## the sauna heater's gas
		"recipe": [
			{"op": "sign", "text": "OM", "color": Color(0.7, 0.45, 1.0)},
			{"op": "circle"},
			{"op": "mats"},
		],
		"light": {"color": Color(1.0, 0.68, 0.34), "energy": 6.8, "range": 8.5, "flicker": 0.35},
	},
	"gym": {
		"name": "Gym", "site": "bunker", "min_cells": 60,
		"note_word": "gym", "floor_mat": FloorMaterials.F_RUBBER,
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
		"note_word": "server room", "floor_mat": FloorMaterials.F_DIAMOND,
		"priced": ["server_rack"],
		"hazards": ["battery_pack"],              ## the UPS
		"recipe": [
			{"op": "racks"},
			{"op": "desk"},
		],
		"light": {"color": Color(0.3, 1.0, 0.6), "energy": 6.0, "range": 8.0, "flicker": 0.25},
	},
	"panic_room": {
		"name": "Panic room", "site": "bunker", "min_cells": 60,
		"note_word": "panic room", "floor_mat": FloorMaterials.F_DIAMOND_DARK,
		"priced": ["gold_toilet"],
		"hazards": ["gas_cylinders", "battery_pack"],   ## the air supply and the backup power
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
		"note_word": "pool room", "floor_mat": FloorMaterials.F_POOL_TILE, "pool_look": PoolGeo.LOOK_POOL,
		"priced": ["marble_statue"],
		"hazards": ["propane_tank"],              ## the pool heater
		"recipe": [
			{"op": "sign", "text": "POOL", "color": Color(0.3, 0.95, 1.0)},
			{"op": "pool"},
		],
		"light": {"color": Color(0.25, 0.85, 0.95), "energy": 6.8, "range": 9.0, "flicker": 0.2},
	},
	"torture_chamber": {
		"name": "Torture chamber", "site": "lair", "min_cells": 60,
		"note_word": "torture chamber", "floor_mat": FloorMaterials.F_FLAGSTONE,
		"priced": ["torture_rack", "brazier"],
		"hazards": ["oil_drum"],                  ## lamp oil for the braziers
		"recipe": [
			{"op": "cage"},
			{"op": "cage", "min_cells": 110},
		],
		"light": {"color": Color(1.0, 0.24, 0.12), "energy": 7.2, "range": 8.5, "flicker": 0.4},
	},
	"throne_room": {
		"name": "Throne room", "site": "lair", "min_cells": 80,
		"note_word": "throne room", "floor_mat": FloorMaterials.F_MARBLE, "wall_mat": FloorMaterials.W_MARBLE,
		"priced": ["villain_throne", "doomsday_console", "evil_portrait"],
		"recipe": [
			{"op": "sign", "text": "EVIL", "color": Color(1.0, 0.2, 0.15), "dead": [3]},
			{"op": "carpet"},
		],
		"light": {"color": Color(1.0, 0.42, 0.18), "energy": 6.8, "range": 9.0, "flicker": 0.15},
	},
	"lab": {
		"name": "Lab / vat room", "site": "lair", "min_cells": 60,
		"note_word": "lab", "floor_mat": FloorMaterials.F_LAB_TILE,
		"priced": ["specimen_vat"],
		"hazards": ["gas_cylinders"],             ## lab gas
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
		"note_word": "barracks", "floor_mat": FloorMaterials.F_CONCRETE,
		"priced": ["henchman_locker"],
		"hazards": ["oil_drum"],                  ## the generator's fuel
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
		"note_word": "shark moat", "floor_mat": FloorMaterials.F_FLAGSTONE, "pool_look": PoolGeo.LOOK_MOAT,
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
		"note_word": "science room", "floor_mat": FloorMaterials.F_LAB_TILE, "pool_look": PoolGeo.LOOK_SPECIMEN,
		"priced": ["specimen_vat", "doomsday_console"],
		"hazards": ["gas_cylinders", "oil_drum"], ## lab gas, and drums of whatever is in the pool
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
		"note_word": "service entrance", "floor_mat": FloorMaterials.F_CONCRETE,
		"priced": [],
		"recipe": [
			{"op": "hazard"},
			{"op": "hazard", "min_cells": 90},
			{"op": "wet_floor"},
		],
		"light": {"color": Color(1.0, 0.78, 0.25), "energy": 4.0, "range": 7.0, "flicker": 0.0},
	},
	# The service level: the rooms of a sewer cluster (docs/design/sewer-concept.md, "Phase 3 as built"). Not in POOLS: only
	# SewerPlanner.theme gives it, to the cluster DungeonGen cut. The water, the sump grates, the outfall and the culvert bars
	# are SewerPlanner's (they follow the channels), the panel and the pumps HazardPlanner.plan_sewer's; its own recipe is the
	# wet-floor sign. Priced props: none of its own (the panel and the pumps are placed by the water), so a sewer room takes
	# any of the site's kinds, like a room whose theme has none in the catalog.
	"sewer": {
		"name": "Service level", "site": "any", "min_cells": 0,
		"note_word": "service level", "floor_mat": FloorMaterials.F_FLAGSTONE, "wall_mat": FloorMaterials.W_STONE,
		"priced": [],
		"recipe": [
			{"op": "wet_floor"},
		],
		"light": {"color": Color(0.78, 0.92, 0.5), "energy": 5.5, "range": 9.5, "flicker": 0.1},
	},
	# A lava cave's chambers (docs/design/lava-playtest.md, "As built"). Not in POOLS: only LavaPlanner.theme gives it, to the
	# cave CaveGen cut. Rock only: no priced props (a chamber has no walls to stand them on), no decor recipe. "lava" is the
	# look, by whether a hellgate leaks into the cave (LavaPlanner): the lava's colours (crust, hot, core), the glow, the
	# embers, the warm lights over the lava (how many: "lights", the measured budget), the rock's floor material and the
	# cliff tint. The name and the note word are PROPOSALS awaiting the user's review of the text (2026-10-21).
	"lava": {
		"name": "Magma chamber", "site": "any", "min_cells": 0,
		"note_word": "magma chamber", "floor_mat": FloorMaterials.F_BASALT, "wall_mat": FloorMaterials.W_BASALT,
		"priced": [],
		"recipe": [],
		"light": {"color": Color(1.0, 0.48, 0.18), "energy": 4.5, "range": 9.0, "flicker": 0.2},
		"lava": {
			"magma": {"crust": Color(0.09, 0.06, 0.05), "hot": Color(1.0, 0.36, 0.05), "core": Color(1.0, 0.82, 0.3),
				"glow": 2.4, "ember": Color(1.0, 0.55, 0.15), "light": Color(1.0, 0.45, 0.15), "lights": 10, "light_energy": 1.6,
				"floor_mat": FloorMaterials.F_BASALT, "cliff": Color(0.42, 0.36, 0.33)},
			"hellfire": {"crust": Color(0.1, 0.03, 0.04), "hot": Color(1.0, 0.16, 0.08), "core": Color(1.0, 0.55, 0.35),
				"glow": 2.6, "ember": Color(0.75, 0.35, 1.0), "light": Color(1.0, 0.25, 0.2), "lights": 10, "light_energy": 1.7,
				"floor_mat": FloorMaterials.F_BASALT_HELL, "cliff": Color(0.5, 0.3, 0.3)},
		},
	},
}

## Decor kinds (not priced, purely decorative). w/d = footprint (lateral x forward, world units), h = height,
## blocks = walk-blocking (an invisible neutral blocker actor), weight = share of the room's decor budget.
## The look (DecorModels.build): "model" = its DecorModels builder (func(s, params)), or "node_model" for a piece built on
## its own nodes (the neon sign); "after" = a DecorModels hook (func(root, params)) that adds its animation or extra
## children; "flat" = a floor decal (no ink outline, no shadow). "breakable" = it reads as boxes or crates: it joins the
## "breakables" group and smashes like a mail package (BreakableCrate: no loot, no property damage); every other kind
## (shelves, racks, furniture, barrels) stays solid. A new kind is one row here plus its builder in DecorModels.
const DECOR := {
	"recliner": {"place": "group", "orient": "face_target", "w": 1.0, "d": 1.1, "h": 1.3, "blocks": false, "weight": 0.7, "model": "_recliner"},
	"cinema_screen": {"place": "wall", "orient": "away_from_wall", "w": 3.5, "d": 0.5, "h": 2.6, "blocks": false, "weight": 1.2, "model": "_cinema_screen", "after": "_screen_after"},
	"popcorn_machine": {"place": "corner", "orient": "face_center", "w": 0.95, "d": 0.8, "h": 1.8, "blocks": true, "weight": 1.0, "model": "_popcorn_machine"},
	"yoga_mat": {"place": "floor", "orient": "parallel", "w": 0.75, "d": 1.9, "h": 0.06, "blocks": false, "weight": 0.3, "model": "_yoga_mat", "flat": true},
	"summoning_circle": {"place": "center", "orient": "free", "w": 4.2, "d": 4.2, "h": 0.06, "blocks": false, "weight": 1.0, "model": "_summoning_circle", "flat": true},
	"candle": {"place": "ring", "orient": "free", "w": 0.22, "d": 0.22, "h": 0.5, "blocks": false, "weight": 0.1, "model": "_candle", "after": "_candle_after"},
	"dumbbell_rack": {"place": "wall", "orient": "away_from_wall", "w": 1.7, "d": 0.65, "h": 1.0, "blocks": true, "weight": 1.0, "model": "_dumbbell_rack"},
	"weight_bench": {"place": "group", "orient": "face_target", "w": 0.6, "d": 1.6, "h": 0.6, "blocks": false, "weight": 0.5, "model": "_weight_bench"},
	"bunk_bed": {"place": "wall", "orient": "away_from_wall", "w": 2.0, "d": 1.05, "h": 1.6, "blocks": true, "weight": 1.0, "model": "_bunk_bed"},
	"chains_cage": {"place": "corner", "orient": "face_center", "w": 1.2, "d": 1.2, "h": 2.2, "blocks": true, "weight": 1.0, "model": "_chains_cage"},
	"specimen_shelf": {"place": "wall", "orient": "away_from_wall", "w": 1.8, "d": 0.55, "h": 1.95, "blocks": true, "weight": 1.0, "model": "_specimen_shelf"},
	"neon_sign": {"place": "wall", "orient": "away_from_wall", "w": 1.9, "d": 0.4, "h": 2.2, "blocks": false, "weight": 0.5, "node_model": "_neon_sign"},
	"hazard_tape": {"place": "wall", "orient": "away_from_wall", "w": 2.4, "d": 0.3, "h": 0.9, "blocks": false, "weight": 0.3, "model": "_hazard_tape"},
	"wet_floor_sign": {"place": "floor", "orient": "face_start", "w": 0.6, "d": 0.5, "h": 1.0, "blocks": false, "weight": 0.3, "model": "_wet_floor_sign", "after": "_wet_after"},
	"pool_lounger": {"place": "group", "orient": "face_target", "w": 0.85, "d": 1.9, "h": 0.6, "blocks": false, "weight": 0.5, "model": "_pool_lounger"},
	"specimen_tank": {"place": "corner", "orient": "face_center", "w": 1.5, "d": 1.5, "h": 2.1, "blocks": true, "weight": 1.0, "model": "_specimen_tank", "after": "_tank_after"},
	"lab_bench": {"place": "wall", "orient": "away_from_wall", "w": 1.85, "d": 0.8, "h": 1.45, "blocks": true, "weight": 1.0, "model": "_lab_bench"},
	"lab_console": {"place": "wall", "orient": "away_from_wall", "w": 1.55, "d": 1.0, "h": 1.9, "blocks": true, "weight": 1.0, "model": "_lab_console"},
	"pipe_run": {"place": "wall", "orient": "away_from_wall", "w": 3.4, "d": 0.45, "h": 1.0, "blocks": false, "weight": 0.5, "model": "_pipe_run", "backed": true},
	"hazard_sign": {"place": "group", "orient": "face_target", "w": 0.9, "d": 0.3, "h": 1.85, "blocks": false, "weight": 0.3, "model": "_hazard_sign"},
	"moat_bridge": {"place": "group", "orient": "face_target", "w": 1.4, "d": 2.3, "h": 0.2, "blocks": false, "weight": 0.5, "model": "_moat_bridge"},
	"shark_fin": {"place": "ring", "orient": "free", "w": 0.4, "d": 0.8, "h": 0.6, "blocks": false, "weight": 0.2, "model": "_shark_fin", "after": "_fin_after"},
	"red_carpet": {"place": "floor", "orient": "away_from_wall", "w": 1.5, "d": 5.0, "h": 0.05, "blocks": false, "weight": 0.5, "model": "_red_carpet", "flat": true},
	"tasting_table": {"place": "center", "orient": "face_entrance", "w": 1.5, "d": 1.5, "h": 1.0, "blocks": true, "weight": 1.0, "model": "_tasting_table"},
	"chair": {"place": "group", "orient": "face_target", "w": 0.6, "d": 0.6, "h": 1.0, "blocks": false, "weight": 0.4, "model": "_chair"},
	"barrel": {"place": "group", "orient": "free", "w": 0.9, "d": 0.9, "h": 1.0, "blocks": true, "weight": 0.5, "model": "_barrel"},
	"desk": {"place": "wall", "orient": "away_from_wall", "w": 1.7, "d": 0.85, "h": 0.85, "blocks": true, "weight": 1.0, "model": "_desk"},
	"monitor": {"place": "group", "orient": "away_from_wall", "w": 0.7, "d": 0.3, "h": 0.5, "blocks": false, "weight": 0.2, "model": "_monitor"},
	"office_chair": {"place": "group", "orient": "face_target", "w": 0.65, "d": 0.65, "h": 1.0, "blocks": false, "weight": 0.4, "model": "_office_chair"},
	"rack_cab": {"place": "wall", "orient": "away_from_wall", "w": 0.95, "d": 0.85, "h": 2.0, "blocks": true, "weight": 1.0, "model": "_rack_cab"},
	"crate_stack": {"place": "corner", "orient": "face_center", "w": 1.15, "d": 1.15, "h": 1.3, "blocks": true, "weight": 1.0, "model": "_crate_stack", "breakable": true},
	# the sewer's decor kit (docs/design/sewer-concept.md, phase 1: the six that read most; SewerLayouts places them, no
	# theme recipe uses them yet): an outfall pipe pouring into a channel, a pipe run on a wall, a floor grate, a sluice
	# gate across a doorway (the plate raised over the water), iron bars across a culvert, a maintenance tool cart
	"outfall": {"place": "wall", "orient": "away_from_wall", "w": 1.4, "d": 1.3, "h": 1.9, "blocks": false, "weight": 0.5, "model": "_outfall"},
	"pipe_bundle": {"place": "wall", "orient": "away_from_wall", "w": 4.0, "d": 0.45, "h": 1.3, "blocks": false, "weight": 0.5, "model": "_pipe_bundle"},
	"grate": {"place": "floor", "orient": "free", "w": 1.6, "d": 1.6, "h": 0.06, "blocks": false, "weight": 0.2, "model": "_grate", "flat": true},
	"sluice": {"place": "wall", "orient": "away_from_wall", "w": 3.3, "d": 0.3, "h": 2.2, "blocks": false, "weight": 0.5, "model": "_sluice"},
	"bars": {"place": "wall", "orient": "away_from_wall", "w": 2.8, "d": 0.2, "h": 1.3, "blocks": false, "weight": 0.3, "model": "_bars"},
	"tool_cart": {"place": "group", "orient": "face_target", "w": 0.85, "d": 0.5, "h": 0.95, "blocks": true, "weight": 0.5, "model": "_tool_cart"},
}


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


## True for the decor kinds that read as boxes or crates ("breakable"): they break (BreakableCrate) instead of standing
## solid.
static func is_breakable(kind: String) -> bool:
	return bool(decor(kind).get("breakable", false))


## Every breakable decor kind, in table order.
static func breakable_kinds() -> Array[String]:
	var out: Array[String] = []
	for k: String in DECOR:
		if is_breakable(k):
			out.append(k)
	return out


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
