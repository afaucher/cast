class_name NetSteamLink
extends RefCounted
## The link simulator over STEAM (M7): the same presets as NetLink ("off", "coast", "rough"), set as Steam's own fake-lag
## config values (ISteamNetworkingUtils SetGlobalConfigValue*), because the Steam transport never passes through NetWire's
## NetLink queue. Like NetLink it acts on what this process RECEIVES, and every machine sets it (the host's choice is
## broadcast, NetSession.set_link), so both directions of every connection are simulated.
##
## Each preset is latency +- jitter and a loss rate (NetLink.PRESETS). Steam's jitter is a random EXTRA delay (exponential
## with mean Avg, clamped at Max) on Pct % of packets, so `latency +- jitter` becomes a base lag of latency - jitter plus a
## jitter of mean `jitter` clamped at 2 x jitter on every packet: the same spread (coast: 30-60 ms, rough: 50-110 ms).
## Loss is Steam's percent (1.5 for coast). Steam retransmits a lost RELIABLE packet, so reliable messages arrive late,
## never lost, as on ENet.
##
## GodotSteam 4.17 names the lag and loss values (NETWORKING_CONFIG_FAKE_PACKET_LAG_RECV = 5, ..._LOSS_RECV = 3) but not the
## jitter ones, so those are the raw ESteamNetworkingConfigValue ints (FakePacketJitter_Recv_Avg 56, _Max 57, _Pct 58; the
## _Send ones are 53-55). A value whose type the SDK disagrees with is retried as the other type (int32 <-> float).

const LAG_RECV := 5          ## k_ESteamNetworkingConfig_FakePacketLag_Recv (int32, ms)
const LOSS_RECV := 3         ## k_ESteamNetworkingConfig_FakePacketLoss_Recv (float, percent)
const JITTER_RECV_AVG := 56  ## k_ESteamNetworkingConfig_FakePacketJitter_Recv_Avg (float, ms)
const JITTER_RECV_MAX := 57  ## k_ESteamNetworkingConfig_FakePacketJitter_Recv_Max (float, ms)
const JITTER_RECV_PCT := 58  ## k_ESteamNetworkingConfig_FakePacketJitter_Recv_Pct (float, percent of packets)


## The config values a preset sets: [[config id, "int" | "float", value, name], ...]. Unknown presets are "off".
static func values_for(preset: String) -> Array:
	var p: Dictionary = NetLink.PRESETS.get(preset, NetLink.PRESETS["off"])
	var latency := float(p["latency_ms"])
	var jitter := float(p["jitter_ms"])
	return [
		[_id("NETWORKING_CONFIG_FAKE_PACKET_LAG_RECV", LAG_RECV), "int", int(round(maxf(latency - jitter, 0.0))), "FakePacketLag_Recv"],
		[_id("NETWORKING_CONFIG_FAKE_PACKET_LOSS_RECV", LOSS_RECV), "float", float(p["loss"]) * 100.0, "FakePacketLoss_Recv"],
		[JITTER_RECV_AVG, "float", jitter, "FakePacketJitter_Recv_Avg"],
		[JITTER_RECV_MAX, "float", jitter * 2.0, "FakePacketJitter_Recv_Max"],
		[JITTER_RECV_PCT, "float", 100.0 if jitter > 0.0 else 0.0, "FakePacketJitter_Recv_Pct"],
	]


## Set `preset` on Steam (the global scope: every connection of this process). Returns {name: ok} per value; an empty
## dictionary without Steam.
static func apply(steam: Object, preset: String) -> Dictionary:
	var out := {}
	if steam == null:
		return out
	for v: Array in values_for(preset):
		var ok := _set_value(steam, int(v[0]), str(v[1]), v[2])
		if not ok:
			ok = _set_value(steam, int(v[0]), "float" if str(v[1]) == "int" else "int", v[2])
		out[str(v[3])] = ok
	print("[Net] Steam fake link: %s %s" % [preset, str(out)])
	return out


static func _set_value(steam: Object, id: int, kind: String, value: Variant) -> bool:
	if kind == "int":
		return bool(steam.call("setGlobalConfigValueInt32", id, int(round(float(value)))))
	return bool(steam.call("setGlobalConfigValueFloat", id, float(value)))


static func _id(name_: String, fallback: int) -> int:
	if ClassDB.class_has_integer_constant("Steam", name_):
		return ClassDB.class_get_integer_constant("Steam", name_)
	return fallback
