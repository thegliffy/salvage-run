class_name ImprovementDef
extends RefCounted
## A permanent ship upgrade.
##
## Distinct from a part: an improvement fills no slot and grants no cards. It
## changes the SHIP -- more power, more hull, another slot. That separation is
## the point: parts are how the deck grows, improvements are how the ship's
## capacity to carry parts grows, so the two rewards never compete for the same
## decision.

var id: StringName
var name: String
var text: String
var rarity: StringName = &"common"
var stats: Dictionary = {}   # hull, power, draw, evasion, shield, shield_regen
var slots: Dictionary = {}   # weapon, hull, utility

func from_dict(def_id: StringName, d: Dictionary) -> String:
	id = def_id
	name = d.get("name", "")
	if name == "":
		return "missing 'name'"
	text = d.get("text", "")
	rarity = StringName(d.get("rarity", "common"))
	stats = d.get("stats", {})
	slots = d.get("slots", {})
	if stats.is_empty() and slots.is_empty():
		return "does nothing"
	return ""
