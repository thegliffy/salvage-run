class_name EnemyDef
extends RefCounted
## An enemy ship: a set of subsystems plus a telegraphed intent pool.
##
## Intents declare `requires_system`. If the player destroys that subsystem
## before the enemy turn, the intent FIZZLES. That single rule is what makes
## subsystem targeting a real decision rather than flavored damage.

var id: StringName
var name: String
var tier: int = 1
var hull: int = 30
var shield: int = 0
var shield_regen: int = 0
var evasion: int = 0
var systems: Array = []    # [{id, name, integrity, ...}]
var intents: Array = []    # [{id, requires_system, weight, effects, telegraph}]
var reward: Dictionary = {}
var portrait: String = ""   # filename under res://assets/portraits/

func from_dict(def_id: StringName, d: Dictionary) -> String:
	id = def_id
	name = d.get("name", "")
	if name == "":
		return "missing 'name'"
	tier = int(d.get("tier", 1))
	hull = int(d.get("hull", 30))
	shield = int(d.get("shield", 0))
	shield_regen = int(d.get("shield_regen", 0))
	evasion = int(d.get("evasion", 0))
	systems = d.get("systems", [])
	if systems.is_empty():
		return "enemy must define at least one system"
	intents = d.get("intents", [])
	if intents.is_empty():
		return "enemy must define at least one intent"
	reward = d.get("reward", {})
	portrait = d.get("portrait", "")
	return ""

func has_system(sid: StringName) -> bool:
	if sid == &"":
		return true  # intent with no system requirement never fizzles
	for s in systems:
		if StringName(s.get("id", "")) == sid:
			return true
	return false
