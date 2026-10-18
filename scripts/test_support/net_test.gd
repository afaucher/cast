class_name NetTest
extends TestCase
## Base for MULTI-PROCESS net tests (docs/design/networking-build-plan.md §3). A tests/test_net_*.gd that
## extends this and declares `const PEERS := N` is run by test_runner.ps1 as N headless Godot processes over
## ENet on localhost: one host and N-1 clients, each its own process (GameWorld and Ledger are autoloads and
## game.gd keeps static vars, so two worlds can't share a process). `const LINKS := ["off", "coast"]` (the
## default) runs the whole test once per link preset.
##
## Every process runs the same script; `role` says which side it is. The runner passes (after `--`):
##   --run-test X --net-role host|client --net-index i --net-port P --net-peers N --net-link L
##
## THE HOST IS THE JUDGE. Clients send what they saw with report(key, value) on a test-only reliable event;
## the host waits for them (wait_reports) and asserts. A client's own failed checks are forwarded to the host
## too. Override run_host() and run_client(); when run_host() returns the host prints the PASS marker and
## quits. A client, after run_client(), says done and waits for the session to end, then checks the reason
## (expect_end, default "The host clocked out") and exits. The runner fails the test unless EVERY process
## exits 0, the host printed the marker and no log has a SCRIPT ERROR.
##
## Real time, not lockstep: the runner starts net processes with --max-fps 60 instead of --fixed-fps, every
## wait here is "within T seconds" on the wall clock (so is the timeout, net_timeout), and the session's
## clock, link simulator and telemetry all run on wall time.

const ROLE_HOST := "host"

var role := ROLE_HOST
var index := 0                 ## 0 = the host, 1.. = clients in launch order
var port := 0
var peers := 1                 ## processes in this test
var link := "off"
## Seconds before the runner's own kill: the TestCase timer is restarted with this.
var net_timeout := 60.0
## The reason a client expects its session to end with after run_client().
var expect_end := NetSession.HOST_LEFT

## Host: peer -> {key: value} from report().
var reports: Dictionary = {}
var done_peers: Array[int] = []
var ended := false
var ended_reason := ""
## Client: commands from the host, in arrival order: [{"cmd", ...data}].
var commands: Array = []

var _t0_usec := 0


func setup() -> void:
	_t0_usec = Time.get_ticks_usec()
	var args := OS.get_cmdline_user_args()
	role = Boot.arg_value(args, "--net-role") if Boot.arg_value(args, "--net-role") != "" else ROLE_HOST
	index = int(Boot.arg_value(args, "--net-index")) if role != ROLE_HOST else 0
	port = int(Boot.arg_value(args, "--net-port")) if Boot.arg_value(args, "--net-port").is_valid_int() else 28400
	peers = int(Boot.arg_value(args, "--net-peers")) if Boot.arg_value(args, "--net-peers").is_valid_int() else 2
	link = Boot.arg_value(args, "--net-link") if Boot.arg_value(args, "--net-link") != "" else "off"
	Engine.max_fps = 60
	# The TestCase timer runs on game time; a net test watches the wall clock instead (_process).
	for c in get_children():
		if c is Timer:
			(c as Timer).stop()
	print("[NetTest] %s %s index %d, port %d, %d processes, link %s" % [name, role, index, port, peers, link])
	Session.wire.link.configure(link)
	Session.telemetry_dir = "user://net_tests"
	Session.player_name = "host" if is_host() else "c%d" % index
	Session.event_received.connect(_on_event)
	Session.session_ended.connect(func(reason: String) -> void:
		ended = true
		ended_reason = reason)
	if is_host():
		if not check(Session.host_enet(port), "the host opens port %d" % port):
			finish()
			return
		await run_host()
		finish()
		return
	await run_client()
	if not Session.online():
		finish()   # the client already ended (refused, or left on purpose); run_client checked why
		return
	Session.send_event(1, "probe.done", {})
	check(await until(func() -> bool: return ended, 20.0), "the session ends after the test (the host leaves)")
	eq(ended_reason, expect_end, "the session ended for the expected reason")
	await after_end()
	finish()


