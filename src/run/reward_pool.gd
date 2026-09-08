class_name RewardPool
extends RefCounted
## What a victory pays out.
##
## Winning gives HARDWARE, not cards: the deck is downstream of the ship, so a
## part is the card reward. Scaling by node type (regular / elite / boss), not
## just the enemy's hull tier, so a sector-1 gunship boss still pays like a boss:
##
##   regular    credits + a part offer
##   mini-boss  credits + a part offer + a common/uncommon improvement
##   boss       credits + a rare part offer + a rare improvement
##
## Declining the part is not a dead option -- it lets you JETTISON an installed
## part instead. That is the ship-level counterpart to stripping a card: cutting
## a whole part frees its slot and takes all three of its cards with it.

const OFFER_COUNT := 3

const RARITY_BY_TIER := {1: &"common", 2: &"uncommon", 3: &"rare"}

## Which part tiers an enemy of this tier offers, in order of preference.
static func _tier_band(enemy_tier: int) -> Array[int]:
	match enemy_tier:
		1: return [1, 2]
		2: return [2, 1]
		_: return [3, 2]

static func build(run: RunState, meta: MetaState, enemy: EnemyDef,
		node_type: String = "") -> Dictionary:
	var tier: int = _payout_tier(enemy.tier, node_type)
	return {
		"tier": tier,
		"credits": int(enemy.reward.get("credits", 0)),
		"parts": part_offers(run, meta, tier),
		"improvement": _roll_improvement(tier),
		"allow_jettison": not run.ship.parts.is_empty(),
	}

## Node type wins when present so a weaker act-1 boss still pays rare loot.
static func _payout_tier(enemy_tier: int, node_type: String) -> int:
	match node_type:
		"boss":
			return 3
		"elite":
			return 2
		"combat":
			return 1
		_:
			return enemy_tier

# --- Parts -------------------------------------------------------------------

static func part_offers(run: RunState, meta: MetaState, enemy_tier: int) -> Array:
	var band := _tier_band(enemy_tier)
	var pool: Array = []
	for def in meta.available_parts():
		if band.has(def.tier):
			pool.append(def)
	if pool.is_empty():
		pool = meta.available_parts()
	if pool.is_empty():
		return []

	var weights: Dictionary = {}
	for i in pool.size():
		var def: PartDef = pool[i]
		var w := 1.0
		# Prefer the headline tier for this enemy; lower tiers are filler.
		w *= 3.0 if def.tier == band[0] else 1.0
		if run.ship.free_slots(def.slot) > 0:
			w *= 2.5
		if _already_installed(run, def):
			w *= 0.35
		weights[i] = w

	var chosen: Array = []
	var picked: Dictionary = {}
	var guard := 0
	while chosen.size() < mini(OFFER_COUNT, pool.size()) and guard < 80:
		guard += 1
		var idx = Rng.weighted(&"reward", weights)
		if idx == null:
			break
		weights.erase(idx)
		if picked.has(idx):
			continue
		picked[idx] = true
		var def2: PartDef = pool[int(idx)]
		chosen.append({
			"def": def2,
			"slot": def2.slot,
			"rarity": RARITY_BY_TIER.get(def2.tier, &"common"),
			"can_install": run.ship.free_slots(def2.slot) > 0,
			"replaces": _weakest_in_slot(run, def2.slot),
		})
	return chosen

static func _already_installed(run: RunState, def: PartDef) -> bool:
	for inst in run.ship.parts:
		if inst.def.id == def.id:
			return true
	return false

static func _weakest_in_slot(run: RunState, slot: StringName) -> PartInstance:
	if run.ship.free_slots(slot) > 0:
		return null
	var worst: PartInstance = null
	for inst in run.ship.installed_in(slot):
		if worst == null or inst.sale_value() < worst.sale_value():
			worst = inst
	return worst

