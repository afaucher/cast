extends Node3D
## The game: the dispatch JOB BOARD (3 offers) -> spell picker -> three floors of a procedural hex
## dungeon joined by the freight elevator -> the INVOICE -> back to the board. The crew casts spells by voice.
## Wires together DungeonGen/HexMapView (terrain), heroes/spells/HUD (HeroFactory, PlayerController, Hud,
## CameraRig), MonsterFactory (monsters), VoiceCaster/VoiceDebugPanel (voice) and the contract layer
## (ContractRun/ContractSession/SiteBuilder: hellgates, employees, priced props, objectives, the Ledger).
##
## Flow (docs/design/contracts.md): the elevator (the exit cell) opens a menu when the player stands on or next
## to it and presses E (a prompt says so; E never casts): go down (more pay, more
## danger) or cash out; cashing out is always allowed. HP and downed state carry between floors; a new
## contract resets everything (spells are re-picked). All heroes down ends the contract: "Crew
## incapacitated" and the invoice shows what was earned so far.
##
## Command line (after `--`):
##   --seed N            dungeon seed (default: random). Seeds the job board; with --contract N / --spells it is
##                       the contract's seed and floor 1 is exactly DungeonGen.for_run(run, 1) (seed N and the job's elevator)
##   --contract K        skip the board: take offer K (0-2) of the board, or, for K >= 3, the contract rolled from seed K
##   --floor N           start on floor N (1-3) of the contract (implies a contract; default offer from --seed)
##   --spells a,b        skip the picker (e.g. heal,corn); with no --contract it also skips the board
##   --no-mic            don't open the mic / load the model (typed casts only)
##   --shot <png>        save a screenshot after --shot-after game seconds (default 3) and quit
##   --autocast <id>     cast a spell once, 1 s in (for screenshots); in a shared run once the floor has started and the
##                       crew is out of the van, plus --autocast-after S (default 0.5)
##   --aim-offset x,z    dev: --autocast aims at the player's position plus this offset (world units) instead of at the monsters
##   --proto-heroes      use the old capsule prototype bodies instead of the faceted crew
##   --spawn-near k,n[,cluster]  dev: also spawn n monsters of kind k (grunt/archer/brute/swarmer) near the player;
##                       --autocast then aims at them
##   --idle-monsters     dev: --spawn-near monsters ignore heroes until hurt
##   --stage-ledge       dev: raise a 7-cell tower +5 levels near the start; --spawn-near monsters stand on it
##   --give heal:9,corn:3  dev: slot these spells (up to 4) with these charges, after the picked two
##   --hold N            dev: ready slot N (1-4) at the start
##   --zoom S            dev: camera size (default 24; 6 is a close-up of the crew)
##   --focus rebar|gasket|dev|elevator  dev: the camera follows that ally (or the --spawn-near monsters, or looks at the
##                       elevator's landing) instead of the player
##   --give-allies a,b   dev: slot spell a for Rebar and b for Gasket (they only hold the component; allies do not cast)
##   --drop-near a,b     dev: put component pickups for spells a, b on the floor just ahead of the player
##   --slay-near         dev: 1.5 s in, kill the --spawn-near monsters (to watch their drops)
##   --kit-demo draw|hammer|fist  dev: at 0.8 s Wick starts drawing his bow on the --spawn-near monsters (a drawn shot
##                       fires 1.3 s later), or Gasket (hammer) / Rebar (fist) steps up to them and swings once
##   --to-gate           dev: put the crew 5 cells from the first hellgate of the floor (the camera follows)
##   --to-theme <id>     dev: put the crew in the middle of the first room with that theme (wine_cellar, home_cinema, spa, gym,
##                       server_room, panic_room, pool, torture_chamber, throne_room, lab, barracks, moat, science, service_entrance); the
##                       log lists every room's theme. Combine with --zoom 12 for a close look at the set dressing; --focus sign puts the
##                       crew a few steps in front of the room's neon sign
##   --to-corridor       dev: put the crew in the middle of the floor's corridors (to see the site's corridor material)
##   --to-pool [pool|specimen|moat]  dev: put the crew at the floor's first in-ground pool (of that look): the player wading
##                       in it, the next seat on the deck at the rim, the third wading by the rim; at a moat all three wade in
##                       the channel (screenshots; the log lists the floor's pools; the AI allies hold their spots).
##                       --focus pool_corner looks at the pool's corner farthest from the camera instead, --focus island_corner
##                       at a moat island's corner nearest the camera
##   --to-package        dev: put the crew two cells from the first mail package stack of the floor (zoom in with --zoom 10)
##   --to-employee       dev: put the crew 1.5 cells from the first employee (it latches on; E prompts "tell X to wait")
##   --press-e S         dev: press E (the controller's context key) S seconds in
##   --break-crates S    dev: S seconds in, hit every breakable crate stack within 9 units of the player (screenshots)
##   --to-exit           dev: put the crew on the elevator (the use prompt shows over it; E opens the menu)
##   --demo-damage       dev: 1 s in, put two property-damage lines on the Ledger (to see the ticker and the tracker)
##   --show-panel        dev: keep the voice debug panel open in --shot screenshots
##   --hurt N            dev: every hero starts the floor N hp down (to see the HP carry over between floors)
##   --auto-elevator down|out  dev: the elevator menu opens by itself when the crew stands on the exit (no E needed) and picks
##                       that option 1.2 s later ("down" on the last floor cashes out)
##   --invoice-demo      dev: show a sample invoice (no game), for screenshots
##   --pause-demo        dev: open the pause overlay 1.5 s into the floor (screenshots)
##   --show-invite-row   dev: the pause overlay shows its "Invite crew" row without a Steam crew (screenshots; M7)
##   --invite-demo <name>  dev: 1.5 s into the floor, act as if <name> invited this player from the Steam overlay: the
##                       "Leave this job and join?" question (screenshots; M7)
##   --no-grime          dev: no grime / damage decal layer (scripts/world/grime)
##   --grime-demo        dev: 1 s in, cast fireball / corn / tentacles 6 cells from the crew and drop teeth / scuff marks (screenshots)
##   --no-van-intro      dev: skip the van's arrival animation (the van is still parked and the crew stands beside it) and, below
##                       floor 1, the elevator's (the crew stands outside its open doors). Tests (--run-test) and --shot screenshots
##                       skip them by default; --van-intro plays them anyway (--shot-after 1.2 catches the van landing; on --floor 2
##                       --shot-after 1.6 catches the crew stepping out of the elevator)
##   --net-wait N        dev, online host: stay on the job board until the crew has N members, then take offer --contract
##                       (default 0) after a second (two-window local play: README "Online play")
##   --net-bot           dev, online: this window's hero walks a loop of the start area by itself once the floor has started
##                       (a scripted PlayerController walk, so the other windows see it move; the keyboard is ignored)
##   --shot-at board|license|wait|floor|pause|invoice|clockin  dev, online: which screen --shot takes (a client's read-only
##                       board, its license checkout, the waiting-for-the-crew overlay, the floor 3 s after the shared start (the
##                       default), the pause overlay (with --pause-demo), the invoice, a late joiner's "Clocking in..." form, or
##                       `takeover`: every window --shot-after S (default 2) after a joiner took an AI's seat (M6)
##   --shot-floor N      dev, online: with --shot-at floor, take it on floor N (after the elevator) instead of the first
##   --join-hold S       dev, online (M6): a player joining a crew on the job holds its "Clocking in..." form S seconds after
##                       building the floor before reporting ready (screenshots: --shot-at clockin)
## Keys: F1 debug panel, F5 back to the job board (abandons the contract), Esc pause menu (Resume / Abandon
## contract / Main menu; Esc on the job board goes to the main menu), Enter = type an incantation.
## Reached from the main menu's Start (scenes/main_menu.tscn); Boot skips the menu when these dev flags are used.
##
## ONLINE (docs/design/networking-build-plan.md M1, scripts/net/crew_flow.gd). With another player in the crew the
## run is SHARED: the host rolls the board and picks the job (clients see the same three offers, read-only), every
## player signs their own license checkout (the "ready" step), every machine builds the same floor from the
## contract seed behind a load barrier, and the host starts the floor clock: the van arrival plays from that
## shared start. Each machine controls its own seat's hero and shows the others as puppets (M2). The host's world
## (monsters, hellgates, employees, props, crates, mail, pickups) runs on the host and is SHOWN on clients (M3:
## Session.world / Session.objects): a client's hits on props and mail, its pickups and its E on an employee are requests
## the host grants, the host keeps the Ledger and the objectives and every client mirrors them. The elevator and the van
## are first-to-choose: the first player to pick a row decides for the crew (down: every machine builds the next floor
## behind the barrier; out: the host's invoice for everyone). A host alone (Steam lobby, nobody joined) plays exactly
## the solo game. M5: while crewed Esc opens the pause menu WITHOUT pausing (the world, the floor clock and the cast
## schedule run on; only your own hero stands still), and ANY player's "Abandon contract" (or F5), or "Next contract" on
## the invoice, takes the whole crew back to the host's board (a client asks the host: CrewFlow crew.abandon / crew.again).
## The host decides "crew incapacitated" from every hero's replicated `dead` and bills the revivals on its Ledger. Esc on a
## client's board or checkout leaves the crew; the host confirms first (it ends the job for all).
## M6: a player can join a crew on the job. They see "Clocking in..." (ClockInSlip), sign their own license checkout over it
## (user, 2026-10-18; Esc there leaves the crew), and wait on the form until the crew is on a running floor,
## then build that floor from the seed exactly as it was at its barrier (Session.join's seat table, their own seat being an
## AI's), report the checksum, apply the host's late-join snapshot and take the AI's seat: the same hero node becomes their
## character at full health, with the spells they signed at fresh charges, in the AI's spot (SeatHandover). Everyone sees
## "<name> takes over Gasket's seat". A joiner during a floor change arrives on the next floor; one on the invoice starts
## with the crew at the next board (and signs that job's ordinary license).

## Every castable spell, straight from SpellBook (new spells need no change here).
static func all_spells() -> PackedStringArray:
	return PackedStringArray(SpellBook.ids())
const PLAYER_COLOR := Color(0.3, 0.55, 0.95)
const SCREEN_LAYER := 60          ## full-screen screens (board, elevator, invoice) sit above the debug panel (50)
const ELEVATOR_REARM_DIST := 2    ## --auto-elevator only: after "stay", walk this many cells off before it asks again
const ELEVATOR_USE_DIST := 1      ## the player can press E at the elevator from this many cells of its landing (or in its car)
const PROMPT_ABOVE_VAN := 2.7     ## the use prompt floats this far above the floor in front of the van's side door
const PROMPT_ABOVE_ELEVATOR := 3.0
const PROMPT_ABOVE_PICKUP := 1.75 ## above the pickup's own name label
const NOTE_CLOSE_SLACK := 0.6      ## an open note's slip closes once its reader is this far past ClueNote.READ_RANGE
const VAN_FLOOR := 1              ## the van parks on the top floor only; below it the crew arrives by elevator (ElevatorArrival)
const VAN_USE_DIST := 2.8         ## the player can press E at the van from this far (world units) from its side door
const DROPOFF_DIST := 2.5         ## a FOLLOWING employee this close (world units) to the van door or the elevator leaves right away
const OBJECTIVE_INTERVAL := 0.25
const FOLLOW_EXTRACT_CELLS := 3   ## followers within this many cells of the elevator ride along
const INCAP_DELAY := 2.2
const JOIN_LICENSE_BEAT := 0.6    ## a joiner sees its "Clocking in..." form this long before the license checkout opens over it
## The three crew seats. Seat 1 is the host's hero (the AI allies follow it); an empty seat is an AI ally: seat 2
## Rebar, seat 3 Gasket. A human takes the seat with the character id the roster carries (Wick for everyone today).
const CREW_LOOKS := {
	"wick": {"name": "Wick", "color": PLAYER_COLOR},
	"rebar": {"name": "Rebar", "color": Color(0.85, 0.5, 0.25)},
	"gasket": {"name": "Gasket", "color": Color(0.7, 0.4, 0.85)},
}
const AI_SEATS := {
	2: {"character": "rebar", "angle": 2.4, "hexes": 2.6},
	3: {"character": "gasket", "angle": 3.9, "hexes": 3.3},
}

## Survive scene reloads (next floor, next contract, F5).
static var _run: ContractRun = null
static var _session: ContractSession = null
static var _spells: Array[String] = []
static var _dev_released := false   ## F5 pressed: the dev flags that skip the board / picker stop applying
static var _fade_in := false        ## the next scene fades in from black (arrived by elevator)
static var _board_seed := -1        ## the job board's seed while a contract is being set up, so backing out of the
                                    ## license screen shows the same three offers; -1 = deal a new board
static var _board_note := ""        ## online host: the line the next board shows everyone ("c1 abandoned the job")

var opts := {}
## Test seam for "Abandon contract" / "Main menu": called with "" (reload the board) or a scene path.
var scene_changer := Callable()
var map: HexMap
var player: Hero
var allies: Array[Hero] = []
var controller: PlayerController
var rig: CameraRig
var hud: Hud
var voice: VoiceCaster
var debug_layer: CanvasLayer
var debug_panel: Control
var game_stats: Label
var subtitle: Label
var _subtitle_tween: Tween
var _screen_layer: CanvasLayer     ## board / elevator / invoice
var _tracker: ObjectiveTracker
var _use_prompt: UsePrompt         ## "[E] verb" over whatever E would act on right now (van, elevator, employee, note)
var _ticker: Control
var _banner: DispatchBanner        ## dispatch on the headset: the floor line, the origin-closed line
var _note_slip: NoteSlip           ## the note being read, lower left (E opens it; E or walking away closes it)
var _open_note: ClueNote = null    ## the note whose slip is open
var _plan: SitePlan                ## this floor's site plan (made in _build_world, spawned by _populate_site)
var _site: SiteBuilder.Site
var _menu: ElevatorMenu = null
var _van_menu: VanExitMenu = null    ## the clock-out slip at the van (floor 1 only)
var _invoice: InvoiceScreen = null
var _last_invoice: Dictionary = {}   ## the invoice on screen (tests: online, every machine shows the host's)
var _board: JobBoard = null
var _picker: SpellPicker = null
var _pause: PauseMenu = null
var _ended := false               ## the contract is over (invoice shown or coming)
var _ending := false               ## the crew is down, the invoice is a moment away
var _leaving := false              ## a scene change is under way
var _elev_armed := true
var _objective_t := 0.0
var _stats_timer := 0.0
var _kills := 0
var _exit_cell := Vector2i(1 << 20, 1 << 20)
var _closed_gates: Dictionary = {}  ## instance id -> true, so a gate pays once
var _emp_cause: Dictionary = {}     ## employee instance id -> last culprit name
var _player_down_noted := false
var _dev_monsters: Array[Monster] = []   ## --spawn-near
var _dev_hazards: Array[PricedProp] = []  ## --hazard-near (ExplosiveProp)
var _stage_center := Vector2i(1 << 20, 1 << 20)   ## --stage-ledge tower center
var _arrival: VanArrival = null     ## the work van and its arrival sequence (null when the start room had no room for it)

# --- The shared run (online crew) ---
var _shared := false                ## this run is a crew run (the host picked with someone else in the crew; always true on a client)
var _flow: CrewFlow = null
var _backdrop: MenuBackdrop = null
var _board_shown := -1              ## the board seed the board on screen was dealt from
var _wait_label: Label = null       ## "License signed. Waiting for ..."
var _confirm: CrewConfirm = null    ## the host's "this ends the job for everyone" question
var _invite: InviteConfirm = null   ## M7: "Leave this job and join?" (a Steam overlay invite)
var _invite_paused := false         ## the invite question paused the tree (solo; a crew plays on)
var _flow_wired := false
var _arrival_held := false          ## the van arrival is parked at its first frame until the shared start
var _lift: ElevatorArrival = null   ## the elevator set piece (every floor) and the crew's arrival in it (floors 2 and 3)
var _lift_held := false             ## the elevator arrival is parked at its first frame until the shared start
var _barrier_up := false            ## the floor is built and frozen, waiting for the shared start
var _floor_begun := false
var heroes_by_seat: Dictionary = {} ## seat (1-3) -> Hero
var _seat_info: Array[Dictionary] = []   ## _crew_seats() as the floor was built: who sat where (a player may drop later)
var _bot: NetBot = null             ## --net-bot: a scripted walker on the local hero (two-window local play)
var _names: Dictionary = {}         ## peer -> roster name (for "X left the crew")
# --- Joining mid-contract (M6) ---
var _joining := false               ## this machine is a late joiner building the crew's floor; it has no seat until the snapshot
var _join_ticket := -1              ## the join.go this scene is building (a new one reloads the scene)
var _join_seats: Array = []         ## the seat table the host's floor was built with (join.go), for _crew_seats()
var _join_seat := 0                 ## the seat this joiner takes
var _join_slip: ClockInSlip = null  ## "Clocking in..."
var _join_picker: Control = null    ## the joiner's license checkout (its holder; `_picker` is the SpellPicker in it)
var _join_beat := false             ## the license checkout is about to open (JOIN_LICENSE_BEAT after the form)
var _join_wired := false
var _seat_notices: Array[String] = []   ## every "takes over" line this screen showed (tests)


func _ready() -> void:
	InputSetup.ensure_actions()
	_parse_args()
	if opts.has("invoice_demo"):
		_invoice_demo()
		return
	Session.invite_received.connect(_on_invite)   # (M7: a Steam overlay invite while playing: ask first)
	_flow = Net.flow()
	if Session.busy():
		await _wait_for_session()   # --net-join together with game flags: the connection is still opening
		if not Session.online():
			_change_scene(Boot.MENU_SCENE)   # it failed: the menu says why (Session.last_reason)
			return
	if Session.online():
		Session.session_ended.connect(_on_session_ended)
		Session.peer_left.connect(_on_peer_left)
		Session.roster_changed.connect(_note_names)
		Session.seats.to_ai.connect(_on_seat_to_ai)
		Session.objects.exit_decided.connect(_on_exit_decided)
		Session.objects.contract_received.connect(_on_contract_mirror)
		Session.objects.end_received.connect(_end_from_host)
		Session.seats.to_player.connect(_on_seat_to_player)
		Session.join.built_ready.connect(_on_join_ready)
		Session.join.changed.connect(_on_join_changed)
		Session.join.snapshot_received.connect(_on_join_snapshot)
		_join_wired = true
		_note_names()
	if Session.is_client():
		_start_as_client()
		return
	_resolve_run()
	if _session == null:
		_show_board()
		return
	if Session.online() and Net.crewed() and _flow != null and _flow.floor_change and _flow.phase == CrewFlow.LOADING:
		_shared = true   # the crew took the elevator down: the next floor goes through the barrier again (no license)
		_wire_flow()
	_enter_floor()


