class_name MoveFeel
extends RefCounted
## Movement-feel profiles (docs/design/movement-research.md §5.2 and "As built"): one data table, like HeroKit, so two
## ways of moving can be tried side by side. `today` is the game exactly as it was (every key at its OFF value: the old
## code paths run, frame for frame: test_move_feel_today holds it to a recorded trace); `grounded` is package A;
## `grounded_anim` is grounded plus the animation track's treatment B (a lean that leads the velocity, squash on start and
## stop, the stride held while shoved or airborne: HeroFeel) and the strike-first melee with each hero's hit area reshaped
## to its weapon (docs/design/animation-research.md "As built"). Every hero, the camera and the AI allies read the ACTIVE
## profile here; nothing else stores a copy.
##
##   --move-feel today|grounded|grounded_anim|shuffle   (default today: normal play stays as it was until the user picks)
##   --physics-interp on|off              (default off) the owned heroes drawn between physics ticks (Hero, "judder")
##   F6  next profile (the tag names it for a moment; in shuffle the tag says only "feel 1" / "feel 2": blind)
##   F7  physics interpolation on / off
##
## SHUFFLE (the blind A/B): the BLIND profiles (grounded and grounded_anim: the question being asked now) are dealt in a
## random order as "feel 1", "feel 2"; the run starts on feel 1 and F6 moves to the next (today stays selectable by name). Which is which is printed when the order is dealt and written with every row of user://move_lab.csv
## (MoveLog), never shown on screen.
##
## A CREW (networking): the HOST's profile is everyone's. It goes out with the job (CrewFlow.host_pick puts `feel` in
## crew.job, which a late joiner gets too) like the seed: spawn data for the run, nothing streamed. A client's own flag
## and F6 are ignored while it is in a crew (F6 says "set by the host"). The reasons: a puppet's stride, hop and landing
## are drawn on every screen from the shown motion with the profile THAT screen has, so the crew must agree on it; an A/B
## in a crew compares like with like; and a later profile with a dodge is gameplay every machine must agree on.
## Physics interpolation is each machine's own (it only changes how this screen draws its own heroes).

const TODAY := "today"
const GROUNDED := "grounded"
const GROUNDED_ANIM := "grounded_anim"
const SHUFFLE := "shuffle"
## The real profiles, in F6 order.
const ORDER: Array[String] = [TODAY, GROUNDED, GROUNDED_ANIM]
## The profiles shuffle deals (the A/B asked now: user, 2026-10-22, "Animation B + strike-first" on top of grounded).
const BLIND: Array[String] = [GROUNDED, GROUNDED_ANIM]

## What every key means when a profile does not set it: the game as it was (`today` sets nothing).
const OFF := {
	"envelope": false,      ## walking has a velocity with start / stop / turn rates (HeroMotion)
	"boost": 1.0,           ## share of full speed on the first frame of a fresh start
	"start": 0.0,           ## seconds from the boost to full speed
	"stop": 0.0,            ## seconds from full speed to rest
	"reversal": 0.0,        ## seconds from full speed one way to full speed the other (also any turn of more than 60 degrees)
	"hop": false,           ## a +1 step is a hop arc
	"hop_time": 0.0,
	"hop_peak": 0.0,        ## world units above the step's top at the apex
	"mantle": false,        ## a +2 climb is a mantle: held at the lip, then a rise
	"mantle_hold": 0.0,     ## seconds held at the lip (default; per kit in mantle_hold_kits)
	"mantle_hold_kits": {},
	"mantle_rise": 0.0,
	"gravity": 0.0,         ## u/s^2 on a walked-off drop (0: today's eased settle)
	"land_slow": 1.0,       ## a landing from LAND_BIG_LEVELS or more keeps this share of the walking speed (then ramps back)
	"gait": false,          ## the legs from the distance walked, hips toward the motion, lean, landing squash (HeroGait)
	"footsteps": false,     ## a dry footstep per stride (the floor's material)
	"dust": false,          ## dust puffs on a start, a hard stop, a sharp turn and a big landing
	"cam_lead": 0.0,        ## world units the camera leads along the walking velocity
	"cam_lead_time": 0.35,  ## seconds the lead's velocity is smoothed over
	"cam_aim_share": 0.0,   ## ... plus this share of the way toward the aim
	"cam_lead_max": 0.0,
	"ally_arrive": 0.0,     ## an AI ally slows inside this many units of its slot
	"ally_catchup": 1.0,    ## ... and walks this much faster while far behind a moving leader
	"ally_catchup_dist": 0.0,
	"body": false,          ## treatment B (HeroFeel): the lean, the squash, the stride held while shoved or airborne
	"strike_first": false,  ## the melee pose lands on the frame the hit resolves (HeroFeel's strike), a lunge, a 3-frame hit-stop
	"melee_areas": {},      ## kit -> the primary's hit area (Hero.melee_area); a kit not listed keeps its own wedge
}

