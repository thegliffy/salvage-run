class_name ImprovementDef
extends RefCounted
## A permanent ship upgrade.
##
## Distinct from a part: an improvement fills no slot and grants no cards. It
## changes the SHIP -- more power, more hull, another slot, or a combat trigger.
## That separation is the point: parts are how the deck grows, improvements are
## how the ship's capacity to carry parts grows, so the two rewards never
## compete for the same decision.

const TRIGGER_WHENS := {
	&"card_exhausted": true,
	&"zero_cost_played": true,
	&"hand_empty": true,
}

const TRIGGER_OPS := {
	&"draw": true,
	&"energy": true,
}

var id: StringName
var name: String
var text: String
var rarity: StringName = &"common"
var stats: Dictionary = {}   # hull, power, draw, evasion, shield, shield_regen
var slots: Dictionary = {}   # weapon, hull, utility
## Combat hooks: [{when: StringName, op: StringName, amount: int}, ...]
var triggers: Array = []

func from_dict(def_id: StringName, d: Dictionary) -> String:
	id = def_id
	name = d.get("name", "")
	if name == "":
		return "missing 'name'"
	text = d.get("text", "")
	rarity = StringName(d.get("rarity", "common"))
	stats = d.get("stats", {})
	slots = d.get("slots", {})
	var err := _parse_triggers(d.get("triggers", []))
	if err != "":
		return err
	if stats.is_empty() and slots.is_empty() and triggers.is_empty():
		return "does nothing"
	return ""

func _parse_triggers(raw) -> String:
	triggers = []
	if raw == null:
		return ""
	if typeof(raw) != TYPE_ARRAY:
		return "'triggers' must be an array"
	for t in raw:
		if typeof(t) != TYPE_DICTIONARY:
			return "malformed trigger"
		var when := StringName(t.get("when", ""))
		var op := StringName(t.get("op", ""))
		if not TRIGGER_WHENS.has(when):
			return "unknown trigger when '%s'" % String(when)
		if not TRIGGER_OPS.has(op):
			return "unknown trigger op '%s'" % String(op)
		var amount := int(t.get("amount", 1))
		if amount <= 0:
			return "trigger amount must be positive"
		triggers.append({
			"when": when,
			"op": op,
			"amount": amount,
		})
	return ""
