class_name ShipProfile
extends RefCounted
## The flat, combat-ready view of a ship.
##
## Combat never sees the loadout. ShipLoadout.compile() collapses installed
## parts into this stat block + system list + deck list, and combat reads only
## this. One seam, so there is exactly one place where parts become numbers.

var display_name: String = "Brawler"
var max_hull: int = 40
var max_shield: int = 0
var shield_regen: int = 0
var evasion: int = 0
var power: int = 3                  # energy per turn
var power_draw: int = 0             # total draw, for the loadout readout
var mass: int = 0
var draw_per_turn: int = 5
## Player subsystem auto-repair. Zero unless a rare improvement grants it.
var system_regen: int = 0
## Empty drone bays granted by the launcher. Combat starts with them vacant;
## launch cards fill a slot. Occupied drones tick at the start of your turn.
var drone_slots: int = 0
var systems: Array = []             # [{id, name, integrity, part_uids}]
var deck: Array[StringName] = []    # card ids
## Parallel to `deck`: PartInstance.uid that granted each card. Combat stamps
## this onto CardInstance so Calibrate can scope bonuses to one mount.
var deck_sources: Array[int] = []
var warnings: Array[String] = []    # e.g. "power deficit", surfaced in shipyard
## Compiled improvement combat hooks. Combat reads these, not the loadout.
var triggers: Array = []            # [{when, op, amount}, ...]
## Compiled improvement passives (keep_overshield, shop_half_price,
## virus_no_decay, damage_as_virus, and the common combat flags).
var flags: Array[StringName] = []

func has_flag(flag: StringName) -> bool:
	return flags.has(flag)

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
