class_name NetEvents
extends RefCounted
## Which gameplay events carry state the snapshot does not (docs/design/networking-build-plan.md §3, "How
## test_net_contract grows"). test_net_contract holds every OWNER var of a replicated class to this rule: it is
## either in the codec's field list (NetCodec.HERO_FIELDS, NetWorldCodec.*_FIELDS, a runtime actor's
## NetWorldCodec.RUNTIME_ACTORS "fields": it rides every snapshot) or named
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
	# An AI seat's order as the party HUD shows it (FOLLOW / GO / HOLD / ATTACK): only the host runs the AllyBrain.
	"order_state": "ord.st {id, st} from the host on every change (NetOrders); a late joiner: join.snapshot `orders`",
}

## Actor OWNER vars every host-owned class inherits, and why each is right on the other screens.
const _ACTOR_WORLD := {
	"dead": "world.die (NetWorld), shown on the beat the host stamped it",
	"pass_through_until": "never set on host-owned actors (only heroes pass through each other)",
	"_modifiers": "st {k mods} from the host when they change (NetStatus, M4): vines roots, coffee on monsters",
}
const _FIXED := "fixed: it never moves, turns or climbs (built from the floor plan on every machine)"
## A priced prop's break moment and culprit (sewer phase 2: an electrical panel's LiveWire runs from them on every machine).
const _BREAK_AT := "obj.break {t} (PricedProp.net_link / net_event): the break's moment on the shared clock; a late joiner: `breaks`"
const _BREAK_BY := "obj.break {by} (PricedProp.net_link / net_event): who broke it; a late joiner: `breaks`"