## Wait (a few seconds at most) for a session that is still connecting.
func _wait_for_session() -> void:
	var end := Time.get_ticks_msec() + int((NetSession.CONNECT_TIMEOUT + NetSession.HELLO_TIMEOUT) * 1000.0)
	while Session.busy() and Time.get_ticks_msec() < end:
		await get_tree().process_frame


## Forget the contract in progress (tests; F5 and "next contract" do the same inline).
static func reset_flow() -> void:
	_board_seed = -1
	_run = null
	_session = null
	_spells.clear()
	_dev_released = false
	_fade_in = false
	_board_note = ""


func _exit_tree() -> void:
	_unwire_flow()
	if Session.invite_received.is_connected(_on_invite):
		Session.invite_received.disconnect(_on_invite)
	if Session.session_ended.is_connected(_on_session_ended):
		Session.session_ended.disconnect(_on_session_ended)
		Session.peer_left.disconnect(_on_peer_left)
		Session.roster_changed.disconnect(_note_names)
	if Session.seats != null and Session.seats.to_ai.is_connected(_on_seat_to_ai):
		Session.seats.to_ai.disconnect(_on_seat_to_ai)
	if _join_wired and Session.join != null:
		_join_wired = false
		Session.seats.to_player.disconnect(_on_seat_to_player)
		Session.join.built_ready.disconnect(_on_join_ready)
		Session.join.changed.disconnect(_on_join_changed)
		Session.join.snapshot_received.disconnect(_on_join_snapshot)
	if Session.objects != null and Session.objects.exit_decided.is_connected(_on_exit_decided):
		Session.objects.exit_decided.disconnect(_on_exit_decided)
		Session.objects.contract_received.disconnect(_on_contract_mirror)
		Session.objects.end_received.disconnect(_end_from_host)
	if Session.snap != null:
		Session.snap.end()   # the heroes are going with the scene
	if Session.world != null:
		Session.world.end()
	if Session.objects != null:
		Session.objects.end()
	if Session.casts != null:
		Session.casts.end()
	if Session.status != null:
		Session.status.end()
	if _pause != null or _invite_paused:
		get_tree().paused = false   # never leave the next scene frozen
	if GameWorld.actor_died.is_connected(_on_actor_died):
		GameWorld.actor_died.disconnect(_on_actor_died)
	if GameWorld.root != null and GameWorld.root.get_parent() == self:
		GameWorld.end()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var a: String = args[i]
		var nxt: String = args[i + 1] if i + 1 < args.size() else ""
		match a:
			"--seed": opts["seed"] = int(nxt)
			"--net-wait": opts["net_wait"] = int(nxt)
			"--net-bot": opts["net_bot"] = true
			"--shot-at": opts["shot_at"] = nxt
			"--shot-floor": opts["shot_floor"] = int(nxt)
			"--contract": opts["contract"] = int(nxt)
			"--floor": opts["floor"] = clampi(int(nxt), 1, ContractRun.FLOOR_COUNT)
			"--spells": opts["spells"] = nxt
			"--no-mic": opts["no_mic"] = true
			"--shot": opts["shot"] = nxt
			"--shot-after": opts["shot_after"] = float(nxt)
			"--autocast": opts["autocast"] = nxt
			"--autocast-after": opts["autocast_after"] = float(nxt)
			"--aim-offset": opts["aim_offset"] = nxt
			"--proto-heroes": opts["proto_heroes"] = true
			"--spawn-near": opts["spawn_near"] = nxt
			"--stage-ledge": opts["stage_ledge"] = true
			"--idle-monsters": opts["idle_monsters"] = true
			"--give": opts["give"] = nxt
			"--hold": opts["hold"] = int(nxt)
			"--give-allies": opts["give_allies"] = nxt
			"--zoom": opts["zoom"] = float(nxt)
			"--focus": opts["focus"] = nxt
			"--drop-near": opts["drop_near"] = nxt
			"--hazard-near": opts["hazard_near"] = nxt
			"--hazard-demo": opts["hazard_demo"] = nxt
			"--demo-after": opts["demo_after"] = float(nxt)
			"--to-hazard": opts["to_hazard"] = nxt
			"--slay-near": opts["slay_near"] = true
			"--kit-demo": opts["kit_demo"] = nxt
			"--to-gate": opts["to_gate"] = true
			"--to-theme": opts["to_theme"] = nxt
			"--to-exit": opts["to_exit"] = true
			"--to-corridor": opts["to_corridor"] = true
			"--to-pool":
				opts["to_pool"] = args[i + 1] if i + 1 < args.size() and not args[i + 1].begins_with("--") else ""
			"--to-package": opts["to_package"] = true
			"--to-employee": opts["to_employee"] = true
			"--to-note": opts["to_note"] = int(nxt)
			"--press-e": opts["press_e"] = float(nxt)
			"--break-crates": opts["break_crates"] = float(nxt)
			"--demo-damage": opts["demo_damage"] = true
			"--show-panel": opts["show_panel"] = true
			"--hurt": opts["hurt"] = float(nxt)
			"--auto-elevator": opts["auto_elevator"] = nxt
			"--invoice-demo": opts["invoice_demo"] = true
			"--pause-demo": opts["pause_demo"] = true
			"--show-invite-row": opts["show_invite_row"] = true
			"--invite-demo":
				opts["invite_demo"] = args[i + 1] if i + 1 < args.size() and not args[i + 1].begins_with("--") else "Rosa"
			"--no-grime": opts["no_grime"] = true
			"--grime-demo": opts["grime_demo"] = true
			"--no-van-intro": opts["no_van_intro"] = true
			"--van-intro": opts["van_intro"] = true
			"--join-hold": opts["join_hold"] = float(nxt)


# --- Contract flow: board -> contract -> floors -> invoice ------------------------------------

## Pick up the contract from an earlier floor, or (dev flags) start one directly.
func _resolve_run() -> void:
	if _session == null and not _dev_released:
		var board_seed := int(opts.get("seed", randi() % 100000))
		var run: ContractRun = null
		if opts.has("contract"):
			var k: int = opts["contract"]
			run = ContractBoard.offers(board_seed)[k] if k >= 0 and k < ContractBoard.OFFER_COUNT else ContractBoard.run_for_seed(k)
		elif opts.has("spells") or opts.has("floor"):
			run = ContractBoard.run_for_seed(board_seed)
		if opts.has("net_wait"):
			run = null   # the board waits for the crew first (_net_wait_check)
		if run != null:
			_begin_contract(run)
	_apply_dev_spells()


## --spells: skip the license checkout with these (a shared run signs them at once).
func _apply_dev_spells() -> void:
	if _session != null and _spells.is_empty() and not _dev_released and opts.has("spells"):
		for s in str(opts["spells"]).split(","):
			var id := s.strip_edges()
			if id in all_spells() and not _spells.has(id):
				_spells.append(id)


## A new contract: the Ledger restarts, nothing carries over, spells are picked again. The host of a crew (someone
## else is in it) tells everyone which job it took: from here the run is SHARED.
func _begin_contract(run: ContractRun) -> void:
	_run = run
	_session = ContractSession.begin(run, int(opts.get("floor", 1)) if not _dev_released else 1)
	_spells.clear()
	Ledger.mirror = Session.is_client()   # (M3: the host keeps the books; a client shows the host's lines)
	if Session.is_client():
		_shared = true
	elif Session.online() and Net.crewed() and _flow != null:
		_shared = true
		_wire_flow()
		_flow.host_pick(run)


func _screens() -> CanvasLayer:
	if _screen_layer == null:
		_screen_layer = CanvasLayer.new()
		_screen_layer.layer = SCREEN_LAYER
		add_child(_screen_layer)
	return _screen_layer


## The board on screen: the host's (it picks, and rolls the seed) or a client's (the host's seed, read-only).
func _make_board(board_seed: int, read_only: bool, note: String = "") -> JobBoard:
	_board_shown = board_seed
	var board := JobBoard.new(ContractBoard.offers(board_seed))
	board.read_only = read_only
	board.notice = note
	_board = board
	# The same garage as the main menu behind the cards. The menu scene is already gone (Start changes scene), so
	# this is a fresh MenuBackdrop; it picks the same mood and featured hero itself (pick_mood, hero_from_args).
	_backdrop = MenuBackdrop.new()
	_backdrop.name = "Backdrop"
	add_child(_backdrop)
	board.backdrop_behind = true
	_screens().add_child(board)
	board.back.connect(_request_leave)   # Esc voids the board, then leaves (a crew host confirms first)
	return board


func _drop_board() -> void:
	if _board != null:
		_board.queue_free()
		_board = null
	if _backdrop != null:
		_backdrop.queue_free()
		_backdrop = null


func _show_board() -> void:
	var board_seed := _board_seed if _board_seed >= 0 else int(opts.get("seed", randi() % 100000))
	_board_seed = board_seed
	var note := _board_note if Session.online() else ""
	_board_note = ""
	var board := _make_board(board_seed, false, note)
	board.picked.connect(func(run: ContractRun) -> void:
		_drop_board()
		_begin_contract(run)
		_apply_dev_spells()
		_enter_floor())
	if Session.is_host() and Session.online() and _flow != null:
		# The host rolled this board: every client draws the same offers and follows the highlighted card.
		board.highlight_changed.connect(_flow.host_highlight)
		_flow.host_board(board_seed, board.highlighted(), note)
		if opts.has("net_wait"):
			Session.roster_changed.connect(_net_wait_check.bind(board))
			_net_wait_check(board)
	if opts.has("shot") and not opts.has("net_wait"):   # (a --net-wait run takes its picture on the floor)
		_take_shot_later(str(opts["shot"]), float(opts.get("shot_after", 1.0)))


## --net-wait N: take the --contract offer once the crew has N members (a moment later, so the others have the board).
func _net_wait_check(board: JobBoard) -> void:
	if not is_instance_valid(board) or _board != board or Session.roster.size() < int(opts["net_wait"]):
		return
	if Session.roster_changed.is_connected(_net_wait_check):
		Session.roster_changed.disconnect(_net_wait_check)
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if is_instance_valid(board) and _board == board:
			board.choose(clampi(int(opts.get("contract", 0)), 0, ContractBoard.OFFER_COUNT - 1)))


# --- A client's run: it only draws what the host decides -----------------------------------------------

func _start_as_client() -> void:
	_shared = true
	_wire_flow()
	if opts.has("shot") and not opts.has("shot_after"):
		opts["shot_after"] = 3.0
	_sync_with_flow()


func _wire_flow() -> void:
	if _flow == null or _flow_wired:
		return
	_flow_wired = true
	_flow.load_requested.connect(_on_flow_load)
	_flow.waiting_changed.connect(_update_waiting)
	_flow.floor_started.connect(_begin_floor)
	_flow.abandon_requested.connect(_on_abandon_requested)
	_flow.again_requested.connect(_on_again_requested)
	if Session.is_client():
		_flow.board_changed.connect(_on_flow_board)
		_flow.job_changed.connect(_on_flow_job)


func _unwire_flow() -> void:
	if _flow == null or not _flow_wired:
		return
	_flow_wired = false
	_flow.load_requested.disconnect(_on_flow_load)
	_flow.waiting_changed.disconnect(_update_waiting)
	_flow.floor_started.disconnect(_begin_floor)
	_flow.abandon_requested.disconnect(_on_abandon_requested)
	_flow.again_requested.disconnect(_on_again_requested)
	if _flow.board_changed.is_connected(_on_flow_board):
		_flow.board_changed.disconnect(_on_flow_board)
		_flow.job_changed.disconnect(_on_flow_job)


## Show whatever the host's flow says right now (this scene may have been loaded after the events arrived).
func _sync_with_flow() -> void:
	if Session.join != null and Session.join.waiting:
		_on_join_changed()   # (M6: a joiner of a crew on the job)
		return
	if _session != null and _flow.floor_change:
		if _flow.phase == CrewFlow.LOADING:
			_enter_floor()   # the crew took the elevator: the next floor, behind the barrier
		else:
			_show_waiting("Taking the elevator down...")
		return
	match _flow.phase:
		CrewFlow.BOARD:
			_on_flow_board()
		CrewFlow.LICENSE, CrewFlow.LOADING, CrewFlow.PENDING, CrewFlow.FLOOR:
			_on_flow_job()
		_:
			_show_waiting("Waiting for the host's job board...")


func _on_flow_board() -> void:
	if _flow.phase != CrewFlow.BOARD:
		return
	if _session != null and not _leaving:
		# The host went back to the board (or abandoned): so does everyone, with the host's new offers.
		_back_to_board_local()
		return
	if _board != null and _board_shown == _flow.board_seed:
		_board.set_highlight(_flow.board_hi)
		return
	_drop_board()
	_hide_wait()
	_close_join_slip()
	var board := _make_board(_flow.board_seed, true, _flow.board_note)
	board.set_highlight(_flow.board_hi)
	_shot_stage("board", 1.0)


func _on_flow_job() -> void:
	if _session != null or _flow.job.is_empty() or _leaving:
		return
	var run := _flow.job_run()
	if run == null:
		return
	_drop_board()
	_hide_wait()
	_begin_contract(run)
	_apply_dev_spells()
	_enter_floor()


## Build the current floor of the contract (the scene is fresh: first floor, or arrived by elevator).
func _enter_floor() -> void:
	_build_world()
	_setup_voice()
	if _fade_in:
		_fade_in = false
		_fade(1.0, 0.0, 0.5)
	if _shared and _flow != null and _flow.floor_change:
		_start()   # a floor change (the elevator down): no license, straight to the barrier (M6: a joiner may hold no spells)
	elif _spells.is_empty():
		_show_picker()
	elif _shared:
		_sign_license()
	else:
		_start()


func _floor_n() -> int:
	return _session.floor_number


func _heroes() -> Array[Hero]:
	var out: Array[Hero] = [player]
	out.append_array(allies)
	return out


# --- World --------------------------------------------------------------------------------------

func _build_world() -> void:
	map = DungeonGen.for_run(_run, _floor_n())   # (the job's elevator: every floor of a job uses the same style)
	if opts.has("stage_ledge"):
		_stage_plateau()
	# Plan the site now: it writes each cell's floor / wall material (Cell.mat_id, FloorMaterials) before the terrain
	# is built. _populate_site() spawns this plan once the crew has picked its spells.
	_plan = SiteBuilder.plan(map, _run, _floor_n(), ContractParts.prop_catalog(_run.site_type))
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	GameWorld.begin(map, world, _run.floor_seed(_floor_n()))
	GameWorld.actor_died.connect(_on_actor_died)

	var view := HexMapView.new()
	view.name = "Terrain"
	add_child(view)
	view.build(map)

	DungeonLook.apply(self, map)

	var exits := map.cells_with_tag("exit")
	if not exits.is_empty():
		_exit_cell = exits[0]

	# The crew: three seats. Solo, the player is Wick and Rebar and Gasket are AI allies on free neighbours. In a
	# shared run each human takes their seat (a client's own hero is the one it controls), and the AI allies
	# (host only) fill the empty seats and follow the host's hero.
	# Faceted low-poly models by default; --proto-heroes brings back the capsule bodies.
	var faceted: bool = not bool(opts.get("proto_heroes", false))
	# The crew starts a job at the van (floor 1's start cell); taking the elevator down puts it at the elevator on the
	# new floor (user, 2026-10-18), not on that floor's start cell.
	var start: Vector2i = map.cells_with_tag("start")[0]
	if _floor_n() > SiteBuilder.VAN_FLOOR and not map.cells_with_tag("exit").is_empty():
		start = _exit_cell
	var spots := _free_cells_near(start, 2)
	_spawn_crew(start, spots, faceted)
	var rebar: Hero = null
	var gasket: Hero = null
	for h: Hero in heroes_by_seat.values():
		if h.display_name == "Rebar":
			rebar = h
		elif h.display_name == "Gasket":
			gasket = h

	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.target = player
	if opts.get("focus", "") == "rebar" and rebar != null:
		rig.target = rebar
	elif opts.get("focus", "") == "gasket" and gasket != null:
		rig.target = gasket
	if opts.has("zoom"):
		rig._zoom_target = float(opts["zoom"])
		rig.camera.size = float(opts["zoom"])
	rig.snap()
	controller.camera = rig.camera
	var reticle := AimReticle.new()
	reticle.controller = controller
	add_child(reticle)

	hud = Hud.new()
	add_child(hud)
	controller.hud = hud
	hud.console_submitted.connect(_on_console)


## Who sits where: [{seat, character, local, peer, name}] for seats 1-3, in seat order. Solo: Wick (you) and the
## AI allies Rebar and Gasket. A shared run: every human at their roster seat with their character id, the rest AI.
func _crew_seats() -> Array[Dictionary]:
	if _joining and not _join_seats.is_empty():
		return _joined_seats()
	var by_seat: Dictionary = {}
	if _shared:
		for e: Dictionary in Session.crew():
			if CrewFlow.is_joining(e):
				continue   # (M6: still joining: its seat is the AI's on this floor until it takes it)
			by_seat[int(e["seat"])] = e
	var out: Array[Dictionary] = []
	for seat in range(1, NetSession.MAX_CREW + 1):
		if by_seat.has(seat):
			var e: Dictionary = by_seat[seat]
			var character := str(e["character"])
			out.append({"seat": seat, "character": character if CREW_LOOKS.has(character) else NetSession.DEFAULT_CHARACTER,
				"local": int(e["peer"]) == Session.local_id(), "peer": int(e["peer"]), "name": str(e["name"])})
		elif seat == 1:
			out.append({"seat": 1, "character": NetSession.DEFAULT_CHARACTER, "local": true, "peer": 0, "name": ""})
		else:
			out.append({"seat": seat, "character": str((AI_SEATS[seat] as Dictionary)["character"]), "local": false, "peer": 0, "name": ""})
	return out


