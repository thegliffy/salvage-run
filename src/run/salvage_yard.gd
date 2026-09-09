class_name SalvageYard
extends RefCounted
## Store services: strip a card from a mount, or forge a mount so its
## remaining cards play upgraded for the rest of the run.
##
## Both used to be imagined as their own node types. With the StS-style map
## they live at the store — spend credits to thin the deck, or spend more to
## make a mount hit harder. Charge for each lives in one function so shop UI,
## leftover salvage, and `--sim` all hit the same path.

const STRIP_CREDIT_BASE := 40
const STRIP_CREDIT_STEP := 25
const FORGE_CREDIT_BASE := 80
const FORGE_CREDIT_STEP := 40

## Installed parts already stripped this run. Drives the next credit cost.
static func strips_done(run: RunState) -> int:
	var n := 0
	for inst in run.ship.parts:
		if inst.is_stripped():
			n += 1
	return n

## `40 + 25 * strips_already_done` — counted before this strip.
static func credit_cost(run: RunState) -> int:
	return STRIP_CREDIT_BASE + STRIP_CREDIT_STEP * strips_done(run)

static func sale_delta(inst: PartInstance) -> int:
	if inst == null or inst.is_stripped():
		return 0
	return inst.sale_value() - _value_after_strip(inst)

## Every strip currently available, one entry per removable card.
## UI renders these directly; each carries credit cost and sale-value delta.
static func options(run: RunState) -> Array:
	var cost := credit_cost(run)
	var out: Array = []
	for inst in run.ship.parts:
		if not inst.can_strip():
			continue
		var delta: int = sale_delta(inst)
		for i in inst.def.grants.size():
			var card: CardDef = Database.card(inst.def.grants[i])
			if card == null:
				continue
			out.append({
				"part": inst,
				"part_name": inst.def.name,
				"index": i,
				"card_id": inst.def.grants[i],
				"card_name": card.name + ("+" if inst.upgraded else ""),
				"card_text": card.text_for(inst.upgraded),
				"value_cost": delta,
				"credit_cost": cost,
				"can_afford": run.credits >= cost,
			})
	return out

static func _value_after_strip(inst: PartInstance) -> int:
	# Cheap and exact: strip a throwaway copy rather than reimplement the maths.
	var probe := PartInstance.create(inst.def)
	probe.upgraded = inst.upgraded
	probe.wear = inst.wear
	probe.stripped_index = 0
	return probe.sale_value()

## Perform a strip. Charges credits, then cuts the card. Returns "" on
## success, or a player-facing refusal. Does not charge on refusal.
static func strip(run: RunState, inst: PartInstance, index: int) -> String:
	if not run.ship.parts.has(inst):
		return "that part is not installed"
	# Mount rules before money, so "already stripped" is not "need 65 credits".
	if inst.is_stripped() or inst.def.grants.size() <= 1 \
			or index < 0 or index >= inst.def.grants.size():
		return inst.strip(index)
	var cost := credit_cost(run)
	if run.credits < cost:
		return "need %d credits (have %d)" % [cost, run.credits]
	var err: String = inst.strip(index)
	if err != "":
		return err
	run.add_credits(-cost)
	# Recompile immediately so the deck the player sees is the deck they get.
	run.recompile()
	EventBus.part_stripped.emit(inst.def.id, index)
	return ""

## How much of the ship's card pool has already been cut. Handy for a UI
## readout ("3 of 7 mounts stripped") and for the sale screen.
static func strip_summary(run: RunState) -> Dictionary:
	var stripped := 0
	var strippable := 0
	for inst in run.ship.parts:
		if inst.is_stripped():
			stripped += 1
		if inst.def.grants.size() > 1:
			strippable += 1
	return {"stripped": stripped, "strippable": strippable,
		"deck_size": run.profile.deck.size()}

# --- Forge -------------------------------------------------------------------

## Installed parts already forged this run. Drives the next credit cost.
static func forges_done(run: RunState) -> int:
	var n := 0
	for inst in run.ship.parts:
		if inst.upgraded:
			n += 1
	return n

## `80 + 40 * forges_already_done` — counted before this forge.
## Strictly above Strip (`40 + 25 * strips`) at every matching step.
static func forge_cost(run: RunState) -> int:
	return FORGE_CREDIT_BASE + FORGE_CREDIT_STEP * forges_done(run)

## Every forge currently available, one entry per unforged mount.
static func forge_options(run: RunState) -> Array:
	var cost := forge_cost(run)
	var out: Array = []
	for inst in run.ship.parts:
		if not inst.can_forge():
			continue
		var cards: Array = []
		for cid in inst.granted_cards():
			var card: CardDef = Database.card(cid)
			if card == null:
				continue
			cards.append({
				"card_id": cid,
				"card_name": card.name + "+",
				"card_text": card.text_for(true),
			})
		out.append({
			"part": inst,
			"part_name": inst.def.name,
			"credit_cost": cost,
			"can_afford": run.credits >= cost,
			"cards": cards,
		})
	return out

## Perform a forge. Charges credits, then stamps the mount. Returns "" on
## success, or a player-facing refusal. Does not charge on refusal.
static func forge(run: RunState, inst: PartInstance) -> String:
	if not run.ship.parts.has(inst):
		return "that part is not installed"
	# Mount rules before money, so "already forged" is not "need 80 credits".
	if inst.upgraded:
		return inst.forge()
	var cost := forge_cost(run)
	if run.credits < cost:
		return "need %d credits (have %d)" % [cost, run.credits]
	var err: String = inst.forge()
	if err != "":
		return err
	run.add_credits(-cost)
	run.recompile()
	EventBus.part_forged.emit(inst.def.id)
	return ""
