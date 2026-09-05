class_name PartDef
extends RefCounted
## A ship part: occupies cells on the hull grid, provides a subsystem,
## and grants cards to the deck.
##
## This is the pivot of the whole design. The player never edits their deck
## directly -- they change the ship, and the deck follows.

var id: StringName
var name: String
var flavor: String = ""
var system: StringName = &"weapons"   # which subsystem this part powers
var shape: Array[Vector2i] = []       # cells occupied, relative to origin
var integrity: int = 8                # subsystem HP contributed
var power_draw: int = 1               # reactor power consumed
var power_gen: int = 0                # reactor power produced (reactors only)
var mass: int = 1                     # affects evasion via engines
var grants: Array[StringName] = []    # card ids added to deck (duplicates ok)
var stats: Dictionary = {}            # flat modifiers: hull, shield, evasion...
var synergy: Dictionary = {}          # adjacency bonuses, see HullGrid.compile()
var base_value: int = 40              # credits; also drives sale valuation
var tier: int = 1
var unlock_cost: int = 0              # salvage cost in the meta shop; 0 = starter

func from_dict(def_id: StringName, d: Dictionary) -> String:
	id = def_id
	name = d.get("name", "")
	if name == "":
		return "missing 'name'"
	flavor = d.get("flavor", "")
	system = StringName(d.get("system", "weapons"))

	var raw_shape: Array = d.get("shape", [[0, 0]])
	if raw_shape.is_empty():
		return "shape must have at least one cell"
	for cell in raw_shape:
		if typeof(cell) != TYPE_ARRAY or cell.size() != 2:
			return "shape cells must be [x, y] pairs"
		shape.append(Vector2i(int(cell[0]), int(cell[1])))

	integrity = int(d.get("integrity", 8))
	power_draw = int(d.get("power_draw", 1))
	power_gen = int(d.get("power_gen", 0))
	mass = int(d.get("mass", shape.size()))
	for c in d.get("grants", []):
		grants.append(StringName(c))
	stats = d.get("stats", {})
	synergy = d.get("synergy", {})
	base_value = int(d.get("base_value", 40))
	tier = int(d.get("tier", 1))
	unlock_cost = int(d.get("unlock_cost", 0))
	return ""

func is_starter() -> bool:
	return unlock_cost == 0

func footprint() -> int:
	return shape.size()