func _model_for(character: String) -> Node3D:
	match character:
		"rebar":
			return RebarModel.new()
		"gasket":
			return GasketModel.new()
	return WickModel.new()


## Spawn the three heroes. `player` is the one this machine controls (a PlayerController); `allies` are the other
## two in seat order. On the host (and solo) every other hero gets an AllyBrain that follows seat 1's hero; on a
## client they are copies (Net.make_copy, done at the barrier) until M2 syncs them.
func _spawn_crew(start: Vector2i, spots: Array[Vector2i], faceted: bool) -> void:
	heroes_by_seat.clear()
	allies = []
	_seat_info = _crew_seats()
	var leader: Hero = null
	var ai_heroes: Array[Hero] = []
	for s: Dictionary in _seat_info:
		var seat: int = s["seat"]
		var character: String = s["character"]
		var look: Dictionary = CREW_LOOKS[character]
		var cell := start if seat == 1 else spots[mini(seat - 2, spots.size() - 1)]
		# Each hero's kit (HP, primary, secondary, quirks) comes from HeroKit; --proto-heroes keeps the kits.
		var hero := HeroFactory.spawn_hero(cell, str(look["name"]), look["color"], "sword", _model_for(character) if faceted else null, character)
		heroes_by_seat[seat] = hero
		hero.set_meta(ContractSession.CREW_SEAT_META, seat)   # (the HP carry between floors is keyed by seat: two players may both be Wick)
		if seat == 1:
			leader = hero
		if bool(s["local"]):
			player = hero
			var none: Array[String] = []
			controller = HeroFactory.make_player(hero, none)
			controller.interact = _use_key
		else:
			allies.append(hero)
			if int(s["peer"]) == 0:
				ai_heroes.append(hero)   # an empty seat: an AI ally, run by the host
			else:
				hero.set_player_name(str(s["name"]))   # a person plays it: a puppet here, their name over its head
	for h in ai_heroes:
		if Net.is_host():
			var ai: Dictionary = AI_SEATS[_seat_of(h)]
			HeroFactory.make_ally(h, leader, false, float(ai["angle"]), float(ai["hexes"]))


## The name a hero goes by on the books: its player's roster name while crewed (two players may both be Wick), else the
## hero's own name (solo, and the AI seats).
func _crew_label(hero: Hero) -> String:
	if _crewed() and Session.seats != null:
		var peer := int(Session.seats.owners.get(_seat_of(hero), 0))
		if peer != 0 and _names.has(peer):
			return str(_names[peer])
	return hero.display_name


func _seat_of(hero: Hero) -> int:
	for seat: int in heroes_by_seat:
		if heroes_by_seat[seat] == hero:
			return seat
	return 0


## Full floor cells (never wall-cut, never under the elevator) within `radius` of c at about its level.
func _free_cells_near(c: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var base: int = map.get_cell(c).level
	for n in Hex.range_cells(c, radius):
		var cell: HexMap.Cell = map.get_cell(n)
		if n != c and cell != null and cell.type == HexMap.Tile.FLOOR and absi(cell.level - base) <= 1 and map.is_walkable_cell(n):
			out.append(n)
	if out.is_empty():
		out.append(c)
	return out


## Everything the contract puts on this floor: hellgates, employees, priced props, two notes, and the
## monster packs (one per room but the start room, leaning toward the pest). Then the session starts the floor.
func _populate_site() -> void:
	_site = SiteBuilder.spawn(map, _run, _plan)
	var origin := _site.origin_gate != null
	var small := _site.gates.size() - (1 if origin else 0)
	_session.enter_floor(_floor_n(), small, origin, _site.employees.size(), _site.pest_spawned)
	for g in _site.gates:
		if g.has_signal("closed"):
			g.connect("closed", _on_gate_closed)
	for e in _site.employees:
		e.damaged.connect(func(_amount: float, source: Node) -> void: _emp_cause[e.get_instance_id()] = Ledger.culprit_name(source))
	_log("site: %d gates%s, %d employees, %d props, %d monsters (%d pests: %s)" % [small, " + origin" if origin else "", _site.employees.size(),
		_site.props.size(), _site.monsters.size(), _site.pest_spawned, _run.pest], Color(0.8, 0.8, 1.0))
	_log("themes: %s  decor %d" % [str(_site.plan.room_themes), _site.plan.decor.size()], Color(0.8, 0.8, 1.0))
	var note_list: Array[String] = []
	for nt in _site.plan.notes:
		note_list.append("%s %s in %s" % [nt["kind"], nt["format"], nt["room"]])
	_log("notes: %s" % ", ".join(note_list), Color(0.8, 0.8, 1.0))


# --- Voice --------------------------------------------------------------------

func _setup_voice() -> void:
	voice = VoiceCaster.new()
	voice.name = "VoiceCaster"
	voice.settings_path = GameSettings.path   # the menu's voice setup writes here
	add_child(voice)
	voice.spell_spoken.connect(_on_spell_spoken)
	voice.spell_fizzled.connect(_on_spell_fizzled)
	Sfx.listen_to_voice(voice)   # "cast heard", the fizzle and its cut on new speech: this machine only (your mic)
	if voice.has_signal("heard"):
		voice.connect("heard", _on_heard)
	if voice.has_signal("trigger_word_changed"):
		voice.connect("trigger_word_changed", func(w: String) -> void: hud.set_trigger_word(w))

	debug_layer = CanvasLayer.new()
	debug_layer.layer = 50
	add_child(debug_layer)
	debug_panel = VoiceDebugPanel.new()
	# Settings > "Voice debug panel visible at start" (F1 still toggles it); --show-panel always opens it.
	debug_panel.visible = opts.has("show_panel") or bool(GameSettings.load_settings()["voice_panel_visible"])
	debug_layer.add_child(debug_panel)
	debug_panel.attach(voice)
	debug_panel.visibility_changed.connect(_fit_hud_to_panel)
	voice.voice_log.context = _voice_log_context   # (online: which seat, and the shared clock, on every voice log row)
	_refresh_voice_owner()

	game_stats = Label.new()
	game_stats.add_theme_font_size_override("font_size", 13)
	game_stats.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	game_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if debug_panel.has_method("add_section"):
		debug_panel.add_section("GAME", game_stats)
	else:
		debug_layer.add_child(game_stats)

	# What the recognizer heard, verbatim, as a subtitle (even with the panel hidden).
	subtitle = Label.new()
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_outline_color", Color.BLACK)
	subtitle.add_theme_constant_override("outline_size", 6)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle.anchor_left = 0.15
	subtitle.anchor_right = 0.6
	subtitle.anchor_top = 0.74
	subtitle.anchor_bottom = 0.74
	hud.add_overlay(subtitle)

	_fit_hud_to_panel()
	var ok := false
	if not opts.get("no_mic", false):
		ok = voice.start(all_spells())
	if voice.has_method("get_trigger_word"):
		hud.set_trigger_word(voice.call("get_trigger_word"))
	_log("voice: %s" % ("listening" if ok else "no mic/model - type with Enter"), Color(0.6, 0.9, 1.0))


## The voice log's net columns (M7): this machine's role and seat in the crew and the shared clock; nothing offline.
func _voice_log_context() -> Dictionary:
	if not Session.online():
		return {}
	return {"net": "host" if Session.hosting else "client", "seat": int(Session.local_entry().get("seat", 0)),
		"host_time": "%.3f" % Session.host_time()}


## Online the debug panel says whose recognizer it shows: this machine's only (M7).
func _refresh_voice_owner() -> void:
	if debug_panel == null or not debug_panel.has_method("set_mic_owner"):
		return
	if not Session.online() or Session.roster.size() < 2:
		debug_panel.set_mic_owner("")
		return
	var e := Session.local_entry()
	debug_panel.set_mic_owner("THIS MACHINE'S MIC  ·  %s, seat %d  ·  teammates' casts arrive as events" % [
		str(e.get("name", "you")), int(e.get("seat", 0))])


func _fit_hud_to_panel() -> void:
	var inset := VoiceDebugPanel.PANEL_WIDTH if debug_panel.visible else 0.0
	hud.set_right_inset(inset)
	rig.right_inset_px = inset


func _on_spell_spoken(id: String, power: float, heard: String) -> void:
	Net.note_voice(id, voice.last_cast())   # (online: the cast's row in the casts sheet carries its onset and latency)
	_cast(id, power, heard, voice.last_cast_accidental())


## A voice (or typed) cast of any slotted spell: held or not, it goes through the controller, which
## checks charges (out of components fizzles with no cooldown), the cooldown (/1.15 on the held spell)
## and spends a charge. It never changes which slot is held.
func _cast(id: String, power: float, heard: String, accidental: bool = false) -> void:
	if _ended or player == null or player.dead:
		_log("ignored %s: no living player" % id.to_upper(), Color(0.7, 0.7, 0.7))
		return
	var known := player.spell_slots.has(id)
	var cd := player.cooldown_left(id) if known else 0.0
	var empty := known and player.charges_of(id) <= 0
	var tag := "ACCIDENTAL " if accidental else ""
	if controller.cast_spell(id, power):
		_log("%sCAST %s %d%%  (\"%s\")  %d left" % [tag, id.to_upper(), roundi(power * 100.0), heard, player.charges_of(id)], Color(0.5, 1.0, 0.6))
	elif not known:
		_log("%s%s not in slots (%s)" % [tag, id.to_upper(), ", ".join(player.spell_slots)], Color(1.0, 0.6, 0.3))
	elif empty:
		_log("%s%s fizzled: out of %s" % [tag, id.to_upper(), SpellBook.component_name(id)], Color(1.0, 0.5, 0.45))
	elif cd > 0.0:
		_log("%s%s recharging %.1fs" % [tag, id.to_upper(), cd], Color(1.0, 0.8, 0.4))
	else:
		_log("%s refused" % id.to_upper(), Color(1.0, 0.5, 0.5))


func _on_spell_fizzled(heard: String, reason: String) -> void:
	if player and not player.dead:
		SpellBook.fizzle(player)
	hud.show_fizzle(heard, reason)
	_log("fizzle: %s (\"%s\")" % [reason, heard], Color(1.0, 0.75, 0.4))


func _on_heard(text: String, final: bool) -> void:
	if text.strip_edges() == "":
		return
	subtitle.text = "\"%s\"" % text.to_lower()
	subtitle.modulate = Color(1, 1, 1, 1) if final else Color(0.75, 0.75, 0.8, 0.9)
	if _subtitle_tween:
		_subtitle_tween.kill()
	if final:
		_subtitle_tween = create_tween()
		_subtitle_tween.tween_interval(2.0)
		_subtitle_tween.tween_property(subtitle, "modulate:a", 0.0, 0.6)


## Typed incantations go through the voice pipeline, so typed and spoken behave the same.
func _on_console(text: String) -> void:
	if text.strip_edges() != "":
		voice.inject_text(text)


# --- Floor start ---------------------------------------------------------------------------------

func _show_picker() -> void:
	controller.enabled = false
	var picker := SpellPicker.new()
	_picker = picker
	if voice.has_method("get_trigger_word"):
		picker.set_trigger_word(voice.call("get_trigger_word"))
	if _shared and not Net.is_host():
		picker.back_text = "Leave the crew"
		picker.back_hint = "back to the menu"
	if _run != null:
		picker.job = {"job": _run.invoice_number.replace("INV-", ""), "client": _run.company}
	hud.add_overlay(picker)
	picker.cancelled.connect(_back_to_board)
	_shot_stage("license", 1.0)
	picker.picked.connect(func(chosen: Array[String]) -> void:
		_board_seed = -1   # committed to this job: the next board is a new one
		_spells = chosen.duplicate()
		picker.queue_free()
		_picker = null
		if _shared:
			_sign_license()
		else:
			_start())


## A shared run: signing the license is the "ready" step. The floor is built once the whole crew has signed.
func _sign_license() -> void:
	_board_seed = -1
	controller.enabled = false
	_flow.sign(_spells)
	_update_waiting()


## Everyone signed (CrewFlow.load_requested): build the floor and report to the host.
func _on_flow_load() -> void:
	if _session != null and player == null and _flow != null and _flow.floor_change and not _leaving:
		_hide_wait()
		_enter_floor()   # (a client that reloaded before crew.next arrived)
		return
	if _session == null or player == null or _barrier_up or _floor_begun or _spells.is_empty():
		return
	_start()


func _start() -> void:
	player.spell_slots = _spells.duplicate()
	_assign_crew_spells()
	_apply_dev_loadout()
	hud.bind(player, allies)
	hud.enable_console()
	controller.enabled = true
	_apply_carry()
	if opts.has("hurt") and not _fade_in_hurt_done():
		for h in _heroes():
			h.hp = maxf(1.0, h.hp - float(opts["hurt"]))
			h._refresh_bar()
	_populate_site()
	_arrive_by_van()
	_arrive_by_elevator()
	if not opts.has("no_grime"):
		GrimeLayer.attach(self, map, _site.plan, _run.floor_seed(_floor_n()))
		if opts.has("grime_demo"):
			GrimeDemo.run(self, player)
	_spawn_near()
	_hazard_near()
	_build_contract_ui()
	_dev_teleports()
	if not _shared:
		_announce_floor()
	_log("floor %d/%d  seed %d  %s  spells %s" % [_floor_n(), ContractRun.FLOOR_COUNT, _run.floor_seed(_floor_n()), _run.company, ", ".join(_spells)], Color(0.6, 0.9, 1.0))
	_drop_near()
	if opts.has("hazard_demo"):
		_hazard_demo(str(opts["hazard_demo"]))
	if opts.get("focus", "") == "dev" and _dev_centroid() != Vector3.INF:
		var marker := Node3D.new()
		GameWorld.root.add_child(marker)
		marker.global_position = _dev_centroid()
		rig.target = marker
		rig.snap()
	elif opts.get("focus", "") == "elevator" and _lift != null:
		var lm := Node3D.new()   # the camera looks at the elevator's landing (screenshots of a floor-1 elevator, shut)
		GameWorld.root.add_child(lm)
		lm.global_position = Hex.to_world(_exit_cell, float(map.get_cell(_exit_cell).level))
		rig.target = lm
		rig.snap()
	_enter_barrier()
	if opts.has("slay_near"):
		get_tree().create_timer(1.5).timeout.connect(_slay_dev_monsters)
	if opts.has("kit_demo"):
		_kit_demo(str(opts["kit_demo"]))
	if opts.has("autocast"):
		await get_tree().create_timer(1.0).timeout
		if _shared:
			# A shared run (M4): the world is frozen behind the barrier, so cast once the floor runs and the crew is out of
			# the van (the cast is an event that lands on every screen).
			while is_inside_tree() and not (_floor_begun and _arrivals_done()):
				await get_tree().process_frame
			await get_tree().create_timer(float(opts.get("autocast_after", 0.5))).timeout
			if not is_inside_tree() or player == null:
				return
		var centre := _dev_centroid()
		if opts.has("aim_offset"):
			var off := str(opts["aim_offset"]).split(",")
			centre = player.global_position + Vector3(float(off[0]), 0.0, float(off[1]) if off.size() > 1 else 0.0)
		if centre != Vector3.INF:
			controller.aim_override = centre
		_cast(str(opts["autocast"]), 1.0, "autocast")
	if opts.has("pause_demo"):
		_pause_demo()
	if opts.has("invite_demo"):
		_invite_demo()
	if opts.has("press_e"):
		get_tree().create_timer(float(opts["press_e"])).timeout.connect(func() -> void:
			if opts.has("to_note") and not _site.notes.is_empty():
				# the crew settles after the teleport; step the player back up to the note's front before E
				var n: ClueNote = _site.notes[clampi(int(opts["to_note"]), 0, _site.notes.size() - 1)]
				var f := ThemeGeo.facing(n.yaw - 90.0) * 1.2
				player.global_position = n.global_position + Vector3(f.x, 0.0, f.y)
				player.snap_to_ground()
			var used := controller.press_use()
			_log("press-e: %s" % ("used" if used else "nothing"), Color(0.8, 1.0, 0.8)))
	if opts.has("break_crates"):
		get_tree().create_timer(float(opts["break_crates"])).timeout.connect(_break_crates_dev)
	if opts.has("demo_damage"):
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			Ledger.damage("Vintage 1787 wine barrel", 4000, player)
			Ledger.damage("Zen fountain", 900, allies[0]))
	if opts.has("shot") and not _shared:
		_take_shot_later(str(opts["shot"]), float(opts.get("shot_after", 3.0)))   # (a shared run starts its clock at the shared start)


## The crew arrives in the work van on the FIRST floor only: it teleports in over a summoning circle in the start room and
## the heroes step out beside its door (docs/design/environment.md, "Van arrival"). Player control comes back when they are
## out (~2.5 s), any key or click skips ahead, and the van stays parked as solid decor (and an exit, see _use_van). Floors 2
## and 3 have no van: the crew arrives in the elevator instead (_arrive_by_elevator). Without room for the van the crew
## stays at the start.
func _arrive_by_van() -> void:
	if _floor_n() != VAN_FLOOR or _site == null or _site.plan.van.is_empty():
		return
	# The van's crew spots: seat 1 (Wick), seat 3 (Gasket), seat 2 (Rebar) on every machine alike.
	var crew: Array[Hero] = []
	for seat: int in [1, 3, 2]:
		if heroes_by_seat.has(seat):
			crew.append(heroes_by_seat[seat])
	var moved_away := opts.has("to_theme") or opts.has("to_pool") or opts.has("to_package") or opts.has("to_gate") or opts.has("to_exit") or opts.has("to_employee") or opts.has("to_corridor")
	var play := _van_intro_enabled() and not moved_away and not player.dead
	_arrival = VanArrival.spawn(_site.plan.van, crew, play)
	if _arrival == null:
		return
	rig.snap()
	if _arrival.is_running():
		controller.enabled = false
		_arrival.finished.connect(_on_arrival_finished)
		if _shared:
			_arrival.playing = false   # parked at its first frame until the shared start (_begin_floor)
			_arrival_held = true


