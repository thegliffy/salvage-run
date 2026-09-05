class_name SalvageYard
extends RefCounted
## The strip service offered at salvage nodes.
##
## Removal is deliberately housed here rather than at shops. Salvage nodes are
## more common (~2 a sector against ~1.5 shops), and cutting cards out of a
## mount at a scrapyard is what a scrapyard is for. Shops are for buying.
##
## The player pays in the ship's eventual sale value, not credits: stripping is
## a trade of meta-progression for run strength, and the cost lands on the
## end-of-run receipt where the lesson is legible.

## Every strip currently available, one entry per removable card.
## UI renders these directly; each carries the value it will cost.
static func options(run: RunState) -> Array:
	var out: Array = []
	for inst in run.ship.parts:
		if not inst.can_strip():
			continue
		var before: int = inst.sale_value()
		for i in inst.def.grants.size():
			var card: CardDef = Database.card(inst.def.grants[i])
			if card == null:
				continue
			out.append({
				"part": inst,
				"part_name": inst.def.name,
				"index": i,
				"card_id": inst.def.grants[i],
				"card_name": card.name,
				"card_text": card.text_for(inst.upgraded),
				"value_cost": before - _value_after_strip(inst),
			})
	return out

static func _value_after_strip(inst: PartInstance) -> int:
	# Cheap and exact: strip a throwaway copy rather than reimplement the maths.
	var probe := PartInstance.create(inst.def, inst.origin)
	probe.upgraded = inst.upgraded
	probe.wear = inst.wear
	probe.stripped_index = 0
	return probe.sale_value()

## Perform a strip. Returns "" on success, or a player-facing refusal.
static func strip(run: RunState, inst: PartInstance, index: int) -> String:
	if not run.ship.parts.has(inst):
		return "that part is not installed"
	var err: String = inst.strip(index)
	if err != "":
		return err
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
