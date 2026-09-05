class_name ShipProfile
extends RefCounted
## The flat, combat-ready view of a ship.
##
## Combat never sees the grid. HullGrid.compile() collapses spatial layout into
## this stat block + system list + deck list, and combat reads only this.
## That is the hybrid: spatial building out of combat, clean math inside it.

var display_name: String = "Salvager"
var max_hull: int = 40
var max_shield: int = 0
var shield_regen: int = 0
var evasion: int = 0
var power: int = 3                  # energy per turn
var draw_per_turn: int = 5
var systems: Array = []             # [{id, name, integrity, part_uids}]
var deck: Array[StringName] = []    # card ids
var warnings: Array[String] = []    # e.g. "power deficit", surfaced in shipyard

func system_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for s in systems:
		out.append(s["id"])
	return out

func has_system(sid: StringName) -> bool:
	return system_ids().has(sid)

func summary() -> String:
	return "%s  hull %d  shield %d  power %d  evasion %d  deck %d  systems %s" % [
		display_name, max_hull, max_shield, power, evasion, deck.size(),
		str(system_ids())]
