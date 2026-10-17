class_name Net
## Authority classes for networked state (docs/design/networking.md, "Keeping authority straight").
##
## There is no transport yet. Today this file only names who may write each field: every class
## whose state matters in co-op returns `net_fields() -> {var name: Net.KIND}` covering EVERY
## script var it has, and test_net_contract fails when a var is missing or a name is stale. The
## snapshot packer and the debug write guards will be driven by the same declarations.
##
## Owner: a hero's player owns that hero; the host owns everything else (monsters, hellgates,
## employees, props, pickups, the contract). "Owner" below means that machine.

enum {
	SPAWN,    ## Fixed when the thing is created (from the spawn/cast event or the seed), never written after. Same on every machine, never streamed.
	OWNER,    ## The owner writes it; everyone else receives it (snapshot or event). Non-owners never write it.
	PRIVATE,  ## The owner's working state (AI timers, slide internals). Not replicated; non-owners must not use it for gameplay.
	LOCAL,    ## Every machine keeps its own: presentation (models, visual timers, cosmetic phase) or a value recomputed from OWNER/SPAWN state and GameWorld.time.
}

const NAMES := {SPAWN: "SPAWN", OWNER: "OWNER", PRIVATE: "PRIVATE", LOCAL: "LOCAL"}


static func is_kind(v: Variant) -> bool:
	return v is int and NAMES.has(v)
