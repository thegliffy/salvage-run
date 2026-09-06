class_name CardDef
extends RefCounted
## Immutable definition of a card, loaded from content/cards.json.
## Runtime per-copy state (upgraded, temporary cost) lives on CardInstance.

enum Target { NONE, ENEMY_SYSTEM, ENEMY_SHIP, SELF_SYSTEM, SELF_SHIP }

const TARGET_NAMES := {
	"none": Target.NONE,
	"enemy_system": Target.ENEMY_SYSTEM,
	"enemy_ship": Target.ENEMY_SHIP,
	"self_system": Target.SELF_SYSTEM,
	"self_ship": Target.SELF_SHIP,
}

var id: StringName
var name: String
var text: String
var cost: int = 1
var kind: StringName = &"attack"      # attack | tech | maneuver | status
var rarity: StringName = &"common"    # starter | common | uncommon | rare
var target: Target = Target.ENEMY_SYSTEM
var effects: Array = []               # Array[Dictionary] of effect ops
var keywords: Array[StringName] = []  # exhaust, pierce, overload, retain
var source_part: StringName = &""     # which part granted it (for tooltips)
var icon: String = ""                 # filename under res://assets/icons/

# Upgrade variant: same card, better numbers. Populated from "upgrade" block.
var upgrade_text: String = ""
var upgrade_cost: int = -1
var upgrade_effects: Array = []

func from_dict(def_id: StringName, d: Dictionary) -> String:
	id = def_id
	name = d.get("name", "")
	if name == "":
		return "missing 'name'"
	text = d.get("text", "")
	cost = int(d.get("cost", 1))
	kind = StringName(d.get("kind", "attack"))
	rarity = StringName(d.get("rarity", "common"))

	var t: String = d.get("target", "enemy_system")
	if not TARGET_NAMES.has(t):
		return "unknown target '%s'" % t
	target = TARGET_NAMES[t]

	icon = d.get("icon", "")
	effects = d.get("effects", [])
	if typeof(effects) != TYPE_ARRAY:
		return "'effects' must be an array"
	if effects.is_empty():
		return "has no effects"

	for k in d.get("keywords", []):
		keywords.append(StringName(k))

	var up: Dictionary = d.get("upgrade", {})
	if not up.is_empty():
		upgrade_text = up.get("text", text)
		upgrade_cost = int(up.get("cost", cost))
		upgrade_effects = up.get("effects", effects)
	return ""

func has_keyword(k: StringName) -> bool:
	return keywords.has(k)

func effects_for(upgraded: bool) -> Array:
	return upgrade_effects if (upgraded and not upgrade_effects.is_empty()) else effects

func cost_for(upgraded: bool) -> int:
	return upgrade_cost if (upgraded and upgrade_cost >= 0) else cost

func text_for(upgraded: bool) -> String:
	return upgrade_text if (upgraded and upgrade_text != "") else text

## Ops that still do something when aimed at the bare hull. Suppression and
## repair need an actual subsystem; damage does not.
const HULL_CAPABLE_OPS := ["damage_system", "damage_hull"]

## Whether pointing this card at the hull accomplishes anything.
##
## Without this, any enemy-system card could be aimed at the hull, and a pure
## suppression card (EMP Pulse) would spend its energy resolving against a
## subsystem that does not exist -- a silent no-op the player reads as a bug.
func can_target_hull() -> bool:
	for effs in [effects, upgrade_effects]:
		for op in effs:
			if typeof(op) == TYPE_DICTIONARY and HULL_CAPABLE_OPS.has(op.get("op", "")):
				return true
	return false

func needs_target() -> bool:
	return target == Target.ENEMY_SYSTEM or target == Target.SELF_SYSTEM