## Take a part offer: install into a free slot, or swap into a full one.
static func claim(run: RunState, offer: Dictionary,
		replace_target: PartInstance = null) -> String:
	var def: PartDef = offer["def"]
	if run.ship.free_slots(def.slot) > 0:
		return "" if run.install(def) != null else "could not install %s" % def.name
	var target: PartInstance = replace_target if replace_target != null else offer.get("replaces")
	if target == null:
		return "No free %s slot and nothing to replace" % String(def.slot)
	return "" if run.swap(target, def) != null else "could not swap %s" % def.name

## Decline the part and cut an installed one instead. Frees the slot and takes
## all of that part's cards out of the deck with it.
static func jettison(run: RunState, inst: PartInstance) -> String:
	if not run.ship.parts.has(inst):
		return "that part is not installed"
	var id := inst.def.id
	if not run.ship.remove(inst):
		return "could not jettison %s" % inst.def.name
	run.recompile()
	EventBus.part_jettisoned.emit(id)
	return ""

## Skip the part offer and patch the hull instead. Returns HP actually restored.
const SKIP_REPAIR_FRAC := 0.15

static func skip_repair_amount(run: RunState) -> int:
	var cap := int(ceil(float(run.profile.max_hull) * SKIP_REPAIR_FRAC))
	var room := maxi(0, run.profile.max_hull - run.hull_carryover)
	return mini(cap, room)

static func skip_for_repair(run: RunState) -> int:
	var heal := skip_repair_amount(run)
	if heal <= 0:
		return 0
	run.hull_carryover = mini(run.profile.max_hull, run.hull_carryover + heal)
	return heal

# --- Improvements ------------------------------------------------------------

## Mini-bosses drop a common or uncommon improvement; sector bosses a rare one.
## Regular enemies drop none -- improvements are what makes a tough fight worth
## seeking out rather than routing around.
static func _roll_improvement(enemy_tier: int) -> ImprovementDef:
	var rarities: Array = []
	match enemy_tier:
		1: return null
		2: rarities = [&"common", &"uncommon"]
		_: rarities = [&"rare"]
	var pool := Database.improvements_of_rarity(rarities)
	if pool.is_empty():
		return null
	return Rng.pick(&"reward", pool)

## Chest nodes: a random improvement the ship does not already have.
static func chest_improvement(run: RunState) -> ImprovementDef:
	var pool: Array = []
	for iid in Database.improvements:
		if run.ship.improvements.find(iid) == -1:
			pool.append(Database.improvements[iid])
	if pool.is_empty():
		for iid in Database.improvements:
			pool.append(Database.improvements[iid])
	if pool.is_empty():
		return null
	return Rng.pick(&"reward", pool)

## In-run store part price. Discount Codes halves it (integer floor).
## Strip costs and sale penalties are not shop prices.
static func shop_price(run: RunState, base: int) -> int:
	if run != null and run.ship != null and run.ship.has_flag(&"shop_half_price"):
		return int(base) / 2
	return int(base)

## Shop stock: a few parts priced at their base value.
static func shop_stock(run: RunState, meta: MetaState, count: int = 3) -> Array:
	var pool: Array = meta.available_parts()
	if pool.is_empty():
		return []
	var weights: Dictionary = {}
	for i in pool.size():
		var def: PartDef = pool[i]
		var w := 1.0
		if run.ship.free_slots(def.slot) > 0:
			w *= 2.0
		if _already_installed(run, def):
			w *= 0.4
		weights[i] = w
	var chosen: Array = []
	var guard := 0
	while chosen.size() < mini(count, pool.size()) and guard < 80:
		guard += 1
		var idx = Rng.weighted(&"shop", weights)
		if idx == null:
			break
		weights.erase(idx)
		var def2: PartDef = pool[int(idx)]
		chosen.append({
			"def": def2,
			"price": shop_price(run, def2.base_value),
			"can_install": run.ship.free_slots(def2.slot) > 0,
			"replaces": _weakest_in_slot(run, def2.slot),
		})
	return chosen
