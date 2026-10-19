class_name NetEvents
extends RefCounted
## Which gameplay events carry state the snapshot does not (docs/design/networking-build-plan.md §3, "How
## test_net_contract grows"). test_net_contract holds every OWNER var of a replicated class to this rule: it is
## either in the codec's field list (NetCodec.HERO_FIELDS, NetWorldCodec.*_FIELDS: it rides every snapshot) or named
## here, with the event (or the reason) that makes it right on the other screens. A new OWNER var that is in neither
## fails the build, so content cannot silently go unreplicated.
##
## An entry says WHEN it starts being carried ("M4: ...") when the event is not built yet, so the table is also the
## list of what the other screens do NOT show until then. A name here that is also in the codec is a mistake
## (the test fails it): a field has one carrier.

## Hero / Actor OWNER var -> its carrier.
const CARRIES := {
	# Set by the license at the floor start (the roster's `spells` on every machine) and changed by casts and pickups.
	"spell_slots": "roster at the floor start (M1); pickups: obj.loadout from the owner (M3); a joiner's license: seat.take / join.snapshot (M6); a cast that spends the last charge opens that slot on every copy (NetCasts)",
	"_charges": "roster at the floor start (M1); pickups: obj.loadout from the owner (M3); casts: the cast event's charges left (NetCasts, M4); a joiner's license: seat.take / join.snapshot (M6)",
	# Timed buffs and debuffs (armor, coffee, vines roots) are applied by the target's owner and shown from here.
	"_modifiers": "st {k mods} from the owner when they change (NetStatus, M4): armor, coffee, the vines' root",
}

## Actor OWNER vars every host-owned class inherits, and why each is right on the other screens.
const _ACTOR_WORLD := {
	"dead": "world.die (NetWorld), shown on the beat the host stamped it",
	"pass_through_until": "never set on host-owned actors (only heroes pass through each other)",
	"_modifiers": "st {k mods} from the host when they change (NetStatus, M4): vines roots, coffee on monsters",
}
const _FIXED := "fixed: it never moves, turns or climbs (built from the floor plan on every machine)"

## Host-owned classes (M3): script -> {OWNER var -> its carrier}. Their snapshot fields are in NetWorldCodec.
const WORLD_CARRIES := {
	"res://scripts/monsters/monster.gd": {
		"dead": _ACTOR_WORLD["dead"], "pass_through_until": _ACTOR_WORLD["pass_through_until"], "_modifiers": _ACTOR_WORLD["_modifiers"],
		"target": "world.windup names its victim (NetWorld, M4: each client resolves the strike against its own hero)",
		"_windup_total": "world.windup {s, l}: the start and the length (NetWorld, M4); the look rides _telegraph",
		"_windup_left": "world.windup {s, l}: the start and the length (NetWorld, M4); the look rides _telegraph",
	},
	"res://scripts/monsters/goblin.gd": {
		"dead": _ACTOR_WORLD["dead"], "pass_through_until": _ACTOR_WORLD["pass_through_until"], "_modifiers": _ACTOR_WORLD["_modifiers"],
		"target": "world.windup names its victim (the cornered firecracker; NetWorld, M4)",
		"_windup_total": "world.windup {s, l} (the firecracker; NetWorld, M4); the light rides _telegraph",
		"_windup_left": "world.windup {s, l} (the firecracker; NetWorld, M4); the light rides _telegraph",
		"scout_phase": "world.scout {id, p, l} on every change (NetWorld, step 2)",
		"loaded": "world.scout {id, p, l} on every change (NetWorld, step 2)",
	},
	"res://scripts/contracts/employee.gd": {
		"dead": _ACTOR_WORLD["dead"], "pass_through_until": _ACTOR_WORLD["pass_through_until"], "_modifiers": _ACTOR_WORLD["_modifiers"],
		"_extracted": "world.extract (NetWorld)",
		"_say_text": "world.say (NetWorld): the bubble's line and how long it shows",
		"_say_until": "world.say (NetWorld): the bubble's line and how long it shows",
		"_wait_spot": "the host's AI only (where a waiting employee walks back to); M6: the late-join keyframe",
	},
	"res://scripts/contracts/hellgate.gd": {
		"dead": "world.die (NetWorld): the gate closes on every screen", "pass_through_until": _ACTOR_WORLD["pass_through_until"],
		"_modifiers": _ACTOR_WORLD["_modifiers"], "facing": _FIXED, "climbing": _FIXED,
	},
	"res://scripts/contracts/priced_prop.gd": {
		"hp": "obj.hurt (NetObjects): a dent", "dead": "obj.break (NetObjects)", "broke": "obj.break (NetObjects)",
		"pass_through_until": _ACTOR_WORLD["pass_through_until"], "_modifiers": "never set on a prop", "facing": _FIXED, "climbing": _FIXED,
	},
	"res://scripts/world/themes/breakable_crate.gd": {
		"hp": "obj.break (NetObjects): one hit breaks it", "dead": "obj.break (NetObjects)", "broke": "obj.break (NetObjects)",
		"pass_through_until": _ACTOR_WORLD["pass_through_until"], "_modifiers": "never set on a crate", "facing": _FIXED, "climbing": _FIXED,
	},
	"res://scripts/contracts/mail_package.gd": {
		"hp": "obj.break (NetObjects): one hit breaks it", "dead": "obj.break (NetObjects)", "broke": "obj.break (NetObjects)",
		"contents": "obj.break (NetObjects): the host rolls it", "crypto_amount": "obj.break (NetObjects)", "component_id": "obj.break (NetObjects)",
		"_lift": "recomputed on every machine from the breaks below it (MailPackage._settle)",
		"pass_through_until": _ACTOR_WORLD["pass_through_until"], "_modifiers": "never set on a box", "facing": _FIXED, "climbing": _FIXED,
	},
	"res://scripts/spells/component_pickup.gd": {
		"charges": "obj.pickup / obj.pick (NetObjects)", "_used": "obj.gone (NetObjects)",
	},
}

