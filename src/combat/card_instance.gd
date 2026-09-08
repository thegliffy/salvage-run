class_name CardInstance
extends RefCounted
## One physical copy of a card in a deck.

var def: CardDef
var upgraded: bool = false
var uid: int = 0
var cost_override: int = -1   # temporary discounts, cleared each combat

static var _next_uid: int = 1

static func create(def: CardDef, upgraded: bool = false) -> CardInstance:
	var c := CardInstance.new()
	c.def = def
	c.upgraded = upgraded
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
