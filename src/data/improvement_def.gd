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
	&"combat_won": true,
	&"hull_damaged": true,
}

const TRIGGER_OPS := {
	&"draw": true,
	&"energy": true,
	&"credits": true,
	&"shield": true,
}

const KNOWN_FLAGS := {
	&"keep_overshield": true,
	&"shop_half_price": true,
	&"virus_no_decay": true,
	&"damage_as_virus": true,
	&"hot_swap": true,
	&"spare_clip": true,
	&"probe_tip": true,
	&"signal_noise": true,
}

var id: StringName
var name: String
var text: String
var rarity: StringName = &"common"
var stats: Dictionary = {}   # hull, power, draw, evasion, shield, shield_regen
var slots: Dictionary = {}   # weapon, hull, utility
## Combat hooks: [{when: StringName, op: StringName, amount: int}, ...]
var triggers: Array = []
## Named passives compiled onto the ship (keep_overshield, shop_half_price,
## virus_no_decay, damage_as_virus, hot_swap, spare_clip, probe_tip,
## signal_noise).
var flags: Array[StringName] = []

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
	err = _parse_flags(d.get("flags", []))
	if err != "":
		return err
	if stats.is_empty() and slots.is_empty() and triggers.is_empty() and flags.is_empty():
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

func _parse_flags(raw) -> String:
	flags = []
	if raw == null:
		return ""
	if typeof(raw) != TYPE_ARRAY:
		return "'flags' must be an array"
	for f in raw:
		var flag := StringName(str(f))
		if not KNOWN_FLAGS.has(flag):
			return "unknown flag '%s'" % String(flag)
		if not flags.has(flag):
			flags.append(flag)
	return ""