## The packet types and event kinds the sync uses (documented here, defined where they are sent).
##   T_SNAP (unreliable)   hero snapshots, both ways (NetCodec); host -> client also the world (NetWorldCodec, M3)
##   seat.ai (reliable)    host -> clients: a seat went back to the AI as its original character
##   world.* (reliable)    host -> clients (NetWorld): spawn, die, say, extract, phase, shove
##   obj.* (reliable)      NetObjects: req / loadout (client -> host; M4: req hit on any host-owned actor, shove, mod);
##                         break, hurt, pickup, pick, gone, grant, deny, ledger, contract, exit, end, loadout, and (M4)
##                         shove / mod passed on to the owner of a player's hero (host -> clients)
##   world.windup / world.unwind (reliable, M4)  host -> clients: a monster's wind-up (start, length, victim) / called off
##   world.scout / world.fireworks / world.dud (reliable, step 2)  host -> clients: a goblin scout's phase and rack / his
##                         volley (launch point, start, fx seed, drift) / a soaked rack
##   cast, act (reliable, M4)  NetCasts: a cast (lands LEAD later everywhere) / a hero's attack, owner -> host -> others
##   st (reliable, M4)     NetStatus: an actor's modifiers, fire or soak, owner -> host -> others
##   seat.take (reliable, M6)  host -> clients: a joiner took an AI's seat {seat, peer, character, epoch, state}
##   join.* (reliable, M6) NetJoin: wait, go, built, snapshot (the late joiner's way onto a running floor)
const KIND_SEAT_AI := "seat.ai"
const KIND_SEAT_TAKE := "seat.take"

## M6, late-join coverage (test_net_contract holds every replicated class to it): how a player who joins a running floor
## gets each class's state. The joiner builds the floor from the seed (so everything SPAWN is there) and the host's
## late-join snapshot (NetJoin) brings the rest:
##   keyframe  a full world section of every surviving host-owned mover (NetWorld.keyframe), then the stream as usual
##   gone      the seed-built ids that are gone on the host (dead, broken, opened, extracted, used): removed or shown dead
##   replay    the events that made it (runtime spawns, pickups on the floor, statuses, dents), replayed once
##   handover  the heroes: the seat table, each seat's kit and player, its state (NetJoin heroes + SeatHandover.take)
## A new replicated class without an entry here fails the build: it would be wrong on a late joiner's screen.
const LATE_JOIN := {
	"res://scripts/heroes/hero.gd": "handover: kit, player name, owner and epoch per seat; position, HP, slots, charges, held slot (heroes); the joiner's own seat: SeatHandover.hero_state; statuses: replay",
	"res://scripts/monsters/monster.gd": "keyframe (seed-built and runtime); gone ids; runtime spawns: replay of world.spawn; statuses: replay; wind-ups: skipped (under a second)",
	"res://scripts/monsters/grunt.gd": "as monster.gd",
	"res://scripts/monsters/archer.gd": "as monster.gd",
	"res://scripts/monsters/brute.gd": "as monster.gd",
	"res://scripts/monsters/swarmer.gd": "as monster.gd",
	"res://scripts/monsters/goblin.gd": "as monster.gd (keyframe, gone ids); his phase and rack: replay of world.scout per scout in the snapshot (NetWorld.scout_states); a volley in the air: skipped (cosmetic)",
	"res://scripts/contracts/employee.gd": "keyframe (state, leader seat, HP, position); the wait spot; gone ids (dead: shown dead; extracted: removed)",
	"res://scripts/contracts/hellgate.gd": "keyframe (HP, phase, flare); gone ids (closed: shown closed)",
	"res://scripts/contracts/priced_prop.gd": "gone ids (broken: shown broken); a dent: replay of obj.hurt",
	"res://scripts/world/themes/breakable_crate.gd": "gone ids (broken)",
	"res://scripts/contracts/mail_package.gd": "gone ids (opened: removed; its prize is a pickup, replayed)",
	"res://scripts/spells/component_pickup.gd": "replay of obj.pickup for every pickup on the floor (charges and age); a used seed-built one: gone ids",
}