## The crew arrives by elevator on the floors below the first (user, 2026-10-18): it stands in the car's front row, the
## doors open and it steps out onto the landing (ElevatorArrival, ~1.9 s, skippable like the van's). On every floor the
## elevator itself is built here (floor 1: shut until a hero comes to it). The same switch as the van's intro plays it.
func _arrive_by_elevator() -> void:
	if _site == null or _site.plan.elevator.is_empty():
		return
	var arriving: Array[Hero] = []
	if _floor_n() > VAN_FLOOR:
		# the car's spots: seat 1 (Wick) in the middle, seat 3 (Gasket) left, seat 2 (Rebar) right, on every machine alike
		for seat: int in [1, 3, 2]:
			if heroes_by_seat.has(seat) and not _session.carried_down(heroes_by_seat[seat]):
				arriving.append(heroes_by_seat[seat])   # (a downed hero stayed behind on the floor above)
		if _session.carried_down(player):
			_follow_living_ally()   # a downed player watches the crew step out
	var moved_away := opts.has("to_theme") or opts.has("to_pool") or opts.has("to_package") or opts.has("to_gate") or opts.has("to_exit") or opts.has("to_employee") or opts.has("to_corridor")
	var play := _van_intro_enabled() and not moved_away and not player.dead
	_lift = ElevatorArrival.spawn(_site.plan.elevator, _floor_n(), arriving, _heroes(), play)
	if _lift == null:
		return
	var lift := _lift
	lift.doors_opened.connect(func() -> void: Sfx.play_at("elevator_ding", lift.global_position + Vector3.UP * 2.0))
	if _lift.is_running():
		rig.snap()
		controller.enabled = false
		_lift.finished.connect(_on_arrival_finished)
		if _shared:
			_lift.playing = false   # parked at its first frame until the shared start (_begin_floor)
			_lift_held = true
	elif not arriving.is_empty():
		rig.snap()


## Both arrivals (the van on floor 1, the elevator below it) are over, or there was none.
func _arrivals_done() -> bool:
	return (_arrival == null or _arrival.is_done()) and (_lift == null or _lift.is_done())


## An arrival is still playing (the player has no control yet).
func _arrival_running() -> bool:
	return (_arrival != null and _arrival.is_running()) or (_lift != null and _lift.is_running())


## --pause-demo: open the pause overlay 1.5 s into the floor (a shared run: 1.5 s after the shared start and the arrival).
func _pause_demo() -> void:
	if _shared:
		while is_inside_tree() and not (_floor_begun and _arrivals_done()):
			await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout
	if is_inside_tree() and _can_pause():
		_open_pause()


## --invite-demo: the overlay-invite question 1.5 s into the floor, as if Steam had sent one (M7 screenshots).
func _invite_demo() -> void:
	if _shared:
		while is_inside_tree() and not (_floor_begun and _arrivals_done()):
			await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout
	if is_inside_tree() and not _leaving:
		Session.pending_invite = {"lobby": 0, "inviter": str(opts["invite_demo"])}
		_on_invite(0, str(opts["invite_demo"]))


## The animation plays unless --no-van-intro; tests and screenshots skip it unless --van-intro.
func _van_intro_enabled() -> bool:
	if opts.has("no_van_intro"):
		return false
	if opts.has("van_intro"):
		return true
	return not (OS.get_cmdline_user_args().has("--run-test") or opts.has("shot"))


func _on_arrival_finished() -> void:
	if controller != null and player != null and not player.dead and not _ended and _menu == null and _van_menu == null and not _joining:
		controller.enabled = true
	_update_hero_sync()


## The floor line on the headset, the dispatch banner, and (screenshots) the panel put away.
func _announce_floor() -> void:
	if opts.has("shot") and not opts.has("show_panel"):   # keep screenshots clear of the banner and the voice panel
		debug_panel.visible = false
	else:
		hud.show_center("Floor %d of %d" % [_floor_n(), ContractRun.FLOOR_COUNT], Color(0.8, 0.9, 1.0), 2.0)
	_story_banner()


## Shared run: the other players' spells (the roster has them once they signed), so every machine's copy of a
## hero holds what its player licensed.
func _assign_crew_spells() -> void:
	if not _shared:
		return
	for e: Dictionary in Session.crew():
		var hero: Hero = heroes_by_seat.get(int(e["seat"]))
		if hero == null or hero == player or CrewFlow.is_joining(e) or _joining:
			continue
		var slots: Array[String] = []
		for s: Variant in e.get("spells", []) as Array:
			slots.append(str(s))
		hero.spell_slots = slots


# --- The load barrier (shared runs) --------------------------------------------------------------------------

## The floor is built: give the seed-built actors their ids, make the host's things copies (client), freeze the
## world, take the checksum and report to the host. The floor starts when the host says so (_begin_floor).
func _enter_barrier() -> void:
	if not _shared or _barrier_up:
		return
	_barrier_up = true
	NetFloor.assign_ids(GameWorld.root, heroes_by_seat)
	if not Net.is_host():
		NetFloor.freeze_copies(GameWorld.root, [] if _joining else [player])   # (M6: a joiner's seat is still the AI's)
	_begin_hero_sync()
	Session.world.begin()           # M3: the host streams its monsters, gates and employees; a client shows them
	Session.objects.begin(player)   # M3: props, crates, mail, pickups, the Ledger and the exits are the host's
	Session.casts.begin()           # M4: casts and attacks are events; every machine applies what it resolves
	Session.status.begin()          # M4: modifiers, fires and soaks shown on every screen by their owners
	_freeze(true)
	var t0 := Time.get_ticks_usec()
	var sums := NetFloor.checksum(map, _plan, _run, GameWorld.root)
	_log("floor checksum %s (map %s, plan %s, spawns %s; %d cells, %d actors; %.1f ms)" % [sums["all"], sums["map"], sums["plan"], sums["spawn"], sums["cells"], sums["actors"], float(Time.get_ticks_usec() - t0) / 1000.0], Color(0.8, 0.8, 1.0))
	if _joining:
		# M6: the same floor the crew is on (the same checksum as at its barrier). The van has long landed; the host's
		# snapshot brings the rest and the seat.
		if _arrival != null:
			_arrival_held = false
			_arrival.skip()
		if _lift != null:
			_lift_held = false
			_lift.skip()
		_flow.local_sums = sums
		_refresh_join_slip("Catching up with the crew...")
		if opts.has("join_hold"):
			await get_tree().create_timer(float(opts["join_hold"])).timeout   # (dev: hold "Clocking in..." up for a picture)
			if not is_inside_tree() or not _joining:
				return
		Session.join.report_built(sums)
		return
	if Net.is_host():
		var table: Array = []
		for s: Dictionary in _seat_info:
			table.append({"seat": int(s["seat"]), "character": str(s["character"]), "peer": int(s["peer"]), "name": str(s["name"])})
		_flow.note_floor(_floor_n(), table)   # (M6: a late joiner builds this floor with this seat table)
	_flow.report_built(sums)
	_update_waiting()


## The shared start (CrewFlow.floor_started): `elapsed` seconds of the floor have already passed on the shared clock.
## The world unfreezes and the van arrival plays from where the shared clock says it is.
func _begin_floor(elapsed: float) -> void:
	if not _shared or not _barrier_up or _floor_begun or player == null:
		return
	_floor_begun = true
	_hide_wait()
	if _joining:
		_joining = false   # (M6: the seat is ours; from here this is an ordinary crew member's floor)
		_spells = player.spell_slots.duplicate()
		_close_join_slip()
		hud.bind(player, allies)
	_freeze(false)
	if _arrival != null and _arrival_held:
		_arrival.time = elapsed
		_arrival.playing = true
		controller.enabled = false
	if _lift != null and _lift_held:
		_lift_held = false
		_lift.time = elapsed
		_lift.playing = true
		controller.enabled = false
	_announce_floor()
	_log("floor started (%.3f s past the shared start)" % elapsed, Color(0.6, 0.9, 1.0))
	if opts.get("shot_at", "floor") == "floor" and _floor_n() == int(opts.get("shot_floor", _floor_n())):
		_shot_stage("floor", 3.0)
	_update_hero_sync()


# --- Hero sync (M2): every machine owns its own seat's hero and shows the others as puppets -----------------------

## The floor is built: tell the net layer who owns which seat (AI seats are 0) and which heroes are this machine's.
## Remote heroes become puppets (Net.make_puppet) and, on the host, the AI seats stay live. Streaming starts at the
## shared start (_update_hero_sync).
func _begin_hero_sync() -> void:
	if not _joining:
		_drop_departed_seats()   # (a joiner builds the barrier's table as it was; the snapshot says who sits where now)
	var owners := {}
	for s: Dictionary in _seat_info:
		owners[int(s["seat"])] = int(s["peer"])
	var originals := {}
	for seat: int in AI_SEATS:
		originals[seat] = str((AI_SEATS[seat] as Dictionary)["character"])
	Session.seats.begin(owners, originals)
	Session.snap.begin(heroes_by_seat, 0 if _joining else _seat_of(player))


## The heroes were built when the job was picked, from the roster of that moment. A player who left during the license
## checkout is not on the roster any more: their seat is the AI's, as its original character, like a player who drops
## later. Every machine reads the same roster here (the host's roster update travels ahead of `crew.load` on the same
## ordered channel), so all of them convert the same seats and the floor checksum still agrees.
func _drop_departed_seats() -> void:
	for s: Dictionary in _seat_info:
		var seat := int(s["seat"])
		if int(s["peer"]) != 0 and not Session.roster.has(int(s["peer"])) and AI_SEATS.has(seat):
			s["peer"] = 0
			_on_seat_to_ai(seat, str((AI_SEATS[seat] as Dictionary)["character"]))


## Streaming and showing run once the floor has started AND this machine's own van arrival is over (the arrival
## places the heroes itself, hidden, so a puppet must not fight it).
func _update_hero_sync() -> void:
	if not _shared or Session.snap == null:
		return
	var on := _floor_begun and _arrivals_done() and not _leaving
	Session.snap.set_active(on)
	if on and opts.has("net_bot") and _bot == null and player != null and controller != null and not player.dead:
		_bot = NetBot.new()
		_bot.name = "NetBot"
		add_child(_bot)
		_bot.start(player, controller, NetBot.route_from(map, player.current_cell(), 7, player.can_climb))
		_log("net-bot: walking a loop of %d waypoints" % _bot.route.size(), Color(0.8, 1.0, 0.8))


## A player's seat went back to the AI (host: they dropped; client: the host says so): the same hero node becomes the
## seat's original character in place, and on the host an AllyBrain plays it (SeatHandover has already let go of the
## puppet). Clients keep showing it as a puppet, now of the host's stream.
func _on_seat_to_ai(seat: int, character: String) -> void:
	var hero: Hero = heroes_by_seat.get(seat)
	if hero == null or not is_instance_valid(hero) or hero == player or not CREW_LOOKS.has(character):
		return
	var look: Dictionary = CREW_LOOKS[character]
	hero.become(character, str(look["name"]), look["color"], _model_for(character) if not bool(opts.get("proto_heroes", false)) else null)
	if Net.is_host() and AI_SEATS.has(seat) and heroes_by_seat.has(1):
		var ai: Dictionary = AI_SEATS[seat]
		HeroFactory.make_ally(hero, heroes_by_seat[1], false, float(ai["angle"]), float(ai["hexes"]))
	if hud != null and player != null:
		hud.bind(player, allies)   # the ally rows read the new name


# --- Joining mid-contract (M6) ------------------------------------------------------------------------------------

## Every machine: a joiner (`peer`) took `seat` from the AI (SeatHandover). The same hero node becomes their character at
## full health (decided), the AllyBrain goes, and the crew is told. On the joiner this is its own hero (its player).
func _on_seat_to_player(seat: int, peer: int, character: String) -> void:
	var hero: Hero = heroes_by_seat.get(seat)
	if hero == null or not is_instance_valid(hero):
		return
	var kit := character if CREW_LOOKS.has(character) else NetSession.DEFAULT_CHARACTER
	var look: Dictionary = CREW_LOOKS[kit]
	var was := hero.display_name
	hero.become(kit, str(look["name"]), look["color"], _model_for(kit) if not bool(opts.get("proto_heroes", false)) else null, true)
	var brain := hero.get_node_or_null("AllyBrain")
	if brain != null:
		hero.remove_child(brain)   # (the AI stops this frame: the joiner's machine drives it from here)
		brain.queue_free()
	_note_names()
	var who := str(_names.get(peer, "A player"))
	var mine := peer == Session.local_id()
	if not mine:
		hero.set_player_name(who)
	for s: Dictionary in _seat_info:
		if int(s["seat"]) == seat:
			s["peer"] = peer
			s["name"] = who
			s["character"] = kit
			s["local"] = mine
	_log("seat %d: %s over %s's seat as %s" % [seat, "you take" if mine else who + " takes", was, kit], Color(0.6, 0.9, 1.0))
	var notice := "You take over %s's seat." % was if mine else "%s takes over %s's seat." % [who, was]
	_seat_notices.append(notice)
	_shot_stage("takeover", 2.0)   # (dev: --shot-at takeover, every window at the same moment after a seat changes hands)
	if hud != null and player != null:
		hud.bind(player, allies)
		hud.show_message(notice, Color(0.6, 0.9, 1.0))


## Host: a joiner built this floor with the right checksum: send it the snapshot and hand it the seat now.
func _on_join_ready(peer: int) -> void:
	if not Net.is_host() or _leaving or _ended or _session == null or not _floor_begun:
		return
	Session.join.admit(peer, {"contract": _session.mirror_state()})


## A joiner: the host said what the crew is doing (wait), sent us onto a floor (go), or the board came; or we signed.
func _on_join_changed() -> void:
	var j := Session.join
	if j == null or _leaving or j.arrived or not j.waiting:
		return   # (arrived: the floor starts through the flow; not waiting any more: the board came, _on_flow_board)
	var go := j.go
	if not go.is_empty():
		_close_join_picker()   # (the host sends us in only once we signed)
		if int(go.get("ticket", -1)) == _join_ticket:
			return
		if _session != null or map != null:
			_leaving = true   # (this scene already holds a floor: build the new one in a fresh scene)
			_change_scene("")
			return
		_join_floor()
		return
	if _session != null or map != null:
		_leaving = true   # (the crew left the floor this joiner was building: wait in a fresh scene)
		_change_scene("")
		return
	_hide_wait()
	var step := j.note
	if j.license and j.signed.is_empty():
		step = "File your requisition to clock in."
	_refresh_join_slip(step)
	_update_join_license()


## A joiner (user, 2026-10-18): while the crew is on a job we will arrive on, sign our own license first. The checkout opens
## over "Clocking in..." a beat after the form (or, with the dev flag --spells, signs at once); the crew does not wait for
## it, the AI plays our seat until we arrive. Off the job (the invoice, a host alone) there is nothing to sign: the next
## board's license is the ordinary one.
func _update_join_license() -> void:
	var j := Session.join
	if not j.license or not j.signed.is_empty():
		_close_join_picker()
		return
	if _join_picker != null or _join_beat:
		return
	var dev := _dev_join_spells()
	if not dev.is_empty():
		j.sign(dev)
		return
	_join_beat = true
	get_tree().create_timer(JOIN_LICENSE_BEAT).timeout.connect(_join_beat_over)


func _join_beat_over() -> void:
	_join_beat = false
	var j := Session.join
	if is_inside_tree() and not _leaving and j.waiting and j.go.is_empty() and j.license and j.signed.is_empty():
		_open_join_picker()


## --spells a,b on a joiner: sign those at once (as every machine does with it at a contract start). [] when not given.
func _dev_join_spells() -> Array[String]:
	var out: Array[String] = []
	if _dev_released or not opts.has("spells"):
		return out
	for s in str(opts["spells"]).split(","):
		var id := s.strip_edges()
		if id in all_spells() and not out.has(id):
			out.append(id)
	if out.size() != SpellPicker.PICK_COUNT:
		out.clear()
	return out


## The joiner's license requisition: FORM 15-S, the supplemental variant of the FORM 15 a contract start opens, in place of
## "Clocking in..." (the form comes back with the license typed in once it is signed). Its back row and Esc leave the crew,
## as the form's own row does.
func _open_join_picker() -> void:
	if _join_picker != null:
		return
	var holder := Control.new()
	holder.name = "JoinLicense"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var picker := SpellPicker.new()
	picker.set_trigger_word(str(VoiceSettings.load_settings(GameSettings.path).get("trigger_word", "cast")))
	picker.back_text = "Leave the crew"
	picker.back_hint = "back to the menu"
	picker.requisition = _join_requisition()
	holder.add_child(picker)
	_screens().add_child(holder)
	_join_picker = holder
	_picker = picker
	if _join_slip != null:
		_join_slip.visible = false
	picker.cancelled.connect(_request_leave)
	picker.picked.connect(func(chosen: Array[String]) -> void:
		_close_join_picker()
		Session.join.sign(chosen))
	_log("clocking in: sign your license (the AI holds your seat)", Color(0.6, 0.9, 1.0))
	_shot_stage("license", 1.0)


## What the joiner's FORM 15-S types in its header: the job in progress (number, client, floor).
func _join_requisition() -> Dictionary:
	var j := Session.join
	var out := {"job": "", "client": "", "floor": ""}
	if not j.wait_job.is_empty():
		var run := ContractRun.make(str(j.wait_job["archetype"]), int(j.wait_job["seed"]), float(j.wait_job["difficulty"]))
		out["job"] = run.invoice_number.replace("INV-", "")
		out["client"] = run.company
	if j.wait_floor > 0:
		out["floor"] = "%d of %d" % [j.wait_floor, ContractRun.FLOOR_COUNT]
	return out


