class_name CardInstance
extends RefCounted
## One physical copy of a card in a deck.

var def: CardDef
var upgraded: bool = false
var uid: int = 0
var cost_override: int = -1   # temporary discounts, cleared each combat
## PartInstance.uid that granted this copy. Calibrate bonuses key off this so
## a shared card def (armor_brace, laser_burst) only buffs the mount it came
## from. 0 means unknown / injected by tests.
var source_part_uid: int = 0

static var _next_uid: int = 1

static func create(def: CardDef, upgraded: bool = false, source_part_uid: int = 0) -> CardInstance:
	var c := CardInstance.new()
	c.def = def
	c.upgraded = upgraded
	c.source_part_uid = source_part_uid
	c.uid = _next_uid
	_next_uid += 1
	return c

func cost() -> int:
	return cost_override if cost_override >= 0 else def.cost_for(upgraded)

func effects() -> Array:
	return def.effects_for(upgraded)

func text() -> String:
	return def.text_for(upgraded)

func display_name() -> String:
	return def.name + ("+" if upgraded else "")

func has_keyword(k: StringName) -> bool:
	return def.has_keyword(k, upgraded)