## The table. Numbers are the doc's package A starting points, tuned by measurement where the "As built" section says so.
const PROFILES := {
	TODAY: {},
	GROUNDED: {
		"envelope": true, "boost": 0.45, "start": 0.08, "stop": 0.07, "reversal": 0.10,
		"hop": true, "hop_time": 0.12, "hop_peak": 0.15,
		"mantle": true, "mantle_hold": 0.25, "mantle_hold_kits": {"wick": 0.15, "gasket": 0.40}, "mantle_rise": 0.15,
		"gravity": 24.0, "land_slow": 0.4,
		"gait": true, "footsteps": true, "dust": true,
		"cam_lead": 1.2, "cam_lead_time": 0.35, "cam_aim_share": 0.15, "cam_lead_max": 2.0,
		"ally_arrive": 1.0, "ally_catchup": 1.15, "ally_catchup_dist": 3.2,
	},
	# grounded + the animation track (animation-research.md "As built"). The hit areas are a balance PROPOSAL, measured from
	# where each weapon travels in the strike-first swing (anim_lab --overlay): "arc" is today's wedge (reach, arc); "lane"
	# is Combat.melee_lane (everything within `radius` of the line from `near` to `far` ahead; near == far: a disc).
	GROUNDED_ANIM: {
		"envelope": true, "boost": 0.45, "start": 0.08, "stop": 0.07, "reversal": 0.10,
		"hop": true, "hop_time": 0.12, "hop_peak": 0.15,
		"mantle": true, "mantle_hold": 0.25, "mantle_hold_kits": {"wick": 0.15, "gasket": 0.40}, "mantle_rise": 0.15,
		"gravity": 24.0, "land_slow": 0.4,
		"gait": true, "footsteps": true, "dust": true,
		"cam_lead": 1.2, "cam_lead_time": 0.35, "cam_aim_share": 0.15, "cam_lead_max": 2.0,
		"ally_arrive": 1.0, "ally_catchup": 1.15, "ally_catchup_dist": 3.2,
		"body": true, "strike_first": true,
		"melee_areas": {
			"wick": {"shape": "arc", "reach": 1.3, "arc": 90.0},
			"gasket": {"shape": "lane", "near": 0.6, "far": 1.9, "radius": 0.25},
			"rebar": {"shape": "lane", "near": 1.05, "far": 1.05, "radius": 0.85},
		},
	},
}
## A landing from this many levels or more is a big one (dust, a thud, the landing slowdown).
const LAND_BIG_LEVELS := 2

## What the command line (or a test) asked for: today, grounded or shuffle.
static var mode := TODAY
## The profile this machine plays when it is not in a crew.
static var local_id := TODAY
## Shuffle: the profiles in their dealt order ("feel 1" is blind_order[0]) and where F6 is.
static var blind_order: Array[String] = []
static var blind_index := 0
## The host's profile for the crew's run ("" = none: this machine's own), and whether it was blind.
static var crew_id := ""
static var crew_blind := false
## Physics interpolation of this machine's own heroes (F7, --physics-interp).
static var interp := false
## Times the profile changed this run (F6), for the log.
static var switches := 0
static var _booted := false