## Close the joiner's checkout; `show_slip`: "Clocking in..." comes back (with the license on it).
func _close_join_picker(show_slip: bool = true) -> void:
	if _join_picker == null:
		return
	if _picker != null and _join_picker.is_ancestor_of(_picker):
		_picker = null
	_join_picker.queue_free()
	_join_picker = null
	if show_slip and _join_slip != null:
		_join_slip.visible = true
		_join_slip.call_deferred("_focus")


## A joiner: build the crew's floor exactly as the host built it at its barrier (its seat table, with the seat we are taking
## as this machine's hero, still the AI's), behind our own barrier; _enter_barrier reports the checksum to the host.
func _join_floor() -> void:
	var go := Session.join.go
	var job := go.get("job", {}) as Dictionary
	if job.is_empty():
		return
	_join_ticket = int(go.get("ticket", 0))
	_joining = true
	_shared = true
	_join_seats = (go.get("seats", []) as Array).duplicate(true)
	_join_seat = int(go.get("seat", 0))
	_hide_wait()
	_drop_board()
	_run = ContractRun.make(str(job["archetype"]), int(job["seed"]), float(job["difficulty"]))
	_session = ContractSession.begin(_run, int(go.get("floor", 1)))
	_spells.clear()
	Ledger.mirror = true
	_refresh_join_slip("Building floor %d..." % _floor_n())
	_log("clocking in: floor %d of %s, seat %d" % [_floor_n(), _run.company, _join_seat], Color(0.6, 0.9, 1.0))
	_build_world()
	_setup_voice()
	_start()


## The seats as the host's floor was built (join.go): [{seat, character, local, peer, name}].
func _joined_seats() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Variant in _join_seats:
		var d := row as Dictionary
		var seat := int(d.get("seat", 0))
		var character := str(d.get("character", NetSession.DEFAULT_CHARACTER))
		out.append({"seat": seat, "character": character if CREW_LOOKS.has(character) else NetSession.DEFAULT_CHARACTER,
			"local": seat == _join_seat, "peer": int(d.get("peer", 0)), "name": str(d.get("name", ""))})
	return out


## A joiner: the host's snapshot (Session.join applies the world, the Ledger and our seat): the objective bookkeeping, and
## every other seat's character and player as they are NOW (players may have come and gone since the barrier).
func _on_join_snapshot(d: Dictionary) -> void:
	if not _joining or _session == null:
		return
	_session.apply_mirror(d.get("contract", {}) as Dictionary)
	var own := int((d.get("take", {}) as Dictionary).get("seat", 0))
	var kits := d.get("kits", {}) as Dictionary
	for k: Variant in kits:
		var seat := int(k)
		var hero: Hero = heroes_by_seat.get(seat)
		var row := kits[k] as Array
		if seat == own or hero == null or row == null or row.size() < 2:
			continue
		var kit := str(row[0])
		if CREW_LOOKS.has(kit) and hero.kit_id != kit:
			var look: Dictionary = CREW_LOOKS[kit]
			hero.become(kit, str(look["name"]), look["color"], _model_for(kit) if not bool(opts.get("proto_heroes", false)) else null)
		if str(row[1]) != "":
			hero.set_player_name(str(row[1]))
		for s: Dictionary in _seat_info:
			if int(s["seat"]) == seat:
				s["character"] = kit
				s["name"] = str(row[1])
				s["peer"] = Session.seats.owner_of(seat)
	_update_tracker()


func _refresh_join_slip(step: String) -> void:
	if _join_slip == null:
		_join_slip = ClockInSlip.new()
		_join_slip.name = "ClockIn"
		_screens().add_child(_join_slip)
		_join_slip.leave.connect(_request_leave)
		_shot_stage("clockin", 0.8)
	var j := Session.join
	var job_text := ""
	if not j.wait_job.is_empty():
		var run := ContractRun.make(str(j.wait_job["archetype"]), int(j.wait_job["seed"]), float(j.wait_job["difficulty"]))
		job_text = run.company
	var floor_text := "%d of %d" % [j.wait_floor, ContractRun.FLOOR_COUNT] if j.wait_floor > 0 else ""
	var seat_text := ""
	for row: Variant in j.go.get("seats", []) as Array:
		var d := row as Dictionary
		if int(d.get("seat", 0)) == int(j.go.get("seat", -1)):
			var ch := str(d.get("character", ""))
			seat_text = "%s's (seat %d)" % [str((CREW_LOOKS.get(ch, {"name": ch}) as Dictionary)["name"]), int(d["seat"])]
	_join_slip.set_values("%s's crew" % Session.host_name(), job_text, floor_text, seat_text, step)
	var lic: PackedStringArray = []
	for id in j.signed:
		lic.append(SpellBook.spell_name(id).to_upper() if SpellBook.has_spell(id) else id.to_upper())
	_join_slip.set_license(" · ".join(lic))


func _close_join_slip() -> void:
	_close_join_picker(false)
	if _join_slip != null:
		_join_slip.queue_free()
		_join_slip = null


## "License signed. Waiting for Sam..." while the crew catches up (the host's flow knows who is missing).
func _update_waiting() -> void:
	if _flow == null or not _shared:
		return
	var text := _flow.waiting_text()
	if text == "" or _floor_begun:
		_hide_wait()
	else:
		_show_waiting(text)


## --shot with --shot-at: take the picture when this stage is on screen.
func _shot_stage(stage: String, default_after: float) -> void:
	if opts.has("shot") and str(opts.get("shot_at", "floor")) == stage:
		_take_shot_later(str(opts["shot"]), float(opts.get("shot_after", default_after)))


func _show_waiting(text: String) -> void:
	if _wait_label == null:
		_wait_label = FormTheme.label(text, 30, Color(1, 1, 1, 0.95), true)
		_wait_label.name = "Waiting"
		_wait_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_wait_label.add_theme_constant_override("outline_size", 8)
		_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_wait_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_wait_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_wait_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_wait_label.offset_top = -120.0
		_wait_label.offset_bottom = -70.0
		_screens().add_child(_wait_label)
	_wait_label.text = text
	_wait_label.visible = true
	if text.begins_with("License signed"):
		_shot_stage("wait", 1.0)


func _hide_wait() -> void:
	if _wait_label != null:
		_wait_label.visible = false


## Heroes arrive as the previous floor left them (HP, downed). A downed hero's body stayed on the floor above, so it is
## hidden here (on every machine: the hiding is local, `carried_down` is each machine's own carry), and a downed player
## hands the camera to a living ally. There is still no mid-contract revival; corporate bills the revival at the end.
func _apply_carry() -> void:
	for h in _heroes():
		_session.apply_carry(h)
		if _session.carried_down(h):
			h.visible = false
	if player.dead:
		controller.enabled = false
		_follow_living_ally()


## --hurt applies on floor 1 of a contract only (so the carry-over on later floors is visible).
func _fade_in_hurt_done() -> bool:
	return _floor_n() > 1


func _follow_living_ally() -> void:
	for a in allies:
		if not a.dead:
			rig.target = a
			return


func _build_contract_ui() -> void:
	_use_prompt = UsePrompt.new()
	add_child(_use_prompt)
	_tracker = ObjectiveTracker.new()
	hud.add_overlay(_tracker)
	_ticker = ContractParts.make_ticker()
	if _ticker != null:
		hud.add_overlay(_ticker)
	_banner = DispatchBanner.new()
	hud.add_overlay(_banner)
	_note_slip = NoteSlip.new()
	hud.add_overlay(_note_slip)
	Ledger.line_added.connect(_on_ledger_line)
	_update_tracker()


## Dispatch at the top of each floor: ONE message, the line SiteBuilder planned for it (floor 1 tells the contract's event in
## dispatch's voice and what it means for the crew; see NoteCopy.DISPATCH).
func _story_banner() -> void:
	if _site == null:
		return
	_banner.show_line(_site.plan.dispatch, 7.0)


func _show_banner(text: String, hold: float) -> void:
	if _banner != null:
		_banner.show_line(text, hold)


## E on a note: open its slip, or close it when it is the one already open. Reading is LOCAL presentation:
## nothing is sent, tracked or paid.
func _toggle_note(note: ClueNote) -> void:
	if _note_slip == null or note == null:
		return
	if _open_note == note and _note_slip.is_open():
		_close_note()
		return
	_open_note = note
	_note_slip.open_note(note.format, note.header, note.text, note.accent, _run.company if _run != null else "")
	_log("[note %s F%d] %s" % [note.format, _floor_n(), note.text], Color(1.0, 0.95, 0.7))


func _close_note() -> void:
	_open_note = null
	if _note_slip != null:
		_note_slip.close_note()


## Each frame: the open slip closes when its reader walks away (or dies, or a menu or the end takes over).
func _update_note_slip() -> void:
	if _open_note == null:
		return
	var gone := not is_instance_valid(_open_note) or player == null or player.dead or _menu != null or _van_menu != null 			or _leaving or _ended or _ending
	if not gone:
		var d := Vector2(player.global_position.x - _open_note.global_position.x, player.global_position.z - _open_note.global_position.z).length()
		gone = d > ClueNote.READ_RANGE + NOTE_CLOSE_SLACK
	if gone:
		_close_note()


# --- Objectives ------------------------------------------------------------------------------------

func _on_gate_closed(gate: Actor) -> void:
	var id := gate.get_instance_id()
	if _closed_gates.has(id) or _session == null or _ended:
		return
	_closed_gates[id] = true
	var is_origin := gate == _site.origin_gate
	if _joining:
		return   # (M6: a late joiner sees the gates the crew closed before it came as closed, with no fanfare)
	if not _keeps_books():
		# A client: the host closed it (world.die). Its bookkeeping and pay arrive from the host (obj.contract, obj.ledger).
		if is_origin:
			hud.show_center("ORIGIN GATE CLOSED", Color(1.0, 0.85, 0.4), 2.2)
			_show_banner("The origin gate is shut. The site calms down. The invoice does not.", 6.0)
		_log("%s closed" % ("ORIGIN gate" if is_origin else "hellgate"), Color(0.6, 1.0, 0.7))
		return
	var pay := _session.gate_closed(is_origin)
	_publish_contract()
	if is_origin:
		hud.show_center("ORIGIN GATE CLOSED", Color(1.0, 0.85, 0.4), 2.2)
		_show_banner("The origin gate is shut. The site calms down. The invoice does not.", 6.0)
	_log("%s closed  +%s" % ["ORIGIN gate" if is_origin else "hellgate", ContractRun.money(pay)], Color(0.6, 1.0, 0.7))
	_objective_t = 0.0   # re-check cleanliness now


## True where the contract's books are kept: solo, and the host of a shared run (M3). A client mirrors the host's.
func _keeps_books() -> bool:
	return not (_shared and not Net.is_host())


## Host of a crew: the objective bookkeeping changed; every client's tracker follows (NetObjects, obj.contract).
func _publish_contract() -> void:
	if _crewed() and Net.is_host() and _session != null:
		Session.objects.send_contract(_session.mirror_state())


## Client: the host's bookkeeping arrived.
func _on_contract_mirror(d: Dictionary) -> void:
	if _session == null or _keeps_books():
		return
	_session.apply_mirror(d)
	_update_tracker()


func _on_ledger_line(line: Dictionary) -> void:
	if str(line["kind"]) == "earn":
		var lbl := str(line["label"])
		if lbl.begins_with("Hellgate") or lbl.begins_with("Pest") or lbl.begins_with("ORIGIN"):
			hud.show_message("%s  +%s" % [lbl, ContractRun.money(int(line["amount"]))], Color(0.6, 1.0, 0.7))
	_update_tracker()


## Living monsters of the contract's pest kind on this floor ("everything": every monster).
func _pest_alive() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("monsters"):
		var m := node as Monster
		if m == null or m.dead:
			continue
		if _run.pest == "everything" or m.kind == _run.pest:
			n += 1
	return n


func _check_objectives() -> void:
	var paid := _session.check_clean(_pest_alive())
	if paid > 0:
		_publish_contract()
		hud.show_center("FLOOR CLEAN", Color(0.6, 1.0, 0.8), 1.8)
		_log("floor clean: %s cleared  +%s" % [ClientArchetype.pest_name(_run.pest), ContractRun.money(paid)], Color(0.6, 1.0, 0.7))
	_update_tracker()


func _update_tracker() -> void:
	if _tracker == null or _session == null:
		return
	var st := _session.state()
	var rows: Array[Dictionary] = []
	if not st.is_empty():
		var total := int(st["gates_total"])
		if total > 0:
			var closed := int(st["gates_closed"])
			rows.append({"text": "Close hellgates", "detail": "%d / %d" % [closed, total], "state": "done" if closed >= total else ("partial" if closed > 0 else "todo")})
		if bool(st["origin"]):
			rows.append({"text": "ORIGIN gate", "detail": "closed" if bool(st["origin_closed"]) else "OPEN", "state": "done" if bool(st["origin_closed"]) else "todo"})
		var left := _pest_alive()
		var clean := bool(st["pest_paid"])
		rows.append({"text": "Exterminate %s" % ClientArchetype.pest_name(_run.pest), "detail": "clean" if clean else "%d left" % left, "state": "done" if clean else "todo"})
		var alive_here := 0
		var following := 0
		for e in _site.employees:
			if is_instance_valid(e) and not e.dead and not bool(e.call("is_extracted")):
				alive_here += 1
				if e.has_method("is_following") and bool(e.call("is_following")):
					following += 1
		var spawned := int(st["employees"])
		if spawned > 0:
			var lost := int(st["lost"])
			var rescued := int(st["extracted"])
			var parts: Array[String] = []
			if rescued > 0:
				parts.append("%d rescued" % rescued)
			parts.append("%d alive" % alive_here)
			if following > 0:
				parts.append("%d with you" % following)
			if lost > 0:
				parts.append("%d lost" % lost)
			var detail := " · ".join(parts)
			rows.append({"text": "Employees", "detail": detail, "state": "fail" if lost > 0 else ("done" if rescued > 0 and alive_here == 0 else "todo")})
	_tracker.show_state("FLOOR %d / %d" % [_floor_n(), ContractRun.FLOOR_COUNT], _run.company, rows, Ledger.payout(), Ledger.deducted())
	if _ticker != null:
		_ticker.offset_top = _tracker.offset_bottom + 10.0
		_ticker.offset_bottom = _ticker.offset_top + 220.0


func _on_actor_died(a: Actor) -> void:
	if a.team == GameWorld.TEAM_MONSTERS:
		_kills += 1
		_log("%s died" % a.display_name, Color(0.7, 0.7, 0.7))
	elif a.team == GameWorld.TEAM_HEROES:
		_log("%s is down!" % a.display_name, Color(1.0, 0.45, 0.45))
	elif _site != null and _site.employees.has(a) and _joining:
		pass   # (M6: lost before this joiner arrived)
	elif _site != null and _site.employees.has(a):
		var cause: String = str(_emp_cause.get(a.get_instance_id(), "unknown"))
		if _keeps_books():
			_session.employee_lost(a.display_name, cause)
			_publish_contract()
		_log("%s was lost (%s)" % [a.display_name, cause], Color(1.0, 0.6, 0.4))
		hud.show_message("%s lost (%s)" % [a.display_name, cause], Color(1.0, 0.55, 0.4))
		_update_tracker()


# --- The elevator ----------------------------------------------------------------------------------------

## True when the living player stands at the elevator: on or next to its landing (the exit cell, in front of the doors: the
## doorway cells are next to it) or in its car, for both placements.
func _player_at_elevator() -> bool:
	if player == null or player.dead:
		return false
	if Hex.distance(player.current_cell(), _exit_cell) <= ELEVATOR_USE_DIST:
		return true
	return _site != null and ElevatorGeo.inside(_site.plan.elevator, Vector2(player.global_position.x, player.global_position.z))


## True when the van is parked on this floor (floor 1 only) and its plan is there.
func _has_van() -> bool:
	return _arrival != null and _floor_n() == VAN_FLOOR and _site != null and not _site.plan.van.is_empty()


## The floor in front of the van's sliding side door (world X/Z); INF when there is no van here.
func _van_door_pos() -> Vector2:
	if not _has_van():
		return Vector2(INF, INF)
	return _site.plan.van["door"]


## True when `pos` is within `dist` of the van's side door (always false on floors 2 and 3).
func _near_van(pos: Vector3, dist: float) -> bool:
	return _has_van() and Vector2(pos.x, pos.z).distance_to(_van_door_pos()) <= dist


## True when `pos` is within `dist` (world units) of the elevator: its doorway or its landing (or in the car).
func _near_elevator_world(pos: Vector3, dist: float) -> bool:
	if _site != null and not _site.plan.elevator.is_empty():
		return ElevatorGeo.door_distance(_site.plan.elevator, Vector2(pos.x, pos.z)) <= dist
	var ex := Hex.to_world(_exit_cell)
	return Vector2(pos.x, pos.z).distance_to(Vector2(ex.x, ex.z)) <= dist


## True when the living player stands at the van's side door.
func _player_at_van() -> bool:
	return player != null and not player.dead and _near_van(player.global_position, VAN_USE_DIST)


## What E would act on right now. UseTarget.kind: "van" (clock out), "elevator", "employee" (bring / tell to wait) or
## "note" (read it, or close the slip when it is the note already open).
## `verb` is the short caption for the use prompt and `pos` the world point it floats at. This is the ONE place that
## decides the priority (the van exit, then the elevator, then the employee next to the hero, then a note), shared by the E press
## (_use_key, press_use) and the prompt (_update_use_prompts), so the prompt can never promise something else.
## null when E would do nothing: no contract, a slip open, the contract ending, or nothing in reach.
class UseTarget extends RefCounted:
	var kind := ""
	var verb := ""
	var pos := Vector3.ZERO
	var employee: Employee = null
	var note: ClueNote = null