## Host-owned classes (M3): script -> {OWNER var -> its carrier}. Their snapshot fields are in NetWorldCodec (a runtime
## actor's in RUNTIME_ACTORS). A host-arbitrated object's obj.* events are its own (the net-object contract, NetObjects: its
## net_link sends them, its net_event applies them), so its entry names them.
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
	# The pool shark (docs/design/sharks.md): a Monster-format entry; its bite is the monsters' wind-up, its laser two events.
	"res://scripts/monsters/shark.gd": {
		"dead": "world.die (NetWorld): the kill, shown belly-up on the beat the host stamped it; the bill is the host's Ledger",
		"pass_through_until": _ACTOR_WORLD["pass_through_until"], "_modifiers": _ACTOR_WORLD["_modifiers"],
		"target": "world.windup names the bite's victim (each client resolves the bite on its own hero)",
		"_windup_total": "world.windup {s, l}: the bite's wind-up and lunge; the look rides _telegraph",
		"_windup_left": "world.windup {s, l}: the bite's wind-up and lunge; the look rides _telegraph",
		"charge_victim": "world.charge {id, s, l, v} (NetWorld): the laser's victim the red line tracks; world.uncharge drops it",
		"lock_origin": "world.lock {id, x, y, z, dx, dz, t} (NetWorld): the locked beam's origin",
		"lock_dir": "world.lock {id, x, y, z, dx, dz, t} (NetWorld): the locked beam's direction",
		"fire_at": "world.lock {t} (NetWorld): the shared moment it fires, on every machine's own clock",
	},
	# The Pavise Crossbowman (combat-proposals.md §2, "As built"): a monster-format entry; its aim and bolt ride the laser
	# shark's events, its shield world.shield. Its bash is the monsters' wind-up.
	"res://scripts/monsters/pavise.gd": {
		"dead": _ACTOR_WORLD["dead"], "pass_through_until": _ACTOR_WORLD["pass_through_until"], "_modifiers": _ACTOR_WORLD["_modifiers"],
		"target": "world.windup names the bash's victim (each client resolves the bash on its own hero)",
		"_windup_total": "world.windup {s, l}: the bash's wind-up; the look rides _telegraph",
		"_windup_left": "world.windup {s, l}: the bash's wind-up; the look rides _telegraph",
		"shield_state": "world.shield {id, st, x, y, z, w} (NetWorld) on every change: carried, planted, left, flat",
		"shield_pos": "world.shield {x, y, z} (NetWorld): where a left or flat pavise stands or lies",
		"shield_yaw": "world.shield {w} (NetWorld): which way it faces",
		"charge_victim": "world.charge {id, s, l, v} (NetWorld): the aim's victim the dashed line tracks; world.uncharge drops it",
		"lock_origin": "world.lock {id, x, y, z, dx, dz, t} (NetWorld): the locked bolt's origin",
		"lock_dir": "world.lock {id, x, y, z, dx, dz, t} (NetWorld): the locked bolt's direction",
		"fire_at": "world.lock {t} (NetWorld): the shared moment it looses, on every machine's own clock; world.uncharge calls it off",
	},
	# The imp gunner riding an imp laser shark: a swarmer that sits in the saddle until world.dismount.
	"res://scripts/monsters/jockey.gd": {
		"dead": _ACTOR_WORLD["dead"], "pass_through_until": _ACTOR_WORLD["pass_through_until"], "_modifiers": _ACTOR_WORLD["_modifiers"],
		"target": "world.windup names its victim (NetWorld, M4: each client resolves the strike against its own hero)",
		"_windup_total": "world.windup {s, l}: the start and the length (NetWorld, M4); the look rides _telegraph",
		"_windup_left": "world.windup {s, l}: the start and the length (NetWorld, M4); the look rides _telegraph",
		"mounted": "world.dismount {id, h, x, y, z} (NetWorld): knocked off, or its shark died; never true again",
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
		"broke_at": _BREAK_AT, "_break_by": _BREAK_BY,
		"pass_through_until": _ACTOR_WORLD["pass_through_until"], "_modifiers": "never set on a prop", "facing": _FIXED, "climbing": _FIXED,
	},
	"res://scripts/contracts/explosive_prop.gd": {
		"hp": "obj.hurt (NetObjects): a dent", "dead": "obj.break (NetObjects)", "broke": "obj.break (NetObjects)",
		"broke_at": _BREAK_AT, "_break_by": _BREAK_BY,
		"pass_through_until": _ACTOR_WORLD["pass_through_until"], "_modifiers": "never set on a prop", "facing": _FIXED, "climbing": _FIXED,
		"fuse_start": "obj.fuse {s} (NetObjects): the host lit it; obj.out puts it out",
		"fuse_end": "obj.fuse {e} (NetObjects): every machine runs the blast at this moment on its own clock",
		"_igniter": "obj.fuse {by} (NetObjects): who set it off (the host bills them)",
		"blown": "the scheduled blast at obj.fuse's end, on every machine; then obj.break",
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
	# Office doors (exploration.md "Decisions: map information, fog and doors", 2026-10-19): host-arbitrated. A client's walk-in
	# or E is obj.req {what "door", id, shut}; the host decides (OfficeDoor.host_decide) and sends obj.door {id, s, w}.
	"res://scripts/contracts/office_door.gd": {
		"shut": "obj.door {id, s, w} from the host (NetObjects)",
		"swing": "obj.door {id, s, w} from the host (NetObjects): which way the leaves swing",
		"broken": "obj.break {id, by} from the host (NetObjects), its Ledger line as obj.ledger",
	},
	"res://scripts/spells/chicken.gd": {
		"dead": "world.die (NetWorld): a feather explosion, or the poof when it was puffing up (its state rode the stream)",
		"pass_through_until": _ACTOR_WORLD["pass_through_until"],
		"_modifiers": "st {k mods} from the host when they change (NetStatus, M4): vines roots, coffee on a chicken",
	},
	# A goo imp's patch (goo-imp.md, "As built"): a runtime object the host makes (NetObjects obj.new); its two changes are its own.
	"res://scripts/monsters/goo_patch.gd": {
		"lit_at": "obj.goo {id, st 1, t} (GooPatch.net_link / net_event): the host lit it; every machine burns it from shared time t",
		"lit_by": "obj.goo {by}: who lit it (the burn's damage source)",
		"washed": "obj.goo {id, st 2}: the host's Damp washed it away",
	},
}