func _process(_delta: float) -> void:
	if _t0_usec > 0 and wall() > net_timeout:
		_t0_usec = 0
		_fail("timed out after %.0f s (wall clock)" % net_timeout)
		finish()


## Override: the host's script. Return when every check is done.
func run_host() -> void:
	pass


## Override: a client's script.
func run_client() -> void:
	pass


## Override: a client, after its session ended as expected (check what the game did about it).
func after_end() -> void:
	pass


func is_host() -> bool:
	return role == ROLE_HOST


## Wall-clock seconds since the test started.
func wall() -> float:
	return float(Time.get_ticks_usec() - _t0_usec) / 1e6


## Wait (frame by frame) until cond() is true; false after timeout_s seconds of wall time.
func until(cond: Callable, timeout_s: float) -> bool:
	var end := Time.get_ticks_usec() + int(timeout_s * 1e6)
	while not bool(cond.call()):
		if Time.get_ticks_usec() > end:
			return false
		await get_tree().process_frame
	return true


## Wall-clock sleep.
func sleep(seconds: float) -> void:
	await until(func() -> bool: return false, seconds)


# --- Client side ------------------------------------------------------------------------------------

## Join the host (retrying while it is still starting). "" when welcomed, else the reason it ended.
func connect_client(attempts: int = 6) -> String:
	await sleep(0.15 * index)
	for i in attempts:
		ended = false
		ended_reason = ""
		if not Session.join_enet("127.0.0.1", port):
			return Session.last_reason
		await until(func() -> bool: return Session.online() or ended, 15.0)
		if Session.online():
			return ""
		if ended_reason != NetSession.CONNECT_FAILED:
			return ended_reason
		await sleep(0.5)
	return ended_reason


## Send a value to the judge.
func report(key: String, value: Variant) -> void:
	Session.send_event(1, "probe.report", {"key": key, "value": value})


## Wait for the host's next command (or the one already waiting). {} on timeout.
func wait_command(timeout_s: float = 20.0) -> Dictionary:
	await until(func() -> bool: return not commands.is_empty() or ended, timeout_s)
	return commands.pop_front() if not commands.is_empty() else {}


func _fail(msg: String) -> void:
	super._fail(msg)
	if not is_host() and Session.online():
		Session.send_event(1, "probe.fail", {"msg": msg})


# --- Host side --------------------------------------------------------------------------------------

## Wait until `count` peers have reported `key`.
func wait_reports(key: String, count: int, timeout_s: float = 20.0) -> bool:
	return await until(func() -> bool: return peers_with(key).size() >= count, timeout_s)


## Wait until `count` clients have said done (they finished run_client()).
func wait_done(count: int, timeout_s: float = 20.0) -> bool:
	return await until(func() -> bool: return done_peers.size() >= count, timeout_s)


func peers_with(key: String) -> Array[int]:
	var out: Array[int] = []
	for p: int in reports:
		if (reports[p] as Dictionary).has(key):
			out.append(p)
	return out


func reported(peer: int, key: String) -> Variant:
	return (reports.get(peer, {}) as Dictionary).get(key)


func command(peer: int, cmd: String, data: Dictionary = {}) -> void:
	var d := data.duplicate()
	d["cmd"] = cmd
	Session.send_event(peer, "probe.cmd", d)


## The crew as one comparable string: seat:peer:name:character, by seat.
static func roster_signature() -> String:
	var parts: PackedStringArray = []
	for e: Dictionary in Session.crew():
		parts.append("%d:%d:%s:%s" % [int(e["seat"]), int(e["peer"]), str(e["name"]), str(e["character"])])
	return ";".join(parts)


func _on_event(from: int, kind: String, data: Dictionary, _stamp: float) -> void:
	match kind:
		"probe.report":
			if not reports.has(from):
				reports[from] = {}
			(reports[from] as Dictionary)[str(data["key"])] = data["value"]
		"probe.fail":
			super._fail("client peer %d: %s" % [from, str(data.get("msg", ""))])
		"probe.done":
			if not done_peers.has(from):
				done_peers.append(from)
		"probe.cmd":
			commands.append(data)