func use_target() -> UseTarget:
	if _menu != null or _van_menu != null or _leaving or _ended or _ending or _session == null:
		return null
	if player == null or player.dead or _arrival_running():
		return null   # (nothing to use while the crew is still arriving: the van's or the elevator's beat)
	var t := UseTarget.new()
	if _player_at_van():
		var door := _van_door_pos()
		t.kind = "van"
		t.verb = "Clock out"
		t.pos = Vector3(door.x, _floor_y(door.x, door.y) + PROMPT_ABOVE_VAN, door.y)
	elif _player_at_elevator():
		var ex := Hex.to_world(_exit_cell)
		t.kind = "elevator"
		t.verb = "Elevator"
		t.pos = Vector3(ex.x, _floor_y(ex.x, ex.z) + PROMPT_ABOVE_ELEVATOR, ex.z)
	else:
		var e := Employee.interact_target(player)
		if e != null and (Net.simulates(e) or Net.is_puppet(e)):   # (a client's E on the host's employee is a request: Employee.interact)
			t.kind = "employee"
			t.verb = e.interact_verb(player)
			t.pos = e.prompt_point()
			t.employee = e
			return t
		var n := _note_target()
		if n == null:
			var pickup := player.swap_target()   # E swaps a dropped component into the held slot (was F; user, 2026-10-18)
			if pickup == null:
				return null
			t.kind = "pickup"
			t.verb = "Swap in %s" % SpellBook.component_name(pickup.spell_id)
			t.pos = pickup.global_position + Vector3(0.0, PROMPT_ABOVE_PICKUP, 0.0)
			return t
		t.kind = "note"
		t.verb = "Close" if n == _open_note and _note_slip != null and _note_slip.is_open() else n.verb()
		t.pos = n.prompt_point()
		t.note = n
	return t


## The note E would act on: the open one while its reader is still near it, else the nearest in reach.
func _note_target() -> ClueNote:
	if _open_note != null and is_instance_valid(_open_note) and _note_slip != null and _note_slip.is_open():
		var d := Vector2(player.global_position.x - _open_note.global_position.x, player.global_position.z - _open_note.global_position.z).length()
		if d <= ClueNote.READ_RANGE + NOTE_CLOSE_SLACK:
			return _open_note
	return ClueNote.nearest(player.global_position)


## The ground height under world (x, z), falling back to the player's feet when there is no cell there.
func _floor_y(x: float, z: float) -> float:
	var h := map.ground_height(Vector3(x, 0.0, z)) if map != null else NAN
	return player.global_position.y if is_nan(h) else h


## E (the controller calls this first; true = the press is used). Acts on use_target(): the van and elevator open their
## slips; an employee is dismissed or recruited (Employee.interact picks the same one). E never casts.
func _use_key() -> bool:
	var t := use_target()
	if t == null:
		return false
	match t.kind:
		"van":
			_open_van_exit()
			return true
		"elevator":
			_open_elevator()
			return true
		"note":
			_toggle_note(t.note)
			return true
		"pickup":
			return player.swap_in_pickup()
	return Employee.interact(player)


## Point the use prompt: E at use_target(). Each frame.
func _update_use_prompts() -> void:
	if _use_prompt == null:
		return
	var t := use_target()
	if t == null:
		_use_prompt.hide_prompt()
	else:
		_use_prompt.show_at(t.pos, "E", t.verb)


func _check_elevator() -> void:
	if _menu != null or _van_menu != null or _leaving or not opts.has("auto_elevator"):
		return   # without --auto-elevator the menu opens only on E (see _use_key)
	if _shared and not _floor_begun:
		return   # (a shared floor: not behind the barrier)
	if not _arrivals_done():
		return   # (not while the crew is still stepping out of the car)
	var on_exit := false
	for h in _heroes():
		if not h.dead and h.current_cell() == _exit_cell:
			on_exit = true
			break
	if not on_exit:
		if _elev_armed:
			return
		var far := true
		for h in _heroes():
			if not h.dead and Hex.distance(h.current_cell(), _exit_cell) <= ELEVATOR_REARM_DIST:
				far = false
		_elev_armed = far
		return
	if _elev_armed:
		_open_elevator()


## Employees that follow a hero and stand within a few cells of `cell` (an exit) ride out with the crew.
func _followers_near_cell(cell: Vector2i) -> Array[Actor]:
	var out: Array[Actor] = []
	if _site == null:
		return out
	for e in _site.employees:
		if is_instance_valid(e) and not e.dead and e.has_method("is_following") and bool(e.call("is_following")):
			if Hex.distance(e.current_cell(), cell) <= FOLLOW_EXTRACT_CELLS:
				out.append(e)
	return out


func _followers_near_exit() -> Array[Actor]:
	return _followers_near_cell(_exit_cell)


## The followers near the van's side door (none on floors 2 and 3).
func _followers_near_van() -> Array[Actor]:
	if not _has_van():
		var none: Array[Actor] = []
		return none
	var d := _van_door_pos()
	return _followers_near_cell(Hex.from_world(Vector3(d.x, 0.0, d.y)))


## Extract these employees now: the exit animation and bark, then $100 each in the Ledger (ContractSession.extract). An
## employee extracted here is out of the "employees" group and no longer following, so nothing counts them again (not as a
## follower at the exit). Used by the drop-off and by taking an exit.
func _extract_followers(riders: Array[Actor], line: String) -> void:
	if riders.is_empty():
		return
	for e in riders:
		if e.has_method("extract"):
			e.call("extract", line)
	_session.extract(riders.size(), player)
	_publish_contract()
	var pay := ContractRun.money(riders.size() * ContractRun.EMPLOYEE_EXTRACTED)
	if riders.size() == 1:
		_log("%s extracted  +%s" % [riders[0].display_name, pay], Color(0.6, 1.0, 0.7))
		hud.show_message("%s is out  +%s" % [riders[0].display_name, pay], Color(0.6, 1.0, 0.7))
	else:
		_log("%d employees extracted  +%s" % [riders.size(), pay], Color(0.6, 1.0, 0.7))
		hud.show_message("%d employees out  +%s" % [riders.size(), pay], Color(0.6, 1.0, 0.7))
	_update_tracker()


## The drop-off: an employee who is FOLLOWING the crew and gets within DROPOFF_DIST of the van's door or the elevator
## leaves right away ($100, once), whether or not the crew ever takes the exit. Waiting and cowering employees never do.
func _check_dropoffs() -> void:
	if _site == null or _session == null or _menu != null or _van_menu != null or _leaving or _ended:
		return
	for e in _site.employees:
		if not is_instance_valid(e) or e.dead or not e.has_method("is_following") or not bool(e.call("is_following")):
			continue
		var pos: Vector3 = e.global_position
		if _near_van(pos, DROPOFF_DIST) or _near_elevator_world(pos, DROPOFF_DIST):
			var one: Array[Actor] = [e]
			_extract_followers(one, "I'm out, thanks!")


func _elevator_lines() -> Array[String]:
	var lines: Array[String] = []
	var st := _session.state()
	if not st.is_empty():
		var total := int(st["gates_total"])
		if total > 0:
			lines.append("Hellgates closed on this floor: %d of %d." % [int(st["gates_closed"]), total])
		if bool(st["origin"]):
			lines.append("Origin gate: %s." % ("closed" if bool(st["origin_closed"]) else "still open (the biggest line on the invoice)"))
		lines.append("Floor %s." % ("clean" if bool(st["pest_paid"]) else "not clean: %d %s left" % [_pest_alive(), ClientArchetype.pest_name(_run.pest)]))
	lines.append("Objectives not met do not pay. Damage comes out of what you earned.")
	return lines


func _open_elevator() -> void:
	if _crewed() and Session.objects.exit_taken():
		return   # the crew is already on its way
	var info := {
		"floor": _floor_n(), "floor_count": ContractRun.FLOOR_COUNT,
		"payout": Ledger.payout(), "damages": Ledger.deducted(),
		"followers": _followers_near_exit().size(), "lines": _elevator_lines(),
	}
	_menu = ElevatorMenu.new(info)
	_screens().add_child(_menu)
	_freeze(true)
	_menu.go_down.connect(func() -> void: _choose_exit("down"))
	_menu.cash_out.connect(func() -> void: _choose_exit("out"))
	_menu.stay.connect(_close_elevator.bind(true))
	if opts.has("auto_elevator"):
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			if _menu != null:
				_choose_exit("down" if str(opts["auto_elevator"]) == "down" and _menu.can_descend() else "out"))


## The clock-out slip at the van (floor 1): the crew's other exit, the same as the elevator's "Exit".
func _open_van_exit() -> void:
	if _crewed() and Session.objects.exit_taken():
		return
	var info := {
		"floor": _floor_n(), "floor_count": ContractRun.FLOOR_COUNT,
		"payout": Ledger.payout(), "damages": Ledger.deducted(),
		"followers": _followers_near_van().size(), "lines": _elevator_lines(),
	}
	_van_menu = VanExitMenu.new(info)
	_screens().add_child(_van_menu)
	_freeze(true)
	_van_menu.clock_out.connect(func() -> void: _choose_exit("van"))
	_van_menu.cancel.connect(_close_elevator.bind(true))


## Closes whichever exit slip is open (the elevator's or the van's).
func _close_elevator(disarm: bool) -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
	if _van_menu != null:
		_van_menu.queue_free()
		_van_menu = null
	_freeze(false)
	if disarm:
		_elev_armed = false


## Stop (or resume) the simulation and the player's input; the HUD and menus keep running. While crewed (M3, the M5b rule)
## a menu stops only this player's own hero: the world goes on for everyone else.
func _freeze(on: bool) -> void:
	var self_only := on and _crewed() and _floor_begun and not _ended and not _leaving
	if GameWorld.root != null and not self_only:
		GameWorld.root.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	if controller != null and not on:
		controller.enabled = not player.dead and not _ended
	elif controller != null:
		controller.enabled = false


## A row picked on the elevator ("down", "out") or the van ("van"). Solo it happens at once; in a crew the FIRST player
## to choose decides for everyone (NetObjects: the host takes the first choice and tells the crew, _on_exit_decided).
func _choose_exit(choice: String) -> void:
	if not _crewed():
		match choice:
			"down":
				_use_elevator(true)
			"out":
				_use_elevator(false)
			"van":
				_use_van()
		return
	_close_elevator(false)
	if controller != null:
		controller.enabled = false
	hud.show_message("Asking the crew...", Color(0.8, 0.9, 1.0))
	Session.objects.choose_exit(choice)
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if not _leaving and not _ended and not Session.objects.exit_taken() and controller != null and player != null and not player.dead:
			controller.enabled = true)


## The crew's exit was decided (every machine, M3): by whoever chose first. The host does it; a client follows.
func _on_exit_decided(choice: String, seat: int) -> void:
	if _leaving or _ended or _session == null or _joining:
		return   # (M6: a joiner still building follows the crew through Session.join instead)
	_close_pause()
	_close_elevator(false)
	var who := str(_names.get(Session.seats.owners.get(seat, 0), "")) if Session.seats != null else ""
	if who == "" and heroes_by_seat.has(seat):
		who = Net.label_of(heroes_by_seat[seat])
	var what := "takes the elevator down" if choice == "down" else "clocks the crew out"
	hud.show_center("%s %s" % [who, what], Color(1.0, 0.9, 0.6), 2.0)
	_log("exit: %s (seat %d) %s" % [who, seat, what], Color(1.0, 0.9, 0.6))
	if choice == "down":
		_descend_shared()
		return
	if Net.is_host():
		if choice == "van":
			_use_van()
		else:
			_use_elevator(false)
		return
	if controller != null:
		controller.enabled = false   # a client waits for the host's invoice (obj.end)


## The crew goes down (shared run): every machine keeps its heroes' HP and downed state for the next floor, and reloads
## onto it; the host starts the barrier (CrewFlow.host_next_floor) and the floor starts when everyone has built it.
func _descend_shared() -> void:
	if _leaving:
		return
	if Net.is_host():
		_extract_followers(_followers_near_exit(), "thank you!")
	_leaving = true
	_update_hero_sync()
	_freeze(true)
	_session.save_carry(_heroes())
	_session.descend()
	if Net.is_host():
		_flow.host_next_floor()
	_fade(0.0, 1.0, 0.45, func() -> void:
		_fade_in = true
		_change_scene(""))


func _use_elevator(descend: bool) -> void:
	if _leaving:
		return
	_extract_followers(_followers_near_exit(), "thank you!")
	if not descend:
		_end_contract(ContractSession.END_CASHED_OUT)
		return
	_leaving = true
	_close_elevator(false)
	_freeze(true)
	_session.save_carry(_heroes())
	_session.descend()
	_fade(0.0, 1.0, 0.45, func() -> void:
		_fade_in = true
		get_tree().reload_current_scene())


## Clock out at the van: the followers near it are extracted, then the contract ends exactly like the elevator's exit.
func _use_van() -> void:
	if _leaving or _ended:
		return
	_extract_followers(_followers_near_van(), "thank you!")
	_end_contract(ContractSession.END_CASHED_OUT)


## A full-screen black overlay that fades from alpha `a` to `b`.
func _fade(a: float, b: float, seconds: float, done: Callable = Callable()) -> void:
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, a)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screens().add_child(rect)
	var tw := create_tween()
	tw.tween_property(rect, "color:a", b, seconds)
	if done.is_valid():
		tw.tween_callback(done)
	elif b <= 0.0:
		tw.tween_callback(rect.queue_free)


# --- The end: the invoice --------------------------------------------------------------------------------

## All heroes down, or the crew cashed out: pay the employees still alive, then show the invoice.
func _end_contract(reason: String) -> void:
	if _ended:
		return
	_ended = true
	_close_pause()
	_close_elevator(false)
	_freeze(true)
	# Corporate revives every hero still down, and the client is billed (Ledger.revival). Online the host decides it from
	# every hero's replicated `dead` and names each by its player (two players may both be Wick); solo it is the hero's name.
	var downed: Array[String] = []
	for h in _heroes():
		if h.dead:
			downed.append(_crew_label(h))
	_session.finish(reason, downed)
	if Net.is_host() and _flow != null:
		_flow.host_job_ended()   # (M6: a player joining now starts with the crew at the next board)
	var inv := ContractInvoice.build(_session)
	if _crewed() and Net.is_host():
		Session.objects.send_end(inv)   # M3: every client shows the host's invoice
	LastContract.record(inv)   # the main menu's garage shows the morning after a bad job
	_log("contract over (%s): earned %s, damages %s, payout %s" % [reason, ContractRun.money(int(inv["earned"])), ContractRun.money(int(inv["damages"])), ContractRun.money(int(inv["payout"]))], Color(1.0, 0.9, 0.5))
	_show_invoice(inv)


## Client: the host ended the job (cashed out, or the crew went down); its invoice is the one.
func _end_from_host(inv: Dictionary) -> void:
	if _ended or _session == null or _keeps_books() or _joining:
		return
	_ended = true
	_close_pause()
	_close_elevator(false)
	_freeze(true)
	_session.finished = true
	_session.end_reason = str(inv.get("reason", ""))
	Ledger.end_contract()
	LastContract.record(inv)
	_log("contract over (%s): earned %s, damages %s, payout %s" % [str(inv.get("reason", "")), ContractRun.money(int(inv.get("earned", 0))), ContractRun.money(int(inv.get("damages", 0))), ContractRun.money(int(inv.get("payout", 0)))], Color(1.0, 0.9, 0.5))
	_show_invoice(inv)


func _show_invoice(inv: Dictionary) -> void:
	_last_invoice = inv
	if debug_panel != null:
		debug_panel.visible = false
	_invoice = InvoiceScreen.new(inv)
	if _crewed():
		_invoice.next_note = "Takes the whole crew back to the board."   # (M5: anyone's Next does)
	_screens().add_child(_invoice)
	_invoice.next_contract.connect(_on_next_contract)
	if opts.has("shot") and _session != null:
		_take_shot_later(str(opts["shot"]), 1.5)


## "Next contract" on the invoice: back to the job board for a new contract. In a crew ANY player's Next takes everyone
## back (M5, decided like the exits: the first player to choose decides): a client asks the host (crew.again), and the
## host's new board (crew.board) brings the whole crew, the asking client included.
func _on_next_contract() -> void:
	if _leaving:
		return
	if _shared and not Net.is_host() and Net.crewed():
		_flow.request_again()
		return
	_leaving = true
	_dev_released = true
	_run = null
	_session = null
	_spells.clear()
	Ledger.end_contract()
	_change_scene("")   # (the job board; a test records it)


## Host (M5): a client pressed "Next contract" on its invoice; the host's own Next does it for everyone.
func _on_again_requested(peer: int) -> void:
	if _invoice != null and _ended and not _leaving:
		_log("next contract: asked by %s" % str(_names.get(peer, peer)), Color(1.0, 0.9, 0.6))
		_on_next_contract()


## --invoice-demo: a sample contract with a believable ledger, straight to the invoice.
func _invoice_demo() -> void:
	var run := ContractBoard.run_for_seed(int(opts.get("seed", 12)))
	var s := ContractSession.begin(run, 1)
	var wick := _demo_hero("Wick")
	var rebar := _demo_hero("Rebar")
	var gasket := _demo_hero("Gasket")
	s.enter_floor(1, run.floor_gates[0], false, run.floor_employees[0], 12)
	for _i in run.floor_gates[0]:
		s.gate_closed(false)
	s.check_clean(0)
	s.extract(2)
	Ledger.damage("Wine rack", 1200, wick)
	s.enter_floor(2, run.floor_gates[1], false, run.floor_employees[1], 14)
	for _i in run.floor_gates[1]:
		s.gate_closed(false)
	s.check_clean(0)
	Ledger.damage("Zen fountain", 900, rebar)
	Ledger.damage("Crystal lamp", 600, wick)
	Ledger.damage("Crystal lamp", 600, gasket)
	s.employee_lost("Colin (valet)", "Wick")
	s.enter_floor(3, 0, true, run.floor_employees[2], 18)
	s.gate_closed(true)
	s.check_clean(0)
	s.extract(1)
	Ledger.damage("Gold toilet", 15000, wick)
	s.finish(ContractSession.END_CASHED_OUT)
	var inv := ContractInvoice.build(s)
	for h in [wick, rebar, gasket]:
		h.free()
	_session = s
	_run = run
	_show_invoice(inv)
	_invoice.next_contract.disconnect(_on_next_contract)


