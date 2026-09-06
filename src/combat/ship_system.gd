class_name ShipSystem
extends RefCounted
## A targetable subsystem on a ship in combat.
##
## Integrity is separate from hull. Soft enemy systems can be knocked offline
## briefly; they auto-repair unless they were damaged since the last tick.
## Player systems do not auto-repair unless an improvement grants system_regen.

var id: StringName
var display_name: String
var integrity: int = 0
var max_integrity: int = 0
var online: bool = true
var offline_turns: int = 0   # >0 means temporarily suppressed (EMP-style)
var part_uids: Array = []
## HP restored at the start of this combatant's turn when undamaged.
var auto_repair: int = 0
## Set when this system takes damage; cleared after the auto-repair check.
var damaged_since_tick: bool = false

static func from_dict(d: Dictionary) -> ShipSystem:
	var s := ShipSystem.new()
	s.id = StringName(d.get("id", "weapons"))
	s.display_name = d.get("name", String(s.id).capitalize())
	s.max_integrity = int(d.get("integrity", 8))
	s.integrity = s.max_integrity
	s.part_uids = d.get("part_uids", [])
	s.auto_repair = int(d.get("auto_repair", 0))
	return s

func is_active() -> bool:
	return online and offline_turns <= 0 and integrity > 0

## Returns actual damage dealt to this system (may be less than requested).
func take_damage(amount: int) -> int:
	var dealt := mini(amount, integrity)
	integrity -= dealt
	if dealt > 0:
		damaged_since_tick = true
	if integrity <= 0:
		integrity = 0
		online = false
	return dealt

func repair(amount: int) -> int:
	var healed := mini(amount, max_integrity - integrity)
	integrity += healed
	if integrity > 0:
		online = true
	return healed

func suppress(turns: int) -> void:
	offline_turns = maxi(offline_turns, turns)

func tick_suppression() -> void:
	if offline_turns > 0:
		offline_turns -= 1

## If undamaged since the last tick, restore auto_repair HP, then clear the flag.
## Returns HP actually restored (0 when skipped or already full).
func tick_auto_repair() -> int:
	var healed := 0
	if auto_repair > 0 and not damaged_since_tick and integrity < max_integrity:
		healed = repair(auto_repair)
	damaged_since_tick = false
	return healed

## 0.0 (destroyed) .. 1.0 (pristine). Drives partial effectiveness so that
## chipping a system is worthwhile even without destroying it.
func efficiency() -> float:
	if not is_active():
		return 0.0
	if max_integrity <= 0:
		return 1.0
	return clampf(float(integrity) / float(max_integrity), 0.0, 1.0)