## Read the flags once per run (the game, the arena and Boot call it; tests call reset() and set_mode()).
static func boot(args: PackedStringArray = OS.get_cmdline_user_args()) -> void:
	if _booted:
		return
	_booted = true
	var i := args.find("--move-feel")
	if i >= 0 and i + 1 < args.size():
		set_mode(args[i + 1].to_lower())
	var j := args.find("--physics-interp")
	if j >= 0 and j + 1 < args.size():
		interp = args[j + 1].to_lower() == "on"


## Back to the defaults (tests).
static func reset() -> void:
	_booted = true
	mode = TODAY
	local_id = TODAY
	blind_order.clear()
	blind_index = 0
	crew_id = ""
	crew_blind = false
	interp = false
	switches = 0


## today | grounded | grounded_anim | shuffle (anything else is today).
static func set_mode(m: String, seed_value: int = -1) -> void:
	if m == SHUFFLE:
		mode = SHUFFLE
		var rng := RandomNumberGenerator.new()
		if seed_value >= 0:
			rng.seed = seed_value
		else:
			rng.randomize()
		blind_order = BLIND.duplicate()
		for k in range(blind_order.size() - 1, 0, -1):
			var r := rng.randi_range(0, k)
			var tmp := blind_order[k]
			blind_order[k] = blind_order[r]
			blind_order[r] = tmp
		blind_index = 0
		local_id = blind_order[0]
		print("[move] shuffle: %s" % ", ".join(blind_order.map(func(id: String) -> String: return "feel %d = %s" % [blind_order.find(id) + 1, id])))
		return
	mode = m if PROFILES.has(m) else TODAY
	local_id = mode
	blind_order.clear()


## The profile every hero on this machine plays right now.
static func active() -> String:
	if crew_id != "" and Net.crewed():
		return crew_id
	return local_id


## Blind: the tag must not name the profile.
static func blind() -> bool:
	if crew_id != "" and Net.crewed():
		return crew_blind
	return mode == SHUFFLE


## What the tag shows: the profile's name, or "feel N" when blind.
static func label() -> String:
	if not blind():
		return active()
	if crew_id != "" and Net.crewed():
		return "feel (host's)"
	return "feel %d" % (blind_index + 1)


## A key of the active profile (OFF's value when the profile does not set it).
static func value(key: String) -> Variant:
	return (PROFILES.get(active(), {}) as Dictionary).get(key, OFF[key])


## True when a switch key (envelope, hop, gait ...) is on in the active profile.
static func on(key: String) -> bool:
	return bool(value(key))


static func num(key: String) -> float:
	return float(value(key))


## F6: the next profile. False (nothing changes) in a crew: the host's profile is everyone's.
static func cycle() -> bool:
	if Net.crewed():
		return false
	if mode == SHUFFLE and not blind_order.is_empty():
		blind_index = (blind_index + 1) % blind_order.size()
		local_id = blind_order[blind_index]
	else:
		local_id = ORDER[(ORDER.find(local_id) + 1) % ORDER.size()]
		mode = local_id
	switches += 1
	return true


## F7.
static func toggle_interp() -> void:
	interp = not interp


## The host: what goes out with the job (crew.job).
static func crew_data() -> Dictionary:
	return {"id": local_id, "blind": mode == SHUFFLE}


## A client (or a late joiner): the host's profile for this run.
static func apply_crew(job: Dictionary) -> void:
	var d := job.get("feel", {}) as Dictionary
	if d == null or not PROFILES.has(str(d.get("id", ""))):
		return
	crew_id = str(d["id"])
	crew_blind = bool(d.get("blind", false))