func _demo_hero(hero_name: String) -> Actor:
	var a := Actor.new()
	a.display_name = hero_name
	return a


# --- Crew ------------------------------------------------------------------------------------------------

## All heroes down ends the contract (the invoice still pays what was earned). A downed player hands the
## camera to a living ally.
func _check_crew() -> void:
	var any_alive := false
	for h in _heroes():
		if not h.dead:
			any_alive = true
	if not any_alive:
		if not _ending:
			_ending = true
			controller.enabled = false
			hud.show_center("Crew incapacitated", Color(1.0, 0.4, 0.35))
			if _keeps_books():   # (a client: the host ends the job and sends its invoice)
				get_tree().create_timer(INCAP_DELAY).timeout.connect(func() -> void: _end_contract(ContractSession.END_INCAPACITATED))
		return
	if player.dead and not _player_down_noted:
		_player_down_noted = true
		controller.enabled = false
		_follow_living_ally()
		hud.show_message("You are down. Your crew fights on.", Color(1.0, 0.6, 0.45))


func _physics_process(delta: float) -> void:
	if _ended or _leaving or player == null or _session == null or _joining:
		return
	_check_crew()
	if _ending:
		return
	if _shared and not Net.is_host():
		return   # the host decides objectives, drop-offs and exits (M5 shares them)
	_check_elevator()
	_check_dropoffs()
	_objective_t -= delta
	if _objective_t <= 0.0:
		_objective_t = OBJECTIVE_INTERVAL
		_check_objectives()


func _process(delta: float) -> void:
	if voice:
		hud.set_mic_level(voice.get_level())
	_update_note_slip()
	_update_use_prompts()
	_stats_timer -= delta
	if _stats_timer <= 0.0:
		_stats_timer = 0.25
		_update_stats()


## A fresh key / click / pad press (not Esc, which opens the pause menu) skips the van's arrival.
static func _is_skip_press(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo() or event.is_action_pressed("pause"):
		return false
	return event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton


func _unhandled_input(event: InputEvent) -> void:
	if _arrival_running() and _is_skip_press(event):
		# never trap the player: any key or click jumps to the end of the arrival
		if _arrival != null and _arrival.is_running():
			_arrival.skip()
		if _lift != null and _lift.is_running():
			_lift.skip()
	if _confirm != null or _invite != null:
		return   # the leave question (or the invite question) has the keys
	if event.is_action_pressed("restart"):
		if _joining or _join_slip != null:
			return   # (M6: not on the job yet)
		_abandon_to_board()
	elif event.is_action_pressed("pause"):
		# Back is VOID (form-rules.md §6): Esc stamps the form on screen and its own back runs after the hold (FormVoid).
		if _picker != null:
			_picker.void_back()      # the license checkout: back to the same three offers (a client, or a joiner's 15-S, leaves the crew)
		elif _join_slip != null:
			_join_slip.void_back()   # (M6: still clocking in: leave the crew)
		elif _board != null:
			_board.void_back()       # the job board: back to the menu (a crew host confirms first)
		elif _shared and _session == null:
			_request_leave()  # a client still waiting for the host's board
		elif _can_pause():
			_open_pause()
	elif event.is_action_pressed("toggle_voice_debug") and debug_panel != null and _invoice == null:
		debug_panel.visible = not debug_panel.visible


# --- Pause (Esc) ----------------------------------------------------------------------------------------

## A contract is running and nothing else (picker, elevator, invoice, ending, scene change) holds the screen.
func _can_pause() -> bool:
	return _pause == null and _session != null and player != null and _picker == null and _menu == null and _van_menu == null \
			and _invoice == null and not _ended and not _ending and not _leaving


## The pause overlay; the whole tree stops (GameWorld's clock, actors, spells, tweens, the voice caster)
## except the overlay itself, which runs while paused. With another player in the crew nothing pauses (decided, M5: the
## floor clock and the cast schedule run on host_time()): the overlay opens, says so, and only your own hero stands still.
func _open_pause() -> void:
	_pause = PauseMenu.new()
	_pause.online = _crewed()
	_pause.hosting = Net.is_host()
	_pause.can_invite = Session.can_invite() or opts.has("show_invite_row")   # (M7: a Steam crew with a free seat)
	_screens().add_child(_pause)
	_shot_stage("pause", 1.0)
	get_tree().paused = not _crewed()   # with a crew the others play on: no local pause (M5)...
	if _crewed() and controller != null:
		controller.enabled = false          # ... but your own hero stands still while the menu is open
	_pause.resume.connect(_close_pause)
	_pause.abandon.connect(_abandon_to_board)
	_pause.main_menu.connect(_request_leave)
	_pause.invite.connect(func() -> void: Session.invite_crew())


func _close_pause() -> void:
	if _pause == null:
		return
	_pause.queue_free()
	_pause = null
	get_tree().paused = false
	if _crewed() and controller != null and player != null and not player.dead and not _ended and not _arrival_running():
		controller.enabled = true
	if voice != null:
		voice.reset()   # drop audio heard while the game was stopped


## F5 and "Abandon contract": back to the job board; the contract is dropped, and the dev flags that skip
## the board stop applying. In a crew ANYONE's abandon takes the whole crew back to a new board (M5): the host does it
## (a client asks, crew.abandon) and the clients follow its crew.board, whose note says who abandoned.
func _abandon_to_board() -> void:
	if _leaving:
		return
	if _shared and not Net.is_host():
		if not Net.crewed():
			_request_leave()   # (the host is gone: nothing to abandon together)
			return
		_close_pause()
		if controller != null:
			controller.enabled = false
		if hud != null:
			hud.show_message("Abandoning the job...", Color(1.0, 0.75, 0.45))
		_flow.request_abandon()
		return
	if _crewed() and _session != null and not _ended:
		_board_note = "%s abandoned the job" % str(Session.local_entry().get("name", "The host"))
	_abandon_now()


## Host (M5): a client abandoned the contract; the whole crew goes back to the board.
func _on_abandon_requested(peer: int) -> void:
	if _leaving or _session == null or _ended:
		return
	var who := str(_names.get(peer, "A player"))
	_log("abandon: asked by %s" % who, Color(1.0, 0.75, 0.45))
	_board_note = "%s abandoned the job" % who
	_abandon_now()


func _abandon_now() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().paused = false
	_dev_released = true
	_board_seed = -1   # an abandoned job: deal a new board
	_run = null
	_session = null
	_spells.clear()
	Ledger.end_contract()
	_change_scene("")


## Back out of the license checkout (Esc or its "Back to the board" row): the job isn't started, so nothing is
## billed; the board reopens with the same three offers. A client has no board of its own to go back to: it
## leaves the crew. The host going back sends the whole crew back to its board.
func _back_to_board() -> void:
	if _leaving:
		return
	if _shared and not Net.is_host():
		_request_leave()
		return
	_back_to_board_local()


func _back_to_board_local() -> void:
	if _leaving:
		return
	_leaving = true
	_dev_released = true
	_run = null
	_session = null
	_spells.clear()
	Ledger.end_contract()
	_change_scene("")


## Leave the job for the menu: a client leaves the crew; a host with a crew is asked first, because its leaving
## ends the session for everyone. A host alone, and solo, just go.
func _request_leave() -> void:
	if _leaving or _confirm != null:
		return
	if Session.online() and Session.hosting and Net.crewed():
		_confirm = CrewConfirm.new()
		_screens().add_child(_confirm)
		_confirm.confirmed.connect(func() -> void:
			_close_confirm()
			_to_main_menu())
		_confirm.declined.connect(_close_confirm)
		return
	_to_main_menu()


## M7: a Steam overlay invite was accepted while this screen is up. Ask "Leave this job and join?" first (Stay is the
## default). Solo, the tree stops while it asks; with a crew the job runs on (no local pause online).
func _on_invite(_lobby_id: int, inviter: String) -> void:
	if _leaving:
		Session.decline_invite()
		return
	_close_invite()
	_close_pause()
	_invite = InviteConfirm.new()
	_invite.inviter = inviter
	_invite.on_job = _session != null and not _ended
	_invite.hosting_crew = Session.online() and Session.hosting and Net.crewed()
	_invite.in_crew = Session.is_client()
	_screens().add_child(_invite)
	_invite_paused = not _crewed() and not get_tree().paused
	if _invite_paused:
		get_tree().paused = true
	_invite.confirmed.connect(_accept_invite)
	_invite.declined.connect(func() -> void:
		Session.decline_invite()
		_close_invite())


func _accept_invite() -> void:
	_close_invite()
	if _leaving:
		return
	_leaving = true   # (the session ending under us must not send us to the menu a second time)
	get_tree().paused = false
	reset_flow()
	Ledger.end_contract()
	Session.accept_invite()   # leaves this crew (if any) and joins theirs; the menu shows how it goes
	_change_scene(Boot.MENU_SCENE)


func _close_invite() -> void:
	if _invite == null:
		return
	_invite.queue_free()
	_invite = null
	if _invite_paused:
		_invite_paused = false
		get_tree().paused = _pause != null and not _crewed()


func _close_confirm() -> void:
	if _confirm != null:
		_confirm.queue_free()
		_confirm = null


## "Main menu" (pause overlay, Esc on the job board): drop the contract and open the menu scene. Online it also
## leaves the session: a client leaves the crew, a host's leaving ends it for everyone ("The host clocked out").
func _to_main_menu() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().paused = false
	if Session.online():
		Session.leave()
	reset_flow()
	Ledger.end_contract()
	_change_scene(Boot.MENU_SCENE)


## Shared run: the session ended under us (the host left, we were sent out, the link died). Back to the menu, which
## shows the reason (Session.last_reason). Screenshot runs stay put so the picture still gets taken.
func _on_session_ended(_reason: String) -> void:
	if _leaving or not _shared or opts.has("shot"):
		return
	_leaving = true
	get_tree().paused = false
	reset_flow()
	Ledger.end_contract()
	_change_scene(Boot.MENU_SCENE)


func _on_peer_left(peer: int) -> void:
	if hud != null:
		var note := "%s left the crew" % str(_names.get(peer, "A player"))
		for h: Dictionary in Session.seats.history:
			if str(h.get("kind", "ai")) == "ai" and int(h["peer"]) == peer and CREW_LOOKS.has(str(h["character"])):
				note += ". %s takes the seat." % str((CREW_LOOKS[str(h["character"])] as Dictionary)["name"])
		hud.show_message(note, Color(1.0, 0.75, 0.45))
	_note_names()


func _note_names() -> void:
	for e: Dictionary in Session.crew():
		_names[int(e["peer"])] = str(e["name"])
	_refresh_voice_owner()


## True while someone else is in the crew of a shared run: no local pause; exits are first-to-choose (M3).
func _crewed() -> bool:
	return _shared and Net.crewed()


## "" reloads this scene (the job board), anything else opens that scene.
func _change_scene(path: String) -> void:
	if scene_changer.is_valid():
		scene_changer.call(path)
	elif path == "":
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file(path)


func _update_stats() -> void:
	if game_stats == null or player == null or _run == null or _session == null:
		return   # (the run was dropped: a scene change is on its way)
	var lines: Array[String] = []
	lines.append("fps %d   floor %d/%d   seed %d" % [Engine.get_frames_per_second(), _floor_n(), ContractRun.FLOOR_COUNT, _run.floor_seed(_floor_n())])
	var c := player.current_cell()
	var cell: HexMap.Cell = map.get_cell(c)
	lines.append("you  hp %d/%d  cell %s  level %s%s" % [player.hp, player.max_hp, c,
		str(cell.level) if cell else "?", "  CLIMBING" if player.climbing else ""])
	for i in SpellComponents.SLOT_COUNT:
		var s := player.slot_spell(i)
		if s == "":
			lines.append("slot %d  -- empty --%s" % [i + 1, "   <- held" if player.held_slot == i else ""])
			continue
		var cd := player.cooldown_left(s)
		lines.append("slot %d  %s  x%d  %s  (cd %.1fs)%s" % [i + 1, s, player.charges_of(s), "ready" if cd <= 0.0 else "%.1fs" % cd,
				player.cooldown_total(s), "   <- HELD" if player.held_slot == i else ""])
	if player.has_modifier("armor"):
		lines.append("armor  dmg x%.2f" % player.damage_taken_mult())
	for a in allies:
		if is_instance_valid(a):
			lines.append("%s  hp %d%s" % [a.display_name, a.hp, "  DOWN" if a.dead else ""])
	var monsters := GameWorld.team_actors(GameWorld.TEAM_MONSTERS)
	var by_kind := {}
	var active := 0
	for m in monsters:
		var mon := m as Monster
		var k: String = mon.kind if mon else m.display_name
		by_kind[k] = int(by_kind.get(k, 0)) + 1
		if mon and (mon.state == Monster.State.CHASE or mon.state == Monster.State.ATTACK):
			active += 1
	var kinds: Array[String] = []
	for k: String in by_kind:
		kinds.append("%s %d" % [k, by_kind[k]])
	lines.append("monsters %d (%d fighting)  kills %d" % [monsters.size(), active, _kills])
	if not kinds.is_empty():
		lines.append("  " + "  ".join(kinds))
	lines.append("contract %s  pest %s  value %s" % [_run.invoice_number, _run.pest, ContractRun.money(_run.contract_value)])
	lines.append("payout %s  earned %s  damages %s" % [ContractRun.money(Ledger.payout()), ContractRun.money(Ledger.earned()), ContractRun.money(Ledger.damages())])
	lines.append("elevator %d hexes away" % Hex.distance(c, _exit_cell))
	game_stats.text = "\n".join(lines)


func _log(text: String, color: Color = Color.WHITE) -> void:
	print("[game] ", text)
	if debug_panel and debug_panel.has_method("log_game"):
		debug_panel.log_game(text, color)


func _take_shot_later(path: String, after: float) -> void:
	await get_tree().create_timer(after).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[game] screenshot saved: ", path)
	get_tree().quit()


## Dev flags --to-gate / --to-exit: move the crew (screenshots).
func _dev_teleports() -> void:
	if opts.has("to_hazard") and _to_hazard(str(opts["to_hazard"])):
		return
	if opts.has("to_pool") and _to_pool(str(opts["to_pool"])):
		return
	if opts.has("to_theme") and _site != null:
		var themed := _site.plan.rooms_with_theme(str(opts["to_theme"]))
		if not themed.is_empty():
			# the middle of the room's set dressing (the room's centre when it has none)
			var focus: Vector2i = _site.plan.centers[themed[0]]
			var sum := Vector2.ZERO
			var n := 0
			for dc in _site.plan.decor:
				if str(dc["room"]) == themed[0] and String(dc["place"]) != "ring":
					sum += dc["pos"]
					n += 1
			if n > 0:
				var mid := sum / float(n)
				focus = Hex.from_world(Vector3(mid.x, 0.0, mid.y))
				if map.get_cell(focus) == null or map.get_cell(focus).type != HexMap.Tile.FLOOR:
					focus = _site.plan.centers[themed[0]]
			if opts.get("focus", "") == "sign":
				# a few steps in front of the room's neon sign (screenshots of the sign)
				for dc in _site.plan.decor:
					if str(dc["room"]) == themed[0] and str(dc["kind"]) == "neon_sign":
						var front: Vector2 = (dc["pos"] as Vector2) + ThemeGeo.facing(float(dc["yaw"])) * 5.5
						var fc := Hex.from_world(Vector3(front.x, 0.0, front.y))
						if map.is_walkable_cell(fc):
							focus = fc
			_teleport_crew(focus)
			return
	if opts.has("to_corridor"):
		var corr: Array[Vector2i] = []
		for cc: Vector2i in map.cells:
			if map.cells[cc].tag == "corridor" and map.is_walkable_cell(cc):
				corr.append(cc)
		if not corr.is_empty():
			corr.sort()
			_teleport_crew(corr[int(corr.size() * 0.5)])
			return
	if opts.has("to_note") and _site != null and not _site.plan.notes.is_empty():
		# beside note N (the story note is 0, the hint slip 1), off to its side so nobody hides it from the camera
		var nt: Dictionary = _site.plan.notes[clampi(int(opts["to_note"]), 0, _site.plan.notes.size() - 1)]
		var nc: Vector2i = nt["cell"]
		var front := ThemeGeo.world(nc) + ThemeGeo.facing(float(nt.get("yaw", 0.0)) - 90.0) * 1.5
		var stand := nc
		var stand_d := INF
		var nlevel: int = map.get_cell(nc).level
		for c in Hex.range_cells(nc, 2):
			var cell4: HexMap.Cell = map.get_cell(c)
			if c != nc and cell4 != null and cell4.type == HexMap.Tile.FLOOR and cell4.level == nlevel and not _site.plan.blocked.has(c) 					and ThemeGeo.world(c).distance_to(front) < stand_d:
				stand_d = ThemeGeo.world(c).distance_to(front)
				stand = c
		_teleport_crew(stand)
		_log("to-note: %s %s at %s, crew at %s" % [nt["kind"], nt["format"], nc, stand], Color(0.8, 0.8, 1.0))
		return
	if opts.has("to_employee") and _site != null and not _site.plan.employees.is_empty():
		var ec: Vector2i = _site.plan.employees[0]["cell"]
		var stand := ec
		for c in Hex.ring(ec, 1):
			var cell3: HexMap.Cell = map.get_cell(c)
			if cell3 != null and cell3.type == HexMap.Tile.FLOOR:
				stand = c
				break
		_teleport_crew(stand)
		return
	if opts.has("to_package") and _site != null and not _site.plan.packages.is_empty():
		# two cells from the first stack, toward the middle of its room
		var pk: Dictionary = _site.plan.packages[0]
		var pc: Vector2i = pk["cell"]
		var mid: Vector2i = _site.plan.centers[str(pk["room"])]
		var near := pc
		var near_d := 99
		for c in Hex.ring(pc, 2):
			var cell2: HexMap.Cell = map.get_cell(c)
			if cell2 != null and cell2.type == HexMap.Tile.FLOOR and Hex.distance(c, mid) < near_d:
				near_d = Hex.distance(c, mid)
				near = c
		_teleport_crew(near)
		return
	if opts.has("to_gate") and _site != null and not _site.gates.is_empty():
		var gc: Vector2i = _site.plan.gates[0]["cell"]
		var best := gc
		var best_d := 99
		for c in Hex.ring(gc, 5):
			var cell: HexMap.Cell = map.get_cell(c)
			if cell != null and cell.type == HexMap.Tile.FLOOR and absi(cell.level - map.get_cell(gc).level) <= 1:
				var d := Hex.distance(c, gc)
				if d < best_d:
					best_d = d
					best = c
		_teleport_crew(best)
	elif opts.has("to_exit"):
		_teleport_crew(_exit_cell)


## Dev flag --break-crates: hit the crate stacks around the player (screenshots of the break).
func _break_crates_dev() -> void:
	for a in GameWorld.breakables_in_radius(player.global_position, 9.0):
		if a is BreakableCrate:
			a.apply_damage(5.0, player)


## --to-pool: the crew at the floor's first pool (of `look`, any when ""): seat 1 wading in the middle, seat 2 on the deck at
## the camera-near rim, seat 3 wading by the far rim; at a moat all three wade along the channel nearest the camera.
## False when the floor has no such pool.
func _to_pool(look: String) -> bool:
	for rec in map.pools:
		_log("pool: %s in %s (%s), %d basin cells" % [rec["look"], rec["room"], _site.plan.theme_of(str(rec["room"])) if _site != null else "", (rec["basin"] as Array).size()], Color(0.6, 0.9, 1.0))
	for rec in map.pools:
		if look != "" and str(rec["look"]) != look:
			continue
		var c: Vector2 = rec["center"]
		var ax: Vector2 = rec["axis"]
		var n := Vector2(-ax.y, ax.x)
		if n.dot(ThemeGeo.CAMERA_DIR) < 0.0:
			n = -n   # toward the camera
		var hw := float(rec["half_wid"])
		var spots: Array[Vector2] = [c + ax * 0.6, c + n * (hw + 0.75) - ax * 0.4, c - n * (hw - 0.75) - ax * 1.2]
		var path := PoolGeo.channel(rec)
		if path.size() >= 3:
			# a moat: the whole crew wading along the channel on the side nearest the camera
			var total := 0.0
			for i in path.size():
				total += path[i].distance_to(path[(i + 1) % path.size()])
			var best_s := 0.0
			var best := -INF
			for k in 64:
				var s := total * float(k) / 64.0
				var q: Vector2 = DecorAnim.path_pose(path, total, s)[0]
				if q.dot(ThemeGeo.CAMERA_DIR) > best:
					best = q.dot(ThemeGeo.CAMERA_DIR)
					best_s = s
			spots.clear()
			if opts.get("focus", "") == "island_corner":
				best_s += total * 0.5   # (on the far side, out of the way of the island corner the camera looks at)
			for off: float in [0.0, -1.7, 1.7]:
				spots.append(DecorAnim.path_pose(path, total, best_s + off)[0])
		var list: Array[Hero] = []
		for seat in range(1, NetSession.MAX_CREW + 1):
			if heroes_by_seat.has(seat):
				list.append(heroes_by_seat[seat])
		for i in list.size():
			var p: Vector2 = spots[mini(i, spots.size() - 1)]
			list[i].global_position = Vector3(p.x, 0.0, p.y)
			list[i].snap_to_ground()
			list[i].facing = Vector3(-n.x, 0.0, -n.y) if i == 1 and path.size() < 3 else Vector3(n.x, 0.0, n.y)
			var brain := list[i].get_node_or_null("AllyBrain")
			if brain != null:
				brain.set_physics_process(false)   # (the allies hold their spots for the screenshot)
		if opts.get("focus", "") == "pool_corner":
			# the corner farthest from the camera: the liner, the coping and the deck all show there
			var best: Vector2 = (rec["outline"] as Array)[0]
			for q: Vector2 in (rec["outline"] as Array):
				if q.dot(ThemeGeo.CAMERA_DIR) < best.dot(ThemeGeo.CAMERA_DIR):
					best = q
			var mk := Node3D.new()
			GameWorld.root.add_child(mk)
			mk.global_position = Vector3(best.x, float(rec["deck_level"]) * Hex.LEVEL_HEIGHT, best.y)
			rig.target = mk
		elif path.size() >= 3 and not opts.has("focus"):
			# a moat: look at the whole ring, not just the player
			var mc := Node3D.new()
			GameWorld.root.add_child(mc)
			mc.global_position = Vector3(c.x, float(rec["deck_level"]) * Hex.LEVEL_HEIGHT, c.y)
			rig.target = mc
		elif opts.get("focus", "") == "island_corner" and not (rec.get("hole", []) as Array).is_empty():
			# a moat's island corner nearest the camera: the island's liner, its coping and the water round it show there
			var best: Vector2 = (rec["hole"] as Array)[0]
			for q: Vector2 in (rec["hole"] as Array):
				if q.dot(ThemeGeo.CAMERA_DIR) > best.dot(ThemeGeo.CAMERA_DIR):
					best = q
			var mk := Node3D.new()
			GameWorld.root.add_child(mk)
			mk.global_position = Vector3(best.x, float(rec["deck_level"]) * Hex.LEVEL_HEIGHT, best.y)
			rig.target = mk
		rig.snap()
		return true
	return false


func _teleport_crew(cell: Vector2i) -> void:
	var spots := _free_cells_near(cell, 2)
	# In seat order (solo that is the player, Rebar, Gasket, as before), so every machine of a crew puts every hero on the
	# same cell and the floor checksum agrees (the player is a different seat on each machine).
	var list: Array[Hero] = []
	for seat in range(1, NetSession.MAX_CREW + 1):
		if heroes_by_seat.has(seat):
			list.append(heroes_by_seat[seat])
	if list.size() != _heroes().size():
		list = _heroes()
	for i in list.size():
		var c := cell if i == 0 else spots[(i - 1) % spots.size()]
		var lv := map.ground_level(Hex.to_world(c))
		list[i].global_position = Hex.to_world(c, 0.0 if is_nan(lv) else lv)
		list[i].snap_to_ground()
	rig.snap()


## Dev flag --give: "heal:9,corn:3" slots (or tops up) those spells with those charges.
func _apply_dev_loadout() -> void:
	if opts.has("give"):
		for part in str(opts["give"]).split(","):
			var bits := part.strip_edges().split(":")
			var id := bits[0].strip_edges()
			var n := int(bits[1]) if bits.size() > 1 else SpellComponents.START_CHARGES
			if SpellBook.is_available(id):
				player.slot_in(id, n)
	if opts.has("hold"):
		player.select_slot(int(opts["hold"]) - 1)
	if opts.has("give_allies"):
		var ids := str(opts["give_allies"]).split(",")
		for i in mini(ids.size(), allies.size()):
			allies[i].slot_in(ids[i].strip_edges(), SpellComponents.START_CHARGES)


## Dev flag --drop-near: pickups for the listed spells, right next to the player.
func _drop_near() -> void:
	if not opts.has("drop_near"):
		return
	var ids := str(opts["drop_near"]).split(",")
	# The first one lies just outside the collect radius but inside the swap radius, so a hero with
	# full slots is offered the swap at once; the rest follow in a row.
	var base := player.global_position + Vector3(0.9, 0.0, 0.55)
	for i in ids.size():
		var id := ids[i].strip_edges()
		var p := ComponentPickup.drop(id, SpellComponents.PICKUP_CHARGES, base + Vector3(0.0, 0.0, 1.4 * i))
		_log("drop-near: %s %s" % [id, "ok" if p != null else "no floor"], Color(0.8, 0.8, 1.0))


## Dev flag --hazard-near kind[,kind...]: explosive props (ExplosiveProp) in a cluster on open floor 3-6 cells from seat 1's
## hero, each 2.4-3.1 units from the one before (inside its blast: they chain). Built in _start, before the barrier numbers
## the floor, so every machine of a crew builds the same ones (tests, screenshots).
func _hazard_near() -> void:
	if not opts.has("hazard_near"):
		return
	var near_hero: Hero = heroes_by_seat.get(1, player) if _shared else player
	var here := near_hero.current_cell()
	var level: int = map.get_cell(here).level
	var cands: Array[Vector2i] = []
	for c in Hex.range_cells(here, 6):
		if Hex.distance(c, here) >= 3 and map.is_walkable_cell(c) and map.get_cell(c).level == level:
			cands.append(c)
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := Hex.distance(a, here)
		var db := Hex.distance(b, here)
		return da < db or (da == db and (a.x < b.x or (a.x == b.x and a.y < b.y))))
	var placed: Array[Vector3] = []
	for k in str(opts["hazard_near"]).split(","):
		var kind := k.strip_edges()
		for c in cands:
			var w := Hex.to_world(c)
			var ok := true
			var near_last := placed.is_empty()
			for q in placed:
				var d := GameWorld.flat_distance(q, w)
				ok = ok and d >= 2.4
			if not placed.is_empty():
				var d_last := GameWorld.flat_distance(placed.back(), w)
				near_last = d_last >= 2.4 and d_last <= 3.1
			if not ok or not near_last:
				continue
			var e := PricedProp.spawn(c, kind, {})
			if e != null:
				placed.append(w)
				_dev_hazards.append(e)
			break
	_log("hazard-near: %d explosive props" % placed.size(), Color(0.8, 0.8, 1.0))


