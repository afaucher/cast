class_name SpellComponents
extends RefCounted
## Material components: the tuning numbers and the drop table. Everything here is data, so the
## whole economy can be tuned from this one file. Per-spell data (the component's name, whether
## the spell can be slotted yet) lives in SpellBook.SPELLS ("component", "available").
## Design record: docs/design/spells-and-components.md.

# --- Slots and charges ---------------------------------------------------------------------
const SLOT_COUNT := 4            ## spell slots per hero
const START_CHARGES := 5         ## charges of each spell picked at the start
const PICKUP_CHARGES := 3        ## charges one dropped component gives
const MAX_CHARGES := 9           ## cap per spell

# --- The held (readied) slot ---------------------------------------------------------------
const HELD_COOLDOWN_DIV := 1.15  ## the held spell's cooldown is divided by this (15% more often)

# --- Pickups ---------------------------------------------------------------------------------
const COLLECT_RADIUS := 0.8      ## a hero this close picks it up automatically
const SWAP_RADIUS := 1.2         ## a hero this close (slots full) can press F to swap it in
const LABEL_RADIUS := 4.0        ## the floating name label shows when a player is this close
const DROP_SCATTER := 0.55       ## several drops from one kill fan out this far
const FLOOR_DROP_CAP := 5        ## at most this many monster-dropped pickups per floor (GameWorld.floor_drops counts them)
const PICKUP_LIFETIME := 60.0    ## an uncollected pickup vanishes after this many seconds ...
const PICKUP_FADE := 5.0         ## ... and blinks for the last this-many seconds

## Drop table. Every living monster that dies rolls each entry of its kind's list, and then each
## entry of ANY_KIND, independently. An entry: "spells" = the candidate spell ids (one is picked,
## equal odds), "chance" = 0..1, "charges" (optional) = charges in the pickup, default
## PICKUP_CHARGES. A spell that is not `available` (teeth, until its gameplay lands) is skipped
## when rolling, so it never litters the floor with components nobody can use; the entry stays
## here so it switches on the moment SpellBook marks the spell available.
const DROPS := {
	"grunt": [{"spells": ["teeth"], "chance": 0.12}],
	"archer": [{"spells": ["heal"], "chance": 0.15}],
	"brute": [{"spells": ["fireball", "armor"], "chance": 0.35}],
	"swarmer": [{"spells": ["tentacles"], "chance": 0.03}],   ## per imp
}
const ANY_KIND: Array = [{"spells": ["corn"], "chance": 0.02}]   ## in addition, from every monster


## The spell ids that drop when a monster of `kind` dies, rolled with `rng` (pass a seeded rng for
## a repeatable result). Unavailable spells are skipped unless `include_unavailable` is set.
static func roll_drops(kind: String, rng: RandomNumberGenerator, include_unavailable: bool = false) -> Array[String]:
	var out: Array[String] = []
	var entries: Array = []
	if DROPS.has(kind):
		entries.append_array(DROPS[kind] as Array)
	entries.append_array(ANY_KIND)
	for e: Dictionary in entries:
		var spells: Array = e["spells"]
		var chance := float(e["chance"])
		var hit := rng.randf() < chance
		var pick := rng.randi_range(0, spells.size() - 1) if spells.size() > 1 else 0
		if not hit:
			continue
		var id := str(spells[pick])
		if not SpellBook.has_spell(id):
			continue
		if not include_unavailable and not SpellBook.is_available(id):
			continue
		out.append(id)
	return out


## Charges in a pickup dropped for one entry (the table's "charges", or PICKUP_CHARGES).
static func drop_charges(kind: String, id: String) -> int:
	var entries: Array = []
	if DROPS.has(kind):
		entries.append_array(DROPS[kind] as Array)
	entries.append_array(ANY_KIND)
	for e: Dictionary in entries:
		if (e["spells"] as Array).has(id) and e.has("charges"):
			return int(e["charges"])
	return PICKUP_CHARGES


## Called when a monster dies: roll its drops and put the pickups on the floor around it. At most
## FLOOR_DROP_CAP pickups per floor (the dice are always rolled, so the rng stream does not depend on
## the cap; only the pickups past the cap are left out).
static func drop_for(monster: Actor) -> Array[ComponentPickup]:
	var out: Array[ComponentPickup] = []
	if monster == null or GameWorld.root == null:
		return out
	var kind := str(monster.get("kind")) if "kind" in monster else ""
	var ids := roll_drops(kind, GameWorld.rng)
	var room_left := maxi(0, FLOOR_DROP_CAP - GameWorld.floor_drops)
	if ids.size() > room_left:
		ids.resize(room_left)
	for i in ids.size():
		var offset := Vector3.ZERO
		if ids.size() > 1:
			var a := TAU * float(i) / ids.size()
			offset = Vector3(cos(a), 0.0, sin(a)) * DROP_SCATTER
		var p := ComponentPickup.drop(ids[i], drop_charges(kind, ids[i]), monster.global_position + offset)
		if p != null:
			out.append(p)
			GameWorld.floor_drops += 1
	return out
