class_name SteamAvatars
extends Node
## Steam avatars for the crew roster (M7): child "Avatars" of the Session autoload. The UI asks
## `Session.avatars.texture(steam_id)` and gets a texture, or null (no Steam, an id of 0, a test name, or the picture is still
## on its way: then `avatar_ready(steam_id)` fires when it arrives and the UI draws it). Callers always have a fallback (the
## name's initial on a badge), so nothing breaks without Steam.
##
## GodotSteam: `getPlayerAvatar(size, steam_id)` answers with the signal `avatar_loaded(avatar_id, size, data)`, `data` being
## size x size RGBA8 bytes, either at once (the picture is cached by the Steam client) or once Steam has downloaded it. Steam
## is reached through SteamIdentity.steam() by string names, like every other Steam call (scripts/net/ only).

signal avatar_ready(steam_id: int)

const SIZE_MEDIUM := 2        ## Steam.AVATAR_MEDIUM: 64 x 64
const RETRY_SEC := 5.0        ## a request that never answered is asked again after this long

var _cache: Dictionary = {}       ## steam id -> ImageTexture
var _asked: Dictionary = {}       ## steam id -> usec of the last request
var _wired_to: Object = null


## The avatar of `steam_id`, or null for now (see the header).
func texture(steam_id: int) -> Texture2D:
	if steam_id == 0:
		return null
	if _cache.has(steam_id):
		return _cache[steam_id]
	var steam := SteamIdentity.steam()
	if steam == null:
		return null
	_wire(steam)
	var now := Time.get_ticks_usec()
	if _asked.has(steam_id) and now - int(_asked[steam_id]) < int(RETRY_SEC * 1e6):
		return null
	_asked[steam_id] = now
	steam.call("getPlayerAvatar", _size_const(), steam_id)   # (may answer inside this call)
	return _cache.get(steam_id)


func has_texture(steam_id: int) -> bool:
	return _cache.has(steam_id)


## Forget every picture (tests).
func clear() -> void:
	_cache.clear()
	_asked.clear()


## RGBA8 bytes from Steam as an image (null when the size and the bytes disagree).
static func image_from_rgba(size: int, data: PackedByteArray) -> Image:
	if size <= 0 or data.size() != size * size * 4:
		return null
	return Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)


func _wire(steam: Object) -> void:
	if _wired_to == steam:
		return
	_wired_to = steam
	if steam.has_signal("avatar_loaded"):
		steam.connect("avatar_loaded", _on_avatar_loaded)


func _on_avatar_loaded(steam_id: int, size: int, data: PackedByteArray) -> void:
	var img := image_from_rgba(size, data)
	if img == null:
		return
	_cache[steam_id] = ImageTexture.create_from_image(img)
	avatar_ready.emit(steam_id)


static func _size_const() -> int:
	if ClassDB.class_has_integer_constant("Steam", "AVATAR_MEDIUM"):
		return ClassDB.class_get_integer_constant("Steam", "AVATAR_MEDIUM")
	return SIZE_MEDIUM