## Dev flag --to-hazard kind[:n] ("any": any kind): the crew stands a few steps beside the floor's first (n-th) explosive
## prop of that kind, and --focus dev puts the camera on it (screenshots).
func _to_hazard(want: String) -> bool:
	if _site == null:
		return false
	var skip := int(want.get_slice(":", 1)) if want.contains(":") else 0   # kind:n = the n-th of that kind
	want = want.get_slice(":", 0)
	for h in _site.hazards:
		var e := h as ExplosiveProp
		if e == null or (want != "any" and e.kind != want):
			continue
		if skip > 0:
			skip -= 1
			continue
		# off to one side of it (in front, the crew would stand between the camera and the prop)
		var f := e.facing_vector()
		var best := Hex.from_world(e.global_position)
		var best_d := INF
		for side: float in [1.0, -1.0]:
			var target := e.global_position + Vector3(f.x, 0.0, f.y) * 1.2 + Vector3(-f.y, 0.0, f.x) * 3.6 * side
			for c in Hex.range_cells(Hex.from_world(target), 2):
				var d := Hex.to_world(c).distance_to(target) + (0.0 if side > 0.0 else 0.5)
				if map.is_walkable_cell(c) and not _site.plan.blocked.has(c) and d < best_d:
					best_d = d
					best = c
		_teleport_crew(best)
		_dev_hazards.append(e)
		_log("to-hazard: %s in %s" % [e.display_name, _site.plan.theme_of(str(_site.plan.hazards[_site.hazards.find(h)]["room"]))], Color(0.8, 0.8, 1.0))
		return true
	return false


## Dev flag --hazard-demo fuse|chain|invoice (with --hazard-near or --to-hazard; screenshots): after --demo-after seconds (1.0)
## the player sets off the first one. "chain" and "invoice" stand two frozen grunts beside each explosive first;
## "invoice" cashes out 2.5 s after the last blast, so the invoice shows the bill.
func _hazard_demo(stage: String) -> void:
	await get_tree().create_timer(float(opts.get("demo_after", 1.0))).timeout
	var list: Array[ExplosiveProp] = []
	for h in _dev_hazards:
		if is_instance_valid(h) and h is ExplosiveProp and not h.dead:
			list.append(h as ExplosiveProp)
	if list.is_empty() or player == null:
		return
	if stage != "fuse":
		var k := 0
		for e in list:
			for a: float in [0.6, 2.4]:
				var ang := a + float(k) * 1.1
				var at := e.global_position + Vector3(cos(ang), 0.0, sin(ang)) * 1.7
				if not map.is_walkable_cell(Hex.from_world(at)):
					continue
				var m := MonsterFactory.spawn("grunt", Hex.from_world(at))
				if m != null:
					m.global_position = Vector3(at.x, m.global_position.y, at.z)
					m.snap_to_ground()
					m.set_physics_process(false)
			k += 1
	list[0].ignite(player)
	if stage != "invoice":
		return
	while list.any(func(e: ExplosiveProp) -> bool: return is_instance_valid(e) and not e.dead):
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(2.5).timeout
	_end_contract(ContractSession.END_CASHED_OUT)


## Dev flag --kit-demo: show one hero's primary / secondary on the --spawn-near monsters (screenshots).
func _kit_demo(kind: String) -> void:
	for ally in allies:   # only the demo hero acts
		var b := ally.get_node_or_null("AllyBrain")
		if b != null:
			b.set_physics_process(false)
	await get_tree().create_timer(0.8).timeout
	var centre := _dev_centroid()
	if centre == Vector3.INF:
		return
	if kind == "draw":
		controller.enabled = false   # no mouse button is held, so the controller would release at once
		player.face_point(centre)
		player.start_draw()
		await get_tree().create_timer(1.3).timeout
		player.release_draw(centre - player.global_position)
		return
	var hero: Hero = allies[1] if kind == "hammer" else allies[0]
	var away := (centre - player.global_position)
	away.y = 0.0
	away = away.normalized()
	var spot := centre - away * (hero.melee_reach - 0.25)
	hero.global_position = Vector3(spot.x, hero.global_position.y, spot.z)
	hero.snap_to_ground()
	hero.face_point(centre)
	hero.melee(away)


func _slay_dev_monsters() -> void:
	for m in _dev_monsters:
		if is_instance_valid(m) and not m.dead:
			m.die()


## Dev flag --spawn-near kind,n: n extra monsters of `kind` on open floor 4-5 cells from the player.
func _spawn_near() -> void:
	if not opts.has("spawn_near"):
		return
	var parts := str(opts["spawn_near"]).split(",")
	var kind := parts[0].strip_edges()
	var n := int(parts[1]) if parts.size() > 1 else 3
	if map.has_cell(_stage_center):
		for c in Hex.ring(_stage_center, 1):
			if _dev_monsters.size() >= n:
				break
			var tm := MonsterFactory.spawn(kind, c)
			if tm != null:
				_dev_monsters.append(tm)
		_log("spawn-near: %d %s on the tower" % [_dev_monsters.size(), kind], Color(0.8, 0.8, 1.0))
		return
	var near_hero: Hero = heroes_by_seat.get(1, player) if _shared else player   # (a shared run: seat 1's spot on every machine)
	var here := near_hero.current_cell()
	var base_level: int = map.get_cell(here).level
	var cands: Array[Vector2i] = []
	for c in Hex.range_cells(here, 5):
		var d := Hex.distance(c, here)
		var cell: HexMap.Cell = map.get_cell(c)
		if d >= 4 and cell != null and cell.type == HexMap.Tile.FLOOR and absi(cell.level - base_level) <= 1:
			cands.append(c)
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	if parts.size() > 2 and parts[2].strip_edges() == "cluster":
		# Candidates 5-7 cells out with a clear view of the player (so Rebar can bowl at them).
		cands.clear()
		for c in Hex.range_cells(here, 7):
			var cc: HexMap.Cell = map.get_cell(c)
			if Hex.distance(c, here) >= 5 and cc != null and cc.type == HexMap.Tile.FLOOR and cc.level == base_level:
				if map.line_of_sight(Combat.chest(near_hero), Hex.to_world(c, cc.level) + Vector3.UP * 0.9):
					cands.append(c)
		cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	if parts.size() > 2 and parts[2].strip_edges() == "cluster" and not cands.is_empty():
		# A tight clump: the n candidates nearest to the first one.
		var anchor := cands[0]
		cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Hex.distance(a, anchor) < Hex.distance(b, anchor))
		for c in cands:
			if _dev_monsters.size() >= n:
				break
			var cm := MonsterFactory.spawn(kind, c)
			if cm != null:
				_dev_monsters.append(cm)
	else:
		# Spread them: take every k-th candidate.
		var stride := maxi(1, cands.size() / maxi(n, 1))
		var i := 0
		while _dev_monsters.size() < n and i < cands.size():
			var m := MonsterFactory.spawn(kind, cands[i])
			if m != null:
				_dev_monsters.append(m)
			i += stride
	if opts.has("idle_monsters"):
		for im in _dev_monsters:
			im.aggro_range = 0.0
	_log("spawn-near: %d %s" % [_dev_monsters.size(), kind], Color(0.8, 0.8, 1.0))


## Average position of the living --spawn-near monsters, or Vector3.INF if none.
func _dev_centroid() -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for m in _dev_monsters:
		if is_instance_valid(m) and not m.dead:
			sum += m.global_position
			count += 1
	for h in _dev_hazards:   # (--hazard-near / --to-hazard: the explosives)
		if is_instance_valid(h) and not h.dead:
			sum += h.global_position
			count += 1
	return sum / count if count > 0 else Vector3.INF


## Dev flag --stage-ledge: a 7-cell tower 5 levels tall on the roomiest flat ground 2-5 cells from
## the start (so a shove off its edge is a 5-level fall onto open floor). --spawn-near then stands
## its monsters on top.
func _stage_plateau() -> void:
	var start: Vector2i = map.cells_with_tag("start")[0]
	var base: int = map.get_cell(start).level
	var best := Vector2i(1 << 20, 1 << 20)
	var best_score := -1
	for c in Hex.range_cells(start, 5):
		if Hex.distance(c, start) < 3:
			continue
		var ok := true
		for n in Hex.range_cells(c, 1):
			var cell: HexMap.Cell = map.get_cell(n)
			if cell == null or cell.type != HexMap.Tile.FLOOR or cell.level != base or Hex.distance(n, start) < 2:
				ok = false
				break
		if not ok:
			continue
		var score := 0
		for n in Hex.range_cells(c, 4):
			var cell: HexMap.Cell = map.get_cell(n)
			if cell != null and cell.type == HexMap.Tile.FLOOR and cell.level == base:
				score += 1
		if score > best_score:
			best_score = score
			best = c
	if best_score < 0:
		return
	_stage_center = best
	for n in Hex.range_cells(best, 1):
		map.get_cell(n).level = base + 5
