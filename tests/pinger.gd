extends Node
## The RPC endpoint test_enet_loopback uses (ported from Bridge to Friendship's test_support/pinger.gd). Its
## own script because an RPC resolves by NODE PATH relative to the multiplayer root, so the host copy and the
## client copy must be the same node under their roots. Lives in tests/ (not a test: the runner only runs
## test_*.gd) because @rpc is allowed only in scripts/net/ inside scripts/.

signal pinged(value: int)

var last_value := -1
var ping_count := 0


@rpc("any_peer", "call_remote", "reliable")
func ping(value: int) -> void:
	last_value = value
	ping_count += 1
	pinged.emit(value)
