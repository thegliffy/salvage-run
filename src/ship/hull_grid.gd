class_name HullGrid
extends RefCounted
## The ship as a spatial layout of parts.
##
## Placement rules:
##   - parts occupy cells and may not overlap
##   - every cell must be inside the hull mask
##   - adjacency between parts triggers synergy bonuses
##
## compile() is the single bridge to combat. Anything combat needs to know
## must be produced here, so there is exactly one place where layout turns
## into numbers.

var width: int = 6
var height: int = 4
var mask: Array[Vector2i] = []      # legal cells; empty = full rectangle
var parts: Array[PartInstance] = []
var display_name: String = "Salvager"

# Base stats before parts contribute.
var base_hull: int = 30
var base_power: int = 1
var base_draw: int = 5

func _init(w: int = 6, h: int = 4) -> void:
	width = w
	height = h

func in_bounds(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return false
	if mask.is_empty():
		return true
	return mask.has(cell)

func occupant_at(cell: Vector2i) -> PartInstance:
	for p in parts:
		if p.cells().has(cell):
			return p
	return null

## Returns "" if the part fits at `at`, otherwise a human-readable reason.
func placement_error(part: PartDef, at: Vector2i, ignore: PartInstance = null) -> String:
	for offset in part.shape:
		var cell := at + offset
		if not in_bounds(cell):
			return "%s doesn't fit inside the hull" % part.name
		var occ := occupant_at(cell)
		if occ != null and occ != ignore:
			return "%s overlaps %s" % [part.name, occ.def.name]
	return ""

func can_place(part: PartDef, at: Vector2i, ignore: PartInstance = null) -> bool:
	return placement_error(part, at, ignore) == ""

func place(part: PartDef, at: Vector2i) -> PartInstance:
	if not can_place(part, at):
		return null
	var inst := PartInstance.create(part, at)
	parts.append(inst)
	EventBus.part_installed.emit(part.id, at)
	return inst

func remove(inst: PartInstance) -> bool:
	var idx := parts.find(inst)
	if idx == -1:
		return false
	parts.remove_at(idx)
	EventBus.part_removed.emit(inst.def.id, inst.origin)
	return true

## Parts whose cells touch orthogonally.
func neighbors_of(inst: PartInstance) -> Array[PartInstance]:
	var out: Array[PartInstance] = []
	var own := inst.cells()
	const DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for cell in own:
		for d in DIRS:
			var occ := occupant_at(cell + d)
			if occ != null and occ != inst and not out.has(occ):
				out.append(occ)
	return out

func free_cells() -> int:
	var total := mask.size() if not mask.is_empty() else width * height
	var used := 0
	for p in parts:
		used += p.def.footprint()
	return total - used

## ---------------------------------------------------------------------------
## The bridge: layout -> combat-ready ShipProfile.
## ---------------------------------------------------------------------------
func compile() -> ShipProfile:
	var prof := ShipProfile.new()
	prof.display_name = display_name
	prof.max_hull = base_hull
	prof.power = base_power
	prof.draw_per_turn = base_draw

	var systems_acc: Dictionary = {}   # system id -> accumulated dict
	var power_draw := 0
	var total_mass := 0

	for inst in parts:
		if inst.is_wrecked():
			continue  # a destroyed part contributes nothing until repaired
		var d := inst.def

		# Cards
		for cid in d.grants:
			prof.deck.append(cid)

		# Power
		prof.power += d.power_gen
		power_draw += d.power_draw
		total_mass += d.mass

		# Flat stats
		prof.max_hull += int(d.stats.get("hull", 0))
		prof.max_shield += int(d.stats.get("shield", 0))
		prof.shield_regen += int(d.stats.get("shield_regen", 0))
		prof.evasion += int(d.stats.get("evasion", 0))
		prof.draw_per_turn += int(d.stats.get("draw", 0))

		# Subsystem aggregation: several parts can feed one subsystem,
		# stacking its integrity. Losing "weapons" means losing all of them.
		if not systems_acc.has(d.system):
			systems_acc[d.system] = {
				"id": d.system,
				"name": String(d.system).capitalize(),
				"integrity": 0,
				"part_uids": [],
			}
		systems_acc[d.system]["integrity"] += inst.effective_integrity()
		systems_acc[d.system]["part_uids"].append(inst.uid)

	# Adjacency synergy, applied after the base pass so bonuses read off
	# finished neighbor data rather than partial state.
	for inst in parts:
		if inst.is_wrecked() or inst.def.synergy.is_empty():
			continue
		var want := StringName(inst.def.synergy.get("adjacent_system", ""))
		if want == &"":
			continue
		var matched := false
		for n in neighbors_of(inst):
			if n.def.system == want and not n.is_wrecked():
				matched = true
				break
		if not matched:
			continue
		var bonus: Dictionary = inst.def.synergy.get("bonus", {})
		prof.max_hull += int(bonus.get("hull", 0))
		prof.max_shield += int(bonus.get("shield", 0))
		prof.shield_regen += int(bonus.get("shield_regen", 0))
		prof.evasion += int(bonus.get("evasion", 0))
		prof.power += int(bonus.get("power", 0))
		prof.draw_per_turn += int(bonus.get("draw", 0))

	# Heavier ships dodge worse. Engines counteract mass via evasion stats.
	prof.evasion = maxi(0, prof.evasion - int(floor(total_mass / 4.0)))

	prof.systems = systems_acc.values()

	# Power deficit is a design pressure, not an error: you can overload the
	# reactor, you just lose energy per turn for it.
	if power_draw > prof.power:
		var deficit := power_draw - prof.power
		prof.warnings.append("Power deficit: %d (energy reduced)" % deficit)
		prof.power = maxi(0, prof.power - deficit)
	prof.power = maxi(prof.power, 0)
	return prof

## Total credits from scrapping every installed part -- the run-end sale.
func scrap_value() -> int:
	var total := 0
	for p in parts:
		total += p.sale_value()
	return total

func to_dict() -> Dictionary:
	var pd: Array = []
	for p in parts:
		pd.append(p.to_dict())
	return {"width": width, "height": height, "name": display_name, "parts": pd}

static func from_dict(d: Dictionary) -> HullGrid:
	var g := HullGrid.new(int(d.get("width", 6)), int(d.get("height", 4)))
	g.display_name = d.get("name", "Salvager")
	for pd in d.get("parts", []):
		var inst := PartInstance.from_dict(pd)
		if inst != null:
			g.parts.append(inst)
	return g
