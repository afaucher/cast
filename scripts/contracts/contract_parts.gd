class_name ContractParts
extends RefCounted
## Soft links to the contract actors built by other modules (Hellgate, Employee, PricedProp,
## DamageTicker). Everything goes through load() + ResourceLoader.exists(), so the game, the
## generator and the tests run whether or not a part is present: a missing part just means that
## kind of thing is not spawned (has_*() says which are there).

const HELLGATE := "res://scripts/contracts/hellgate.gd"
const EMPLOYEE := "res://scripts/contracts/employee.gd"
const PRICED_PROP := "res://scripts/contracts/priced_prop.gd"
const DAMAGE_TICKER := "res://scripts/contracts/damage_ticker.gd"

## Used by the generator when PricedProp has no catalog (never spawned, only planned).
const FALLBACK_PROPS := {
	"bunker": ["wine_rack", "cinema_screen", "gold_bars", "server_rack"],
	"lair": ["throne", "doomsday_console", "shark_tank", "trophy_case"],
}

static var _cache: Dictionary = {}


static func script_of(path: String) -> GDScript:
	if _cache.has(path):
		return _cache[path]
	var s: GDScript = null
	if ResourceLoader.exists(path):
		s = load(path) as GDScript
	_cache[path] = s
	return s






## Hellgate.spawn(cell, {difficulty, depth, origin, pest}). Null if the part is missing.
static func spawn_gate(cell: Vector2i, opts: Dictionary) -> Actor:
	var s := script_of(HELLGATE)
	if s == null:
		return null
	return s.call("spawn", cell, opts) as Actor


## Employee.spawn(cell, {style, name}). Null if the part is missing.
static func spawn_employee(cell: Vector2i, opts: Dictionary) -> Actor:
	var s := script_of(EMPLOYEE)
	if s == null:
		return null
	return s.call("spawn", cell, opts) as Actor


## PricedProp.spawn(cell, kind, opts). Null if the part is missing.
static func spawn_prop(cell: Vector2i, kind: String, opts: Dictionary) -> Actor:
	var s := script_of(PRICED_PROP)
	if s == null:
		return null
	return s.call("spawn", cell, kind, opts) as Actor


## PricedProp.catalog(site_type) (the fallback list when the part is missing).
static func prop_catalog(site_type: String) -> Array[String]:
	var out: Array[String] = []
	var s := script_of(PRICED_PROP)
	if s != null:
		var got: Array = s.call("catalog", site_type)
		for k in got:
			out.append(str(k))
	if out.is_empty():
		for k: String in FALLBACK_PROPS.get(site_type, FALLBACK_PROPS["bunker"]):
			out.append(k)
	return out


## A new DamageTicker control, or null when the part is missing.
static func make_ticker() -> Control:
	var s := script_of(DAMAGE_TICKER)
	if s == null:
		return null
	return s.call("new") as Control
