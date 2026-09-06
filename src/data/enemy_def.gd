class_name EnemyDef
extends RefCounted
## An enemy ship: a set of subsystems plus a telegraphed intent pool.
##
## Intents declare `requires_system`. An offline system cannot fire; damaged
## systems hit softer. Soft systems (low HP + auto-repair) are optional control
## targets — the player can always shoot the hull instead.

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
## Enemy subsystems auto-repair this much at the start of their turn when
## they were not damaged since the previous tick. Soft systems (low HP +
## regen) are temporary soft targets, not a mandatory first gate.
var system_regen: int = 2

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
	system_regen = int(d.get("system_regen", 2))
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
		return true  # intent with no system requirement is never offline
	for s in systems:
		if StringName(s.get("id", "")) == sid:
			return true
	return false