## The packet types and event kinds the sync uses (documented here, defined where they are sent).
##   T_SNAP (unreliable)   hero snapshots, both ways (NetCodec); host -> client also the world (NetWorldCodec, M3)
##   seat.ai (reliable)    host -> clients: a seat went back to the AI as its original character
##   world.* (reliable)    host -> clients (NetWorld): spawn (monsters and runtime actors: chickens), die, say, extract, phase, shove
##   obj.* (reliable)      NetObjects: req / loadout (client -> host; M4: req hit on any host-owned actor, shove, mod);
##                         break {id, t, by}, hurt, pickup, pick, gone, grant, deny, ledger, contract, exit, end, loadout, and (M4)
##                         shove / mod passed on to the owner of a player's hero (host -> clients); fuse / out (an
##                         explosive prop's fuse lit, with its start, end and igniter / put out by a soak); new (a runtime
##                         object the host made: a goo imp's ball or patch, NetObjects.RUNTIME_OBJECTS) / goo (a patch lit or washed)
##   world.windup / world.unwind (reliable, M4)  host -> clients: a monster's wind-up (start, length, victim) / called off
##   world.scout / world.fireworks / world.dud (reliable, step 2)  host -> clients: a goblin scout's phase and rack / his
##                         volley (launch point, start, fx seed, drift) / a soaked rack
##   world.shield (reliable)  host -> clients: a Pavise's shield state {id, st, x, y, z, w} (carried, planted, left, flat)
##   world.charge / world.uncharge / world.lock / world.dismount (reliable)  host -> clients: a laser shark's charge (start,
##                         length, victim) / dropped / its beam locked (origin, direction, the shared fire time: every machine
##                         fires it then and applies what it resolves) / an imp gunner off its shark (how, where)
##   cast, act (reliable, M4)  NetCasts: a cast (lands LEAD later everywhere) / a hero's attack, owner -> host -> others
##   st (reliable, M4)     NetStatus: an actor's modifiers, fire or soak, owner -> host -> others
##   seat.take (reliable, M6)  host -> clients: a joiner took an AI's seat {seat, peer, character, epoch, state}
##   join.* (reliable, M6) NetJoin: wait, go, built, snapshot (the late joiner's way onto a running floor)
##   ord.req / ord.ok (reliable)  NetOrders: a voice order, the speaker's machine -> host (req); the host applied it -> everyone
##                         (ok: the AI heroes' barks, the people it names for a marker). Cosmetic once applied: what an order
##                         changes is the host's AI state (AllyBrain, PRIVATE) or rides the employee's stream and keyframe
##                         (state, leader, dismissed, wait spot), so a late joiner needs no replay of it
##   ord.st (reliable)     NetOrders: host -> everyone, an AI hero's order state changed {id, st} (follow, go, hold, attack;
##                         "" when a person takes the seat): the party HUD's chip. Late join: join.snapshot `orders`
const KIND_SEAT_AI := "seat.ai"
const KIND_SEAT_TAKE := "seat.take"

