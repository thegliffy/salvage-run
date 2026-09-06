class_name ShipLoadout
extends RefCounted
## The ship as a set of typed slots.
##
## Replaced the spatial hull grid. Placement was never a real decision: at a
## typical endgame ship the grid sat 61% empty, and only three parts used the
## adjacency rule that was the grid's only non-spatial-accounting job. Picking
## up a laser should attach a laser.
##
## What limits a ship instead is three soft costs, none of them spatial:
##   - power   : draw beyond reactor output costs energy every turn
##   - mass    : heavier ships dodge worse
##   - the deck: every part adds three cards, so a big ship draws badly
##
## None of them ever refuse a part. Slots are the only hard limit, and their
## job is to shape WHAT you carry, not how much.

const SLOT_WEAPON := &"weapon"
const SLOT_HULL := &"hull"
const SLOT_UTILITY := &"utility"
const SLOT_TYPES: Array[StringName] = [SLOT_WEAPON, SLOT_HULL, SLOT_UTILITY]

var display_name: String = "Salvager"
var capacity: Dictionary = {SLOT_WEAPON: 4, SLOT_HULL: 3, SLOT_UTILITY: 4}
var parts: Array[PartInstance] = []
## Permanent ship upgrades. They fill no slot and grant no cards -- they change
## what the hull itself can do, including how many slots it has.
var improvements: Array[StringName] = []

# Base hull stats before any part contributes. The HULL generates the power --
# no module does. Parts only ever draw. Reactor output is raised by improvements,
# which keeps energy a property of the ship rather than a slot tax.
var base_hull: int = 30
var base_power: int = 5
var base_draw: int = 5

func _init(name: String = "Salvager") -> void:
	display_name = name

# --- Slots -------------------------------------------------------------------

func slot_capacity(slot: StringName) -> int:
	var n := int(capacity.get(slot, 0))
	for iid in improvements:
		var imp: ImprovementDef = Database.improvement(iid)
		if imp != null:
			n += int(imp.slots.get(String(slot), 0))
	return n

func add_improvement(id: StringName) -> bool:
	if Database.improvement(id) == null:
		return false
	improvements.append(id)
	EventBus.improvement_installed.emit(id)
	return true

func improvement_defs() -> Array:
	var out: Array = []
	for iid in improvements:
		var imp: ImprovementDef = Database.improvement(iid)
		if imp != null:
			out.append(imp)
	return out

func installed_in(slot: StringName) -> Array[PartInstance]:
	var out: Array[PartInstance] = []
	for p in parts:
		if p.def.slot == slot:
			out.append(p)
	return out

func free_slots(slot: StringName) -> int:
	return slot_capacity(slot) - installed_in(slot).size()

func has_room_for(def: PartDef) -> bool:
	return free_slots(def.slot) > 0

## "" if the part can be installed, otherwise a player-facing reason.
func install_error(def: PartDef) -> String:
	if not has_room_for(def):
		return "No free %s slot" % String(def.slot)
	return ""

func install(def: PartDef) -> PartInstance:
	if not has_room_for(def):
		return null
	var inst := PartInstance.create(def)
	parts.append(inst)
	EventBus.part_installed.emit(def.id, Vector2i.ZERO)
	return inst

func remove(inst: PartInstance) -> bool:
	var idx := parts.find(inst)
	if idx == -1:
		return false
	parts.remove_at(idx)
	EventBus.part_removed.emit(inst.def.id, Vector2i.ZERO)
	return true

## Swap a new part into an occupied slot. Returns the new instance, or null.
## Needed because a full slot must still be an upgrade opportunity, or rewards
## dry up the moment the ship is fitted out.
func replace(old: PartInstance, def: PartDef) -> PartInstance:
	if old.def.slot != def.slot:
		return null
	if not remove(old):
		return null
	return install(def)

func total_slots() -> int:
	var n := 0
	for s in SLOT_TYPES:
		n += slot_capacity(s)
	return n

# --- Compile to a combat profile ---------------------------------------------

