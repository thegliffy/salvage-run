class_name MetaState
extends RefCounted
## Persistent progression: salvage currency, unlocked parts, and starter hulls.
##
## The fantasy: every run is a theft. What you bolt on mid-run becomes scrap at
## the yard; salvage unlocks new parts into the reward pool and new starter
## hulls to steal. Unlocks are additive (more variety), not a flat power grant,
## so run 200 stays as interesting as run 5.

var salvage: int = 0
var unlocked: Dictionary = {}       # part id -> true
var unlocked_ships: Dictionary = {} # starter ship id -> true
var runs_started: int = 0
var runs_won: int = 0
var best_total: int = 0
var lifetime_salvage: int = 0

func grant_starting_unlocks() -> void:
	for pid in Database.parts:
		if Database.parts[pid].is_starter():
			unlocked[pid] = true
	for choice in StarterShips.choices():
		if int(choice.get("unlock_cost", 0)) == 0:
			unlocked_ships[choice["id"]] = true

func is_unlocked(part_id: StringName) -> bool:
	return unlocked.has(part_id)

func is_ship_unlocked(ship_id: StringName) -> bool:
	return unlocked_ships.has(ship_id)

func unlockable() -> Array:
	return Database.parts_matching(func(p: PartDef):
		return not is_unlocked(p.id) and p.unlock_cost > 0)

func unlockable_ships() -> Array:
	var out: Array = []
	for choice in StarterShips.choices():
		if int(choice.get("unlock_cost", 0)) > 0 and not is_ship_unlocked(choice["id"]):
			out.append(choice)
	out.sort_custom(func(a, b): return int(a["unlock_cost"]) < int(b["unlock_cost"]))
	return out

func can_afford(part_id: StringName) -> bool:
	var p: PartDef = Database.part(part_id)
	return p != null and not is_unlocked(part_id) and salvage >= p.unlock_cost

func can_afford_ship(ship_id: StringName) -> bool:
	var cost := StarterShips.unlock_cost(ship_id)
	return cost > 0 and not is_ship_unlocked(ship_id) and salvage >= cost

func unlock(part_id: StringName) -> bool:
	if not can_afford(part_id):
		return false
	var p: PartDef = Database.part(part_id)
	salvage -= p.unlock_cost
	unlocked[part_id] = true
	EventBus.salvage_changed.emit(salvage)
	EventBus.part_unlocked.emit(part_id)
	return true

func unlock_ship(ship_id: StringName) -> bool:
	if not can_afford_ship(ship_id):
		return false
	var cost := StarterShips.unlock_cost(ship_id)
	salvage -= cost
	unlocked_ships[ship_id] = true
	EventBus.salvage_changed.emit(salvage)
	EventBus.ship_unlocked.emit(ship_id)
	return true

## Parts eligible to show up as run rewards / shop stock.
func available_parts() -> Array:
	var out: Array = []
	for pid in unlocked:
		var p: PartDef = Database.part(pid)
		if p != null:
			out.append(p)
	return out

func record_sale(valuation: Dictionary) -> void:
	var amount: int = valuation["total"]
	salvage += amount
	lifetime_salvage += amount
	best_total = maxi(best_total, amount)
	if valuation.get("boss_killed", false):
		runs_won += 1
	EventBus.ship_sold.emit(valuation)
	EventBus.salvage_changed.emit(salvage)

func to_dict() -> Dictionary:
	var u: Array = []
	for k in unlocked:
		u.append(String(k))
	var ships: Array = []
	for k in unlocked_ships:
		ships.append(String(k))
	return {"salvage": salvage, "unlocked": u, "unlocked_ships": ships,
		"runs_started": runs_started, "runs_won": runs_won, "best_total": best_total,
		"lifetime_salvage": lifetime_salvage}

func from_dict(d: Dictionary) -> void:
	salvage = int(d.get("salvage", 0))
	unlocked.clear()
	for k in d.get("unlocked", []):
		unlocked[StringName(k)] = true
	unlocked_ships.clear()
	for k in d.get("unlocked_ships", []):
		unlocked_ships[StringName(k)] = true
	runs_started = int(d.get("runs_started", 0))
	runs_won = int(d.get("runs_won", 0))
	best_total = int(d.get("best_total", 0))
	lifetime_salvage = int(d.get("lifetime_salvage", 0))
	# A save from before a part/ship existed should still get free starters.
	grant_starting_unlocks()
