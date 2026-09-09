class_name PartInstance
extends RefCounted
## A specific installed part: a PartDef plus per-copy state.
## Wear persists across fights and is what makes selling a used ship
## worth less than selling a fresh one.

var def: PartDef
var upgraded: bool = false
var wear: int = 0          # accumulated permanent damage, 0..def.integrity
var uid: int = 0           # stable id for save/load and UI diffing

## Index into def.grants of the card stripped from this mount, or -1.
##
## A single int, not a list: one strip per part, so a ship can never be
## thinned past three quarters of its cards. The store also charges run credits
## that scale with how many mounts are already stripped (see SalvageYard).
var stripped_index: int = -1

## Value lost by stripping a mount. Still applied on sale; the store also
## charges run credits (SalvageYard.credit_cost).
const STRIP_VALUE_PENALTY := 0.25

static var _next_uid: int = 1

static func create(part_def: PartDef) -> PartInstance:
	var p := PartInstance.new()
	p.def = part_def
	p.uid = _next_uid
	_next_uid += 1
	return p

## Cards this part actually contributes, honouring the strip.
func granted_cards() -> Array[StringName]:
	var out: Array[StringName] = []
	for i in def.grants.size():
		if i == stripped_index:
			continue
		out.append(def.grants[i])
	return out

func is_stripped() -> bool:
	return stripped_index >= 0

## A part with only one card left cannot be stripped to nothing.
func can_strip() -> bool:
	return not is_stripped() and def.grants.size() > 1

## Returns "" on success, or why the strip was refused.
func strip(index: int) -> String:
	if is_stripped():
		return "%s has already been stripped" % def.name
	if def.grants.size() <= 1:
		return "%s has nothing to spare" % def.name
	if index < 0 or index >= def.grants.size():
		return "no such mount"
	stripped_index = index
	return ""

func effective_integrity() -> int:
	return maxi(0, def.integrity - wear)

func is_wrecked() -> bool:
	return effective_integrity() <= 0

## Resale value decays with wear and rises with upgrades.
func sale_value() -> int:
	var condition := 1.0
	if def.integrity > 0:
		condition = float(effective_integrity()) / float(def.integrity)
	var v := float(def.base_value) * (0.35 + 0.65 * condition)
	if upgraded:
		v *= 1.4
	if is_stripped():
		v *= (1.0 - STRIP_VALUE_PENALTY)
	return int(round(v))

func to_dict() -> Dictionary:
	return {"def": String(def.id), "upgraded": upgraded, "wear": wear,
		"stripped": stripped_index}

static func from_dict(d: Dictionary) -> PartInstance:
	var pd: PartDef = Database.part(StringName(d.get("def", "")))
	if pd == null:
		return null
	var p := PartInstance.create(pd)
	p.upgraded = bool(d.get("upgraded", false))
	p.wear = int(d.get("wear", 0))
	p.stripped_index = int(d.get("stripped", -1))
	return p