## The single bridge to combat. Combat never sees the loadout.
func compile() -> ShipProfile:
	var prof := ShipProfile.new()
	prof.display_name = display_name
	prof.max_hull = base_hull
	prof.power = base_power
	prof.draw_per_turn = base_draw

	var systems_acc: Dictionary = {}
	var power_draw := 0
	var total_mass := 0
	var present_systems: Dictionary = {}

	for inst in parts:
		if inst.is_wrecked():
			continue
		present_systems[inst.def.system] = true

	for inst in parts:
		if inst.is_wrecked():
			continue  # a destroyed part contributes nothing until repaired
		var d := inst.def

		for cid in inst.granted_cards():
			prof.deck.append(cid)

		prof.power += d.power_gen
		power_draw += d.power_draw
		total_mass += d.mass

		prof.max_hull += int(d.stats.get("hull", 0))
		prof.max_shield += int(d.stats.get("shield", 0))
		prof.shield_regen += int(d.stats.get("shield_regen", 0))
		prof.evasion += int(d.stats.get("evasion", 0))
		prof.draw_per_turn += int(d.stats.get("draw", 0))

		if not systems_acc.has(d.system):
			systems_acc[d.system] = {
				"id": d.system,
				"name": String(d.system).capitalize(),
				"integrity": 0,
				"part_uids": [],
			}
		systems_acc[d.system]["integrity"] += inst.effective_integrity()
		systems_acc[d.system]["part_uids"].append(inst.uid)

	# Synergy is keyed to whether the ship HAS a system, not to where a part
	# sits. Same combo design, and discoverable without a layout screen.
	for inst in parts:
		if inst.is_wrecked() or inst.def.synergy.is_empty():
			continue
		var want := StringName(inst.def.synergy.get("requires_system", ""))
		if want == &"" or not present_systems.has(want):
			continue
		var bonus: Dictionary = inst.def.synergy.get("bonus", {})
		prof.max_hull += int(bonus.get("hull", 0))
		prof.max_shield += int(bonus.get("shield", 0))
		prof.shield_regen += int(bonus.get("shield_regen", 0))
		prof.evasion += int(bonus.get("evasion", 0))
		prof.power += int(bonus.get("power", 0))
		prof.draw_per_turn += int(bonus.get("draw", 0))

	# Improvements land before the mass penalty so evasion bonuses are not
	# silently eaten by a heavy ship's own tonnage.
	for imp in improvement_defs():
		prof.max_hull += int(imp.stats.get("hull", 0))
		prof.max_shield += int(imp.stats.get("shield", 0))
		prof.shield_regen += int(imp.stats.get("shield_regen", 0))
		prof.evasion += int(imp.stats.get("evasion", 0))
		prof.power += int(imp.stats.get("power", 0))
		prof.draw_per_turn += int(imp.stats.get("draw", 0))

	prof.evasion = maxi(0, prof.evasion - int(floor(total_mass / 4.0)))
	prof.systems = systems_acc.values()

	# Overdrawing the reactor is allowed and costs energy every turn. It is a
	# price, not a wall -- the player should always be able to take the part.
	prof.power_draw = power_draw
	if power_draw > prof.power:
		var deficit := power_draw - prof.power
		prof.warnings.append("Power deficit %d — energy reduced" % deficit)
		prof.power = maxi(0, prof.power - deficit)
	prof.power = maxi(prof.power, 0)
	prof.mass = total_mass
	return prof

func scrap_value() -> int:
	var total := 0
	for p in parts:
		total += p.sale_value()
	return total

func to_dict() -> Dictionary:
	var pd: Array = []
	for p in parts:
		pd.append(p.to_dict())
	var imp: Array = []
	for i in improvements:
		imp.append(String(i))
	return {"name": display_name, "capacity": capacity, "parts": pd,
		"improvements": imp}

static func from_dict(d: Dictionary) -> ShipLoadout:
	var g := ShipLoadout.new(d.get("name", "Salvager"))
	var cap: Dictionary = d.get("capacity", {})
	for k in cap:
		g.capacity[StringName(k)] = int(cap[k])
	for i in d.get("improvements", []):
		g.improvements.append(StringName(i))
	for pd in d.get("parts", []):
		var inst := PartInstance.from_dict(pd)
		if inst != null:
			g.parts.append(inst)
	return g