## M6, late-join coverage (test_net_contract holds every replicated class to it): how a player who joins a running floor
## gets each class's state. The joiner builds the floor from the seed (so everything SPAWN is there) and the host's
## late-join snapshot (NetJoin) brings the rest:
##   keyframe  a full world section of every surviving host-owned mover (NetWorld.keyframe), then the stream as usual
##   gone      the seed-built ids that are gone on the host (dead, broken, opened, extracted, used): removed or shown dead
##   replay    the events that made it (runtime spawns, pickups on the floor, statuses, dents), replayed once
##   handover  the heroes: the seat table, each seat's kit and player, its state (NetJoin heroes + SeatHandover.take)
## A host-arbitrated object's replay rows are its own (late_join_state / apply_late_join, the net-object contract in
## NetObjects); a runtime actor's are the world.spawn replay and the keyframe (NetWorld, RUNTIME_ACTORS).
## A new replicated class without an entry here fails the build: it would be wrong on a late joiner's screen.
const LATE_JOIN := {
	"res://scripts/heroes/hero.gd": "handover: kit, player name, owner and epoch per seat; position, HP, slots, charges, held slot (heroes); the joiner's own seat: SeatHandover.hero_state; statuses: replay; the AI seats' order states: `orders` (NetOrders.late_join_state)",
	"res://scripts/monsters/monster.gd": "keyframe (seed-built and runtime); gone ids; runtime spawns: replay of world.spawn; statuses: replay; wind-ups: skipped (under a second)",
	"res://scripts/monsters/grunt.gd": "as monster.gd",
	"res://scripts/monsters/archer.gd": "as monster.gd",
	"res://scripts/monsters/brute.gd": "as monster.gd",
	"res://scripts/monsters/swarmer.gd": "as monster.gd",
	"res://scripts/monsters/goblin.gd": "as monster.gd (keyframe, gone ids); his phase and rack: replay of world.scout per scout in the snapshot (NetWorld.scout_states); a volley in the air: skipped (cosmetic)",
	"res://scripts/monsters/shark.gd": "keyframe (seed-built: position, facing, HP, state); a killed one: gone ids (removed); a charge or a beam under way: skipped (under 1.5 s)",
	"res://scripts/monsters/jockey.gd": "as monster.gd (keyframe, gone ids); off its shark: replay of world.dismount per gunner in the snapshot (NetWorld.dismount_states)",
	"res://scripts/monsters/gator.gd": "keyframe (seed-built: position, facing, HP, state), as the shark; a killed one: gone ids (removed); a nip under way: skipped (under a second); its relocation and riling: the host's AI (PRIVATE), the keyframe and the stream show where it goes",
	"res://scripts/monsters/pavise.gd": "as monster.gd (keyframe, gone ids); its shield: replay of world.shield per pavise in the snapshot (NetWorld.shield_states); an aim or a bolt under way: skipped (under 1.5 s); stuck arrows: cosmetic, skipped",
	"res://scripts/monsters/water_boy.gd": "as monster.gd (keyframe, gone ids); a pour under way: skipped (a wind-up, under a second)",
	"res://scripts/contracts/employee.gd": "keyframe (state, leader seat, HP, position); the wait spot; gone ids (dead: shown dead; extracted: removed)",
	"res://scripts/contracts/hellgate.gd": "keyframe (HP, phase, flare); gone ids (closed: shown closed)",
	"res://scripts/contracts/priced_prop.gd": "gone ids (broken: shown broken); a dent: replay of obj.hurt; a broken one something runs from (an electrical panel's LiveWire): replay of its break moment and culprit, `breaks` (PricedProp.break_synced: the wire skips the shocks already past)",
	"res://scripts/contracts/explosive_prop.gd": "gone ids (blown or broken: shown broken); a dent: replay of obj.hurt; a fuse burning now: replay of obj.fuse (its start, end and igniter), so the joiner runs the blast at the same moment",
	"res://scripts/world/themes/breakable_crate.gd": "gone ids (broken)",
	"res://scripts/contracts/mail_package.gd": "gone ids (opened: removed; its prize is a pickup, replayed)",
	"res://scripts/spells/chicken.gd": "runtime spawns: replay of world.spawn (kind chicken); then the keyframe (a monster-format entry); statuses: replay",
	"res://scripts/spells/component_pickup.gd": "replay of obj.pickup for every pickup on the floor (charges and age); a used seed-built one: gone ids",
	"res://scripts/contracts/office_door.gd": "replay of obj.door / obj.break for every door (OfficeDoor.late_join_state `doors`: id, shut, swing, broken)",
	"res://scripts/monsters/goo_imp.gd": "as monster.gd (keyframe, gone ids); a throw's tell under way: skipped (a wind-up, under a second)",
	"res://scripts/monsters/goo_ball.gd": "no replay: a ball in flight lands within about a second, so a late joiner skips it; the patch it leaves is replayed (goo_patch.gd)",
	"res://scripts/monsters/goo_patch.gd": "replay of obj.new for every live patch with its state (GooPatch.late_join_state, section `new`: where, its start, lit and by whom)",
}
