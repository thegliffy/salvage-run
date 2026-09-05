class_name PartInstance
extends RefCounted
## A specific installed part: a PartDef plus per-copy state.
## Wear persists across fights and is what makes selling a used ship
## worth less than selling a fresh one.

var def: PartDef
var origin: Vector2i = Vector2i.ZERO
var upgraded: bool = false
var wear: int = 0          # accumulated permanent damage, 0..def.integrity
var uid: int = 0           # stable id for save/load and UI diffing

static var _next_uid: int = 1

static func create(part_def: PartDef, at: Vector2i = Vector2i.ZERO) -> PartInstance:
	var p := PartInstance.new()
	p.def = part_def
	p.origin = at
	p.uid = _next_uid
	_next_uid += 1
	return p

## Absolute cells this part occupies on the hull grid.
func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in def.shape:
		out.append(origin + c)
	return out

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
	return int(round(v))

func to_dict() -> Dictionary:
	return {"def": String(def.id), "origin": [origin.x, origin.y],
		"upgraded": upgraded, "wear": wear}

static func from_dict(d: Dictionary) -> PartInstance:
	var pd: PartDef = Database.part(StringName(d.get("def", "")))
	if pd == null:
		return null
	var o: Array = d.get("origin", [0, 0])
	var p := PartInstance.create(pd, Vector2i(int(o[0]), int(o[1])))
	p.upgraded = bool(d.get("upgraded", false))
	p.wear = int(d.get("wear", 0))
	return p
