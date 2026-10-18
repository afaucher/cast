extends TestCase
## A REAL host and a REAL client in one headless process exchanging a real RPC over ENet on localhost
## (ported from Bridge to Friendship's test_enet_loopback.gd; networking-build-plan.md M0a "done when").
##
## Two peers fit in one process because a SceneTree can hold several MultiplayerAPIs, each rooted at a node
## (SceneTree.set_multiplayer). RPCs resolve by node path RELATIVE to that root, so `Pinger` under NetHost
## and `Pinger` under NetClient are the same address and the call crosses the socket. Also checks Godot 4.7's
## GodotSteam peer class is present when the extension is (SteamMultiplayerPeer can't be exercised headless).

const PORT := 28777
const PING_VALUE := 4242

var host_mp: SceneMultiplayer
var client_mp: SceneMultiplayer
var host_pinger: Node
var client_pinger: Node


func setup() -> void:
	var host_root := Node.new()
	host_root.name = "NetHost"
	add_child(host_root)
	var client_root := Node.new()
	client_root.name = "NetClient"
	add_child(client_root)
	host_mp = SceneMultiplayer.new()
	get_tree().set_multiplayer(host_mp, host_root.get_path())
	client_mp = SceneMultiplayer.new()
	get_tree().set_multiplayer(client_mp, client_root.get_path())

	var pinger := load("res://tests/pinger.gd") as GDScript
	host_pinger = pinger.new()
	host_pinger.name = "Pinger"
	host_root.add_child(host_pinger)
	client_pinger = pinger.new()
	client_pinger.name = "Pinger"
	client_root.add_child(client_pinger)

	var host_peer := ENetMultiplayerPeer.new()
	if not check(host_peer.create_server(PORT, 4) == OK, "the host binds port %d" % PORT):
		finish()
		return
	host_mp.multiplayer_peer = host_peer
	var client_peer := ENetMultiplayerPeer.new()
	if not check(client_peer.create_client("127.0.0.1", PORT) == OK, "the client opens a socket"):
		finish()
		return
	client_mp.multiplayer_peer = client_peer
	eq(host_mp.get_unique_id(), 1, "the host is peer 1")

	var host_saw := [0]
	var client_connected := [false]
	host_mp.peer_connected.connect(func(id: int) -> void: host_saw[0] = id)
	client_mp.connected_to_server.connect(func() -> void: client_connected[0] = true)

	# WAIT FOR BOTH SIDES: the client's connected_to_server fires a frame or two before the host's
	# peer_connected. An RPC sent on the client's signal alone goes to an empty peer list and is lost silently.
	await _until(func() -> bool: return client_connected[0] and host_saw[0] != 0, 5.0)
	if not check(client_connected[0] and host_saw[0] != 0, "both ends see the connection"):
		finish()
		return
	eq(host_saw[0], client_mp.get_unique_id(), "the host sees the peer id the client reports for itself")
	check(client_mp.get_unique_id() > 1, "the client got a peer id above the host's")

	host_pinger.rpc("ping", PING_VALUE)
	await _until(func() -> bool: return int(client_pinger.get("ping_count")) > 0, 3.0)
	check(int(client_pinger.get("ping_count")) > 0, "the RPC reached the client")
	eq(int(client_pinger.get("last_value")), PING_VALUE, "the client received the value the host sent")
	eq(int(host_pinger.get("ping_count")), 0, "call_remote did not run the RPC on the sender")

	# Godot 4.7 + GodotSteam 4.17: the transport class exists whenever the extension is installed.
	if Engine.has_singleton("Steam"):
		check(ClassDB.class_exists("SteamMultiplayerPeer"), "GodotSteam's SteamMultiplayerPeer loads in Godot 4.7")
		check(ClassDB.class_has_method("SteamMultiplayerPeer", "create_host") and ClassDB.class_has_method("SteamMultiplayerPeer", "create_client"),
			"SteamMultiplayerPeer has create_host / create_client")
	host_peer.close()
	client_peer.close()
	finish()


## Wall-clock wait (the batch runs --fixed-fps, so frames say nothing about elapsed time).
func _until(cond: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(cond.call()) and Time.get_ticks_msec() < end:
		await get_tree().process_frame
