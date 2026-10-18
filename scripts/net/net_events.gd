class_name NetEvents
extends RefCounted
## Which gameplay events carry state the snapshot does not (docs/design/networking-build-plan.md §3, "How
## test_net_contract grows"). test_net_contract holds every OWNER var of a replicated class to this rule: it is
## either in the codec's field list (NetCodec.HERO_FIELDS: it rides every snapshot) or named here, with the event
## (or the reason) that makes it right on the other screens. A new OWNER var that is in neither fails the build, so
## content cannot silently go unreplicated.
##
## An entry says WHEN it starts being carried ("M4: ...") when the event is not built yet, so the table is also the
## list of what a hero's other screens do NOT show until then. A name here that is also in the codec is a mistake
## (the test fails it): a field has one carrier.

## Hero / Actor OWNER var -> its carrier.
const CARRIES := {
	# Set by the license at the floor start (the roster's `spells` on every machine) and changed by casts and pickups.
	"spell_slots": "roster at the floor start (M1); pickups M3, casts M4: events",
	"_charges": "roster at the floor start (M1); spends and pickups M3/M4: events",
	# Timed buffs and debuffs (armor, coffee, vines roots) are applied by the target's owner and shown from here.
	"_modifiers": "M4: modifier events from the owner (armor, coffee, vines)",
}

## The packet types and event kinds the hero sync uses (documented here, defined where they are sent).
##   T_SNAP (unreliable)   hero snapshots, both ways (NetCodec)
##   seat.ai (reliable)    host -> clients: a seat went back to the AI as its original character
const KIND_SEAT_AI := "seat.ai"
