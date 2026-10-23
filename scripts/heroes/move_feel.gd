class_name MoveFeel
extends RefCounted
## Movement-feel profiles (docs/design/movement-research.md §5.2, "As built" and §5.3): one data table, like HeroKit.
## `today` is the game as it was before the movement work (every key at its OFF value: the old code paths run, frame for
## frame: test_move_feel_today holds it to a recorded trace); `grounded` is package A; `grounded_anim` is grounded plus the
## animation track's treatment B (a lean that leads the velocity, squash on start and stop, the stride held while shoved
## or airborne: HeroFeel) and the strike-first melee with each hero's hit area reshaped to its weapon
## (docs/design/animation-research.md "As built"). Every hero, the camera and the AI allies read the ACTIVE profile here;
## nothing else stores a copy.
##
## THE DEFAULT is grounded_anim (the user, 2026-10-23: "For movement profile - the new one is better."): normal play, an
## exported build and a crew's job all play it with no flag. The A/B is concluded, so no key switches profiles in play any
## more (the user: "lets put experiments in the gym menu instead of adding keybindings"): the test gym's panel picks the
## profile and the judder smoothing (GymDev, "Experiments").
##
##   --move-feel today|grounded|grounded_anim   (default grounded_anim) this run's profile, solo or as a crew's host
##   --physics-interp on|off              (default off) the owned heroes drawn between physics ticks (Hero, "judder")
##
## A CREW (networking): the HOST's profile is everyone's. It goes out with the job (CrewFlow.host_pick puts `feel` in
## crew.job, which a late joiner gets too) like the seed: spawn data for the run, nothing streamed. A client's own flag is
## ignored while it is in a crew. The reasons: a puppet's stride, hop and landing are drawn on every screen from the shown
## motion with the profile THAT screen has, so the crew must agree on it; and a later profile with a dodge is gameplay
## every machine must agree on. Physics interpolation is each machine's own (it only changes how this screen draws its own
## heroes).

const TODAY := "today"
const GROUNDED := "grounded"
const GROUNDED_ANIM := "grounded_anim"
## The profile with no flag (normal play, exported builds, a host's job).
const DEFAULT := GROUNDED_ANIM
## The real profiles (the gym's picker lists them in this order).
const ORDER: Array[String] = [TODAY, GROUNDED, GROUNDED_ANIM]

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
	"footsteps": true,      ## a dry footstep per stride (the floor's material; on in every profile)
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
	"spin_reach": 0.0,      ## Gasket's spin radius (Hero.spin_area); 0 keeps Hero.SPIN_REACH
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
			# Gasket's smash (the user, 2026-10-22: "The impact of the hammer should be a little bigger too. It is a smash
			# weapon."): the lane of the shaft, ending in a disc round the head's landing, marked on the floor
			"gasket": {"shape": "lane", "near": 0.6, "far": 1.95, "radius": 0.25, "end_radius": 0.6, "smash": true},
			"rebar": {"shape": "lane", "near": 1.05, "far": 1.05, "radius": 0.85},
		},
		# Gasket's spin (the user, 2026-10-22: "What about the secondary?"): the wrench head sweeps round 2.1-2.3 from her
		# (Hero.SPIN_REACH is 1.9), so a monster the head visibly crosses is one it hits
		"spin_reach": 2.1,
	},
}
## A landing from this many levels or more is a big one (dust, a thud, the landing slowdown).
const LAND_BIG_LEVELS := 2

## What the command line (or a test, or the gym's picker) asked for.
static var mode := DEFAULT
## The profile this machine plays when it is not in a crew.
static var local_id := DEFAULT
## The host's profile for the crew's run ("" = none: this machine's own).
static var crew_id := ""
## Physics interpolation of this machine's own heroes (--physics-interp, the gym's "Smoothing").
static var interp := false
## Times the profile changed this run (the gym's picker), for the log.
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
	mode = DEFAULT
	local_id = DEFAULT
	crew_id = ""
	interp = false
	switches = 0


## today | grounded | grounded_anim (anything else warns and plays the default).
static func set_mode(m: String) -> void:
	if not PROFILES.has(m):
		push_warning("--move-feel: today, grounded or grounded_anim (got '%s'); playing %s" % [m, DEFAULT])
		m = DEFAULT
	mode = m
	local_id = m


## The profile every hero on this machine plays right now.
static func active() -> String:
	if crew_id != "" and Net.crewed():
		return crew_id
	return local_id


## What the dev tag shows: the profile's name.
static func label() -> String:
	return active()


## A key of the active profile (OFF's value when the profile does not set it).
static func value(key: String) -> Variant:
	return (PROFILES.get(active(), {}) as Dictionary).get(key, OFF[key])


## True when a switch key (envelope, hop, gait ...) is on in the active profile.
static func on(key: String) -> bool:
	return bool(value(key))


static func num(key: String) -> float:
	return float(value(key))


## The gym's picker: play `id` from now on. False (nothing changes) for an unknown id, or in a crew, where the host's
## profile is everyone's.
static func pick(id: String) -> bool:
	if Net.crewed() or not PROFILES.has(id):
		return false
	if id != local_id:
		switches += 1
	mode = id
	local_id = id
	return true


## The host: what goes out with the job (crew.job).
static func crew_data() -> Dictionary:
	return {"id": local_id}


## A client (or a late joiner): the host's profile for this run.
static func apply_crew(job: Dictionary) -> void:
	var d := job.get("feel", {}) as Dictionary
	if d == null or not PROFILES.has(str(d.get("id", ""))):
		return
	crew_id = str(d["id"])
